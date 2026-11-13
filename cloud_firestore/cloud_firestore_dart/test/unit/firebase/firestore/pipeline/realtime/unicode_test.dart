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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/UnicodeTests.kt
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
  test('basic unicode', () {
    final doc1 = doc('🐵/Łukasiewicz', 1000, <String, Object?>{
      'Ł': 'Jan Łukasiewicz',
    });
    final doc2 = doc('🐵/Sierpiński', 1000, <String, Object?>{
      'Ł': 'Wacław Sierpiński',
    });
    final doc3 = doc('🐵/iwasawa', 1000, <String, Object?>{'Ł': '岩澤'});

    final documents = [doc1, doc2, doc3];
    final pipeline = RealtimePipelineSource().collection('/🐵').sort([
      field('Ł').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc2, doc3]).inOrder();
  });

  test('unicode surrogates', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{'str': '🄟'});
    final doc2 = doc('users/b', 1000, <String, Object?>{'str': 'Ｐ'});
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'str': '︒',
    }); // This char is U+FE12, sorts before P and 🄟

    final documents = [doc1, doc2, doc3];
    final pipeline = RealtimePipelineSource()
        .collection(
          'users',
        ) // C++ uses DatabaseSource, 'users' collection matches doc paths
        .where(
          and(
            field('str').lessThanOrEqual(constant('🄟')),
            field('str').greaterThanOrEqual(constant('Ｐ')),
          ),
        )
        .sort([field('str').ascending()]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc2, doc1]).inOrder();
  });

  test('unicode surrogates in array', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'foo': ['🄟'],
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'foo': ['Ｐ'],
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'foo': ['︒'],
    });

    final documents = [doc1, doc2, doc3];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('foo').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc3, doc2, doc1]).inOrder();
  });

  test('unicode surrogates in map keys', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'map': <String, Object?>{'︒': true, 'z': true},
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'map': <String, Object?>{'🄟': true, '︒': true},
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'map': <String, Object?>{'Ｐ': true, '︒': true},
    });

    final documents = [doc1, doc2, doc3];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('map').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3, doc2]).inOrder();
  });

  test('unicode surrogates in map values', () {
    final doc1 = doc('users/a', 1000, <String, Object?>{
      'map': <String, Object?>{'foo': '︒'},
    });
    final doc2 = doc('users/b', 1000, <String, Object?>{
      'map': <String, Object?>{'foo': '🄟'},
    });
    final doc3 = doc('users/c', 1000, <String, Object?>{
      'map': <String, Object?>{'foo': 'Ｐ'},
    });

    final documents = [doc1, doc2, doc3];
    final pipeline = RealtimePipelineSource().collection('users').sort([
      field('map').ascending(),
    ]);

    final result = runPipeline(pipeline, documents);
    assertThat(result).containsExactly([doc1, doc3, doc2]).inOrder();
  });
}
