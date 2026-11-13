// The local expression evaluator of pipelines against the Enterprise edition
// emulator: random documents and random expressions, evaluated locally and
// with `select(expression)` on the emulator. Every difference has to be a
// known one (see [knownDifference]); anything else fails the test with the
// seed, the expression, the document and both results.
//
//   FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//     dart test test/integration_enterprise/pipeline_evaluation_property_test.dart
//
// PROPERTY_SEED and PROPERTY_SCALE work as in the other property tests.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';
import '../util/pipeline_evaluation_cases.dart';
import '../util/property.dart';
import '../util/property_pipeline.dart';

const String _errorSentinel = '\u0001error';

/// A difference between the local evaluator and the emulator that is
/// understood: the reason, or null for a difference that fails the test.
///
/// Keep this list short and every entry explained: it is the list of what
/// local evaluation does differently on purpose or can not do.
String? knownDifference(
  String expression,
  String document,
  String local,
  String remote,
) {
  if (expression.contains('regex_') &&
      (_astral.hasMatch(expression) || _astral.hasMatch(document))) {
    return 'emulator: regular expressions see the two UTF-16 code units of a '
        'character outside the BMP (the emulator runs on Java; the evaluator '
        'matches whole characters)';
  }
  if (_mapParts.hasMatch(expression)) {
    return 'the order of the keys of a map that an expression built '
        '(map_set, map_merge, map_remove, map) is not specified: the '
        'emulator returns them as its hash map has them, the evaluator '
        'sorted';
  }
  if (expression.contains('join(') &&
      (expression.contains('Blob') || expression.contains('Field(b1)'))) {
    return 'emulator: join() with a bytes delimiter returns a string; the '
        'evaluator returns bytes, as the Android SDK';
  }
  return null;
}

/// Why the emulator fails with an error that is not INVALID_ARGUMENT (the
/// whole pipeline fails, also inside `if_error`) for [expression], or null
/// when that is not a known defect.
String? knownEmulatorFailure(String expression) {
  if (_splitOfConcat.hasMatch(expression)) {
    return 'emulator: split() with string_concat(), concat() or join() '
        'somewhere in its value or delimiter fails the pipeline with '
        'INTERNAL, whatever the documents are';
  }
  if (expression.contains('mod(') &&
      (expression.contains('Decimal128') ||
          expression.contains('Field(dec)'))) {
    return 'emulator: mod() of decimal128 numbers whose integer quotient has '
        'more than 34 digits fails the pipeline with INTERNAL; the evaluator '
        'returns the exact remainder';
  }
  if (expression.contains('round(') &&
      (expression.contains('Decimal128') ||
          expression.contains('Field(dec)'))) {
    return 'emulator: round(decimal128, places) of a value between -1 and 1 '
        'fails the pipeline with INTERNAL; the evaluator rounds it';
  }
  return null;
}

final RegExp _splitOfConcat = RegExp(
  r'split\(.*\b(string_concat|concat|join)\(',
);
final RegExp _mapParts = RegExp(r'map_(keys|values|entries)\(');
final RegExp _astral = RegExp('[\u{10000}-\u{10ffff}]', unicode: true);

