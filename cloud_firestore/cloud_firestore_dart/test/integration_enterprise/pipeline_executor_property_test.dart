// The local pipeline executor against the Enterprise edition emulator:
// random pipelines over random documents run locally and with execute(),
// with the same results (in order where the pipeline defines one), or both
// failing. A difference fails the test unless it is a known one (see
// pipeline_known_differences.dart).
//
//   FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//     dart test test/integration_enterprise/pipeline_executor_property_test.dart
//
// PROPERTY_SEED and PROPERTY_SCALE as in test/util/property.dart.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/pipeline_executor.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';
import '../util/pipeline_known_differences.dart';
import '../util/property.dart';
import '../util/property_pipeline_stages.dart';

/// Thrown by [_remote] when the emulator fails a pipeline with INTERNAL: a
/// defect of the emulator, not an answer about the pipeline.
class _EmulatorFailure implements Exception {}

/// The rows of [pipeline] on the backend, or null when the backend fails it
/// (INVALID_ARGUMENT). INTERNAL is an [_EmulatorFailure]; other errors are
/// retried, then rethrown.
Future<List<PipelineResult>?> _remote(Pipeline pipeline) async {
  for (int attempt = 0; ; attempt++) {
    try {
      return (await pipeline.execute().timeout(
        const Duration(seconds: 30),
      )).results;
    } on FirestoreError catch (e) {
      if (e.code == FirestoreErrorCode.invalidArgument) {
        return null;
      }
      if (e.code == FirestoreErrorCode.internal) {
        throw _EmulatorFailure();
      }
      if (attempt == 4) {
        rethrow;
      }
    } on TimeoutException {
      if (attempt == 4) {
        rethrow;
      }
    }
    await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
  }
}

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/pipeline_executor_property';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test(
    'pipelines run locally as execute() on the emulator',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () async {
      final Firestore db = await IntegrationTestUtil.testEnterpriseFirestore();
      final LocalPipelines local = LocalPipelines(db.modelDatabaseId);
      int compared = 0;
      int bothFailed = 0;
      int unsupported = 0;
      int failedOnly = 0;
      final Map<String, int> known = <String, int>{};
      final List<String> unknown = <String>[];

      for (int round = 0; round < cases(3); round++) {
        final int seed = caseSeed(round);
        final Gen gen = Gen(seed);
        final String run = 'r$seed-${DateTime.now().microsecondsSinceEpoch}';
        final PipelineData data = PipelineData('pipe-$run', 'sub-$run', run);
        final WriteBatch batch = db.batch();
        for (int i = 0; i < 8; i++) {
          final String path = '${data.collection}/d$i';
          data.documents[path] = gen.stageDocument(i, run);
          if (gen.chance(40)) {
            final String sub = '$path/${data.subcollectionId}/s$i';
            data.documents[sub] = gen.stageDocument(100 + i, run);
          }
        }
        data.documents.forEach(
          (String path, Map<String, Object?> value) =>
              batch.set(db.doc(path), value),
        );
        await batch.commit();

        for (int i = 0; i < 40; i++) {
          final GeneratedPipeline generated = gen.stagePipeline(
            db.pipeline(),
            data,
          );
          List<PipelineRow>? localRows;
          String? localFailure;
          try {
            localRows = local.run(generated.pipeline, data.documents);
          } on UnsupportedExpression {
            unsupported++;
            continue;
          } on PipelineFailure catch (e) {
            localFailure = e.message;
          }
          final List<PipelineResult>? remote;
          try {
            remote = await _remote(generated.pipeline);
          } on _EmulatorFailure {
            final String? reason = knownEmulatorFailure(generated.description);
            if (reason != null) {
              known[reason] = (known[reason] ?? 0) + 1;
            } else {
              unknown.add(
                'seed $seed: ${generated.description}\n'
                '    the emulator fails with INTERNAL',
              );
            }
            continue;
          }
          final List<PipelineRow>? remoteRows = remote
              ?.map(local.remoteRow)
              .toList();
          String? difference;
          if (localRows == null || remoteRows == null) {
            if (localRows == null && remoteRows == null) {
              bothFailed++;
              continue;
            }
            failedOnly++;
            difference = localRows == null
                ? 'fails locally ($localFailure), not on the emulator'
                : 'fails on the emulator, not locally';
          } else if (sameRows(
            localRows,
            remoteRows,
            ordered: generated.ordered,
          )) {
            compared++;
            continue;
          } else {
            compared++;
            difference = 'different results';
          }
          final String? reason = knownPipelineDifference(
            generated.description,
            localRows,
            remoteRows,
            ordered: generated.ordered,
          );
          if (reason != null) {
            known[reason] = (known[reason] ?? 0) + 1;
            continue;
          }
          unknown.add(
            'seed $seed: ${generated.description}\n'
            '    $difference\n'
            '    ${localRows != null && remoteRows != null ? describeRowDifference(localRows, remoteRows, ordered: generated.ordered) : 'local ${localRows?.length ?? localFailure}, remote ${remoteRows?.length}'}',
          );
        }
      }
      // ignore: avoid_print
      print(
        'compared $compared pipelines, $bothFailed failed on both, '
        '$failedOnly failed on one side, $unsupported not supported locally; '
        'known differences: $known',
      );
      expect(
        unknown,
        isEmpty,
        reason:
            '${unknown.length} unexplained differences:\n'
            '${unknown.take(20).join('\n')}',
      );
      expect(compared, greaterThan(20));
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
