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

// Ported from the Android SDK:
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/PipelineWindowTest.java
//
// The cases keep their Java names; android_pipeline_test_util.dart has the
// functions they call. They run against the Enterprise edition emulator of
// FIRESTORE_ENTERPRISE_EMULATOR_HOST (tool/start_enterprise_emulator.sh);
// without it they are skipped.
//
// The Enterprise edition emulator (v1.22.0) does not support the
// add_window_fields stage: it fails every pipeline with it with
// INVALID_ARGUMENT ("Unsupported stage: add_window_fields"). The cases
// record that answer: where the pipeline fails with it the case passes,
// where it runs (a backend with window functions) Android's checks apply.
// The cases that expect a server error check the emulator's.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables, unawaited_futures
// ignore_for_file: unnecessary_await_in_return, unnecessary_parenthesis
// ignore_for_file: unnecessary_statements

import 'package:test/test.dart' show expect, group, isA, setUp, tearDown, test;

import '../util/integration_test_util.dart';
import 'android_pipeline_test_util.dart';

/// The sales of Android's windowTestDocs(): partitions by product and region
/// overlap, salesPrice has ties, and date increases with an 11 day gap
/// before the last sale.
final Map<String, Map<String, Object?>> windowTestDocs =
    <String, Map<String, Object?>>{
      // 2026-07-01T12:00:00Z
      "sale1": <String, Object?>{
        "product": "phone",
        "region": "east",
        "salesPrice": 12,
        "quantity": 1,
        "date": Timestamp(1782907200, 0),
      },
      // 2026-07-02T12:00:00Z
      "sale2": <String, Object?>{
        "product": "phone",
        "region": "west",
        "salesPrice": 30,
        "quantity": 2,
        "date": Timestamp(1782993600, 0),
      },
      // 2026-07-02T18:00:00Z
      "sale3": <String, Object?>{
        "product": "tablet",
        "region": "east",
        "salesPrice": 30,
        "quantity": 3,
        "date": Timestamp(1783015200, 0),
      },
      // 2026-07-04T12:00:00Z
      "sale4": <String, Object?>{
        "product": "tablet",
        "region": "west",
        "salesPrice": 60,
        "quantity": 4,
        "date": Timestamp(1783166400, 0),
      },
      // 2026-07-15T12:00:00Z
      "sale5": <String, Object?>{
        "product": "tablet",
        "region": "east",
        "salesPrice": 60,
        "quantity": 5,
        "date": Timestamp(1784116800, 0),
      },
    };

Future<CollectionReference<Map<String, Object?>>> windowTestCollection() =>
    testCollectionWithDocs(windowTestDocs);

/// The emulator's answer to a pipeline with add_window_fields.
Future<void> expectEmulatorRejectsWindows(Future<Object?> execute) async {
  final Object error = await assertThrows(null, () => execute);
  expect(error, isA<FirestoreError>());
  expect((error as FirestoreError).code, FirestoreErrorCode.invalidArgument);
  assertThat("$error").contains("add_window_fields");
}

/// Whether [execute] fails with the emulator's answer to add_window_fields.
/// False when the pipeline runs (a backend with window functions); any
/// other failure is rethrown.
Future<bool> emulatorRejectsWindows(Future<PipelineSnapshot> execute) async {
  try {
    await execute;
    return false;
  } on FirestoreError catch (e) {
    if (e.code == FirestoreErrorCode.invalidArgument &&
        "$e".contains("Unsupported stage: add_window_fields")) {
      return true;
    }
    rethrow;
  }
}

