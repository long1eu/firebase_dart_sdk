// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// The pipelines surface added to match the JS SDK's firestore-pipelines.api.md,
// against the Enterprise edition emulator (tool/start_enterprise_emulator.sh):
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//         dart test test/integration_enterprise/pipeline_surface_test.dart
//
// Covers pipelines in a read-only transaction, arraySum, log10, mapSet with
// several pairs and the explain options. The emulator (v1.22.0) does not
// support the rest, which is only checked for its encoding in
// test/unit/firebase/firestore/pipeline/pipeline_surface_test.dart:
// add_window_fields ("Unsupported stage"), search, document_matches and score
// ("does not exist", or an internal error for a search with another
// condition), and it ignores explain options. The last group records those
// answers, so that a newer emulator that supports them shows up as a failure.
// Everything is skipped, with a reason, when the variable is not set.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/pipeline_surface';

  final String? skip = IntegrationTestUtil.enterpriseEmulatorSkipReason;
  final TransactionOptions readOnly = TransactionOptions(readOnly: true);

  late Firestore firestore;
  late CollectionReference<Map<String, Object?>> collection;

  List<Map<String, Object?>> rows(PipelineSnapshot snapshot) =>
      snapshot.results.map((PipelineResult r) => r.data()).toList();

  Pipeline source() => firestore.pipeline().collection(collection);

  Matcher failsWith(FirestoreErrorCode code, [String? message]) => throwsA(
    isA<FirestoreError>()
        .having((FirestoreError e) => e.code, 'code', code)
        .having(
          (FirestoreError e) => e.message,
          'message',
          message == null ? anything : contains(message),
        ),
  );

  group('pipelines surface', () {
    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      collection = firestore.collection('surface_${autoId()}');
      await collection.document('a').set(<String, Object?>{
        'n': 1,
        'region': 'eu',
        'scores': <int>[1, 5, 9],
        'm': <String, Object?>{'x': 1},
      });
      await collection.document('b').set(<String, Object?>{
        'n': 2,
        'region': 'us',
        'scores': <int>[2],
        'm': <String, Object?>{},
      });
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await IntegrationTestUtil.tearDown();
    });

    group('in a read-only transaction', () {
      test('every pipeline reads the snapshot of the transaction', () async {
        final List<List<Object?>> seen = await firestore
            .runTransaction<List<List<Object?>>>((
              Transaction transaction,
            ) async {
              List<Object?> ns(PipelineSnapshot s) =>
                  s.results.map((PipelineResult r) => r.get('n')).toList();
              final Pipeline sorted = source().sort(<Ordering>[
                field('n').ascending(),
              ]);

              final PipelineSnapshot before = await transaction.execute(sorted);
              // Another writer changes the collection meanwhile.
              await collection.document('c').set(<String, Object?>{'n': 3});
              await collection.document('a').delete();
              final PipelineSnapshot after = await transaction.execute(sorted);
              final PipelineSnapshot count = await transaction.execute(
                source().aggregate(<AliasedAggregate>[countAll().as('count')]),
              );
              expect(before.executionTime, isNotNull);
              expect(before.results.first.ref!.id, 'a');
              return <List<Object?>>[ns(before), ns(after), rows(count)];
            }, options: readOnly);

        expect(seen, <List<Object?>>[
          <Object?>[1, 2],
          <Object?>[1, 2],
          <Object?>[
            <String, Object?>{'count': 2},
          ],
        ]);
        // Outside of the transaction the writes are there.
        expect(
          (await source().sort(<Ordering>[
            field('n').ascending(),
          ]).execute()).results.map((PipelineResult r) => r.get('n')),
          <Object?>[2, 3],
        );
      }, skip: skip);

      test('mixes with document reads and queries', () async {
        await firestore.runTransaction<void>((Transaction transaction) async {
          final DocumentSnapshot<Map<String, Object?>> a = await transaction
              .get(collection.document('a'));
          final PipelineSnapshot snapshot = await transaction.execute(
            source().where(field('region').equal('eu')),
          );
          expect(snapshot.results.single.data(), a.data);
          final QuerySnapshot<Map<String, Object?>> query = await transaction
              .getQuery(collection.where('region', isEqualTo: 'eu'));
          expect(query.docs.single.id, snapshot.results.single.id);
        }, options: readOnly);
      }, skip: skip);

      test('write stages are rejected and nothing is written', () async {
        await expectLater(
          firestore.runTransaction<void>(
            (Transaction transaction) => transaction.execute(source().delete()),
            options: readOnly,
          ),
          failsWith(FirestoreErrorCode.invalidArgument, 'delete'),
        );
        expect(
          (await source().execute()).results.map((PipelineResult r) => r.id),
          unorderedEquals(<String>['a', 'b']),
        );
      }, skip: skip);

      test('a read-write transaction rejects pipelines', () async {
        await expectLater(
          firestore.runTransaction<void>(
            (Transaction transaction) => transaction.execute(source()),
          ),
          failsWith(FirestoreErrorCode.invalidArgument, 'read-only'),
        );
      }, skip: skip);
    });

    group('functions', () {
      test('arraySum, log10 and mapSet with several pairs', () async {
        final PipelineSnapshot snapshot = await source()
            .sort(<Ordering>[field('n').ascending()])
            .select(<Object>[
              field('scores').arraySum().as('sum'),
              field('n').multiply(100).log10().as('log'),
              field('m').mapSet('y', 2, <Object?>['z', field('n')]).as('m'),
            ])
            .execute();
        expect(rows(snapshot), <Map<String, Object?>>[
          <String, Object?>{
            'sum': 15,
            'log': 2.0,
            'm': <String, Object?>{'x': 1, 'y': 2, 'z': 1},
          },
          <String, Object?>{
            'sum': 2,
            'log': closeTo(2.30103, 1e-5),
            'm': <String, Object?>{'y': 2, 'z': 2},
          },
        ]);
      }, skip: skip);

      test('pipelineResultEqual compares two reads', () async {
        final Pipeline pipeline = source().sort(<Ordering>[
          field('n').ascending(),
        ]);
        final List<PipelineResult> first = (await pipeline.execute()).results;
        final List<PipelineResult> second = (await pipeline.execute()).results;
        expect(pipelineResultEqual(first[0], second[0]), isTrue);
        expect(pipelineResultEqual(first[0], second[1]), isFalse);
      }, skip: skip);
    });

    group('explain options', () {
      test('are accepted; the emulator runs the pipeline and explains '
          'nothing', () async {
        for (final PipelineExplainMode mode in PipelineExplainMode.values) {
          final PipelineSnapshot snapshot = await source()
              .sort(<Ordering>[field('n').ascending()])
              .execute(
                explainOptions: PipelineExplainOptions(
                  mode: mode,
                  outputFormat: PipelineExplainOutputFormat.text,
                ),
              );
          // A backend that explains would return no results for `explain`
          // and an explanation for `explain` and `analyze`.
          expect(snapshot.results, hasLength(2), reason: mode.name);
          expect(snapshot.explainStats, isNull, reason: mode.name);
        }
      }, skip: skip);
    });

    group('what the emulator does not support', () {
      test('add_window_fields is an unsupported stage', () async {
        await expectLater(
          source().addWindowFields(
            WindowSpec(sort: <Ordering>[field('n').ascending()]),
            <Object>[rank().as('rank'), field('n').sum().as('total')],
          ).execute(),
          failsWith(FirestoreErrorCode.invalidArgument, 'add_window_fields'),
        );
      }, skip: skip);

      test('search, document_matches and score do not exist', () async {
        await expectLater(
          source().search('waffles').execute(),
          failsWith(FirestoreErrorCode.invalidArgument, 'document_matches'),
        );
        await expectLater(
          source().select(<Object>[score().as('s')]).execute(),
          failsWith(FirestoreErrorCode.invalidArgument, 'score'),
        );
        await expectLater(
          source().search(field('n').greaterThan(0)).execute(),
          failsWith(FirestoreErrorCode.internal),
        );
      }, skip: skip);
    });
  });
}
