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
// firebase-firestore/src/test/java/com/google/firebase/firestore/pipeline/CanonifyEqTest.kt
//
// The cases test `RealtimePipeline.canonicalId()` and
// `RealtimePipeline.equals()`, which Android uses to share one listen target
// between equal realtime pipelines. The Dart SDK has no realtime pipelines
// (design notes, phase 4): `Pipeline` has neither a canonical id nor value
// equality, and the stand-in RealtimePipeline of
// realtime_pipeline_test_util.dart only builds a pipeline to run locally.
// The cases are kept, skipped, with what Android expects.

import 'package:test/test.dart' show test;

const String noRealtimePipeline =
    'The Dart SDK has no RealtimePipeline, so no canonicalId() and no '
    'equality of pipelines (realtime pipelines are phase 4 of the design).';

void main() {
  // collection(test)|where(fn(equal[fld(foo),cst(42)]))|sort(fld(__name__)asc)
  test('canonify simple where', () {}, skip: noRealtimePipeline);

  // collection(test)|where(fn(equal[fld(foo),cst(42L)]))|sort(fld(__name__)asc)
  //   |limit(10)|sort(fld(bar)desc,fld(__name__)asc)
  test('canonify multiple stages', () {}, skip: noRealtimePipeline);

  // collection_group(cities)|sort(fld(__name__)asc)
  test('canonify collection group source', () {}, skip: noRealtimePipeline);

  test(
    'eq returns true for identical pipelines',
    () {},
    skip: noRealtimePipeline,
  );

  test(
    'eq returns false for different stages',
    () {},
    skip: noRealtimePipeline,
  );

  test(
    'eq returns false for different params in stage',
    () {},
    skip: noRealtimePipeline,
  );

  test(
    'eq returns false for different stage order',
    () {},
    skip: noRealtimePipeline,
  );

  // The canonical ids of equal("42") and equal(42) are the same; the
  // pipelines are not equal.
  test(
    'eq returns false for same canonicalId but different types',
    () {},
    skip: noRealtimePipeline,
  );
}
