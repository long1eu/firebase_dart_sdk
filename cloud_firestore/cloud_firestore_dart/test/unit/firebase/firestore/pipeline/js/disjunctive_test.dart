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

// Ported from the JS SDK:
// packages/firestore/test/unit/core/pipeline/disjunctive.test.ts
//
// The cases keep their JS names; js_pipeline_test_util.dart has the
// functions they call. JS numbers that are integral (1.0) are integers here,
// as the JS SDK encodes them.
//
// The cases that Android's DisjunctiveTests.kt has too are skipped here (they run in
// ../realtime/disjunctive_test.dart); the reason says when the JS expectation differs.

// ignore_for_file: prefer_single_quotes, always_specify_types
// ignore_for_file: lines_longer_than_80_chars, prefer_final_locals
// ignore_for_file: omit_local_variable_types, unused_local_variable
// ignore_for_file: prefer_const_declarations, prefer_const_constructors

// The documents hold doubles and 64-bit integers, which compiled to
// JavaScript are not what they are on the VM.
@TestOn('vm')
library;

import 'package:test/test.dart' show TestOn, test;

import 'js_pipeline_test_util.dart';

/// Why a case is skipped: Android's DisjunctiveTests.kt has the same case, ported in
/// ../realtime/disjunctive_test.dart.
const String sameAsAndroid =
    'The same case as in Android\'s DisjunctiveTests.kt, ported in '
    'realtime/disjunctive_test.dart.';

/// Why a case is skipped: as above, and the JS expectation differs from the
/// Enterprise edition backend, which the local executor and Android follow.
const String sameAsAndroidJsDiffers =
    'The same case as in Android\'s DisjunctiveTests.kt, ported in '
    'realtime/disjunctive_test.dart. JS expects a different result: its local '
    'evaluation treats null and missing values, NaN and errors differently '
    'from the Enterprise edition backend, which the Dart executor follows.';