class _Stats {
  int compared = 0;
  int rejected = 0;
  int unsupported = 0;
  final Map<String, int> known = <String, int>{};
  final List<String> unknown = <String>[];
  final Set<String> functionsSeen = <String>{};
}

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/pipeline_evaluation_property';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test(
    'every function agrees with the emulator on nulls, missing values, '
    'wrong types and errors in its arguments',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () async {
      final Firestore db = await IntegrationTestUtil.testEnterpriseFirestore();
      // ignore: invalid_use_of_internal_member
      final LocalEvaluation local = LocalEvaluation(db.modelDatabaseId);
      final _Stats stats = _Stats();
      final CollectionReference<Map<String, Object?>> collection = db
          .collection('pipeline-edge-${DateTime.now().microsecondsSinceEpoch}');
      final Map<String, Map<String, Object?>> documents =
          <String, Map<String, Object?>>{
            'd': <String, Object?>{'nul': null},
          };
      await collection.doc('d').set(documents['d']!);
      final List<Expression> expressions = edgeMatrix();
      for (int start = 0; start < expressions.length; start += 40) {
        await _compare(
          db,
          local,
          collection,
          documents,
          expressions.sublist(start, (start + 40).clamp(0, expressions.length)),
          0,
          stats,
        );
      }
      // ignore: avoid_print
      print(
        'compared ${stats.compared} results, ${stats.rejected} expressions '
        'rejected by the emulator before running; known differences: '
        '${stats.known}',
      );
      expect(
        stats.unknown,
        isEmpty,
        reason:
            '${stats.unknown.length} unexplained differences:\n'
            '${stats.unknown.take(400).join('\n')}',
      );
      expect(stats.compared, greaterThan(1000));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'the recorded emulator results of the fixed cases are current',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () async {
      final Firestore db = await IntegrationTestUtil.testEnterpriseFirestore();
      // The recorded references name the project and the document.
      expect(db.projectId, evaluationCasesProject);
      // ignore: invalid_use_of_internal_member
      final LocalEvaluation local = LocalEvaluation(db.modelDatabaseId);
      final DocumentReference<Map<String, Object?>> document = db.doc(
        evaluationCaseDocumentPath,
      );
      await document.set(evaluationCaseDocument);
      final List<Expression> expressions = evaluationCases();

      final List<String> lines = <String>[];
      for (int start = 0; start < expressions.length; start += 40) {
        final List<Expression> batch = expressions.sublist(
          start,
          (start + 40).clamp(0, expressions.length),
        );
        final Map<int, FirestoreErrorCode> failures =
            <int, FirestoreErrorCode>{};
        final Map<String, List<EvaluateResult?>> remote = await _remote(
          db,
          local,
          document.parent,
          batch,
          failures: failures,
        );
        for (int i = 0; i < batch.length; i++) {
          final EvaluateResult? result = remote[document.id]?[i];
          lines.add(
            jsonEncode(<String, String>{
              'expression': '${batch[i]}'.replaceAll('\n', ' '),
              'result': result != null
                  ? local.encodeResult(result)
                  : failures[i] == FirestoreErrorCode.invalidArgument
                  ? 'REJECTED'
                  : 'FAILED ${failures[i]}',
            }),
          );
        }
      }

      final File golden = File(evaluationCasesGolden);
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        golden.writeAsStringSync('${lines.join('\n')}\n');
        return;
      }
      expect(
        golden.existsSync(),
        isTrue,
        reason: 'Missing $evaluationCasesGolden. Run with UPDATE_GOLDEN=1.',
      );
      final List<String> recorded = golden.readAsLinesSync();
      expect(
        recorded.length,
        lines.length,
        reason: 'The list of cases changed: regenerate with UPDATE_GOLDEN=1',
      );
      final List<String> changed = <String>[
        for (int i = 0; i < lines.length; i++)
          if (lines[i] != recorded[i] &&
              !_sameRecordedResult(local, lines[i], recorded[i]))
            '${recorded[i]}\n    now ${lines[i]}',
      ];
      expect(
        changed,
        isEmpty,
        reason:
            'The emulator no longer returns what was recorded (or the '
            'cases changed). If intended, regenerate with UPDATE_GOLDEN=1 '
            'and review the diff.\n${changed.take(20).join('\n')}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'aggregate functions evaluate locally as aggregate() on the emulator',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () async {
      final Firestore db = await IntegrationTestUtil.testEnterpriseFirestore();
      // ignore: invalid_use_of_internal_member
      final LocalEvaluation local = LocalEvaluation(db.modelDatabaseId);
      final List<String> unknown = <String>[];
      int compared = 0;
      int rejected = 0;
      int failed = 0;

      final CollectionReference<Map<String, Object?>> empty = db.collection(
        'pipeline-agg-empty-${DateTime.now().microsecondsSinceEpoch}',
      );
      for (int round = 0; round < cases(4); round++) {
        final int seed = caseSeed(round);
        final Gen gen = Gen(seed);
        final CollectionReference<Map<String, Object?>> collection = db
            .collection(
              'pipeline-agg-$seed-${DateTime.now().microsecondsSinceEpoch}',
            );
        // The documents in the order of their field `o`: the aggregates that
        // depend on an order (first, last, array_agg) get sorted input.
        final int count = gen.between(0, 8);
        final Map<String, Map<String, Object?>> documents =
            <String, Map<String, Object?>>{
              for (int i = 0; i < count; i++)
                '${collection.path}/d$i': <String, Object?>{
                  ...gen.pipelineDocument(),
                  'o': i,
                },
            };
        final WriteBatch batch = db.batch();
        documents.forEach(
          (String path, Map<String, Object?> data) =>
              batch.set(db.doc(path), data),
        );
        await batch.commit();

        for (int i = 0; i < 40; i++) {
          final String name = gen.pick(aggregateFunctions);
          final AggregateFunction function = AggregateFunction(name, <Object?>[
            if (name != 'count' || gen.chance(70))
              gen.chance(50)
                  ? field(
                      gen.pick(const <String>[
                        'n1',
                        'n2',
                        'f1',
                        'f2',
                        'i32',
                        'dec',
                        's1',
                        't1',
                        'a1', //
                        'm1', 'ts1', 'v1', 'k1', 'nul', 'zz',
                      ]),
                    )
                  : gen.expression(
                      name == 'count_if' ? Kind.bool : Kind.any,
                      1,
                    ),
          ]);
          FirestoreErrorCode? failure;
          Future<EvaluateResult> remote(
            CollectionReference<Map<String, Object?>> source,
          ) async {
            try {
              final Map<String, Object?> data = (await _execute(
                db
                    .pipeline()
                    .collection(source.path)
                    .sort(<Ordering>[field('o').ascending()])
                    .aggregate(<AliasedAggregate>[function.as('r')]),
              )).single.data();
              return data.containsKey('r')
                  ? EvaluateValue(local.toModel(data['r']))
                  : EvaluateResult.unset;
            } on FirestoreError catch (e) {
              failure = e.code;
              return EvaluateResult.error;
            }
          }

          final EvaluateResult expected = await remote(collection);
          if (expected.isError &&
              failure != FirestoreErrorCode.invalidArgument &&
              knownEmulatorFailure('$function') != null) {
            // Not the error of an expression, which is INVALID_ARGUMENT.
            failed++;
            continue;
          }
          if (expected.isError && (await remote(empty)).isError) {
            // Rejected whatever the documents are.
            rejected++;
            continue;
          }
          final EvaluateResult actual = local.aggregate(function, documents);
          compared++;
          final model.FieldValue? a = actual.value;
          final model.FieldValue? e = expected.value;
          final bool same = a != null && e != null
              ? (name == 'array_agg_distinct'
                    ? sameElements(a, e)
                    : sameValue(a, e))
              : actual.isError == expected.isError && a == null && e == null;
          if (!same) {
            unknown.add(
              'seed $seed: $function\n'
              '    local  ${describeResult(actual).replaceAll('\n', ' ')}\n'
              '    remote ${describeResult(expected).replaceAll('\n', ' ')}\n'
              '    documents ${'${documents.values.toList()}'.replaceAll('\n', ' ')}',
            );
          }
        }
      }
      // ignore: avoid_print
      print(
        'compared $compared aggregates, $rejected rejected by the emulator '
        'before running, $failed known failures of the emulator',
      );
      expect(
        unknown,
        isEmpty,
        reason:
            '${unknown.length} unexplained differences:\n'
            '${unknown.take(40).join('\n')}',
      );
      expect(compared, greaterThan(100));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'expressions evaluate locally as select(expression) on the emulator',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () async {
      final Firestore db = await IntegrationTestUtil.testEnterpriseFirestore();
      // ignore: invalid_use_of_internal_member
      final LocalEvaluation local = LocalEvaluation(db.modelDatabaseId);
      final _Stats stats = _Stats();

      for (int round = 0; round < cases(4); round++) {
        final int seed = caseSeed(round);
        final Gen gen = Gen(seed);
        final CollectionReference<Map<String, Object?>> collection = db
            .collection(
              'pipeline-eval-$seed-${DateTime.now().microsecondsSinceEpoch}',
            );
        final Map<String, Map<String, Object?>> documents =
            <String, Map<String, Object?>>{
              for (int i = 0; i < 6; i++) 'd$i': gen.pipelineDocument(),
            };
        final WriteBatch batch = db.batch();
        documents.forEach(
          (String id, Map<String, Object?> data) =>
              batch.set(collection.doc(id), data),
        );
        await batch.commit();

        final List<Expression> expressions = <Expression>[
          for (int i = 0; i < 120; i++) gen.pipelineExpression(),
        ];
        for (int start = 0; start < expressions.length; start += 20) {
          await _compare(
            db,
            local,
            collection,
            documents,
            expressions.sublist(start, start + 20),
            seed,
            stats,
          );
        }
      }

      // ignore: avoid_print
      print(
        'compared ${stats.compared} results, ${stats.rejected} expressions '
        'rejected by the emulator before running, ${stats.unsupported} not '
        'supported locally; known differences: ${stats.known}',
      );
      expect(
        stats.unknown,
        isEmpty,
        reason:
            '${stats.unknown.length} unexplained differences:\n'
            '${stats.unknown.take(40).join('\n')}',
      );
      expect(stats.compared, greaterThan(1000));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Runs [pipeline] like [_remote] does: only INVALID_ARGUMENT is an answer.
Future<List<PipelineResult>> _execute(Pipeline pipeline) async {
  for (int attempt = 0; ; attempt++) {
    try {
      return (await pipeline.execute().timeout(
        const Duration(seconds: 30),
      )).results;
    } on FirestoreError catch (e) {
      if (e.code == FirestoreErrorCode.invalidArgument || attempt == 4) {
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

/// The remote results of [expressions] for every document: by document id,
/// one [EvaluateResult] per expression, or null for an expression the
/// emulator rejected before running the pipeline.
Future<Map<String, List<EvaluateResult?>>> _remote(
  Firestore db,
  LocalEvaluation local,
  CollectionReference<Map<String, Object?>> collection,
  List<Expression> expressions, {
  Map<int, FirestoreErrorCode>? failures,
}) async {
  Future<List<PipelineResult>> run(List<int> indexes) async {
    final Pipeline pipeline = db.pipeline().collection(collection.path).select(
      <Selectable>[
        field('__name__').documentId().as('id'),
        for (final int i in indexes) ...<Selectable>[
          expressions[i].isError().as('e$i'),
          expressions[i].ifError(_errorSentinel).as('v$i'),
        ],
      ],
    );
    return _execute(pipeline);
  }

  final Map<String, List<EvaluateResult?>> results =
      <String, List<EvaluateResult?>>{};
  void record(List<PipelineResult> rows, List<int> indexes) {
    for (final PipelineResult row in rows) {
      final Map<String, Object?> data = row.data();
      final List<EvaluateResult?> list = results.putIfAbsent(
        data['id']! as String,
        () => List<EvaluateResult?>.filled(expressions.length, null),
      );
      for (final int i in indexes) {
        if (data['e$i'] == true) {
          list[i] = EvaluateResult.error;
        } else if (!data.containsKey('v$i')) {
          list[i] = EvaluateResult.unset;
        } else {
          list[i] = EvaluateValue(local.toModel(data['v$i']));
        }
      }
    }
  }

  // An expression the emulator rejects fails the whole pipeline: halve the
  // batch until the rejected ones are alone.
  Future<void> runAll(List<int> indexes) async {
    try {
      record(await run(indexes), indexes);
    } on FirestoreError catch (e) {
      if (indexes.length > 1) {
        final int half = indexes.length ~/ 2;
        await runAll(indexes.sublist(0, half));
        await runAll(indexes.sublist(half));
      } else {
        // A single failing expression is left as null: rejected
        // (INVALID_ARGUMENT), or the emulator failed running it.
        failures?[indexes.single] = e.code;
      }
    }
  }

  await runAll(<int>[for (int i = 0; i < expressions.length; i++) i]);
  return results;
}

Future<void> _compare(
  Firestore db,
  LocalEvaluation local,
  CollectionReference<Map<String, Object?>> collection,
  Map<String, Map<String, Object?>> documents,
  List<Expression> expressions,
  int seed,
  _Stats stats,
) async {
  final Map<int, FirestoreErrorCode> failures = <int, FirestoreErrorCode>{};
  final Map<String, List<EvaluateResult?>> remote = await _remote(
    db,
    local,
    collection,
    expressions,
    failures: failures,
  );
  for (int i = 0; i < expressions.length; i++) {
    final Expression expression = expressions[i];
    bool rejected = false;
    final FirestoreErrorCode? failure = failures[i];
    if (failure != null && failure != FirestoreErrorCode.invalidArgument) {
      // Not an answer about the expression: the emulator itself failed.
      final String? reason = knownEmulatorFailure('$expression');
      if (reason != null) {
        stats.known[reason] = (stats.known[reason] ?? 0) + 1;
      } else {
        // Which documents it fails for, and what the evaluator makes of
        // them.
        final List<String> failing = <String>[];
        for (final MapEntry<String, Map<String, Object?>> document
            in documents.entries) {
          try {
            await _execute(
              db
                  .pipeline()
                  .documents(<DocumentReference<Map<String, Object?>>>[
                    collection.doc(document.key),
                  ])
                  .select(<Selectable>[expression.isError().as('e')]),
            );
          } on FirestoreError {
            String localText;
            try {
              localText = describeResult(
                local.evaluate(
                  expression,
                  '${collection.path}/${document.key}',
                  document.value,
                ),
              );
            } on UnsupportedExpression catch (e) {
              localText = 'unsupported: ${e.message}';
            }
            failing.add(
              '    local  ${localText.replaceAll('\n', ' ')}\n'
              '    document ${'${document.value}'.replaceAll('\n', ' ')}',
            );
          }
        }
        stats.unknown.add(
          'seed $seed: ${'$expression'.replaceAll('\n', ' ')}\n'
          '    the emulator fails with $failure for\n${failing.join('\n')}',
        );
      }
      continue;
    }
    for (final MapEntry<String, Map<String, Object?>> document
        in documents.entries) {
      final EvaluateResult? expected = remote[document.key]?[i];
      if (expected == null) {
        rejected = true;
        continue;
      }
      EvaluateResult actual;
      try {
        actual = local.evaluate(
          expression,
          '${collection.path}/${document.key}',
          document.value,
        );
      } on UnsupportedExpression {
        stats.unsupported++;
        continue;
      }
      stats.compared++;
      final model.FieldValue? a = actual.value;
      final model.FieldValue? e = expected.value;
      final bool same = a != null && e != null
          ? sameValue(a, e)
          : actual.isError == expected.isError &&
                actual.isUnset == expected.isUnset &&
                a == null &&
                e == null;
      if (same) {
        continue;
      }
      final String localText = describeResult(actual);
      final String remoteText = describeResult(expected);
      final String? reason = knownDifference(
        '$expression',
        '${document.value}',
        localText,
        remoteText,
      );
      if (reason != null) {
        stats.known[reason] = (stats.known[reason] ?? 0) + 1;
      } else {
        stats.unknown.add(
          'seed $seed: ${'$expression'.replaceAll('\n', ' ')}\n'
          '    local  ${localText.replaceAll('\n', ' ')}\n'
          '    remote ${remoteText.replaceAll('\n', ' ')}\n'
          '    document ${'${document.value}'.replaceAll('\n', ' ')}',
        );
      }
    }
    if (rejected) {
      stats.rejected++;
    }
  }
}

/// Whether two lines of the recorded results are the same expression with
/// the same result, up to the last bits of a double.
bool _sameRecordedResult(LocalEvaluation local, String a, String b) {
  final Map<String, Object?> x = jsonDecode(a) as Map<String, Object?>;
  final Map<String, Object?> y = jsonDecode(b) as Map<String, Object?>;
  if (x['expression'] != y['expression'] ||
      x['result'] == 'REJECTED' ||
      y['result'] == 'REJECTED') {
    return false;
  }
  final model.FieldValue? left = local
      .decodeResult(x['result']! as String)
      .value;
  final model.FieldValue? right = local
      .decodeResult(y['result']! as String)
      .value;
  return left != null && right != null && sameValue(left, right);
}
