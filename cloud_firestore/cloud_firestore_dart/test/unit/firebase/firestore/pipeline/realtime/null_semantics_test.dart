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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/NullSemanticsTests.kt
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
  // ===================================================================
  // Where Tests
  // ===================================================================
  test('whereIsNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'score': null,
    }); // score: null -> Match
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'score': <Object?>[],
    }); // score: []
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    }); // score: [null]
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': <String, Object?>{},
    }); // score: {}
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': 42,
    }); // score: 42
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': double.nan,
    }); // score: NaN
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': 42,
    }); // score: missing
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equal(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereIsNotNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'score': null,
    }); // score: null
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'score': <Object?>[],
    }); // score: [] -> Match
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    }); // score: [null] -> Match
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': <String, Object?>{},
    }); // score: {} -> Match
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': 42,
    }); // score: 42 -> Match
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': double.nan,
    }); // score: NaN -> Match
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': 42,
    }); // score: missing
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(exists(field('score')), field('score').notEqual(nullValue())),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactlyElementsIn([doc2, doc3, doc4, doc5, doc6]);
  });

  test('whereIsNullAndIsNotNullEmpty', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'score': [null],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{'score': 42});
    final doc4 = doc('users/d', 1000, <String, Object?>{'bar': 42});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            equal(field('score'), nullValue()),
            and(exists(field('score')), field('score').notEqual(nullValue())),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('whereEqConstantAsNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{'score': double.nan});
    final doc4 = doc('users/4', 1000, <String, Object?>{'not-score': 42});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equal(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqFieldAsNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'score': null,
      'rank': null,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'score': 42,
      'rank': null,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': null,
      'rank': 42,
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': null});
    final doc5 = doc('users/5', 1000, <String, Object?>{'rank': null});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equal(field('score'), field('rank')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqSegmentField', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'score': <String, Object?>{'bonus': null},
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'score': <String, Object?>{'bonus': 42},
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': <String, Object?>{'bonus': double.nan},
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': <String, Object?>{'not-bonus': 42},
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{'score': 'foo-bar'});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'not-score': <String, Object?>{'bonus': 42},
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equal(field('score.bonus'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqSingleFieldAndSegmentField', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'score': <String, Object?>{'bonus': null},
      'rank': null,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'score': <String, Object?>{'bonus': 42},
      'rank': null,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': <String, Object?>{'bonus': double.nan},
      'rank': null,
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': <String, Object?>{'not-bonus': 42},
      'rank': null,
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{'score': 'foo-bar'});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'not-score': <String, Object?>{'bonus': 42},
      'rank': null,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            equal(field('score.bonus'), nullValue()),
            equal(field('rank'), nullValue()),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqNullInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(field('foo'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqNullOtherInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [1, null],
    }); // Note: 1 becomes 1.0
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(field('foo'), array(constant(1.0), nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc3]);
  });

  test('whereEqNullNanInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(field('foo'), array(nullValue(), constant(double.nan))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('whereEqNullInMap', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1.0, 'b': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': double.nan},
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(field('foo'), map(<String, Object?>{'a': nullValue()})));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqNullOtherInMap', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1.0, 'b': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1, 'b': null},
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': double.nan},
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(
            field('foo'),
            map(<String, Object?>{'a': constant(1.0), 'b': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc3]);
  });

  test('whereEqNullNanInMap', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1.0, 'b': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': double.nan},
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(
            field('foo'),
            map(<String, Object?>{'a': nullValue(), 'b': constant(double.nan)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('whereEqMapWithNullArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null],
      },
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1.0, null],
      },
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null, double.nan],
      },
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': <Object?>[]},
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1.0],
      },
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null, 1.0],
      },
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'not-a': [null],
      },
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(field('foo'), map(<String, Object?>{'a': array(nullValue())})),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqMapWithNullOtherArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null],
      },
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1.0, null],
      },
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1, null],
      },
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null, double.nan],
      },
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': <Object?>[]},
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1.0],
      },
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null, 1.0],
      },
    });
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'not-a': [null],
      },
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(
            field('foo'),
            map(<String, Object?>{'a': array(constant(1.0), nullValue())}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc3]);
  });

  test('whereEqMapWithNullNanArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null],
      },
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1.0, null],
      },
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null, double.nan],
      },
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': <Object?>[]},
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [1.0],
      },
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'a': [null, 1.0],
      },
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': <String, Object?>{
        'not-a': [null],
      },
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(
            field('foo'),
            map(<String, Object?>{
              'a': array(nullValue(), constant(double.nan)),
            }),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('whereCompositeConditionWithNull', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'score': 42,
      'rank': null,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'score': 42,
      'rank': 42,
    });
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            equal(field('score'), constant(42)),
            equal(field('rank'), nullValue()),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqAnyNullOnly', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/c', 1000, <String, Object?>{'rank': 42});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equalAny(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqAnyPartialNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': <Object?>[]});
    final doc3 = doc('users/3', 1000, <String, Object?>{'score': 25});
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': 100}); // Match
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 100});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equalAny(field('score'), array(nullValue(), constant(100))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc4]);
  });

  test('whereArrayContainsNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': <Object?>[]});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': [101, null],
    });
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': ['foo', 'bar'],
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': ['foo', 'bar'],
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'not-score': ['foo', null],
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'not-score': [null, 'foo'],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8, doc9];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(arrayContains(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4, doc5]);
  });

  test('whereArrayContainsAnyOnlyNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': <Object?>[]});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': [101, null],
    });
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': ['foo', 'bar'],
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': ['foo', 'bar'],
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'not-score': ['foo', null],
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'not-score': [null, 'foo'],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8, doc9];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(arrayContainsAny(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4, doc5]);
  });

  test('whereArrayContainsAnyPartialNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': <Object?>[]});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': [101, null],
    });
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': ['foo', 'bar'],
    }); // Match 'foo'
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': ['foo', 'bar'],
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'not-score': ['foo', null],
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'not-score': [null, 'foo'],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8, doc9];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          arrayContainsAny(field('score'), array(nullValue(), constant('foo'))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4, doc5, doc6]);
  });

  test('whereArrayContainsAllOnlyNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': <Object?>[]});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': [101, null],
    });
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': ['foo', 'bar'],
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': ['foo', 'bar'],
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'not-score': ['foo', null],
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'not-score': [null, 'foo'],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8, doc9];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(arrayContainsAll(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc3, doc4, doc5]);
  });

  test('whereArrayContainsAllPartialNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': <Object?>[]});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': [null],
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc5 = doc('users/5', 1000, <String, Object?>{
      'score': [101, null],
    });
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': ['foo', 'bar'],
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'not-score': ['foo', 'bar'],
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'not-score': ['foo', null],
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'not-score': [null, 'foo'],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8, doc9];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          arrayContainsAll(field('score'), array(nullValue(), constant(42))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('whereNeqConstantAsNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{'score': double.nan});
    final doc4 = doc('users/4', 1000, <String, Object?>{'not-score': 42});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(notEqual(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3, doc4]);
  });

  test('whereNeqFieldAsNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{
      'score': null,
      'rank': null,
    });
    final doc2 = doc('users/2', 1000, <String, Object?>{
      'score': 42,
      'rank': null,
    });
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': null,
      'rank': 42,
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': null});
    final doc5 = doc('users/5', 1000, <String, Object?>{'rank': null});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(notEqual(field('score'), field('rank')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3, doc4, doc5]);
  });

  // ... (Tests between these are unchanged, but the replace tool needs context or separate calls. I
  // will use separate calls or a large block if contiguous)
  // The tests are not contiguous. I will use separate replacements.
  // Actually, wait. `whereNeqConstantAsNull` is followed by `whereNeqFieldAsNull` which is followed
  // by others. `whereGt` is further down.
  // I will do `whereNeq` tests first.
  test('whereNeqNullInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(notEqual(field('foo'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('whereNeqNullOtherInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [1, null],
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(notEqual(field('foo'), array(constant(1.0), nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc4]);
  });

  test('whereNeqNullNanInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          notEqual(field('foo'), array(nullValue(), constant(double.nan))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('whereNeqNullInMap', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1.0, 'b': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': double.nan},
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          notEqual(field('foo'), map(<String, Object?>{'a': nullValue()})),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc2, doc3]);
  });

  test('whereNeqNullOtherInMap', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1.0, 'b': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1, 'b': null},
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': double.nan},
    });
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          notEqual(
            field('foo'),
            map(<String, Object?>{'a': constant(1.0), 'b': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc4]);
  });

  test('whereNeqNullNanInMap', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1.0, 'b': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': double.nan},
    });
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          notEqual(
            field('foo'),
            map(<String, Object?>{'a': nullValue(), 'b': constant(double.nan)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactlyElementsIn([doc1, doc2]);
  });

  test('whereNotEqAnyWithNull', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/b', 1000, <String, Object?>{'score': 42});
    final documents = [doc1, doc2];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(notEqualAny(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('whereGt', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('whereGte', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThanOrEqual(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereLt', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('whereLte', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThanOrEqual(field('score'), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereAnd', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': true, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': false, 'b': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': null});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': true, 'b': true});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(and(field('a').asBoolean(), field('b').asBoolean()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('whereIsErrorAnd', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null, 'b': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': true});
    final doc5 = doc('k/5', 1000, <String, Object?>{'a': null, 'b': false});
    final doc6 = doc('k/6', 1000, <String, Object?>{'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': true, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{'a': false, 'b': null});
    final doc9 = doc('k/9', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });
    final doc10 = doc('k/10', 1000, <String, Object?>{'a': 1, 'b': 2});
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
        .collection('k')
        .where(isError(and(field('a').asBoolean(), field('b').asBoolean())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc10]);
  });

  test('whereOr', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': true, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': false, 'b': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': null});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(or(field('a').asBoolean(), field('b').asBoolean()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1]);
  });

  test('whereEqNullOr', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': true});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': false});
    final doc5 = doc('k/5', 1000, <String, Object?>{'b': null});
    final doc6 = doc('k/6', 1000, <String, Object?>{'a': true, 'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': false, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(
            or(field('a').asBoolean(), field('b').asBoolean()),
            nullValue(),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc4, doc5, doc7, doc8]);
  });

  test('whereIsErrorOr', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null, 'b': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': true});
    final doc5 = doc('k/5', 1000, <String, Object?>{'a': null, 'b': false});
    final doc6 = doc('k/6', 1000, <String, Object?>{'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': true, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{'a': false, 'b': null});
    final doc9 = doc('k/9', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });
    final doc10 = doc('k/10', 1000, <String, Object?>{'a': 1, 'b': 2});
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
        .collection('k')
        .where(isError(or(field('a').asBoolean(), field('b').asBoolean())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc10]);
  });

  test('whereXor', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': true, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': false, 'b': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': null});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': true, 'b': false});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(xor(field('a').asBoolean(), field('b').asBoolean()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('whereEqNullXor', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null, 'b': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null, 'b': true});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': false});
    final doc5 = doc('k/5', 1000, <String, Object?>{'b': null});
    final doc6 = doc('k/6', 1000, <String, Object?>{'a': true, 'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': false, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(
          equal(
            xor(field('a').asBoolean(), field('b').asBoolean()),
            nullValue(),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8]);
  });

  test('whereIsErrorXor', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': null, 'b': null});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null});
    final doc4 = doc('k/4', 1000, <String, Object?>{'a': null, 'b': true});
    final doc5 = doc('k/5', 1000, <String, Object?>{'a': null, 'b': false});
    final doc6 = doc('k/6', 1000, <String, Object?>{'b': null});
    final doc7 = doc('k/7', 1000, <String, Object?>{'a': true, 'b': null});
    final doc8 = doc('k/8', 1000, <String, Object?>{'a': false, 'b': null});
    final doc9 = doc('k/9', 1000, <String, Object?>{
      'not-a': true,
      'not-b': true,
    });
    final doc10 = doc('k/10', 1000, <String, Object?>{'a': 1, 'b': 2});
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
        .collection('k')
        .where(isError(xor(field('a').asBoolean(), field('b').asBoolean())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc10]);
  });

  test('whereNot', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': true});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': false});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': null});
    final documents = [doc1, doc2, doc3];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(not(field('a').asBoolean()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('whereEqNullNot', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': true});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': false});
    final doc4 = doc('k/4', 1000, <String, Object?>{'not-a': true});
    final documents = [doc1, doc2, doc3, doc4];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equal(not(field('a').asBoolean()), nullValue()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc4]);
  });

  test('whereIsErrorNot', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'a': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{'a': true});
    final doc3 = doc('k/3', 1000, <String, Object?>{'a': false});
    final doc4 = doc('k/4', 1000, <String, Object?>{'not-a': true});
    final doc5 = doc('k/5', 1000, <String, Object?>{'a': 1});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(isError(not(field('a').asBoolean())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5]);
  });

  test('whereEqFieldAsUnset', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'rank': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'unset': null});
    final doc3 = doc('users/3', 1000, <String, Object?>{'rank': 42});
    final doc4 = doc('users/4', 1000, <String, Object?>{'unset': 'foo'});
    final doc5 = doc('users/5', 1000, <String, Object?>{});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(equal(field('unset'), field('rank')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5]);
  });

  test('whereEqAnyNullInArray', () {
    final doc1 = doc('k/1', 1000, <String, Object?>{'foo': null});
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [
        [null],
      ],
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': [1.0, null],
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': [null, double.nan],
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('k')
        .where(equalAny(field('foo'), array(array(nullValue()))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2]);
  });

  test('whereGtArrayEmpty', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), array()));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc14, doc15, doc16, doc17, doc18, doc19]);
  });

  test('whereGtArraySingleton', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), array(constant(42))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc18, doc19]);
  });

  test('whereGtArraySingletonNull', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc16, doc17, doc18, doc19]);
  });

  test('whereGtArrayNullFirst', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), array(nullValue(), constant(42))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc16, doc18, doc19]);
  });

  test('whereGtArrayNullLast', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
    });
    final doc20 = doc('users/20', 1000, <String, Object?>{
      'score': [43, null],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
      doc20,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), array(constant(42), nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc19, doc20]);
  });

  test('whereGtMapEmpty', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThan(field('score'), map(<String, Object?>{})));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc7, doc8, doc9, doc10, doc11, doc12]);
  });

  test('whereGtMapSingleton', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThan(
            field('score'),
            map(<String, Object?>{'a': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc8, doc11, doc12]);
  });

  test('whereGtMapSingletonNull', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThan(field('score'), map(<String, Object?>{'a': nullValue()})),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc7, doc8, doc10, doc11, doc12]);
  });

  test('whereGtMapNullFirst', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
    });
    // Java adds doc13 with 'c' to null, but logic same without it if not referenced
    // Java test `where_gt_map_nullFirst_database` creates:
    // doc13: {c:null}
    // Query: {a:null, b:42}
    // result: doc7, doc8, doc11, doc12, doc13.
    // doc10 ({a:null, b:42}) is EQUAL, so not GT.
    // doc9 ({a:null}) < {a:null, b:42}
    // Wait, {a:null} is shorter than {a:null, b:42}, so it's smaller. Correct.

    // I'll add doc20 for completeness if I want to match Java exactly but I'll stick to doc1-19 +
    // maybe doc20 if needed.
    // Java: doc13 = {c:null}.
    // Let's add it to be safe.
    final doc20 = doc('users/20', 1000, <String, Object?>{
      'score': <String, Object?>{'c': null},
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
      doc20,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThan(
            field('score'),
            map(<String, Object?>{'a': nullValue(), 'b': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc7, doc8, doc11, doc12, doc20]);
  });

  test('whereGtMapNullLast', () {
    // Docs same as above
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThan(
            field('score'),
            map(<String, Object?>{'a': constant(42), 'b': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc8, doc12]);
  });

  test('whereGteArrayEmpty', () {
    // Reuse docs setup
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThanOrEqual(field('score'), array()));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc13, doc14, doc15, doc16, doc17, doc18, doc19]);
  });

  test('whereGteArraySingleton', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThanOrEqual(field('score'), array(constant(42))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc16, doc18, doc19]);
  });

  test('whereGteArraySingletonNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThanOrEqual(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc14, doc15, doc16, doc17, doc18, doc19]);
  });

  test('whereGteArrayNullFirst', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThanOrEqual(field('score'), array(nullValue(), constant(42))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc16, doc17, doc18, doc19]);
  });

  test('whereGteArrayNullLast', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThanOrEqual(field('score'), array(constant(42), nullValue())),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc15, doc18, doc19]);
  });

  test('whereGteMapEmpty', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(greaterThanOrEqual(field('score'), map(<String, Object?>{})));

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc6, doc7, doc8, doc9, doc10, doc11, doc12]);
  });

  test('whereGteMapSingleton', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc7, doc8, doc11, doc12]);
  });

  test('whereGteMapSingletonNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
    });
    final doc20 = doc('users/20', 1000, <String, Object?>{
      'score': <String, Object?>{'c': null},
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
      doc20,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc7, doc8, doc9, doc10, doc11, doc12, doc20]);
  });

  test('whereGteMapNullFirst', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
    });
    final doc20 = doc('users/20', 1000, <String, Object?>{
      'score': <String, Object?>{'c': null},
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
      doc20,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': nullValue(), 'b': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(
      result,
    ).containsExactly([doc7, doc8, doc10, doc11, doc12, doc20]);
  });

  test('whereGteMapNullLast', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          greaterThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': constant(42), 'b': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc8, doc11, doc12]);
  });

  test('whereLtArrayEmpty', () {
    // Reuse docs setup
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), array()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('whereLtArraySingleton', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
    });
    final doc21 = doc('users/21', 1000, <String, Object?>{
      'score': [41, null],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
      doc21,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), array(constant(42))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14, doc17, doc21]);
  });

  test('whereLtArraySingletonNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13]);
  });

  test('whereLtArrayNullFirst', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), array(nullValue(), constant(42))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14]);
  });

  test('whereLtArrayNullLast', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), array(constant(42), nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14, doc16, doc17]);
  });

  test('whereLtMapEmpty', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThan(field('score'), map(<String, Object?>{})));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('whereLtMapSingleton', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThan(field('score'), map(<String, Object?>{'a': constant(42)})),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc9, doc10]);
  });

  test('whereLtMapSingletonNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThan(field('score'), map(<String, Object?>{'a': nullValue()})),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6]);
  });

  test('whereLtMapNullFirst', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThan(
            field('score'),
            map(<String, Object?>{'a': nullValue(), 'b': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc9]);
  });

  test('whereLtMapNullLast', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThan(
            field('score'),
            map(<String, Object?>{'a': constant(42), 'b': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc7, doc9, doc10]);
  });

  test('whereLteArrayEmpty', () {
    // Reuse docs setup
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThanOrEqual(field('score'), array()));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13]);
  });

  test('whereLteArraySingleton', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
    });
    final doc21 = doc('users/21', 1000, <String, Object?>{
      'score': [41, null],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
      doc21,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThanOrEqual(field('score'), array(constant(42))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14, doc16, doc17, doc21]);
  });

  test('whereLteArraySingletonNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThanOrEqual(field('score'), array(nullValue())));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14]);
  });

  test('whereLteArrayNullFirst', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThanOrEqual(field('score'), array(nullValue(), constant(42))),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14, doc17]);
  });

  test('whereLteArrayNullLast', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThanOrEqual(field('score'), array(constant(42), nullValue())),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc13, doc14, doc16, doc17, doc18]);
  });

  test('whereLteMapEmpty', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(lessThanOrEqual(field('score'), map(<String, Object?>{})));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6]);
  });

  test('whereLteMapSingleton', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc7, doc9, doc10]);
  });

  test('whereLteMapSingletonNull', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc9]);
  });

  test('whereLteMapNullFirst', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': nullValue(), 'b': constant(42)}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc9, doc10]);
  });

  test('whereLteMapNullLast', () {
    final doc1 = doc('users/1', 1000, <String, Object?>{'score': null});
    final doc2 = doc('users/2', 1000, <String, Object?>{'score': 42});
    final doc3 = doc('users/3', 1000, <String, Object?>{
      'score': 'hello world',
    });
    final doc4 = doc('users/4', 1000, <String, Object?>{'score': double.nan});
    final doc5 = doc('users/5', 1000, <String, Object?>{'not-score': 42});
    final doc6 = doc('users/6', 1000, <String, Object?>{
      'score': <String, Object?>{},
    });
    final doc7 = doc('users/7', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42},
    });
    final doc8 = doc('users/8', 1000, <String, Object?>{
      'score': <String, Object?>{
        'a': <String, Object?>{'b': null},
      },
    });
    final doc9 = doc('users/9', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null},
    });
    final doc10 = doc('users/10', 1000, <String, Object?>{
      'score': <String, Object?>{'a': null, 'b': 42},
    });
    final doc11 = doc('users/11', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': null},
    });
    final doc12 = doc('users/12', 1000, <String, Object?>{
      'score': <String, Object?>{'a': 42, 'b': 43},
    });
    final doc13 = doc('users/13', 1000, <String, Object?>{
      'score': <Object?>[],
    });
    final doc14 = doc('users/14', 1000, <String, Object?>{
      'score': [null],
    });
    final doc15 = doc('users/15', 1000, <String, Object?>{
      'score': [
        [null],
      ],
    });
    final doc16 = doc('users/16', 1000, <String, Object?>{
      'score': [42],
    });
    final doc17 = doc('users/17', 1000, <String, Object?>{
      'score': [null, 42],
    });
    final doc18 = doc('users/18', 1000, <String, Object?>{
      'score': [42, null],
    });
    final doc19 = doc('users/19', 1000, <String, Object?>{
      'score': [42, 43],
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
      doc11,
      doc12,
      doc13,
      doc14,
      doc15,
      doc16,
      doc17,
      doc18,
      doc19,
    ];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          lessThanOrEqual(
            field('score'),
            map(<String, Object?>{'a': constant(42), 'b': nullValue()}),
          ),
        );

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc6, doc7, doc9, doc10, doc11]);
  });

  // ===================================================================
  // Sort Tests
  // ===================================================================
  test('sortNullInArrayAscending', () {
    final doc0 = doc('k/0', 1000, <String, Object?>{
      'not-foo': <Object?>[],
    }); // foo missing
    final doc1 = doc('k/1', 1000, <String, Object?>{'foo': <Object?>[]}); // []
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [null],
    }); // [null]
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [null, null],
    }); // [null, null]
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': [null, 1],
    }); // [null, 1]
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': [null, 2],
    }); // [null, 2]
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': [1, null],
    }); // [1, null]
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': [2, null],
    }); // [2, null]
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'foo': [2, 1],
    }); // [2, 1]
    final documents = [doc0, doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([
      doc0,
      doc1,
      doc2,
      doc3,
      doc4,
      doc5,
      doc6,
      doc7,
      doc8,
    ]).inOrder();
  });

  test('sortNullInArrayDescending', () {
    final doc0 = doc('k/0', 1000, <String, Object?>{'not-foo': <Object?>[]});
    final doc1 = doc('k/1', 1000, <String, Object?>{'foo': <Object?>[]});
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': [null],
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': [null, null],
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': [null, 1],
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': [null, 2],
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': [1, null],
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': [2, null],
    });
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'foo': [2, 1],
    });
    final documents = [doc0, doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([
      doc8,
      doc7,
      doc6,
      doc5,
      doc4,
      doc3,
      doc2,
      doc1,
      doc0,
    ]).inOrder();
  });

  test('sortNullInMapAscending', () {
    final doc0 = doc('k/0', 1000, <String, Object?>{
      'not-foo': <String, Object?>{},
    }); // foo missing
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{},
    }); // {}
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    }); // {a:null}
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': null},
    }); // {a:null, b:null}
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': 1},
    }); // {a:null, b:1}
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': 2},
    }); // {a:null, b:2}
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1, 'b': null},
    }); // {a:1, b:null}
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 2, 'b': null},
    }); // {a:2, b:null}
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 2, 'b': 1},
    }); // {a:2, b:1}
    final documents = [doc0, doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([
      doc0,
      doc1,
      doc2,
      doc3,
      doc4,
      doc5,
      doc6,
      doc7,
      doc8,
    ]).inOrder();
  });

  test('sortNullInMapDescending', () {
    final doc0 = doc('k/0', 1000, <String, Object?>{
      'not-foo': <String, Object?>{},
    });
    final doc1 = doc('k/1', 1000, <String, Object?>{
      'foo': <String, Object?>{},
    });
    final doc2 = doc('k/2', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null},
    });
    final doc3 = doc('k/3', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': null},
    });
    final doc4 = doc('k/4', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': 1},
    });
    final doc5 = doc('k/5', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': null, 'b': 2},
    });
    final doc6 = doc('k/6', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 1, 'b': null},
    });
    final doc7 = doc('k/7', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 2, 'b': null},
    });
    final doc8 = doc('k/8', 1000, <String, Object?>{
      'foo': <String, Object?>{'a': 2, 'b': 1},
    });
    final documents = [doc0, doc1, doc2, doc3, doc4, doc5, doc6, doc7, doc8];

    final pipeline = RealtimePipelineSource().collection('k').sort([
      field('foo').descending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([
      doc8,
      doc7,
      doc6,
      doc5,
      doc4,
      doc3,
      doc2,
      doc1,
      doc0,
    ]).inOrder();
  });
}