void main() {
  test('eqAny_sortOnEqAnyField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10,
    });

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(
          equalAny(field('name'), [
            constant('alice'),
            constant('bob'),
            constant('charlie'),
            constant('diane'),
          ]),
        )
        .sort([field('name').ascending()]);

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5]),
    ).toEqual([doc1, doc2, doc3, doc4]);
  });

  test('or_isNullAndEqOnSameField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(or(equal(field('a'), constant(1)), field('a').equal(null)));

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6]),
    ).toEqual([doc1, doc2, doc3, doc4]);
  });

  test('or_isNullAndEqOnDifferentField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(or(equal(field('b'), constant(1)), equal(field('a'), null)));

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6]),
    ).toEqual([doc3, doc4]);
  });

  test('or_isNotNullAndEqOnSameField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(
          or(
            greaterThan(field('a'), constant(1)),
            not(equal(field('a'), null)),
          ),
        );

    // JS expects users/f (no `a`) not to match. On the Enterprise edition
    // backend equal(missing, null) is false (equal(Field(zz), Constant(null))
    // in ../evaluation/emulator_results.golden.jsonl), so not(...) is true.
    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6]),
    ).toEqual([doc1, doc2, doc3, doc5, doc6]);
  });

  test('or_isNotNullAndEqOnDifferentField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': 1});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc4 = doc('users/d', 1000, <String, Object?>{'a': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'a': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(
          or(equal(field('b'), constant(1)), not(equal(field('a'), null))),
        );

    // JS expects users/f (no `a`) not to match. On the Enterprise edition
    // backend equal(missing, null) is false (equal(Field(zz), Constant(null))
    // in ../evaluation/emulator_results.golden.jsonl), so not(...) is true.
    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6]),
    ).toEqual([doc1, doc2, doc3, doc5, doc6]);
  });

  test('or_isNullAndIsNaNOnSameField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 'abc'});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(or(equal(field('a'), null), equal(field('a'), double.nan)));

    // JS expects NaN not to equal NaN. On the Enterprise edition backend it
    // does (equal(Field(nan), Field(nan)) is true in
    // ../evaluation/emulator_results.golden.jsonl).
    expectThat(runPipeline(pipeline, [doc1, doc2, doc3])).toEqual([doc1, doc2]);
  });

  test('or_isNullAndIsNaNOnDifferentField', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'a': double.nan});
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 'abc'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'b': null});
    final doc5 = doc('users/e', 1000, <String, Object?>{'b': double.nan});
    final doc6 = doc('users/f', 1000, <String, Object?>{'b': 'abc'});

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(or(equal(field('a'), null), equal(field('b'), double.nan)));

    // JS expects NaN not to equal NaN. On the Enterprise edition backend it
    // does (equal(Field(nan), Field(nan)) is true in
    // ../evaluation/emulator_results.golden.jsonl).
    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5, doc6]),
    ).toEqual([doc1, doc5]);
  });

  test('multipileNotEqAnys_withOr', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100,
    });
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10,
    });

    final pipeline = db
        .pipeline()
        .collection('/users')
        .where(
          or(
            notEqualAny(field('name'), [constant('alice'), constant('bob')]),
            notEqualAny(field('age'), [constant(10), constant(25)]),
          ),
        );

    expectThat(
      runPipeline(pipeline, [doc1, doc2, doc3, doc4, doc5]),
    ).toEqual([doc1, doc3, doc4, doc5]);
  });

  test('basicEqAny', () {}, skip: sameAsAndroid);
  test('multipleEqAny', () {}, skip: sameAsAndroid);
  test('eqAny_multipleStages', () {}, skip: sameAsAndroid);
  test('multipleEqAnys_withOr', () {}, skip: sameAsAndroid);
  test('eqAny_onCollectionGroup', () {}, skip: sameAsAndroid);
  test('eqAny_withSortOnDifferentField', () {}, skip: sameAsAndroid);
  test('eqAny_withSortOnEqAnyField', () {}, skip: sameAsAndroid);
  test(
    'eqAny_withAdditionalEquality_differentFields',
    () {},
    skip: sameAsAndroid,
  );
  test('eqAny_withAdditionalEquality_sameField', () {}, skip: sameAsAndroid);
  test(
    'eqAny_withAdditionalEquality_sameField_emptyResult',
    () {},
    skip: sameAsAndroid,
  );
  test('eqAny_withInequalities_exclusiveRange', () {}, skip: sameAsAndroid);
  test('eqAny_withInequalities_inclusiveRange', () {}, skip: sameAsAndroid);
  test('eqAny_withInequalitiesAndSort', () {}, skip: sameAsAndroid);
  test('eqAny_withNotEqual', () {}, skip: sameAsAndroid);
  test(
    'eqAny_singleValue_sortOnInField_ambiguousOrder',
    () {},
    skip: sameAsAndroid,
  );
  test('eqAny_withExtraEquality_sortOnEqAnyField', () {}, skip: sameAsAndroid);
  test('eqAny_withExtraEquality_sortOnEquality', () {}, skip: sameAsAndroid);
  test('eqAny_withInequality_onSameField', () {}, skip: sameAsAndroid);
  test(
    'eqAny_withDifferentInequality_sortOnEqAnyField',
    () {},
    skip: sameAsAndroid,
  );
  test('eqAny_containsNull', () {}, skip: sameAsAndroidJsDiffers);
  test('arrayContains_null', () {}, skip: sameAsAndroidJsDiffers);
  test('arrayContainsAny_null', () {}, skip: sameAsAndroid);
  test('eqAny_containsNullOnly', () {}, skip: sameAsAndroidJsDiffers);
  test('basicArrayContainsAny', () {}, skip: sameAsAndroid);
  test('multipleArrayContainsAny', () {}, skip: sameAsAndroid);
  test('arrayContainsAny_withInequality', () {}, skip: sameAsAndroid);
  test('arrayContainsAny_withIn', () {}, skip: sameAsAndroid);
  test('basicOr', () {}, skip: sameAsAndroid);
  test('multipleOr', () {}, skip: sameAsAndroid);
  test('or_multipleStages', () {}, skip: sameAsAndroid);
  test('or_twoConjunctions', () {}, skip: sameAsAndroid);
  test('or_withInAnd', () {}, skip: sameAsAndroid);
  test('andOfTwoOrs', () {}, skip: sameAsAndroid);
  test('orOfTwoOrs', () {}, skip: sameAsAndroid);
  test('or_withEmptyRangeInOneDisjunction', () {}, skip: sameAsAndroid);
  test('or_withSort', () {}, skip: sameAsAndroid);
  test('or_withInequalityAndSort_sameField', () {}, skip: sameAsAndroid);
  test('or_withInequalityAndSort_differentFields', () {}, skip: sameAsAndroid);
  test('or_withInequalityAndSort_multipleFields', () {}, skip: sameAsAndroid);
  test('or_withSortOnPartialMissingField', () {}, skip: sameAsAndroid);
  test('or_withLimit', () {}, skip: sameAsAndroid);
  test('basicNotEqAny', () {}, skip: sameAsAndroid);
  test('multipleNotEqAnys', () {}, skip: sameAsAndroid);
  test('notEqAny_onCollectionGroup', () {}, skip: sameAsAndroid);
  test('notEqAny_withSort', () {}, skip: sameAsAndroid);
  test(
    'notEqAny_withAdditionalEquality_differentFields',
    () {},
    skip: sameAsAndroid,
  );
  test('notEqAny_withAdditionalEquality_sameField', () {}, skip: sameAsAndroid);
  test('notEqAny_withInequalities_exclusiveRange', () {}, skip: sameAsAndroid);
  test('notEqAny_withInequalities_inclusiveRange', () {}, skip: sameAsAndroid);
  test('notEqAny_withInequalitiesAndSort', () {}, skip: sameAsAndroid);
  test('notEqAny_withNotEqual', () {}, skip: sameAsAndroid);
  test('notEqAny_sortOnNotEqAnyField', () {}, skip: sameAsAndroid);
  test(
    'notEqAny_singleValue_sortOnNotEqAnyField_ambiguousOrder',
    () {},
    skip: sameAsAndroid,
  );
  test(
    'notEqAny_withExtraEquality_sortOnNotEqAnyField',
    () {},
    skip: sameAsAndroid,
  );
  test('notEqAny_withExtraEquality_sortOnEquality', () {}, skip: sameAsAndroid);
  test('notEqAny_withInequality_onSameField', () {}, skip: sameAsAndroid);
  test(
    'notEqAny_withDifferentInequality_sortOnInField',
    () {},
    skip: sameAsAndroid,
  );
  test('noLimitOnNumOfDisjunctions', () {}, skip: sameAsAndroid);
  test('eqAny_duplicateValues', () {}, skip: sameAsAndroid);
  test('notEqAny_duplicateValues', () {}, skip: sameAsAndroid);
  test('arrayContainsAny_duplicateValues', () {}, skip: sameAsAndroid);
  test('arrayContainsAll_duplicateValues', () {}, skip: sameAsAndroid);
}