/// Android's expectResults(results, expected): the results in order,
/// compared as whole documents. On the emulator, which rejects the stage,
/// checks that answer instead.
Future<void> expectWindowResults(
  Future<PipelineSnapshot> execute,
  List<Object?> expected,
) async {
  if (await emulatorRejectsWindows(execute)) {
    return;
  }
  final List<PipelineResult> results = (await execute).results;
  assertThat(results).hasSize(expected.length);
  for (int i = 0; i < expected.length; i++) {
    assertThat(results[i].data()).isEqualTo(expected[i]);
  }
}

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/android_pipeline_window';
  late Firestore firestore;

  group('PipelineWindowTest', skip: IntegrationTestUtil.enterpriseEmulatorSkipReason, () {
    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
    });

    tearDown(() async {
      await IntegrationTestUtil.tearDown();
    });

    test(
      'testWindowFieldsComputesRunningAggregatesOverADocumentsFramePartitionedByAFieldAndAnExpressionAndSortedByMultipleKeys',
      () async {
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                partition: <Object>["product", ex("region").toUpper()],
                sort: <Ordering>[
                  ex("date").ascending(),
                  ex("salesPrice").descending(),
                ],
                frame: WindowFrame.documents(
                  preceding: WindowFrame.unbounded,
                  following: constant(0),
                ),
              ),
              <Object>[
                ex("salesPrice").sum().as("stats.runningTotal"),
                ex("quantity").arrayAgg().as("quantities"),
                countAll().as("count"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "stats", "quantities", "count"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{
            "product": "phone",
            "stats": <String, Object?>{"runningTotal": 12},
            "quantities": <Object?>[1],
            "count": 1,
          },
          <String, Object?>{
            "product": "phone",
            "stats": <String, Object?>{"runningTotal": 30},
            "quantities": <Object?>[2],
            "count": 1,
          },
          <String, Object?>{
            "product": "tablet",
            "stats": <String, Object?>{"runningTotal": 30},
            "quantities": <Object?>[3],
            "count": 1,
          },
          <String, Object?>{
            "product": "tablet",
            "stats": <String, Object?>{"runningTotal": 60},
            "quantities": <Object?>[4],
            "count": 1,
          },
          <String, Object?>{
            "product": "tablet",
            "stats": <String, Object?>{"runningTotal": 90},
            "quantities": <Object?>[3, 5],
            "count": 2,
          },
        ]);
      },
    );

    test('testWindowFieldsCountsDocumentsInATimeUnitRangeFrame', () async {
      var salesCol = (await windowTestCollection());
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection(salesCol.path)
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.range(
                preceding: 12,
                following: WindowFrame.current,
                unit: "hour",
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
      ]);
    });

    test(
      'testWindowFieldsComputesLookAheadAndNearbyAggregatesWithAccumulatorLevelFrames',
      () async {
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(sort: <Ordering>[ex("quantity").ascending()]),
              <Object>[
                ex("salesPrice")
                    .average()
                    .over(WindowFrame.documents(preceding: -1, following: 2))
                    .as("lookAheadAverage"),
                ex("salesPrice")
                    .sum()
                    .over(WindowFrame.range(preceding: 1.5, following: 0.5))
                    .as("nearbyTotal"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "lookAheadAverage", "nearbyTotal"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{
            "product": "phone",
            "lookAheadAverage": 30.0,
            "nearbyTotal": 12,
          },
          <String, Object?>{
            "product": "phone",
            "lookAheadAverage": 45.0,
            "nearbyTotal": 42,
          },
          <String, Object?>{
            "product": "tablet",
            "lookAheadAverage": 60.0,
            "nearbyTotal": 60,
          },
          <String, Object?>{
            "product": "tablet",
            "lookAheadAverage": 60.0,
            "nearbyTotal": 90,
          },
          <String, Object?>{
            "product": "tablet",
            "lookAheadAverage": null,
            "nearbyTotal": 120,
          },
        ]);
      },
    );

    test('testWindowFieldsComputesRank', () async {
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(sort: <Ordering>[ex("salesPrice").ascending()]),
            <Object>[rank().as("priceRank")],
          )
          .sort([ex("date").ascending()])
          .select(["salesPrice", "priceRank"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"salesPrice": 12, "priceRank": 1},
        <String, Object?>{"salesPrice": 30, "priceRank": 2},
        <String, Object?>{"salesPrice": 30, "priceRank": 2},
        <String, Object?>{"salesPrice": 60, "priceRank": 4},
        <String, Object?>{"salesPrice": 60, "priceRank": 4},
      ]);
    });

    test('testWindowFieldsRejectsARangeFrameWithoutASort', () async {
      var salesCol = (await windowTestCollection());
      // Android expects a server error that mentions "range"; the emulator
      // rejects the stage first (EMULATOR_ANSWER).
      await expectEmulatorRejectsWindows(
        firestore.pipeline().collection(salesCol).addWindowFields(
          WindowSpec(
            frame: WindowFrame.range(
              preceding: WindowFrame.unbounded,
              following: WindowFrame.current,
            ),
          ),
          <Object>[ex("quantity").count().as("windowCount")],
        ).execute(),
      );
    });

    test('testWindowFieldsRejectsDuplicateAliases', () async {
      dynamic exception = await assertThrows(
        null,
        () => firestore
            .pipeline()
            .collection(firestore.collection("sales"))
            .addWindowFields(
              WindowSpec(partition: <Object>["product"]),
              <Object>[
                ex("salesPrice").sum().as("total"),
                ex("salesPrice").average().as("total"),
              ],
            ),
      );
      // Android: "Duplicate alias: 'total'".
      assertThat("$exception").contains("Duplicate alias or field 'total'");
    });

    test('testWindowFieldsEmptySpecIsASingleGlobalWindow', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(), <Object>[
            ex("quantity").count().as("windowCount"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 5},
        <String, Object?>{"product": "phone", "windowCount": 5},
        <String, Object?>{"product": "tablet", "windowCount": 5},
        <String, Object?>{"product": "tablet", "windowCount": 5},
        <String, Object?>{"product": "tablet", "windowCount": 5},
      ]);
    });

    test('testWindowFieldsOmittedSpecIsASingleGlobalWindow', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      // The no-window overload is sugar for `WindowSpec()`. Dart has no such
      // overload: the window is WindowSpec().
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(), <Object>[
            ex("quantity").count().as("windowCount"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 5},
        <String, Object?>{"product": "phone", "windowCount": 5},
        <String, Object?>{"product": "tablet", "windowCount": 5},
        <String, Object?>{"product": "tablet", "windowCount": 5},
        <String, Object?>{"product": "tablet", "windowCount": 5},
      ]);
    });

    test('testWindowFieldsPartitionsBySingleFieldName', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(partition: <Object>["product"]), <Object>[
            ex("quantity").count().as("windowCount"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
      ]);
    });

    test('testWindowFieldsPartitionsByMultipleFields', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(partition: <Object>["product", "region"]),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "region", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "region": "east",
          "windowCount": 1,
        },
        <String, Object?>{
          "product": "phone",
          "region": "west",
          "windowCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "region": "east",
          "windowCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "region": "west",
          "windowCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "region": "east",
          "windowCount": 2,
        },
      ]);
    });

    test('testWindowFieldsPartitionsByExpression', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(partition: <Object>[ex("region").toUpper()]),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["region", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"region": "east", "windowCount": 3},
        <String, Object?>{"region": "west", "windowCount": 2},
        <String, Object?>{"region": "east", "windowCount": 3},
        <String, Object?>{"region": "west", "windowCount": 2},
        <String, Object?>{"region": "east", "windowCount": 3},
      ]);
    });

    test('testWindowFieldsRunningCountWithTheDefaultFrame', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      // The implicit default frame when `sort` is specified is `range(UNBOUNDED, CURRENT)`.
      // `quantity` is 1..5 in the same order as `date`, and has no ties, so the running count is
      // 1..5.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(sort: <Ordering>[ex("quantity").ascending()]),
            <Object>[ex("quantity").count().as("runningCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "runningCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "runningCount": 1},
        <String, Object?>{"product": "phone", "runningCount": 2},
        <String, Object?>{"product": "tablet", "runningCount": 3},
        <String, Object?>{"product": "tablet", "runningCount": 4},
        <String, Object?>{"product": "tablet", "runningCount": 5},
      ]);
    });

    test('testWindowFieldsRunningCountWithinEachPartition', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("quantity").ascending()],
            ),
            <Object>[ex("quantity").count().as("runningCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "runningCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "runningCount": 1},
        <String, Object?>{"product": "phone", "runningCount": 2},
        <String, Object?>{"product": "tablet", "runningCount": 1},
        <String, Object?>{"product": "tablet", "runningCount": 2},
        <String, Object?>{"product": "tablet", "runningCount": 3},
      ]);
    });

    test('testWindowFieldsHonorsADescendingSort', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").descending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("runningCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "runningCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "runningCount": 5},
        <String, Object?>{"product": "phone", "runningCount": 4},
        <String, Object?>{"product": "tablet", "runningCount": 3},
        <String, Object?>{"product": "tablet", "runningCount": 2},
        <String, Object?>{"product": "tablet", "runningCount": 1},
      ]);
    });

    test('testWindowFieldsHonorsMultipleSortOrderings', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[
                ex("product").ascending(),
                ex("date").ascending(),
              ],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("runningCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "runningCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "runningCount": 1},
        <String, Object?>{"product": "phone", "runningCount": 2},
        <String, Object?>{"product": "tablet", "runningCount": 3},
        <String, Object?>{"product": "tablet", "runningCount": 4},
        <String, Object?>{"product": "tablet", "runningCount": 5},
      ]);
    });

    test('testWindowFieldsDocumentsUnboundedToCurrent', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 4},
        <String, Object?>{"product": "tablet", "windowCount": 5},
      ]);
    });

    test('testWindowFieldsDocumentsUnboundedToCurrentExcludesTiedPeers', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      // In a `documents` frame, CURRENT cuts off strictly at the current document's position (ties
      // are not included), so tied `salesPrice` values (30, 30 and 60, 60) receive distinct
      // sequential counts 1..5 rather than peer-grouped counts.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("salesPrice").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("windowCount").ascending()])
          .select(["salesPrice", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"salesPrice": 12, "windowCount": 1},
        <String, Object?>{"salesPrice": 30, "windowCount": 2},
        <String, Object?>{"salesPrice": 30, "windowCount": 3},
        <String, Object?>{"salesPrice": 60, "windowCount": 4},
        <String, Object?>{"salesPrice": 60, "windowCount": 5},
      ]);
    });

    test('testWindowFieldsDocumentsUnboundedToUnbounded', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.unbounded,
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
      ]);
    });

    test('testWindowFieldsDocumentsCurrentToCurrent', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.current,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
      ]);
    });

    test('testWindowFieldsRangeCurrentToCurrentCountsTiedPeers', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("salesPrice").ascending()],
              frame: WindowFrame.range(
                preceding: WindowFrame.current,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("samePriceCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "salesPrice", "samePriceCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "salesPrice": 12,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "phone",
          "salesPrice": 30,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 30,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 60,
          "samePriceCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 60,
          "samePriceCount": 2,
        },
      ]);
    });

    test('testWindowFieldsRangeZeroOffsetCountsTiedPeers', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("salesPrice").ascending()],
              frame: WindowFrame.range(preceding: 0, following: 0),
            ),
            <Object>[ex("quantity").count().as("samePriceCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "salesPrice", "samePriceCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "salesPrice": 12,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "phone",
          "salesPrice": 30,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 30,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 60,
          "samePriceCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 60,
          "samePriceCount": 2,
        },
      ]);
    });

    test('testWindowFieldsRangeUnboundedToCurrentIncludesTiedPeers', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("salesPrice").ascending()],
              frame: WindowFrame.range(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("cumulativeCount")],
          )
          .sort([ex("date").ascending()])
          .select(["salesPrice", "cumulativeCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"salesPrice": 12, "cumulativeCount": 1},
        <String, Object?>{"salesPrice": 30, "cumulativeCount": 3},
        <String, Object?>{"salesPrice": 30, "cumulativeCount": 3},
        <String, Object?>{"salesPrice": 60, "cumulativeCount": 5},
        <String, Object?>{"salesPrice": 60, "cumulativeCount": 5},
      ]);
    });

    test(
      'testWindowFieldsRangeUnboundedToZeroOffsetIncludesTiedPeers',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("salesPrice").ascending()],
                frame: WindowFrame.range(
                  preceding: WindowFrame.unbounded,
                  following: 0,
                ),
              ),
              <Object>[ex("quantity").count().as("cumulativeCount")],
            )
            .sort([ex("date").ascending()])
            .select(["salesPrice", "cumulativeCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"salesPrice": 12, "cumulativeCount": 1},
          <String, Object?>{"salesPrice": 30, "cumulativeCount": 3},
          <String, Object?>{"salesPrice": 30, "cumulativeCount": 3},
          <String, Object?>{"salesPrice": 60, "cumulativeCount": 5},
          <String, Object?>{"salesPrice": 60, "cumulativeCount": 5},
        ]);
      },
    );

    test('testWindowFieldsRangeUnboundedToCurrentWithStringSortKey', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("product").ascending()],
              frame: WindowFrame.range(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("quantity").count().as("cumulativeCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "cumulativeCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "cumulativeCount": 2},
        <String, Object?>{"product": "phone", "cumulativeCount": 2},
        <String, Object?>{"product": "tablet", "cumulativeCount": 5},
        <String, Object?>{"product": "tablet", "cumulativeCount": 5},
        <String, Object?>{"product": "tablet", "cumulativeCount": 5},
      ]);
    });

    test(
      'testWindowFieldsRangeUnboundedToCurrentWithMultipleSortOrderings',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[
                  ex("product").ascending(),
                  ex("region").ascending(),
                ],
                frame: WindowFrame.range(
                  preceding: WindowFrame.unbounded,
                  following: WindowFrame.current,
                ),
              ),
              <Object>[ex("quantity").count().as("cumulativeCount")],
            )
            .sort([ex("date").ascending()])
            .select(["product", "region", "cumulativeCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{
            "product": "phone",
            "region": "east",
            "cumulativeCount": 1,
          },
          <String, Object?>{
            "product": "phone",
            "region": "west",
            "cumulativeCount": 2,
          },
          <String, Object?>{
            "product": "tablet",
            "region": "east",
            "cumulativeCount": 4,
          },
          <String, Object?>{
            "product": "tablet",
            "region": "west",
            "cumulativeCount": 5,
          },
          <String, Object?>{
            "product": "tablet",
            "region": "east",
            "cumulativeCount": 4,
          },
        ]);
      },
    );

    test('testWindowFieldsRangeUnboundedToUnbounded', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("salesPrice").ascending()],
              frame: WindowFrame.range(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.unbounded,
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
      ]);
    });

    test('testWindowFieldsAppliesTheTimeUnitToARangeFrameOffset', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.range(
                preceding: 12,
                following: WindowFrame.current,
                unit: "hour",
              ),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
      ]);
    });

    test('testWindowFieldsEvaluatesEachAccumulatorOverItsOwnFrame', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("date").ascending()],
            ),
            <Object>[
              ex("quantity")
                  .count()
                  .over(
                    WindowFrame.documents(
                      preceding: WindowFrame.unbounded,
                      following: WindowFrame.current,
                    ),
                  )
                  .as("runningCount"),
              ex("quantity")
                  .count()
                  .over(
                    WindowFrame.documents(
                      preceding: WindowFrame.unbounded,
                      following: WindowFrame.unbounded,
                    ),
                  )
                  .as("partitionCount"),
            ],
          )
          .sort([ex("date").ascending()])
          .select(["product", "runningCount", "partitionCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "runningCount": 1,
          "partitionCount": 2,
        },
        <String, Object?>{
          "product": "phone",
          "runningCount": 2,
          "partitionCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "runningCount": 1,
          "partitionCount": 3,
        },
        <String, Object?>{
          "product": "tablet",
          "runningCount": 2,
          "partitionCount": 3,
        },
        <String, Object?>{
          "product": "tablet",
          "runningCount": 3,
          "partitionCount": 3,
        },
      ]);
    });

    test('testWindowFieldsSupportsARangeFrameInOver', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("salesPrice").ascending()],
            ),
            <Object>[
              ex("quantity")
                  .count()
                  .over(WindowFrame.range(preceding: 0, following: 0))
                  .as("samePriceCount"),
            ],
          )
          .sort([ex("date").ascending()])
          .select(["product", "salesPrice", "samePriceCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "salesPrice": 12,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "phone",
          "salesPrice": 30,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 30,
          "samePriceCount": 1,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 60,
          "samePriceCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "salesPrice": 60,
          "samePriceCount": 2,
        },
      ]);
    });

    test(
      'testWindowFieldsSupportsMultipleOutputFieldsInASingleStage',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(partition: <Object>["product"]),
              <Object>[
                ex("quantity").count().as("productCount"),
                ex("quantity").count().as("productCountCopy"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "productCount", "productCountCopy"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{
            "product": "phone",
            "productCount": 2,
            "productCountCopy": 2,
          },
          <String, Object?>{
            "product": "phone",
            "productCount": 2,
            "productCountCopy": 2,
          },
          <String, Object?>{
            "product": "tablet",
            "productCount": 3,
            "productCountCopy": 3,
          },
          <String, Object?>{
            "product": "tablet",
            "productCount": 3,
            "productCountCopy": 3,
          },
          <String, Object?>{
            "product": "tablet",
            "productCount": 3,
            "productCountCopy": 3,
          },
        ]);
      },
    );

    test('testWindowFieldsSupportsNestedOutputFieldPaths', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(partition: <Object>["product"]), <Object>[
            ex("quantity").count().as("stats.productCount"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "stats"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "stats": <String, Object?>{"productCount": 2},
        },
        <String, Object?>{
          "product": "phone",
          "stats": <String, Object?>{"productCount": 2},
        },
        <String, Object?>{
          "product": "tablet",
          "stats": <String, Object?>{"productCount": 3},
        },
        <String, Object?>{
          "product": "tablet",
          "stats": <String, Object?>{"productCount": 3},
        },
        <String, Object?>{
          "product": "tablet",
          "stats": <String, Object?>{"productCount": 3},
        },
      ]);
    });

    test('testWindowFieldsSupportsChainingMultipleStages', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(partition: <Object>["product"]), <Object>[
            ex("quantity").count().as("productCount"),
          ])
          .addWindowFields(WindowSpec(partition: <Object>["region"]), <Object>[
            ex("quantity").count().as("regionCount"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "region", "productCount", "regionCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "region": "east",
          "productCount": 2,
          "regionCount": 3,
        },
        <String, Object?>{
          "product": "phone",
          "region": "west",
          "productCount": 2,
          "regionCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "region": "east",
          "productCount": 3,
          "regionCount": 3,
        },
        <String, Object?>{
          "product": "tablet",
          "region": "west",
          "productCount": 3,
          "regionCount": 2,
        },
        <String, Object?>{
          "product": "tablet",
          "region": "east",
          "productCount": 3,
          "regionCount": 3,
        },
      ]);
    });

    test(
      'testWindowFieldsSupportsFilteringOnAWindowFieldInALaterStage',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(partition: <Object>["product"]),
              <Object>[ex("quantity").count().as("productCount")],
            )
            .where(field("productCount").greaterThan(2))
            .sort([ex("date").ascending()])
            .select(["product", "productCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"product": "tablet", "productCount": 3},
          <String, Object?>{"product": "tablet", "productCount": 3},
          <String, Object?>{"product": "tablet", "productCount": 3},
        ]);
      },
    );

    test(
      'testWindowFieldsSupportsSortingOnAWindowFieldInALaterStage',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(partition: <Object>["product"]),
              <Object>[ex("quantity").count().as("productCount")],
            )
            .sort([ex("productCount").ascending(), ex("date").ascending()])
            .select(["product", "productCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"product": "phone", "productCount": 2},
          <String, Object?>{"product": "phone", "productCount": 2},
          <String, Object?>{"product": "tablet", "productCount": 3},
          <String, Object?>{"product": "tablet", "productCount": 3},
          <String, Object?>{"product": "tablet", "productCount": 3},
        ]);
      },
    );

    test('testWindowFieldsRejectsMixingStageAndAccumulatorFraming', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      var salesCol = (await windowTestCollection());
      // Android expects a server error; the emulator rejects the stage first
      // (EMULATOR_ANSWER).
      await expectEmulatorRejectsWindows(
        firestore.pipeline().collection(salesCol).addWindowFields(
          WindowSpec(
            sort: <Ordering>[ex("date").ascending()],
            frame: WindowFrame.documents(
              preceding: WindowFrame.unbounded,
              following: WindowFrame.current,
            ),
          ),
          <Object>[
            ex("quantity")
                .count()
                .over(
                  WindowFrame.documents(
                    preceding: WindowFrame.unbounded,
                    following: WindowFrame.unbounded,
                  ),
                )
                .as("windowCount"),
          ],
        ).execute(),
      );
    });

    test(
      'testWindowFieldsEvaluatesAccumulatorsWithoutOverUsingTheDefaultFrameWhenOthersUseOver',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(sort: <Ordering>[ex("date").ascending()]),
              <Object>[
                ex("quantity")
                    .count()
                    .over(WindowFrame.documents(preceding: 0, following: 0))
                    .as("framed"),
                ex("quantity").count().as("unframed"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "framed", "unframed"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"product": "phone", "framed": 1, "unframed": 1},
          <String, Object?>{"product": "phone", "framed": 1, "unframed": 2},
          <String, Object?>{"product": "tablet", "framed": 1, "unframed": 3},
          <String, Object?>{"product": "tablet", "framed": 1, "unframed": 4},
          <String, Object?>{"product": "tablet", "framed": 1, "unframed": 5},
        ]);
      },
    );

    test(
      'testWindowFieldsRejectsAPartitionSuppliedToAnAccumulatorLevelOver',
      () {},
      skip:
          'Dart\'s over() takes a WindowFrame, which cannot hold a partition: '
          'the case cannot be written.',
    );

    test('testWindowFieldsComputesSumAverageMinimumAndMaximum', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(partition: <Object>["product"]), <Object>[
            ex("salesPrice").sum().as("total"),
            ex("salesPrice").average().as("averagePrice"),
            ex("salesPrice").minimum().as("minimumPrice"),
            ex("salesPrice").maximum().as("maximumPrice"),
          ])
          .sort([ex("date").ascending()])
          .select([
            "product",
            "total",
            "averagePrice",
            "minimumPrice",
            "maximumPrice",
          ])
          .execute();
      if (await emulatorRejectsWindows(execute)) {
        return;
      }
      var results = (await execute).results;
      assertThat(results).hasSize(5);

      assertThat(results[0].data()["total"]).isEqualTo(42);
      assertThat(results[0].data()["averagePrice"]).isEqualTo(21.0);
      assertThat(results[0].data()["minimumPrice"]).isEqualTo(12);
      assertThat(results[0].data()["maximumPrice"]).isEqualTo(30);

      assertThat(results[2].data()["total"]).isEqualTo(150);
      assertThat(results[2].data()["averagePrice"]).isEqualTo(50.0);
      assertThat(results[2].data()["minimumPrice"]).isEqualTo(30);
      assertThat(results[2].data()["maximumPrice"]).isEqualTo(60);
    });

    test(
      'testWindowFieldsComputesCountIf',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(partition: <Object>["product"]),
              <Object>[
                field(
                  "salesPrice",
                ).greaterThan(20).countIf().as("expensiveCount"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "expensiveCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"product": "phone", "expensiveCount": 1},
          <String, Object?>{"product": "phone", "expensiveCount": 1},
          <String, Object?>{"product": "tablet", "expensiveCount": 3},
          <String, Object?>{"product": "tablet", "expensiveCount": 3},
          <String, Object?>{"product": "tablet", "expensiveCount": 3},
        ]);
      },
      skip:
          "Pending backend support for countIf and countDistinct in addWindowFields",
    );

    test(
      'testWindowFieldsComputesCountDistinct',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(partition: <Object>["product"]),
              <Object>[
                ex("salesPrice").countDistinct().as("distinctPriceCount"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "distinctPriceCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"product": "phone", "distinctPriceCount": 2},
          <String, Object?>{"product": "phone", "distinctPriceCount": 2},
          <String, Object?>{"product": "tablet", "distinctPriceCount": 2},
          <String, Object?>{"product": "tablet", "distinctPriceCount": 2},
          <String, Object?>{"product": "tablet", "distinctPriceCount": 2},
        ]);
      },
      skip:
          "Pending backend support for countIf and countDistinct in addWindowFields",
    );

    test('testWindowFieldsAggregatesOverAComputedExpression', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(partition: <Object>["product"]), <Object>[
            ex(
              ex(field("salesPrice")).multiply(field("quantity")),
            ).sum().as("totalRevenue"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "totalRevenue"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "totalRevenue": 72},
        <String, Object?>{"product": "phone", "totalRevenue": 72},
        <String, Object?>{"product": "tablet", "totalRevenue": 630},
        <String, Object?>{"product": "tablet", "totalRevenue": 630},
        <String, Object?>{"product": "tablet", "totalRevenue": 630},
      ]);
    });

    test('testWindowFieldsComputesFirstAndLastOverThePartition', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.unbounded,
              ),
            ),
            <Object>[
              ex("salesPrice").first().as("firstPrice"),
              ex("salesPrice").last().as("lastPrice"),
            ],
          )
          .sort([ex("date").ascending()])
          .select(["product", "firstPrice", "lastPrice"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "firstPrice": 12,
          "lastPrice": 30,
        },
        <String, Object?>{
          "product": "phone",
          "firstPrice": 12,
          "lastPrice": 30,
        },
        <String, Object?>{
          "product": "tablet",
          "firstPrice": 30,
          "lastPrice": 60,
        },
        <String, Object?>{
          "product": "tablet",
          "firstPrice": 30,
          "lastPrice": 60,
        },
        <String, Object?>{
          "product": "tablet",
          "firstPrice": 30,
          "lastPrice": 60,
        },
      ]);
    });

    test('testWindowFieldsComputesArrayAgg', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.unbounded,
              ),
            ),
            <Object>[ex("salesPrice").arrayAgg().as("allPrices")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "allPrices"])
          .execute();
      if (await emulatorRejectsWindows(execute)) {
        return;
      }
      var results = (await execute).results;
      assertThat(results).hasSize(5);

      assertThat(results[0].data()["allPrices"]).isEqualTo(<Object?>[12, 30]);
      assertThat(
        results[2].data()["allPrices"],
      ).isEqualTo(<Object?>[30, 60, 60]);
    });

    test('testWindowFieldsComputesArrayAggDistinct', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              partition: <Object>["product"],
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.unbounded,
              ),
            ),
            <Object>[ex("salesPrice").arrayAggDistinct().as("distinctPrices")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "distinctPrices"])
          .execute();
      if (await emulatorRejectsWindows(execute)) {
        return;
      }
      var results = (await execute).results;
      assertThat(results).hasSize(5);

      assertThat(results[0].data()["distinctPrices"]).containsExactly([12, 30]);
      assertThat(results[2].data()["distinctPrices"]).containsExactly([30, 60]);
    });

    test('testWindowFieldsComputesARunningTotal', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(
                preceding: WindowFrame.unbounded,
                following: WindowFrame.current,
              ),
            ),
            <Object>[ex("salesPrice").sum().as("runningTotal")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "runningTotal"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "runningTotal": 12},
        <String, Object?>{"product": "phone", "runningTotal": 42},
        <String, Object?>{"product": "tablet", "runningTotal": 72},
        <String, Object?>{"product": "tablet", "runningTotal": 132},
        <String, Object?>{"product": "tablet", "runningTotal": 192},
      ]);
    });

    test('testWindowFieldsComputesACenteredMovingAverage', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(preceding: 1, following: 1),
            ),
            <Object>[
              ex("salesPrice").average().as("movingAverage"),
              countAll().as("windowCount"),
            ],
          )
          .sort([ex("date").ascending()])
          .select(["product", "movingAverage", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{
          "product": "phone",
          "movingAverage": 21.0,
          "windowCount": 2,
        },
        <String, Object?>{
          "product": "phone",
          "movingAverage": 24.0,
          "windowCount": 3,
        },
        <String, Object?>{
          "product": "tablet",
          "movingAverage": 40.0,
          "windowCount": 3,
        },
        <String, Object?>{
          "product": "tablet",
          "movingAverage": 50.0,
          "windowCount": 3,
        },
        <String, Object?>{
          "product": "tablet",
          "movingAverage": 60.0,
          "windowCount": 2,
        },
      ]);
    });

    test('testWindowFieldsComputesATrailingSum', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(preceding: 2, following: 0),
            ),
            <Object>[ex("salesPrice").sum().as("trailingTotal")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "trailingTotal"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "trailingTotal": 12},
        <String, Object?>{"product": "phone", "trailingTotal": 42},
        <String, Object?>{"product": "tablet", "trailingTotal": 72},
        <String, Object?>{"product": "tablet", "trailingTotal": 120},
        <String, Object?>{"product": "tablet", "trailingTotal": 150},
      ]);
    });

    test(
      'testWindowFieldsComputesALookAheadAverageWithANegativePrecedingBound',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        // Equivalent to "documents between 1 following and 2 following": the window is
        // [index - preceding, index + following].
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("date").ascending()],
                frame: WindowFrame.documents(preceding: -1, following: 2),
              ),
              <Object>[
                ex("salesPrice").average().as("lookAheadAverage"),
                countAll().as("windowCount"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "lookAheadAverage", "windowCount"])
            .execute();
        if (await emulatorRejectsWindows(execute)) {
          return;
        }
        var results = (await execute).results;
        assertThat(results).hasSize(5);

        assertThat(results[0].data()["lookAheadAverage"]).isEqualTo(30.0);
        assertThat(results[0].data()["windowCount"]).isEqualTo(2);

        assertThat(results[1].data()["lookAheadAverage"]).isEqualTo(45.0);
        assertThat(results[1].data()["windowCount"]).isEqualTo(2);

        assertThat(results[2].data()["lookAheadAverage"]).isEqualTo(60.0);
        assertThat(results[2].data()["windowCount"]).isEqualTo(2);

        assertThat(results[3].data()["lookAheadAverage"]).isEqualTo(60.0);
        assertThat(results[3].data()["windowCount"]).isEqualTo(1);

        // The last document has an empty window.
        assertThat(results[4].data()["lookAheadAverage"]).isNull();
        assertThat(results[4].data()["windowCount"]).isEqualTo(0);
      },
    );

    test(
      'testWindowFieldsComputesALookBehindAverageWithANegativeFollowingBound',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        // Equivalent to "documents between 2 preceding and 1 preceding": the window is
        // [index - preceding, index + following].
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("date").ascending()],
                frame: WindowFrame.documents(preceding: 2, following: -1),
              ),
              <Object>[
                ex("salesPrice").average().as("lookBehindAverage"),
                countAll().as("windowCount"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "lookBehindAverage", "windowCount"])
            .execute();
        if (await emulatorRejectsWindows(execute)) {
          return;
        }
        var results = (await execute).results;
        assertThat(results).hasSize(5);

        // The first document has an empty window.
        assertThat(results[0].data()["lookBehindAverage"]).isNull();
        assertThat(results[0].data()["windowCount"]).isEqualTo(0);

        assertThat(results[1].data()["lookBehindAverage"]).isEqualTo(12.0);
        assertThat(results[1].data()["windowCount"]).isEqualTo(1);

        assertThat(results[2].data()["lookBehindAverage"]).isEqualTo(21.0);
        assertThat(results[2].data()["windowCount"]).isEqualTo(2);

        assertThat(results[3].data()["lookBehindAverage"]).isEqualTo(30.0);
        assertThat(results[3].data()["windowCount"]).isEqualTo(2);

        assertThat(results[4].data()["lookBehindAverage"]).isEqualTo(45.0);
        assertThat(results[4].data()["windowCount"]).isEqualTo(2);
      },
    );

    test(
      'testWindowFieldsComputesARangeLookBehindAverageWithANegativeFollowingBound',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("salesPrice").ascending()],
                frame: WindowFrame.range(
                  preceding: WindowFrame.unbounded,
                  following: -1,
                ),
              ),
              <Object>[
                ex("salesPrice").average().as("lookBehindAverage"),
                countAll().as("windowCount"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "lookBehindAverage", "windowCount"])
            .execute();
        if (await emulatorRejectsWindows(execute)) {
          return;
        }
        var results = (await execute).results;
        assertThat(results).hasSize(5);

        assertThat(results[0].data()["lookBehindAverage"]).isNull();
        assertThat(results[0].data()["windowCount"]).isEqualTo(0);

        assertThat(results[1].data()["lookBehindAverage"]).isEqualTo(12.0);
        assertThat(results[1].data()["windowCount"]).isEqualTo(1);

        assertThat(results[2].data()["lookBehindAverage"]).isEqualTo(12.0);
        assertThat(results[2].data()["windowCount"]).isEqualTo(1);

        assertThat(results[3].data()["lookBehindAverage"]).isEqualTo(24.0);
        assertThat(results[3].data()["windowCount"]).isEqualTo(3);

        assertThat(results[4].data()["lookBehindAverage"]).isEqualTo(24.0);
        assertThat(results[4].data()["windowCount"]).isEqualTo(3);
      },
    );

    test(
      'testWindowFieldsComputesARangeLookAheadAverageWithANegativePrecedingBound',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("salesPrice").ascending()],
                frame: WindowFrame.range(
                  preceding: -1,
                  following: WindowFrame.unbounded,
                ),
              ),
              <Object>[
                ex("salesPrice").average().as("lookAheadAverage"),
                countAll().as("windowCount"),
              ],
            )
            .sort([ex("date").ascending()])
            .select(["product", "lookAheadAverage", "windowCount"])
            .execute();
        if (await emulatorRejectsWindows(execute)) {
          return;
        }
        var results = (await execute).results;
        assertThat(results).hasSize(5);

        assertThat(results[0].data()["lookAheadAverage"]).isEqualTo(45.0);
        assertThat(results[0].data()["windowCount"]).isEqualTo(4);

        assertThat(results[1].data()["lookAheadAverage"]).isEqualTo(60.0);
        assertThat(results[1].data()["windowCount"]).isEqualTo(2);

        assertThat(results[2].data()["lookAheadAverage"]).isEqualTo(60.0);
        assertThat(results[2].data()["windowCount"]).isEqualTo(2);

        assertThat(results[3].data()["lookAheadAverage"]).isNull();
        assertThat(results[3].data()["windowCount"]).isEqualTo(0);

        assertThat(results[4].data()["lookAheadAverage"]).isNull();
        assertThat(results[4].data()["windowCount"]).isEqualTo(0);
      },
    );

    test('testWindowFieldsComputesAValueBasedRangeWindow', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("salesPrice").ascending()],
              frame: WindowFrame.range(preceding: 20, following: 0),
            ),
            <Object>[ex("salesPrice").sum().as("nearbyTotal")],
          )
          .sort([ex("date").ascending()])
          .select(["salesPrice", "nearbyTotal"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"salesPrice": 12, "nearbyTotal": 12},
        <String, Object?>{"salesPrice": 30, "nearbyTotal": 72},
        <String, Object?>{"salesPrice": 30, "nearbyTotal": 72},
        <String, Object?>{"salesPrice": 60, "nearbyTotal": 120},
        <String, Object?>{"salesPrice": 60, "nearbyTotal": 120},
      ]);
    });

    test(
      'testWindowFieldsComputesAValueBasedRangeWindowWithDoubleOffsets',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("salesPrice").ascending()],
                frame: WindowFrame.range(preceding: 17.5, following: 0.5),
              ),
              <Object>[ex("salesPrice").sum().as("nearbyTotal")],
            )
            .sort([ex("date").ascending()])
            .select(["salesPrice", "nearbyTotal"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"salesPrice": 12, "nearbyTotal": 12},
          <String, Object?>{"salesPrice": 30, "nearbyTotal": 60},
          <String, Object?>{"salesPrice": 30, "nearbyTotal": 60},
          <String, Object?>{"salesPrice": 60, "nearbyTotal": 120},
          <String, Object?>{"salesPrice": 60, "nearbyTotal": 120},
        ]);
      },
    );

    test('testWindowFieldsComputesATrailingThreeDayTotal', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.range(
                preceding: 3,
                following: WindowFrame.current,
                unit: "day",
              ),
            ),
            <Object>[ex("salesPrice").sum().as("threeDayTotal")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "threeDayTotal"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "threeDayTotal": 12},
        <String, Object?>{"product": "phone", "threeDayTotal": 42},
        <String, Object?>{"product": "tablet", "threeDayTotal": 72},
        <String, Object?>{"product": "tablet", "threeDayTotal": 132},
        <String, Object?>{"product": "tablet", "threeDayTotal": 60},
      ]);
    });

    test('testWindowFieldsCountAllCountsEveryDocumentInTheWindow', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(WindowSpec(partition: <Object>["product"]), <Object>[
            countAll().as("windowCount"),
          ])
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "phone", "windowCount": 2},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
        <String, Object?>{"product": "tablet", "windowCount": 3},
      ]);
    });

    test('testWindowFieldsDocumentsZeroPrecedingAndZeroFollowing', () async {
      // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
      Future<PipelineSnapshot> execute = firestore
          .pipeline()
          .collection((await windowTestCollection()))
          .addWindowFields(
            WindowSpec(
              sort: <Ordering>[ex("date").ascending()],
              frame: WindowFrame.documents(preceding: 0, following: 0),
            ),
            <Object>[ex("quantity").count().as("windowCount")],
          )
          .sort([ex("date").ascending()])
          .select(["product", "windowCount"])
          .execute();
      await expectWindowResults(execute, <Object?>[
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "phone", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
        <String, Object?>{"product": "tablet", "windowCount": 1},
      ]);
    });

    test(
      'testWindowFieldsDocumentsZeroPrecedingToUnboundedFollowing',
      () async {
        // Android runs this case only with FIRESTORE_RUN_COMPREHENSIVE_TESTS.
        Future<PipelineSnapshot> execute = firestore
            .pipeline()
            .collection((await windowTestCollection()))
            .addWindowFields(
              WindowSpec(
                sort: <Ordering>[ex("date").ascending()],
                frame: WindowFrame.documents(
                  preceding: 0,
                  following: WindowFrame.unbounded,
                ),
              ),
              <Object>[ex("quantity").count().as("windowCount")],
            )
            .sort([ex("date").ascending()])
            .select(["product", "windowCount"])
            .execute();
        await expectWindowResults(execute, <Object?>[
          <String, Object?>{"product": "phone", "windowCount": 5},
          <String, Object?>{"product": "phone", "windowCount": 4},
          <String, Object?>{"product": "tablet", "windowCount": 3},
          <String, Object?>{"product": "tablet", "windowCount": 2},
          <String, Object?>{"product": "tablet", "windowCount": 1},
        ]);
      },
    );
  });
}
