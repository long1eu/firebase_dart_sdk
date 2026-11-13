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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/InequalityTests.kt
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
  test('greater than', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThan(90));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('greater than or equal', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThanOrEqual(90));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3]);
  });

  test('less than', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').lessThan(90));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('less than or equal', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').lessThanOrEqual(90));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('not equal', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 50});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').notEqual(90));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('not equal returns mixed types', () {
    final doc1 = doc('users/alice', 1000, <String, Object?>{
      'score': 90,
    }); // Should be filtered out
    final doc2 = doc('users/boc', 1000, <String, Object?>{'score': true});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 42.0});
    final doc4 = doc('users/drew', 1000, <String, Object?>{'score': 'abc'});
    final doc5 = doc('users/eric', 1000, <String, Object?>{
      'score': Timestamp(0, 2000000),
    });
    final doc6 = doc('users/francis', 1000, <String, Object?>{
      'score': GeoPoint(0.0, 0.0),
    });
    final doc7 = doc('users/george', 1000, <String, Object?>{
      'score': [42],
    });
    final doc8 = doc('users/hope', 1000, <String, Object?>{
      'score': <String, Object?>{'foo': 42},
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').notEqual(90));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc2, doc3, doc4, doc5, doc6, doc7, doc8]);
  });

  test('comparison has implicit bound', () {
    final doc1 = doc('users/alice', 1000, <String, Object?>{'score': 42});
    final doc2 = doc('users/boc', 1000, <String, Object?>{
      'score': 100.0,
    }); // Matches > 42
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': true});
    final doc4 = doc('users/drew', 1000, <String, Object?>{'score': 'abc'});
    final doc5 = doc('users/eric', 1000, <String, Object?>{
      'score': Timestamp(0, 2000000),
    });
    final doc6 = doc('users/francis', 1000, <String, Object?>{
      'score': GeoPoint(0.0, 0.0),
    });
    final doc7 = doc('users/george', 1000, <String, Object?>{
      'score': [42],
    });
    final doc8 = doc('users/hope', 1000, <String, Object?>{
      'score': <String, Object?>{'foo': 42},
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThan(42));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('not comparison returns mixed type', () {
    final doc1 = doc('users/alice', 1000, <String, Object?>{
      'score': 42,
    }); // !(42 > 90) -> !F -> T
    final doc2 = doc('users/boc', 1000, <String, Object?>{
      'score': 100.0,
    }); // !(100 > 90) -> !T -> F
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': true,
    }); // !(true > 90) -> !F -> T
    final doc4 = doc('users/drew', 1000, <String, Object?>{
      'score': 'abc',
    }); // !('abc' > 90) -> !F -> T
    final doc5 = doc('users/eric', 1000, <String, Object?>{
      'score': Timestamp(0, 2000000),
    }); // !(T > 90) -> !F -> T
    final doc6 = doc('users/francis', 1000, <String, Object?>{
      'score': GeoPoint(0.0, 0.0),
    }); // !(G > 90) -> !F -> T
    final doc7 = doc('users/george', 1000, <String, Object?>{
      'score': [42],
    }); // !(A > 90) -> !F -> T
    final doc8 = doc('users/hope', 1000, <String, Object?>{
      'score': <String, Object?>{'foo': 42},
    }); // !(M > 90) -> !F -> T
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(field('score').greaterThan(90)));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc1, doc3, doc4, doc5, doc6, doc7, doc8]);
  });

  test('inequality with equality on different field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank=2, score=90 > 80 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // rank!=2
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // rank!=2
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').equal(2), field('score').greaterThan(80)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('inequality with equality on same field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // score=90, score > 80 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
    }); // score!=90
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
    }); // score!=90
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('score').equal(90), field('score').greaterThan(80)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('with sort on same field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'score': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
    }); // score < 90
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': 97});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThanOrEqual(90))
        .sort([field('score').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3]).inOrder();
  });

  test('with sort on different fields', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    });
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score < 90
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThanOrEqual(90))
        .sort([field('rank').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc1]).inOrder();
  });

  test('with or on single field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // score not > 90 and not < 60
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
    }); // score < 60 -> Match
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
    }); // score > 90 -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(or(field('score').greaterThan(90), field('score').lessThan(60)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('with or on different fields', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // score > 80 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80, rank !< 2
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // score > 80, rank < 2 -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(or(field('score').greaterThan(80), field('rank').lessThan(2)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3]);
  });

  test('with eqAny on single field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // score > 80, but not in [50, 80, 97]
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
    }); // score > 80, score in [50, 80, 97] -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('score').greaterThan(80),
            field('score').equalAny([50, 80, 97]),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('with eqAny on different fields', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank < 3, score not in [50, 80, 97]
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // rank !< 3
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // rank < 3, score in [50, 80, 97] -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(field('rank').lessThan(3), field('score').equalAny([50, 80, 97])),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('with notEqAny on single field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'notScore': 90,
    }); // score missing
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 90,
    }); // score > 80, but score is in [90, 95]
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 50,
    }); // score !> 80
    final doc4 = doc('users/diane', 1000, <String, Object?>{
      'score': 97,
    }); // score > 80, score not in [90, 95] -> Match
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('score').greaterThan(80),
            field('score').notEqualAny([90, 95]),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('with notEqAny returns mixed types', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{'notScore': 90});
    final doc2 = doc('users/alice', 1000, <String, Object?>{'score': 90});
    final doc3 = doc('users/charlie', 1000, <String, Object?>{'score': true});
    final doc4 = doc('users/diane', 1000, <String, Object?>{'score': 42.0});
    final doc5 = doc('users/eric', 1000, <String, Object?>{
      'score': double.nan,
    });
    final doc6 = doc('users/francis', 1000, <String, Object?>{'score': 'abc'});
    final doc7 = doc('users/george', 1000, <String, Object?>{
      'score': Timestamp(0, 2000000),
    });
    final doc8 = doc('users/hope', 1000, <String, Object?>{
      'score': GeoPoint(0.0, 0.0),
    });
    final doc9 = doc('users/isla', 1000, <String, Object?>{
      'score': [42],
    });
    final doc10 = doc('users/jack', 1000, <String, Object?>{
      'score': <String, Object?>{'foo': 42},
    });
    final documents = [
      doc1,
      doc2,
      doc3,
      doc4,
      doc5,
      doc6,
      doc7,
      doc8,
      doc9,
      doc10,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').notEqualAny(['foo', 90, false]));

    final result = runPipeline(pipeline, documents);
    // Android expects doc3 to doc10: it drops doc1, whose `score` is missing.
    // The Enterprise edition emulator evaluates not_equal_any of a missing
    // value and a list of values to true
    // (not_equal_any(Field(zz), [3, a, null, 1.5]) in
    // emulator_results.golden.jsonl is true), so doc1 matches too.
    assertThat(result).containsExactlyElementsIn([
      doc1,
      doc3,
      doc4,
      doc5,
      doc6,
      doc7,
      doc8,
      doc9,
      doc10,
    ]);
  });

  test('with notEqAny on different fields', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank < 3, score is in [90, 95]
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // rank !< 3
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // rank < 3, score not in [90, 95] -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(field('rank').lessThan(3), field('score').notEqualAny([90, 95])),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('sort by equality', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank=2, score > 80 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 4,
    }); // rank!=2
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // rank!=2
    final doc4 = doc('users/david', 1000, <String, Object?>{
      'score': 91,
      'rank': 2,
    }); // rank=2, score > 80 -> Match
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').equal(2), field('score').greaterThan(80)))
        .sort([field('rank').ascending(), field('score').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc4]).inOrder();
  });

  test('with eqAny sort by equality', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 3,
    }); // rank in [2,3,4], score > 80 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 4,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // rank not in [2,3,4]
    final doc4 = doc('users/david', 1000, <String, Object?>{
      'score': 91,
      'rank': 2,
    }); // rank in [2,3,4], score > 80 -> Match
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('rank').equalAny([2, 3, 4]),
            field('score').greaterThan(80),
          ),
        )
        .sort([field('rank').ascending(), field('score').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc1]).inOrder();
  });

  test('with array', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'scores': [80, 85, 90],
      'rounds': [1, 2, 3],
    }); // scores <= [90,90,90], rounds > [1,2] -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'scores': [50, 65],
      'rounds': [1, 2],
    }); // rounds !> [1,2]
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'scores': [90, 95, 97],
      'rounds': [1, 2, 4],
    }); // scores !<= [90,90,90]
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('scores').lessThanOrEqual(array(90, 90, 90)),
            field('rounds').greaterThan(array(1, 2)),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('with arrayContainsAny', () {
    // Renamed from C++: withArrayContains
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'scores': [80, 85, 90],
      'rounds': [1, 2, 3],
    }); // scores <= [90,90,90], rounds contains 3 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'scores': [50, 65],
      'rounds': [1, 2],
    }); // rounds does not contain 3
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'scores': [90, 95, 97],
      'rounds': [1, 2, 4],
    }); // scores !<= [90,90,90]
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('scores').lessThanOrEqual(array(90, 90, 90)),
            field('rounds').arrayContains(3), // C++ used ArrayContainsExpr
          ),
        );
    // In Kotlin, arrayContains is the equivalent of C++ ArrayContainsExpr for a single element.
    // For multiple elements, it would be arrayContainsAny.

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('with sort and limit', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 3,
    });
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 4,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    });
    final doc4 = doc('users/david', 1000, <String, Object?>{
      'score': 91,
      'rank': 2,
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('score').greaterThan(80))
        .sort([field('rank').ascending()])
        .limit(2);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4]).inOrder();
  });

  test('multiple inequalities on single field', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
    }); // score !> 90
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
    }); // score !> 90
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
    }); // score > 90 and < 100 -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(field('score').greaterThan(90), field('score').lessThan(100)),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('multiple inequalities on different fields single match', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank !< 2
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 90
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // score > 90, rank < 2 -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('score').greaterThan(90), field('rank').lessThan(2)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('multiple inequalities on different fields multiple match', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // score > 80, rank < 3 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // score > 80, rank < 3 -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('score').greaterThan(80), field('rank').lessThan(3)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc3]);
  });

  test('multiple inequalities on different fields all match', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // score > 40, rank < 4 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score > 40, rank < 4 -> Match
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // score > 40, rank < 4 -> Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('score').greaterThan(40), field('rank').lessThan(4)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2, doc3]);
  });

  test('multiple inequalities on different fields no match', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank !> 3
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !< 90
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // rank !> 3
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('score').lessThan(90), field('rank').greaterThan(3)));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('multiple inequalities with bounded ranges', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // rank > 0 & < 4, score > 80 & < 95 -> Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 4,
    }); // rank !< 4
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // score !< 95
    final doc4 = doc('users/david', 1000, <String, Object?>{
      'score': 80,
      'rank': 3,
    }); // score !> 80
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('rank').greaterThan(0),
            field('rank').lessThan(4),
            field('score').greaterThan(80),
            field('score').lessThan(95),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('multiple inequalities with single sort asc', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').lessThan(3), field('score').greaterThan(80)))
        .sort([field('rank').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc1]).inOrder();
  });

  test('multiple inequalities with single sort desc', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').lessThan(3), field('score').greaterThan(80)))
        .sort([field('rank').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3]).inOrder();
  });

  test('multiple inequalities with multiple sort asc', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').lessThan(3), field('score').greaterThan(80)))
        .sort([field('rank').ascending(), field('score').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc1]).inOrder();
  });

  test('multiple inequalities with multiple sort desc', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').lessThan(3), field('score').greaterThan(80)))
        .sort([field('rank').descending(), field('score').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3]).inOrder();
  });

  test('multiple inequalities with multiple sort desc on reverse index', () {
    final doc1 = doc('users/bob', 1000, <String, Object?>{
      'score': 90,
      'rank': 2,
    }); // Match
    final doc2 = doc('users/alice', 1000, <String, Object?>{
      'score': 50,
      'rank': 3,
    }); // score !> 80
    final doc3 = doc('users/charlie', 1000, <String, Object?>{
      'score': 97,
      'rank': 1,
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(field('rank').lessThan(3), field('score').greaterThan(80)))
        .sort([field('score').descending(), field('rank').descending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc1]).inOrder();
  });
}
