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
// firebase-firestore/src/androidTest/java/com/google/firebase/firestore/PipelineBsonTypeTest.java
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
// ignore_for_file: unnecessary_statements

import 'dart:typed_data';

import 'package:test/test.dart' show group, setUp, tearDown, test;

import '../util/integration_test_util.dart';
import 'android_pipeline_test_util.dart';

Blob bsonBinary(int subtype, List<int> bytes) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(bytes));

final Map<String, Map<String, Object?>> bsonDocs =
    <String, Map<String, Object?>>{
      "doc1": <String, Object?>{
        "bsonObjectId": const BsonObjectId("507f191e810c19729de860ea"),
        "bsonTimestamp": BsonTimestamp(1000, 1),
        "bsonBinary": bsonBinary(127, <int>[1, 2, 3]),
        "int32": Int32Value(100),
        "decimal128": Decimal128Value("1.2e3"),
        "regex": const RegexValue("^foo", "i"),
      },
      "doc2": <String, Object?>{
        "bsonObjectId": const BsonObjectId("507f191e810c19729de860eb"),
        "bsonTimestamp": BsonTimestamp(2000, 2),
        "bsonBinary": bsonBinary(127, <int>[1, 2, 4]),
        "int32": Int32Value(200),
        "decimal128": Decimal128Value("2.4e3"),
        "regex": const RegexValue("^bar", "i"),
      },
    };

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/android_pipeline_bson_type';
  late CollectionReference<Map<String, Object?>> collection;
  late Firestore firestore;

  group(
    'PipelineBsonTypeTest',
    skip: IntegrationTestUtil.enterpriseEmulatorSkipReason,
    () {
      setUp(() async {
        collection = await testCollectionWithDocs(bsonDocs);
        firestore = collection.firestore;
      });

      tearDown(() async {
        await IntegrationTestUtil.tearDown();
      });

      test('testSelectBsonTypes', () async {
        final PipelineSnapshot snapshot = await firestore
            .pipeline()
            .collection(collection.path)
            .sort([field("int32").ascending()])
            .select([
              field("bsonObjectId").as("oid"),
              field("bsonTimestamp").as("ts"),
              field("bsonBinary").as("bin"),
              field("int32").as("i32"),
              field("decimal128").as("dec"),
              field("regex").as("reg"),
            ])
            .execute();

        final List<PipelineResult> results = snapshot.results;
        assertThat(results).hasSize(2);
        final Map<String, Object?> data1 = results[0].data();
        assertThat(
          data1["oid"],
        ).isEqualTo(const BsonObjectId("507f191e810c19729de860ea"));
        assertThat(data1["ts"]).isEqualTo(BsonTimestamp(1000, 1));
        assertThat(data1["bin"]).isEqualTo(bsonBinary(127, <int>[1, 2, 3]));
        assertThat(data1["i32"]).isEqualTo(Int32Value(100));
        assertThat(data1["dec"]).isEqualTo(Decimal128Value("1.2e3"));
        assertThat(data1["reg"]).isEqualTo(const RegexValue("^foo", "i"));
      });

      test('testFilterBsonTypes', () async {
        final PipelineSnapshot snapshot = await firestore
            .pipeline()
            .collection(collection.path)
            .where(field("int32").equal(constant(100)))
            .execute();

        final List<PipelineResult> results = snapshot.results;
        assertThat(results).hasSize(1);
        assertThat(results[0].data()["int32"]).isEqualTo(Int32Value(100));
      });

      test('testIsTypeBsonTypes', () async {
        final PipelineSnapshot snapshot = await firestore
            .pipeline()
            .collection(collection.path)
            .limit(1)
            .select([field("decimal128").isType("decimal128").as("isDec")])
            .execute();

        final List<PipelineResult> results = snapshot.results;
        assertThat(results).hasSize(1);
        assertThat(results[0].data()["isDec"]).isTrue();
      });

      test('testSortMixedTypes', () async {
        final Map<String, Map<String, Object?>> mixDocs =
            <String, Map<String, Object?>>{
              "2_null": <String, Object?>{"id": "null", "mix": null},
              "3_bool": <String, Object?>{"id": "bool", "mix": true},
              "4_num": <String, Object?>{"id": "num", "mix": Int32Value(42)},
              "5_ts": <String, Object?>{"id": "ts", "mix": BsonTimestamp(1, 1)},
              "6_str": <String, Object?>{"id": "str", "mix": "abc"},
              "7_blob": <String, Object?>{
                "id": "blob",
                "mix": bsonBinary(1, <int>[1, 2]),
              },
              "8_oid": <String, Object?>{
                "id": "oid",
                "mix": const BsonObjectId("507f191e810c19729de860ea"),
              },
              "9_reg": <String, Object?>{
                "id": "reg",
                "mix": const RegexValue("^foo", "i"),
              },
            };

        final CollectionReference<Map<String, Object?>> mixColl =
            await testCollectionWithDocs(mixDocs);

        final PipelineSnapshot snapshot = await mixColl.firestore
            .pipeline()
            .collection(mixColl.path)
            .sort([field("mix").ascending()])
            .select([field("id").as("id")])
            .execute();

        final List<PipelineResult> results = snapshot.results;
        assertThat(results).hasSize(8);
        assertThat(results[0].data()["id"]).isEqualTo("null");
        assertThat(results[1].data()["id"]).isEqualTo("bool");
        assertThat(results[2].data()["id"]).isEqualTo("num");
        assertThat(results[3].data()["id"]).isEqualTo("ts");
        assertThat(results[4].data()["id"]).isEqualTo("str");
        assertThat(results[5].data()["id"]).isEqualTo("blob");
        assertThat(results[6].data()["id"]).isEqualTo("oid");
        assertThat(results[7].data()["id"]).isEqualTo("reg");
      });
    },
  );
}
