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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/FieldTests.kt
//
// The Kotlin local `doc` is `document` here: Dart cannot shadow the
// function it is initialised with.

import 'package:test/test.dart' show test;

import 'realtime_pipeline_test_util.dart';

void main() {
  test('can get field', () {
    final TestDocument docWithField = doc('coll/doc1', 1, <String, Object?>{
      'exists': true,
    });
    final Field fieldExpr = field('exists');
    final EvaluateResult result = evaluate(fieldExpr, docWithField);
    assertEvaluatesTo(
      result,
      true,
      "Expected field 'exists' to evaluate to true",
    );
  });

  test('returns unset if not found', () {
    final TestDocument document = doc('coll/doc1', 1, <String, Object?>{});
    final Field fieldExpr = field('not-exists');
    final EvaluateResult result = evaluate(fieldExpr, document);
    assertEvaluatesToUnset(
      result,
      'Expected non-existent field to evaluate to UNSET',
    );
  });
}
