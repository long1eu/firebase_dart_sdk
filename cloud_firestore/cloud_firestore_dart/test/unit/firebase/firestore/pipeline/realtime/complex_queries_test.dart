// Copyright 2025 Google LLC
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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/ComplexQueriesTests.kt
//
// The port keeps the names and the structure of the Kotlin tests;
// realtime_pipeline_test_util.dart has the functions they call. Where the
// expected result differs from Android's, a comment says why.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles with integral values (1.0, -0.0) and 64-bit
// integers, which compiled to JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import 'realtime_pipeline_test_util.dart';

void main() {
  const String collectionId = 'test';
  int docIdCounter = 1;
  String nextDocId() => '$collectionId/${docIdCounter++}';
  List<TestDocument> seedDatabase(
    int numOfDocuments,
    int numOfFields,
    Object? Function(int docIndex, int fieldIndex) valueSupplier,
  ) {
    docIdCounter = 1; // Reset for each seed
    return List<TestDocument>.generate(numOfDocuments, (int docIndex) {
      final Map<String, Object?> fields = <String, Object?>{
        for (int fieldIndex = 1; fieldIndex <= numOfFields; fieldIndex++)
          'field_$fieldIndex': valueSupplier(docIndex, fieldIndex),
      };
      return doc(nextDocId(), 1000, fields);
    });
  }

  test('where with max number of stages', () {
    final numOfFields = 127;
    var valueCounter = 1;
    final documents = seedDatabase(10, numOfFields, (_, _) => valueCounter++);

    var pipeline = RealtimePipelineSource().collection(collectionId);
    for (int i = 1; i <= numOfFields; i++) {
      pipeline = pipeline.where(field('field_$i').greaterThan(0));
    }

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(documents);
  });

  test('eqAny with max number of elements', () {
    final numOfDocuments = 1000;
    final maxElements = 3000;
    var valueCounter = 1;
    final documentsSource = seedDatabase(
      numOfDocuments,
      1,
      (_, _) => valueCounter++,
    );
    final nonMatchingDoc = doc(nextDocId(), 1000, <String, Object?>{
      'field_1': 3001,
    });
    final allDocuments = [...documentsSource, nonMatchingDoc];

    final values = List<int>.generate(maxElements, (i) => i + 1);

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(field('field_1').equalAny(values));

    final result = runPipeline(pipeline, allDocuments);
    assertThat(result).containsExactlyElementsIn(documentsSource);
  });

  test('eqAny with max number of elements on multiple fields', () {
    final numOfFields = 10;
    final numOfDocuments = 100;
    final maxElements = 3000;
    var valueCounter = 1;
    final documentsSource = seedDatabase(
      numOfDocuments,
      numOfFields,
      (_, _) => valueCounter++,
    );
    final nonMatchingDoc = doc(nextDocId(), 1000, <String, Object?>{
      'field_1': 3001,
    });
    final allDocuments = [...documentsSource, nonMatchingDoc];

    final values = List<int>.generate(maxElements, (i) => i + 1);
    final conditions = [
      for (int i = 1; i <= numOfFields; i++) field('field_$i').equalAny(values),
    ];

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(conditions.first.and(conditions[1], conditions.sublist(2)));

    final result = runPipeline(pipeline, allDocuments);
    assertThat(result).containsExactlyElementsIn(documentsSource);
  });

  test('notEqAny with max number of elements', () {
    final numOfDocuments = 1000;
    final maxElements = 3000;
    var valueCounter = 1;
    final documentsSource = seedDatabase(
      numOfDocuments,
      1,
      (_, _) => valueCounter++,
    );
    final matchingDoc = doc(nextDocId(), 1000, <String, Object?>{
      'field_1': 3001,
    });
    final allDocuments = [...documentsSource, matchingDoc];

    final values = List<int>.generate(maxElements, (i) => i + 1);

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(field('field_1').notEqualAny(values));

    final result = runPipeline(pipeline, allDocuments);
    assertThat(result).containsExactly([matchingDoc]);
  });

  test('notEqAny with max number of elements on multiple fields', () {
    final numOfFields = 10;
    final numOfDocuments = 100;
    final maxElements = 3000;
    // Seed documents where field_x = (docIndex * numOfFields) + fieldIndex_1_based
    // This makes values unique and predictable.
    // For doc 0, field_1=1, field_2=2 ... field_10=10
    // For doc 1, field_1=11, field_2=12 ... field_10=20
    // Max value will be (99*10)+10 = 990+10 = 1000.
    final documentsSource = seedDatabase(
      numOfDocuments,
      numOfFields,
      (docIdx, fieldIdx) => (docIdx * numOfFields) + fieldIdx,
    );

    // This doc has field_1 = 3001 (which is NOT IN 1..3000)
    // Other fields are not set, so they are absent.
    // An absent field when checked with notEqAny(someList) should evaluate to true (as it's not in
    // the list).
    final matchingDocData = <String, Object?>{'field_1': (maxElements + 1)};
    // For the OR condition to be specific to field_1, other fields in matchingDoc
    // must be IN the `values` list if they exist.
    // Let's make other fields in matchingDoc have values that are in the `values` list.
    for (int i = 2; i <= numOfFields; i++) {
      matchingDocData['field_$i'] = i; // value i is in 1..3000
    }
    final matchingDoc = doc(nextDocId(), 1000, matchingDocData);
    final allDocuments = [...documentsSource, matchingDoc];

    final values = List<int>.generate(maxElements, (i) => i + 1); // 1 to 3000

    final conditions = [
      for (int i = 1; i <= numOfFields; i++)
        field('field_$i').notEqualAny(values),
    ];

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(conditions.first.or(conditions[1], conditions.sublist(2)));

    final result = runPipeline(pipeline, allDocuments);
    // matchingDoc: field_1=3001 (not in values) -> true. Other fields are in values. So OR is true.
    // documentsSource: All fields have values from 1 to 1000. All are IN `values`. So notEqAny is
    // false for all fields. OR is false.
    assertThat(result).containsExactly([matchingDoc]);
  });

  test('arrayContainsAny with large number of elements', () {
    final numOfDocuments = 1000;
    final maxElements = 3000;
    var valueCounter = 1;
    final documentsSource = seedDatabase(
      numOfDocuments,
      1,
      (_, _) => [valueCounter++],
    ); // field_1 contains [valueCounter]
    final nonMatchingDoc = doc(nextDocId(), 1000, <String, Object?>{
      'field_1': [(maxElements + 1)],
    });
    final allDocuments = [...documentsSource, nonMatchingDoc];

    final valuesToSearch = List<int>.generate(maxElements, (i) => i + 1);

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(field('field_1').arrayContainsAny(valuesToSearch));

    final result = runPipeline(pipeline, allDocuments);
    assertThat(result).containsExactlyElementsIn(documentsSource);
  });

  test('arrayContainsAny with max number of elements on multiple fields', () {
    final numOfFields = 10;
    final numOfDocuments = 100;
    final maxElements = 3000;
    var valueCounter = 1;
    final documentsSource = seedDatabase(
      numOfDocuments,
      numOfFields,
      (_, _) => [valueCounter++],
    );

    // nonMatchingDoc: field_1 = [3001]. Other fields will be arrays like [3002], [3003] etc.
    // if we use valueCounter for them.
    // To make it non-matching for an OR condition, all its array fields must not contain any of
    // valuesToSearch.
    final nonMatchingDocData = <String, Object?>{
      for (int i = 1; i <= numOfFields; i++) 'field_$i': [(maxElements + i)],
    };
    final nonMatchingDoc = doc(nextDocId(), 1000, nonMatchingDocData);
    final allDocuments = [...documentsSource, nonMatchingDoc];

    final valuesToSearch = List<int>.generate(
      maxElements,
      (i) => i + 1,
    ); // 1 to 3000

    final conditions = [
      for (int i = 1; i <= numOfFields; i++)
        field('field_$i').arrayContainsAny(valuesToSearch),
    ];

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(conditions.first.or(conditions[1], conditions.sublist(2)));

    final result = runPipeline(pipeline, allDocuments);
    // documentsSource: each field_i has a list like [some_value_between_1_and_1000].
    // Since valuesToSearch is [1..3000], arrayContainsAny will be true for each field. So OR is
    // true.
    // nonMatchingDoc: field_i has list like [3000+i]. None of these are in valuesToSearch.
    // So arrayContainsAny is false for all fields. OR is false.
    assertThat(result).containsExactlyElementsIn(documentsSource);
  });

  test('sortBy max num of fields without index', () {
    final numOfFields = 31;
    final numOfDocuments = 100;
    // All docs have field_i = 10
    final documents = seedDatabase(numOfDocuments, numOfFields, (_, _) => 10);

    final sortOrders = [
      for (int i = 1; i <= numOfFields; i++) field('field_$i').ascending(),
      Field.of(FieldPath.documentIdField).ascending(),
    ];

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .sort(sortOrders);

    // Since all field values are the same, sort order is determined by document ID.
    final expectedDocs = [...documents]..sort((a, b) => a.key.compareTo(b.key));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(expectedDocs).inOrder();
  });

  test('where with nested add function max depth', () {
    final numOfFields = 1;
    final numOfDocuments = 10;
    final depth = 31;
    // All docs have field_1 = 0
    final documents = seedDatabase(numOfDocuments, numOfFields, (_, _) => 0);

    Expression addExpr = field('field_1');
    for (int i = 1; i <= depth; i++) {
      addExpr = add(addExpr, constant(1));
    }
    // addExpr is field_1 + 1 (depth times) = field_1 + depth = 0 + 31 = 31

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(addExpr.greaterThan(0)); // 31 > 0 is true

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn(documents);
  });

  test('where with large number ors', () {
    final numOfFields = 100;
    final numOfDocuments = 50;
    // valueCounter removed as it was unused here. Seed values are generated based on docIdx and
    // fieldIdx.
    // field_1 = 1, field_2 = 2, ..., field_100 = 100 (for first doc)
    // field_1 = 101, field_2 = 102, ..., field_100 = 200 (for second doc)
    // ...
    // Max value assigned will be for the last field of the last document:
    // (49 * 100) + 100 = 4900 + 100 = 5000
    final documents = seedDatabase(
      numOfDocuments,
      numOfFields,
      (docIdx, fieldIdx) => (docIdx * numOfFields) + fieldIdx,
    );
    final maxValueInDb =
        (numOfDocuments - 1) * numOfFields + numOfFields; // 5000

    final orConditions = [
      for (int i = 1; i <= numOfFields; i++)
        field('field_$i').lessThanOrEqual(maxValueInDb),
    ];

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(orConditions.first.or(orConditions[1], orConditions.sublist(2)));

    final result = runPipeline(pipeline, documents);
    // Every document will have at least one field_i <= maxValueInDb (actually all fields are)
    assertThat(result).containsExactlyElementsIn(documents);
  });

  test('where with large number of conjunctions', () {
    final numOfFields = 50;
    final numOfDocuments = 100;
    // Values from 1 up to 100 * 50 = 5000
    final documents = seedDatabase(
      numOfDocuments,
      numOfFields,
      (docIdx, fieldIdx) => (docIdx * numOfFields) + fieldIdx,
    );

    final andConditions1 = [
      for (int i = 1; i <= numOfFields; i++) field('field_$i').greaterThan(0),
    ]; // Use 0 for clarity with Long types
    final andConditions2 = [
      for (int i = 1; i <= numOfFields; i++)
        field('field_$i').lessThan(maxLong),
    ];

    final pipeline = RealtimePipelineSource()
        .collection(collectionId)
        .where(
          or(
            andConditions1.first.and(
              andConditions1[1],
              andConditions1.sublist(2),
            ),
            andConditions2.first.and(
              andConditions2[1],
              andConditions2.sublist(2),
            ),
          ),
        );
    final result = runPipeline(pipeline, documents);
    // All seeded values are > 0 and < maxLong, so all documents match.
    assertThat(result).containsExactlyElementsIn(documents);
  });
}
