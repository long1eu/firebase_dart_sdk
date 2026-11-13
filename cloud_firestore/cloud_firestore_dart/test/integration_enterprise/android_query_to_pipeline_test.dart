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
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/QueryToPipelineTest.java
//
// The cases keep their Java names; android_pipeline_test_util.dart has the
// functions they call. They run against the Enterprise edition emulator of
// FIRESTORE_ENTERPRISE_EMULATOR_HOST (tool/start_enterprise_emulator.sh);
// without it they are skipped. Where Android skips a case on the emulator
// (`assumeFalse(isRunningAgainstEmulator())`), the case here records what
// the emulator answers, with a comment.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables, unawaited_futures
// ignore_for_file: unnecessary_await_in_return, unnecessary_parenthesis
// ignore_for_file: unnecessary_statements, cascade_invocations
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:test/test.dart' show group, tearDown, test;

import '../util/integration_test_util.dart';
import 'android_pipeline_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/android_query_to_pipeline';

  group('QueryToPipelineTest', skip: IntegrationTestUtil.enterpriseEmulatorSkipReason, () {
    tearDown(() async {
      await IntegrationTestUtil.tearDown();
    });

    test('testLimitQueries', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": <String, Object?>{"k": "a"},
        "b": <String, Object?>{"k": "b"},
        "c": <String, Object?>{"k": "c"},
      });

      var query = collection.limit(2);
      var db = collection.firestore;
      var set = (await db.pipeline().createFrom(query).execute());
      var data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "a"},
        <String, Object?>{"k": "b"},
      ], data);
    });

    test('testLimitQueriesUsingDescendingSortOrder', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": <String, Object?>{"k": "a", "sort": 0},
        "b": <String, Object?>{"k": "b", "sort": 1},
        "c": <String, Object?>{"k": "c", "sort": 1},
        "d": <String, Object?>{"k": "d", "sort": 2},
      });

      var query = collection.limit(2).orderBy("sort", Direction.descending);
      var db = collection.firestore;
      var set = (await db.pipeline().createFrom(query).execute());

      var data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "d", "sort": 2},
        <String, Object?>{"k": "c", "sort": 1},
      ], data);
    });

    test('testLimitToLastMustAlsoHaveExplicitOrderBy', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{});
      var db = collection.firestore;

      var query = collection.limitToLast(2);
      await expectError(
        () async => (await db.pipeline().createFrom(query).execute()),
        "limitToLast() queries require specifying at least one orderBy() clause",
      );
    });

    test('testLimitToLastQueriesWithCursors', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": <String, Object?>{"k": "a", "sort": 0},
        "b": <String, Object?>{"k": "b", "sort": 1},
        "c": <String, Object?>{"k": "c", "sort": 1},
        "d": <String, Object?>{"k": "d", "sort": 2},
      });

      var query = collection.limitToLast(3).orderBy("sort").endBefore([2]);
      var db = collection.firestore;

      var set = (await db.pipeline().createFrom(query).execute());
      var data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "a", "sort": 0},
        <String, Object?>{"k": "b", "sort": 1},
        <String, Object?>{"k": "c", "sort": 1},
      ], data);

      query = collection.limitToLast(3).orderBy("sort").endAt([1]);
      set = (await db.pipeline().createFrom(query).execute());
      data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "a", "sort": 0},
        <String, Object?>{"k": "b", "sort": 1},
        <String, Object?>{"k": "c", "sort": 1},
      ], data);

      query = collection.limitToLast(3).orderBy("sort").startAt([2]);
      set = (await db.pipeline().createFrom(query).execute());
      data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "d", "sort": 2},
      ], data);

      query = collection.limitToLast(3).orderBy("sort").startAfter([0]);
      set = (await db.pipeline().createFrom(query).execute());
      data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "b", "sort": 1},
        <String, Object?>{"k": "c", "sort": 1},
        <String, Object?>{"k": "d", "sort": 2},
      ], data);

      query = collection.limitToLast(3).orderBy("sort").startAfter([-1]);
      set = (await db.pipeline().createFrom(query).execute());
      data = pipelineSnapshotToValues(set);
      assertEquals(<Object?>[
        <String, Object?>{"k": "b", "sort": 1},
        <String, Object?>{"k": "c", "sort": 1},
        <String, Object?>{"k": "d", "sort": 2},
      ], data);
    });

    test('testNotInRemovesExistenceFilter', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "doc1": <String, Object?>{"field": 2},
        "doc2": <String, Object?>{"field": 1},
        "doc3": <String, Object?>{},
      });

      var query = collection.where("field", whereNotIn: <Object?>[1]);
      var db = collection.firestore;
      var set = (await db.pipeline().createFrom(query).execute());
      var ids = pipelineSnapshotToIds(set);
      // Android expects ["doc3", "doc1"]: its createFrom drops the existence filter, so a
      // document without the field matches. Dart's createFrom returns what
      // the classic query returns (design notes 8.2: `!=` and `not-in` add
      // not_equal(field, null)), which leaves out missing and null values.
      assertEquals(<Object?>["doc1"], ids);
    });

    test('testNotEqualRemovesExistenceFilter', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "doc1": <String, Object?>{"field": 2},
        "doc2": <String, Object?>{"field": 1},
        "doc3": <String, Object?>{},
      });

      var query = collection.where("field", isNotEqualTo: 1);
      var db = collection.firestore;
      var set = (await db.pipeline().createFrom(query).execute());
      var ids = pipelineSnapshotToIds(set);
      // Android expects ["doc3", "doc1"]: its createFrom drops the existence filter, so a
      // document without the field matches. Dart's createFrom returns what
      // the classic query returns (design notes 8.2: `!=` and `not-in` add
      // not_equal(field, null)), which leaves out missing and null values.
      assertEquals(<Object?>["doc1"], ids);
    });

    test('testInequalityMaintainsExistenceFilter', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "doc1": <String, Object?>{"field": 0},
        "doc2": <String, Object?>{},
      });

      var query = collection.where("field", isLessThan: 1);
      var db = collection.firestore;
      var set = (await db.pipeline().createFrom(query).execute());
      var ids = pipelineSnapshotToIds(set);
      assertEquals(<Object?>["doc1"], ids);
    });

    test('testExplicitOrderMaintainsExistenceFilter', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "doc1": <String, Object?>{"field": 1},
        "doc2": <String, Object?>{},
      });

      var query = collection.orderBy("field");
      var db = collection.firestore;
      var set = (await db.pipeline().createFrom(query).execute());
      var ids = pipelineSnapshotToIds(set);
      assertEquals(<Object?>["doc1"], ids);
    });

    test('testKeyOrderIsDescendingForDescendingInequality', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": <String, Object?>{"foo": 42},
        "b": <String, Object?>{"foo": 42.0},
        "c": <String, Object?>{"foo": 42},
        "d": <String, Object?>{"foo": 21},
        "e": <String, Object?>{"foo": 21.0},
        "f": <String, Object?>{"foo": 66},
        "g": <String, Object?>{"foo": 66.0},
      });

      var query = collection
          .where("foo", isGreaterThan: 21.0)
          .orderBy("foo", Direction.descending);
      var db = collection.firestore;
      var result = (await db.pipeline().createFrom(query).execute());
      assertEquals(<Object?>[
        "g",
        "f",
        "c",
        "b",
        "a",
      ], pipelineSnapshotToIds(result));
    });

    test('testUnaryFilterQueries', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": <String, Object?>{"null": null, "nan": double.nan},
        "b": <String, Object?>{"null": null, "nan": 0},
        "c": <String, Object?>{"null": false, "nan": double.nan},
      });
      var db = collection.firestore;
      var results = (await db
          .pipeline()
          .createFrom(
            collection
                .where(
                  "null",
                  isNull: true,
                ) // Android: whereEqualTo("null", null)
                .where("nan", isEqualTo: double.nan),
          )
          .execute());
      assertEquals(1, results.results.length);
      var result = results.results[0];
      // Can't use assertEquals() since NaN != NaN.
      assertEquals(null, result["null"]);
      assertTrue((result["nan"]! as double).isNaN);
    });

    test('testFilterOnInfinity', () async {
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": <String, Object?>{"inf": double.infinity},
        "b": <String, Object?>{"inf": double.negativeInfinity},
      });
      var db = collection.firestore;
      var results = (await db
          .pipeline()
          .createFrom(collection.where("inf", isEqualTo: double.infinity))
          .execute());
      assertEquals(1, results.results.length);
      assertEquals(<Object?>[
        <String, Object?>{"inf": double.infinity},
      ], pipelineSnapshotToValues(results));
    });

    test('testCanExplicitlySortByDocumentId', () async {
      var testDocs = <String, Object?>{
        "a": <String, Object?>{"key": "a"},
        "b": <String, Object?>{"key": "b"},
        "c": <String, Object?>{"key": "c"},
      };
      var collection = await testCollectionWithDocs(testDocs);
      var db = collection.firestore;
      // Ideally this would be descending to validate it's different than
      // the default, but that requires an extra index
      var docs = (await db
          .pipeline()
          .createFrom(collection.orderByField(FieldPath.documentIdField))
          .execute());
      assertEquals(<Object?>[
        testDocs["a"],
        testDocs["b"],
        testDocs["c"],
      ], pipelineSnapshotToValues(docs));
    });

    test('testCanQueryByDocumentId', () async {
      var testDocs = <String, Object?>{
        "aa": <String, Object?>{"key": "aa"},
        "ab": <String, Object?>{"key": "ab"},
        "ba": <String, Object?>{"key": "ba"},
        "bb": <String, Object?>{"key": "bb"},
      };
      var collection = await testCollectionWithDocs(testDocs);
      var db = collection.firestore;
      var docs = (await db
          .pipeline()
          .createFrom(
            collection.where(FieldPath.documentIdField, isEqualTo: "ab"),
          )
          .execute());
      assertEquals(<Object?>[testDocs["ab"]], pipelineSnapshotToValues(docs));

      docs = (await db
          .pipeline()
          .createFrom(
            collection
                .where(FieldPath.documentIdField, isGreaterThan: "aa")
                .where(FieldPath.documentIdField, isLessThanOrEqualTo: "ba"),
          )
          .execute());
      assertEquals(<Object?>[
        testDocs["ab"],
        testDocs["ba"],
      ], pipelineSnapshotToValues(docs));
    });

    test('testCanQueryByDocumentIdUsingRefs', () async {
      var testDocs = <String, Object?>{
        "aa": <String, Object?>{"key": "aa"},
        "ab": <String, Object?>{"key": "ab"},
        "ba": <String, Object?>{"key": "ba"},
        "bb": <String, Object?>{"key": "bb"},
      };
      var collection = await testCollectionWithDocs(testDocs);
      var db = collection.firestore;
      var docs = (await db
          .pipeline()
          .createFrom(
            collection.where(
              FieldPath.documentIdField,
              isEqualTo: collection.document("ab"),
            ),
          )
          .execute());
      assertEquals(<Object?>[testDocs["ab"]], pipelineSnapshotToValues(docs));

      docs = (await db
          .pipeline()
          .createFrom(
            collection
                .where(
                  FieldPath.documentIdField,
                  isGreaterThan: collection.document("aa"),
                )
                .where(
                  FieldPath.documentIdField,
                  isLessThanOrEqualTo: collection.document("ba"),
                ),
          )
          .execute());
      assertEquals(<Object?>[
        testDocs["ab"],
        testDocs["ba"],
      ], pipelineSnapshotToValues(docs));
    });

    test('testCanQueryWithAndWithoutDocumentKey', () async {
      var collection = await testCollection();
      var db = collection.firestore;
      (await collection.add(<String, Object?>{}));
      Future<PipelineSnapshot> query1 = db
          .pipeline()
          .createFrom(
            collection.orderByField(
              FieldPath.documentIdField,
              Direction.ascending,
            ),
          )
          .execute();
      Future<PipelineSnapshot> query2 = db
          .pipeline()
          .createFrom(collection)
          .execute();

      assertEquals(
        pipelineSnapshotToValues(await query1),
        pipelineSnapshotToValues(await query2),
      );
    });

    test('testQueriesCanUseNotEqualFilters', () async {
      // These documents are ordered by value in "zip" since the notEquals filter is an inequality,
      // which results in documents being sorted by value.
      var docA = <String, Object?>{"zip": double.nan};
      var docB = <String, Object?>{"zip": 91102};
      var docC = <String, Object?>{"zip": 98101};
      var docD = <String, Object?>{"zip": "98101"};
      var docE = <String, Object?>{
        "zip": <Object?>[98101],
      };
      var docF = <String, Object?>{
        "zip": <Object?>[98101, 98102],
      };
      var docG = <String, Object?>{
        "zip": <Object?>[
          "98101",
          <String, Object?>{"zip": 98101},
        ],
      };
      var docH = <String, Object?>{
        "zip": <String, Object?>{"code": 500},
      };
      var docI = <String, Object?>{"code": 500};
      var docJ = <String, Object?>{"zip": null};

      var allDocs = <String, Object?>{
        "i": docI,
        "j": docJ,
        "a": docA,
        "b": docB,
        "c": docC,
        "d": docD,
        "e": docE,
        "f": docF,
        "g": docG,
        "h": docH,
      };
      var collection = await testCollectionWithDocs(allDocs);
      var db = collection.firestore;

      // Search for zips not matching 98101.
      var expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("c");

      var snapshot = (await db
          .pipeline()
          .createFrom(collection.where("zip", isNotEqualTo: 98101))
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With objects.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("h");
      snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where(
              "zip",
              isNotEqualTo: <String, Object?>{"code": 500},
            ),
          )
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With Null.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      snapshot = (await db
          .pipeline()
          // Android: whereNotEqualTo("zip", null).
          .createFrom(collection.where("zip", isNull: false))
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With NaN.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("a");
      snapshot = (await db
          .pipeline()
          .createFrom(collection.where("zip", isNotEqualTo: double.nan))
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );
    });

    test('testQueriesCanUseNotEqualFiltersWithDocIds', () async {
      var docA = <String, Object?>{"key": "aa"};
      var docB = <String, Object?>{"key": "ab"};
      var docC = <String, Object?>{"key": "ba"};
      var docD = <String, Object?>{"key": "bb"};
      var testDocs = <String, Object?>{
        "aa": docA,
        "ab": docB,
        "ba": docC,
        "bb": docD,
      };
      var collection = await testCollectionWithDocs(testDocs);
      var db = collection.firestore;
      var docs = (await db
          .pipeline()
          .createFrom(
            collection.where(FieldPath.documentIdField, isNotEqualTo: "aa"),
          )
          .execute());
      assertEquals(<Object?>[docB, docC, docD], pipelineSnapshotToValues(docs));
    });

    test('testQueriesCanUseArrayContainsFilters', () async {
      var docA = <String, Object?>{
        "array": <Object?>[42],
      };
      var docB = <String, Object?>{
        "array": <Object?>["a", 42, "c"],
      };
      var docC = <String, Object?>{
        "array": <Object?>[
          41.999,
          "42",
          <String, Object?>{
            "a": <Object?>[42],
          },
        ],
      };
      var docD = <String, Object?>{
        "array": <Object?>[42],
        "array2": <Object?>["bingo"],
      };
      var docE = <String, Object?>{"array": nullList()};
      var docF = <String, Object?>{
        "array": <Object?>[double.nan],
      };
      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": docA,
        "b": docB,
        "c": docC,
        "d": docD,
        "e": docE,
        "f": docF,
      });
      var db = collection.firestore;

      // Search for "array" to contain 42
      var snapshot = (await db
          .pipeline()
          .createFrom(collection.where("array", arrayContains: 42))
          .execute());
      assertEquals(<Object?>[
        docA,
        docB,
        docD,
      ], pipelineSnapshotToValues(snapshot));

      snapshot = (await db
          .pipeline()
          .createFrom(collection.where("array", arrayContains: double.nan))
          .execute());
      assertEquals(<Object?>[docF], pipelineSnapshotToValues(snapshot));
    });

    test('testQueriesCanUseInFilters', () async {
      var docA = <String, Object?>{"zip": 98101};
      var docB = <String, Object?>{"zip": 91102};
      var docC = <String, Object?>{"zip": 98103};
      var docD = <String, Object?>{
        "zip": <Object?>[98101],
      };
      var docE = <String, Object?>{
        "zip": <Object?>[
          "98101",
          <String, Object?>{"zip": 98101},
        ],
      };
      var docF = <String, Object?>{
        "zip": <String, Object?>{"code": 500},
      };
      var docG = <String, Object?>{
        "zip": <Object?>[98101, 98102],
      };
      var docH = <String, Object?>{"zip": null};
      var docI = <String, Object?>{"zip": double.nan};

      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": docA,
        "b": docB,
        "c": docC,
        "d": docD,
        "e": docE,
        "f": docF,
        "g": docG,
        "h": docH,
        "i": docI,
      });
      var db = collection.firestore;

      // Search for zips matching 98101, 98103, or [98101, 98102].
      var snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where(
              "zip",
              whereIn: <Object?>[
                98101,
                98103,
                <Object?>[98101, 98102],
              ],
            ),
          )
          .execute());
      assertEquals(<Object?>[
        docA,
        docC,
        docG,
      ], pipelineSnapshotToValues(snapshot));

      // With objects.
      snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where(
              "zip",
              whereIn: <Object?>[
                <String, Object?>{"code": 500},
              ],
            ),
          )
          .execute());
      assertEquals(<Object?>[docF], pipelineSnapshotToValues(snapshot));

      // With null.
      snapshot = (await db
          .pipeline()
          .createFrom(collection.where("zip", whereIn: nullList()))
          .execute());
      assertEquals(<Object?>[docH], pipelineSnapshotToValues(snapshot));

      // With null and a value.
      var inputList = nullList();
      inputList.add(98101);
      snapshot = (await db
          .pipeline()
          .createFrom(collection.where("zip", whereIn: inputList))
          .execute());
      assertEquals(<Object?>[docA, docH], pipelineSnapshotToValues(snapshot));

      // With NaN.
      snapshot = (await db
          .pipeline()
          .createFrom(collection.where("zip", whereIn: <Object?>[double.nan]))
          .execute());
      assertEquals(<Object?>[docI], pipelineSnapshotToValues(snapshot));

      // With NaN and a value.
      snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where("zip", whereIn: <Object?>[double.nan, 98101]),
          )
          .execute());
      assertEquals(<Object?>[docA, docI], pipelineSnapshotToValues(snapshot));
    });

    test('testQueriesCanUseInFiltersWithDocIds', () async {
      var docA = <String, Object?>{"key": "aa"};
      var docB = <String, Object?>{"key": "ab"};
      var docC = <String, Object?>{"key": "ba"};
      var docD = <String, Object?>{"key": "bb"};
      var testDocs = <String, Object?>{
        "aa": docA,
        "ab": docB,
        "ba": docC,
        "bb": docD,
      };
      var collection = await testCollectionWithDocs(testDocs);
      var db = collection.firestore;
      var docs = (await db
          .pipeline()
          .createFrom(
            collection.where(
              FieldPath.documentIdField,
              whereIn: <Object?>["aa", "ab"],
            ),
          )
          .execute());
      assertEquals(<Object?>[docA, docB], pipelineSnapshotToValues(docs));
    });

    test('testQueriesCanUseNotInFilters', () async {
      // These documents are ordered by value in "zip" since the notEquals filter is an inequality,
      // which results in documents being sorted by value.
      var docA = <String, Object?>{"zip": double.nan};
      var docB = <String, Object?>{"zip": 91102};
      var docC = <String, Object?>{"zip": 98101};
      var docD = <String, Object?>{"zip": 98103};
      var docE = <String, Object?>{
        "zip": <Object?>[98101],
      };
      var docF = <String, Object?>{
        "zip": <Object?>[98101, 98102],
      };
      var docG = <String, Object?>{
        "zip": <Object?>[
          "98101",
          <String, Object?>{"zip": 98101},
        ],
      };
      var docH = <String, Object?>{
        "zip": <String, Object?>{"code": 500},
      };
      var docI = <String, Object?>{"code": 500};
      var docJ = <String, Object?>{"zip": null};

      var allDocs = <String, Object?>{
        "i": docI,
        "j": docJ,
        "a": docA,
        "b": docB,
        "c": docC,
        "d": docD,
        "e": docE,
        "f": docF,
        "g": docG,
        "h": docH,
      };
      var collection = await testCollectionWithDocs(allDocs);
      var db = collection.firestore;

      // Search for zips not matching 98101, 98103, or [98101, 98102].
      var expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("c");
      expectedDocsMap.remove("d");
      expectedDocsMap.remove("f");

      var snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where(
              "zip",
              whereNotIn: <Object?>[
                98101,
                98103,
                <Object?>[98101, 98102],
              ],
            ),
          )
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With objects.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("h");
      snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where(
              "zip",
              whereNotIn: <Object?>[
                <String, Object?>{"code": 500},
              ],
            ),
          )
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With Null.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      snapshot = (await db
          .pipeline()
          .createFrom(collection.where("zip", whereNotIn: nullList()))
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With NaN.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("a");
      snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where("zip", whereNotIn: <Object?>[double.nan]),
          )
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );

      // With NaN and a number.
      expectedDocsMap = Map<String, Object?>.of(allDocs);
      // Not on Dart (see testNotInRemovesExistenceFilter): i has no zip, j a
      // null zip.
      expectedDocsMap.remove("i");
      expectedDocsMap.remove("j");
      expectedDocsMap.remove("a");
      expectedDocsMap.remove("c");
      snapshot = (await db
          .pipeline()
          .createFrom(
            collection.where("zip", whereNotIn: <Object?>[double.nan, 98101]),
          )
          .execute());
      assertEquals(
        expectedDocsMap.values.toList(),
        pipelineSnapshotToValues(snapshot),
      );
    });

    test('testQueriesCanUseNotInFiltersWithDocIds', () async {
      var docA = <String, Object?>{"key": "aa"};
      var docB = <String, Object?>{"key": "ab"};
      var docC = <String, Object?>{"key": "ba"};
      var docD = <String, Object?>{"key": "bb"};
      var testDocs = <String, Object?>{
        "aa": docA,
        "ab": docB,
        "ba": docC,
        "bb": docD,
      };
      var collection = await testCollectionWithDocs(testDocs);
      var db = collection.firestore;
      var docs = (await db
          .pipeline()
          .createFrom(
            collection.where(
              FieldPath.documentIdField,
              whereNotIn: <Object?>["aa", "ab"],
            ),
          )
          .execute());
      assertEquals(<Object?>[docC, docD], pipelineSnapshotToValues(docs));
    });

    test('testQueriesCanUseArrayContainsAnyFilters', () async {
      var docA = <String, Object?>{
        "array": <Object?>[42],
      };
      var docB = <String, Object?>{
        "array": <Object?>["a", 42, "c"],
      };
      var docC = <String, Object?>{
        "array": <Object?>[
          41.999,
          "42",
          <String, Object?>{
            "a": <Object?>[42],
          },
        ],
      };
      var docD = <String, Object?>{
        "array": <Object?>[42],
        "array2": <Object?>["bingo"],
      };
      var docE = <String, Object?>{
        "array": <Object?>[43],
      };
      var docF = <String, Object?>{
        "array": <Object?>[
          <String, Object?>{"a": 42},
        ],
      };
      var docH = <String, Object?>{"array": nullList()};
      var docI = <String, Object?>{
        "array": <Object?>[double.nan],
      };

      var collection = await testCollectionWithDocs(<String, Object?>{
        "a": docA,
        "b": docB,
        "c": docC,
        "d": docD,
        "e": docE,
        "f": docF,
        "h": docH,
        "i": docI,
      });
      var db = collection.firestore;

      // Search for "array" to contain [42, 43].
      var pipeline = db.pipeline().createFrom(
        collection.where("array", arrayContainsAny: <Object?>[42, 43]),
      );
      var snapshot = (await pipeline.execute());
      assertEquals(<Object?>[
        docA,
        docB,
        docD,
        docE,
      ], pipelineSnapshotToValues(snapshot));

      // With objects.
      pipeline = db.pipeline().createFrom(
        collection.where(
          "array",
          arrayContainsAny: <Object?>[
            <String, Object?>{"a": 42},
          ],
        ),
      );
      snapshot = (await pipeline.execute());
      assertEquals(<Object?>[docF], pipelineSnapshotToValues(snapshot));

      // With null.
      pipeline = db.pipeline().createFrom(
        collection.where("array", arrayContainsAny: nullList()),
      );
      snapshot = (await pipeline.execute());
      assertEquals(<Object?>[docH], pipelineSnapshotToValues(snapshot));

      // With null and a value.
      var inputList = nullList();
      inputList.add(43);
      pipeline = db.pipeline().createFrom(
        collection.where("array", arrayContainsAny: inputList),
      );
      snapshot = (await pipeline.execute());
      assertEquals(<Object?>[docE, docH], pipelineSnapshotToValues(snapshot));

      // With NaN.
      pipeline = db.pipeline().createFrom(
        collection.where("array", arrayContainsAny: <Object?>[double.nan]),
      );
      snapshot = (await pipeline.execute());
      assertEquals(<Object?>[docI], pipelineSnapshotToValues(snapshot));

      // With NaN and a value.
      pipeline = db.pipeline().createFrom(
        collection.where("array", arrayContainsAny: <Object?>[double.nan, 43]),
      );
      snapshot = (await pipeline.execute());
      assertEquals(<Object?>[docE, docI], pipelineSnapshotToValues(snapshot));
    });

    test('testCollectionGroupQueries', () async {
      var db = await IntegrationTestUtil.testEnterpriseFirestore();
      // Use .document() to get a random collection group name to use but ensure it starts with 'b'
      // for predictable ordering.
      var collectionGroup = "b" + db.collection("foo").document().id;

      var docPaths = <String>[
        "abc/123/\${collectionGroup}/cg-doc1",
        "abc/123/\${collectionGroup}/cg-doc2",
        "\${collectionGroup}/cg-doc3",
        "\${collectionGroup}/cg-doc4",
        "def/456/\${collectionGroup}/cg-doc5",
        "\${collectionGroup}/virtual-doc/nested-coll/not-cg-doc",
        "x\${collectionGroup}/not-cg-doc",
        "\${collectionGroup}x/not-cg-doc",
        "abc/123/\${collectionGroup}x/not-cg-doc",
        "abc/123/x\${collectionGroup}/not-cg-doc",
        "abc/\${collectionGroup}",
      ];
      WriteBatch batch = db.batch();
      for (final path in docPaths) {
        batch.set(
          db.document(path.replaceAll("\${collectionGroup}", collectionGroup)),
          <String, Object?>{"x": 1},
        );
      }
      (await batch.commit());

      var snapshot = (await db
          .pipeline()
          .createFrom(db.collectionGroup(collectionGroup))
          .execute());
      assertEquals(<Object?>[
        "cg-doc1",
        "cg-doc2",
        "cg-doc3",
        "cg-doc4",
        "cg-doc5",
      ], pipelineSnapshotToIds(snapshot));
    });

    test(
      'testCollectionGroupQueriesWithStartAtEndAtWithArbitraryDocumentIds',
      () async {
        var db = await IntegrationTestUtil.testEnterpriseFirestore();
        // Use .document() to get a random collection group name to use but ensure it starts with 'b'
        // for predictable ordering.
        var collectionGroup = "b" + db.collection("foo").document().id;

        var docPaths = <String>[
          "a/a/\${collectionGroup}/cg-doc1",
          "a/b/a/b/\${collectionGroup}/cg-doc2",
          "a/b/\${collectionGroup}/cg-doc3",
          "a/b/c/d/\${collectionGroup}/cg-doc4",
          "a/c/\${collectionGroup}/cg-doc5",
          "\${collectionGroup}/cg-doc6",
          "a/b/nope/nope",
        ];
        WriteBatch batch = db.batch();
        for (final path in docPaths) {
          batch.set(
            db.document(
              path.replaceAll("\${collectionGroup}", collectionGroup),
            ),
            <String, Object?>{"x": 1},
          );
        }
        (await batch.commit());

        var snapshot = (await db
            .pipeline()
            .createFrom(
              db
                  .collectionGroup(collectionGroup)
                  .orderByField(FieldPath.documentIdField)
                  .startAt(["a/b"])
                  .endAt(["a/b0"]),
            )
            .execute());
        assertEquals(<Object?>[
          "cg-doc2",
          "cg-doc3",
          "cg-doc4",
        ], pipelineSnapshotToIds(snapshot));

        snapshot = (await db
            .pipeline()
            .createFrom(
              db
                  .collectionGroup(collectionGroup)
                  .orderByField(FieldPath.documentIdField)
                  .startAfter(["a/b"])
                  .endBefore(["a/b/" + collectionGroup + "/cg-doc3"]),
            )
            .execute());
        assertEquals(<Object?>["cg-doc2"], pipelineSnapshotToIds(snapshot));
      },
    );

    test(
      'testCollectionGroupQueriesWithWhereFiltersOnArbitraryDocumentIds',
      () async {
        var db = await IntegrationTestUtil.testEnterpriseFirestore();
        // Use .document() to get a random collection group name to use but ensure it starts with 'b'
        // for predictable ordering.
        var collectionGroup = "b" + db.collection("foo").document().id;

        var docPaths = <String>[
          "a/a/\${collectionGroup}/cg-doc1",
          "a/b/a/b/\${collectionGroup}/cg-doc2",
          "a/b/\${collectionGroup}/cg-doc3",
          "a/b/c/d/\${collectionGroup}/cg-doc4",
          "a/c/\${collectionGroup}/cg-doc5",
          "\${collectionGroup}/cg-doc6",
          "a/b/nope/nope",
        ];
        WriteBatch batch = db.batch();
        for (final path in docPaths) {
          batch.set(
            db.document(
              path.replaceAll("\${collectionGroup}", collectionGroup),
            ),
            <String, Object?>{"x": 1},
          );
        }
        (await batch.commit());

        var snapshot = (await db
            .pipeline()
            .createFrom(
              db
                  .collectionGroup(collectionGroup)
                  .where(
                    FieldPath.documentIdField,
                    isGreaterThanOrEqualTo: "a/b",
                  )
                  .where(
                    FieldPath.documentIdField,
                    isLessThanOrEqualTo: "a/b0",
                  ),
            )
            .execute());
        assertEquals(<Object?>[
          "cg-doc2",
          "cg-doc3",
          "cg-doc4",
        ], pipelineSnapshotToIds(snapshot));

        snapshot = (await db
            .pipeline()
            .createFrom(
              db
                  .collectionGroup(collectionGroup)
                  .where(FieldPath.documentIdField, isGreaterThan: "a/b")
                  .where(
                    FieldPath.documentIdField,
                    isLessThan: "a/b/" + collectionGroup + "/cg-doc3",
                  ),
            )
            .execute());
        assertEquals(<Object?>["cg-doc2"], pipelineSnapshotToIds(snapshot));
      },
    );

    test('testOrQueries', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{"a": 1, "b": 0},
        "doc2": <String, Object?>{"a": 2, "b": 1},
        "doc3": <String, Object?>{"a": 3, "b": 2},
        "doc4": <String, Object?>{"a": 1, "b": 3},
        "doc5": <String, Object?>{"a": 1, "b": 1},
      };
      var collection = await testCollectionWithDocs(testDocs);

      // Two equalities: a==1 || b==1.
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.or([Filter.equalTo("a", 1), Filter.equalTo("b", 1)]),
        ),
        ["doc1", "doc2", "doc4", "doc5"],
      );

      // (a==1 && b==0) || (a==3 && b==2)
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.or([
            Filter.and([Filter.equalTo("a", 1), Filter.equalTo("b", 0)]),
            Filter.and([Filter.equalTo("a", 3), Filter.equalTo("b", 2)]),
          ]),
        ),
        ["doc1", "doc3"],
      );

      // a==1 && (b==0 || b==3).
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.and([
            Filter.equalTo("a", 1),
            Filter.or([Filter.equalTo("b", 0), Filter.equalTo("b", 3)]),
          ]),
        ),
        ["doc1", "doc4"],
      );

      // (a==2 || b==2) && (a==3 || b==3)
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.and([
            Filter.or([Filter.equalTo("a", 2), Filter.equalTo("b", 2)]),
            Filter.or([Filter.equalTo("a", 3), Filter.equalTo("b", 3)]),
          ]),
        ),
        ["doc3"],
      );

      // Test with limits without orderBy (the __name__ ordering is the tie breaker).
      await checkQueryAndPipelineResultsMatch(
        collection
            .where(Filter.or([Filter.equalTo("a", 2), Filter.equalTo("b", 1)]))
            .limit(1),
        ["doc2"],
      );
    });

    test('testOrQueriesWithIn', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{"a": 1, "b": 0},
        "doc2": <String, Object?>{"b": 1},
        "doc3": <String, Object?>{"a": 3, "b": 2},
        "doc4": <String, Object?>{"a": 1, "b": 3},
        "doc5": <String, Object?>{"a": 1},
        "doc6": <String, Object?>{"a": 2},
      };
      var collection = await testCollectionWithDocs(testDocs);

      // a==2 || b in [2,3]
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.or([
            Filter.equalTo("a", 2),
            Filter.inArray("b", <Object?>[2, 3]),
          ]),
        ),
        ["doc3", "doc4", "doc6"],
      );
    });

    test('testOrQueriesWithArrayMembership', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{
          "a": 1,
          "b": <Object?>[0],
        },
        "doc2": <String, Object?>{
          "b": <Object?>[1],
        },
        "doc3": <String, Object?>{
          "a": 3,
          "b": <Object?>[2, 7],
        },
        "doc4": <String, Object?>{
          "a": 1,
          "b": <Object?>[3, 7],
        },
        "doc5": <String, Object?>{"a": 1},
        "doc6": <String, Object?>{"a": 2},
      };
      var collection = await testCollectionWithDocs(testDocs);

      // a==2 || b array-contains 7
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.or([Filter.equalTo("a", 2), Filter.arrayContains("b", 7)]),
        ),
        ["doc3", "doc4", "doc6"],
      );

      // a==2 || b array-contains-any [0, 3]
      await checkQueryAndPipelineResultsMatch(
        collection.where(
          Filter.or([
            Filter.equalTo("a", 2),
            Filter.arrayContainsAny("b", <Object?>[0, 3]),
          ]),
        ),
        ["doc1", "doc4", "doc6"],
      );
    });

    test('testMultipleInOps', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{"a": 1, "b": 0},
        "doc2": <String, Object?>{"b": 1},
        "doc3": <String, Object?>{"a": 3, "b": 2},
        "doc4": <String, Object?>{"a": 1, "b": 3},
        "doc5": <String, Object?>{"a": 1},
        "doc6": <String, Object?>{"a": 2},
      };
      var collection = await testCollectionWithDocs(testDocs);

      // Two IN operations on different fields with disjunction.
      var query1 = collection.where(
        Filter.or([
          Filter.inArray("a", <Object?>[2, 3]),
          Filter.inArray("b", <Object?>[0, 2]),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query1, ["doc1", "doc3", "doc6"]);

      // Two IN operations on the same field with disjunction.
      // a IN [0,3] || a IN [0,2] should union them (similar to: a IN [0,2,3]).
      var query2 = collection.where(
        Filter.or([
          Filter.inArray("a", <Object?>[0, 3]),
          Filter.inArray("a", <Object?>[0, 2]),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query2, ["doc3", "doc6"]);
    });

    test('testUsingInWithArrayContainsAny', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{
          "a": 1,
          "b": <Object?>[0],
        },
        "doc2": <String, Object?>{
          "b": <Object?>[1],
        },
        "doc3": <String, Object?>{
          "a": 3,
          "b": <Object?>[2, 7],
          "c": 10,
        },
        "doc4": <String, Object?>{
          "a": 1,
          "b": <Object?>[3, 7],
        },
        "doc5": <String, Object?>{"a": 1},
        "doc6": <String, Object?>{"a": 2, "c": 20},
      };
      var collection = await testCollectionWithDocs(testDocs);

      var query1 = collection.where(
        Filter.or([
          Filter.inArray("a", <Object?>[2, 3]),
          Filter.arrayContainsAny("b", <Object?>[0, 7]),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query1, [
        "doc1",
        "doc3",
        "doc4",
        "doc6",
      ]);

      var query2 = collection.where(
        Filter.or([
          Filter.and([
            Filter.inArray("a", <Object?>[2, 3]),
            Filter.equalTo("c", 10),
          ]),
          Filter.arrayContainsAny("b", <Object?>[0, 7]),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query2, ["doc1", "doc3", "doc4"]);
    });

    test('testUsingInWithArrayContains', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{
          "a": 1,
          "b": <Object?>[0],
        },
        "doc2": <String, Object?>{
          "b": <Object?>[1],
        },
        "doc3": <String, Object?>{
          "a": 3,
          "b": <Object?>[2, 7],
        },
        "doc4": <String, Object?>{
          "a": 1,
          "b": <Object?>[3, 7],
        },
        "doc5": <String, Object?>{"a": 1},
        "doc6": <String, Object?>{"a": 2},
      };
      var collection = await testCollectionWithDocs(testDocs);

      var query1 = collection.where(
        Filter.or([
          Filter.inArray("a", <Object?>[2, 3]),
          Filter.arrayContains("b", 3),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query1, ["doc3", "doc4", "doc6"]);

      var query2 = collection.where(
        Filter.and([
          Filter.inArray("a", <Object?>[2, 3]),
          Filter.arrayContains("b", 7),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query2, ["doc3"]);

      var query3 = collection.where(
        Filter.or([
          Filter.inArray("a", <Object?>[2, 3]),
          Filter.and([Filter.arrayContains("b", 3), Filter.equalTo("a", 1)]),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query3, ["doc3", "doc4", "doc6"]);

      var query4 = collection.where(
        Filter.and([
          Filter.inArray("a", <Object?>[2, 3]),
          Filter.or([Filter.arrayContains("b", 7), Filter.equalTo("a", 1)]),
        ]),
      );
      await checkQueryAndPipelineResultsMatch(query4, ["doc3"]);
    });

    test('testOrderByEquality', () async {
      var testDocs = <String, Object?>{
        "doc1": <String, Object?>{
          "a": 1,
          "b": <Object?>[0],
        },
        "doc2": <String, Object?>{
          "b": <Object?>[1],
        },
        "doc3": <String, Object?>{
          "a": 3,
          "b": <Object?>[2, 7],
          "c": 10,
        },
        "doc4": <String, Object?>{
          "a": 1,
          "b": <Object?>[3, 7],
        },
        "doc5": <String, Object?>{"a": 1},
        "doc6": <String, Object?>{"a": 2, "c": 20},
      };
      var collection = await testCollectionWithDocs(testDocs);

      var query1 = collection.where(Filter.equalTo("a", 1)).orderBy("a");
      await checkQueryAndPipelineResultsMatch(query1, ["doc1", "doc4", "doc5"]);

      var query2 = collection
          .where(Filter.inArray("a", <Object?>[2, 3]))
          .orderBy("a");
      await checkQueryAndPipelineResultsMatch(query2, ["doc6", "doc3"]);
    });
  });
}
