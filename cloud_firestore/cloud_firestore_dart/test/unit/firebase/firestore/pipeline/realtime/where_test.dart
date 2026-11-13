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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/WhereTests.kt
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
  test('empty database returns no results', () {
    final documents = <TestDocument>[];
    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').greaterThanOrEqual(10));

    final result = runPipeline(pipeline, documents);
    assertThat(result).isEmpty();
  });

  test('duplicate conditions', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(
          and(
            field('age').greaterThanOrEqual(10.0),
            field('age').greaterThanOrEqual(20.0),
          ),
        );
    // age >= 10.0 AND age >= 20.0 => age >= 20.0
    // Matches: doc1 (75.5), doc2 (25.0), doc3 (100.0)
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]);
  });

  test('logical equivalent condition equal', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline1 = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(25.0));

    final pipeline2 = RealtimePipelineSource()
        .collection('users')
        .where(constant(25.0).equal(field('age')));

    final result1 = runPipeline(pipeline1, documents);
    final result2 = runPipeline(pipeline2, documents);

    assertThat(result1).containsExactly([doc2]);
    assertThat(result1).isEqualTo(result2);
  });

  test('logical equivalent condition and', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final documents = [doc1, doc2, doc3];

    final pipeline1 = RealtimePipelineSource()
        .collection('users')
        .where(
          and(field('age').greaterThan(10.0), field('age').lessThan(70.0)),
        );

    final pipeline2 = RealtimePipelineSource()
        .collection('users')
        .where(
          and(field('age').lessThan(70.0), field('age').greaterThan(10.0)),
        );

    final result1 = runPipeline(pipeline1, documents);
    final result2 = runPipeline(pipeline2, documents);

    assertThat(result1).containsExactly([doc2]);
    assertThat(result1).isEqualTo(result2);
  });

  test('logical equivalent condition or', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    }); // Match
    final documents = [doc1, doc2, doc3];

    final pipeline1 = RealtimePipelineSource()
        .collection('users')
        .where(or(field('age').lessThan(10.0), field('age').greaterThan(80.0)));

    final pipeline2 = RealtimePipelineSource()
        .collection('users')
        .where(or(field('age').greaterThan(80.0), field('age').lessThan(10.0)));
    final result1 = runPipeline(pipeline1, documents);
    final result2 = runPipeline(pipeline2, documents);

    assertThat(result1).containsExactly([doc3]);
    assertThat(result1).isEqualTo(result2);
  });

  test('logical equivalent condition in', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    });
    final documents = [doc1, doc2, doc3];

    final values = ['alice', 'matthew', 'joe'];

    final pipeline1 = RealtimePipelineSource()
        .collection('users')
        .where(field('name').equalAny(values));

    final pipeline2 = RealtimePipelineSource()
        .collection('users')
        .where(equalAny(field('name'), array(values)));

    final result1 = runPipeline(pipeline1, documents);
    final result2 = runPipeline(pipeline2, documents);

    assertThat(result1).containsExactly([doc1]);
    assertThat(result1).isEqualTo(result2);
  });

  test('repeated stages', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
      'age': 100.0,
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'name': 'diane',
      'age': 10.0,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'name': 'eric',
      'age': 10.0,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').greaterThanOrEqual(10.0))
        .where(field('age').greaterThanOrEqual(20.0));

    // age >= 10.0 THEN age >= 20.0 => age >= 20.0
    // Matches: doc1 (75.5), doc2 (25.0), doc3 (100.0)
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]);
  });

  test('composite equalities', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'height': 60,
      'age': 75,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'height': 55,
      'age': 50,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'height': 55.0,
      'age': 75,
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'height': 50,
      'age': 41,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'height': 80,
      'age': 75,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(75))
        .where(field('height').equal(55)); // 55 will also match 55.0

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3]);
  });

  test('composite inequalities', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'height': 60,
      'age': 75,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'height': 55,
      'age': 50,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'height': 55.0,
      'age': 75,
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'height': 50,
      'age': 41,
    });
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'height': 80,
      'age': 75,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').greaterThan(50))
        .where(field('height').lessThan(75));

    // age > 50 AND height < 75
    // doc1: 75 > 50 (T) AND 60 < 75 (T) -> True
    // doc2: 50 > 50 (F)
    // doc3: 75 > 50 (T) AND 55.0 < 75 (T) -> True
    // doc4: 41 > 50 (F)
    // doc5: 75 > 50 (T) AND 80 < 75 (F) -> False
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3]);
  });

  test('composite non seekable', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'first': 'alice',
      'last': 'smith',
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'first': 'bob',
      'last': 'smith',
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'first': 'charlie',
      'last': 'baker',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'first': 'diane',
      'last': 'miller',
    }); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'first': 'eric',
      'last': 'davis',
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        // Using regexMatch for LIKE '%a%' -> '.*a.*'
        .where(field('first').regexMatch('.*a.*'))
        // Using regexMatch for LIKE '%er' -> '.*er$'
        .where(field('last').regexMatch(r'.*er$'));

    // first contains 'a' AND last ends with 'er'
    // doc1: alice (yes), smith (no)
    // doc2: bob (no), smith (no)
    // doc3: charlie (yes), baker (yes) -> Match
    // doc4: diane (yes), miller (yes) -> Match
    // doc5: eric (no), davis (no)
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4]);
  });

  test('composite mixed', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'first': 'alice',
      'last': 'smith',
      'age': 75,
      'height': 40,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'first': 'bob',
      'last': 'smith',
      'age': 75,
      'height': 50,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'first': 'charlie',
      'last': 'baker',
      'age': 75,
      'height': 50,
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{
      'first': 'diane',
      'last': 'miller',
      'age': 75,
      'height': 50,
    }); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'first': 'eric',
      'last': 'davis',
      'age': 80,
      'height': 50,
    });
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(field('age').equal(75))
        .where(field('height').greaterThan(45))
        .where(field('last').regexMatch(r'.*er$')); // ends with 'er'

    // age == 75 AND height > 45 AND last ends with 'er'
    // doc1: 75==75 (T), 40>45 (F) -> False
    // doc2: 75==75 (T), 50>45 (T), smith ends er (F) -> False
    // doc3: 75==75 (T), 50>45 (T), baker ends er (T) -> True
    // doc4: 75==75 (T), 50>45 (T), miller ends er (T) -> True
    // doc5: 80==75 (F) -> False
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4]);
  });

  test('exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{'other': true});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(exists(field('name')));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]);
  });

  test('not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(exists(field('name'))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4, doc5]);
  });

  test('not not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{'other': true});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(not(exists(field('name')))));

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]);
  });

  test('exists and exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{'other': true});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(exists(field('name')), exists(field('age'))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2]);
  });

  test('exists or exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{'other': true});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(or(exists(field('name')), exists(field('age'))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3, doc4]);
  });

  test('not exists and exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(and(exists(field('name')), exists(field('age')))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4, doc5]);
  });

  test('not exists or exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(or(exists(field('name')), exists(field('age')))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5]);
  });

  test('not exists xor exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(not(xor(exists(field('name')), exists(field('age')))));
    // NOT ( (name exists AND NOT age exists) OR (NOT name exists AND age exists) )
    // = (name exists AND age exists) OR (NOT name exists AND NOT age exists)
    // Matches: doc1, doc2, doc5
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc5]);
  });

  test('and not exists not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(not(exists(field('name'))), not(exists(field('age')))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc5]);
  });

  test('or not exists not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(or(not(exists(field('name'))), not(exists(field('age')))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4, doc5]);
  });

  test('xor not exists not exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'name': 'charlie',
    }); // Match
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{'other': true});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(xor(not(exists(field('name'))), not(exists(field('age')))));
    // (NOT name exists AND NOT (NOT age exists)) OR (NOT (NOT name exists) AND NOT age exists)
    // (NOT name exists AND age exists) OR (name exists AND NOT age exists)
    // Matches: doc3, doc4
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc4]);
  });

  test('and not exists exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{'other': true});
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(and(not(exists(field('name'))), exists(field('age'))));
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc4]);
  });

  test('or not exists exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0}); // Match
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(or(not(exists(field('name'))), exists(field('age'))));
    // (NOT name exists) OR (age exists)
    // Matches: doc1, doc2, doc4, doc5
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc4, doc5]);
  });

  test('xor not exists exists', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'name': 'alice',
      'age': 75.5,
    }); // Match
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'name': 'bob',
      'age': 25.0,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{'name': 'charlie'});
    final doc4 = doc('users/d', 1000, <String, Object?>{'age': 30.0});
    final doc5 = doc('users/e', 1000, <String, Object?>{
      'other': true,
    }); // Match
    final documents = [doc1, doc2, doc3, doc4, doc5];

    final pipeline = RealtimePipelineSource()
        .collection('users')
        .where(xor(not(exists(field('name'))), exists(field('age'))));
    // (NOT name exists AND NOT age exists) OR (name exists AND age exists)
    // Matches: doc1, doc2, doc5
    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc5]);
  });

  test('and expression logically equivalent to separated stages', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'a': 1, 'b': 1});
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'a': 1,
      'b': 2,
    }); // Match
    final doc3 = doc('users/c', 1000, <String, Object?>{'a': 2, 'b': 2});
    final documents = [doc1, doc2, doc3];

    final equalityArgument1 = field('a').equal(1);
    final equalityArgument2 = field('b').equal(2);

    // Combined AND
    final pipelineAnd1 = RealtimePipelineSource()
        .collection('users')
        .where(and(equalityArgument1, equalityArgument2));
    final resultAnd1 = runPipeline(pipelineAnd1, documents);
    assertThat(resultAnd1).containsExactly([doc2]);

    // Combined AND (reversed order)
    final pipelineAnd2 = RealtimePipelineSource()
        .collection('users')
        .where(and(equalityArgument2, equalityArgument1));
    final resultAnd2 = runPipeline(pipelineAnd2, documents);
    assertThat(resultAnd2).containsExactly([doc2]);

    // Separate Stages
    final pipelineSep1 = RealtimePipelineSource()
        .collection('users')
        .where(equalityArgument1)
        .where(equalityArgument2);
    final resultSep1 = runPipeline(pipelineSep1, documents);
    assertThat(resultSep1).containsExactly([doc2]);

    // Separate Stages (reversed order)
    final pipelineSep2 = RealtimePipelineSource()
        .collection('users')
        .where(equalityArgument2)
        .where(equalityArgument1);
    final resultSep2 = runPipeline(pipelineSep2, documents);
    assertThat(resultSep2).containsExactly([doc2]);
  });
}
