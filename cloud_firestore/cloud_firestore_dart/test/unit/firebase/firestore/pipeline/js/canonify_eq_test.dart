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
// packages/firestore/test/unit/core/pipeline/canonify_eq.test.ts
//
// The cases test `canonifyPipeline` and `pipelineEq` of
// core/pipeline-util.ts, which JS uses to share one listen target between
// equal realtime pipelines. The Dart SDK has no realtime pipelines, no
// canonical id of a pipeline and no pipeline equality (see
// ../realtime/canonify_eq_test.dart for Android's version of these cases).

import 'package:test/test.dart' show test;

const String noCanonicalPipeline =
    'The Dart SDK has no canonical id and no equality of pipelines '
    '(realtime pipelines are phase 4 of the design).';

void main() {
  test(
    'works as expected for simple where clause',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'works as expected for multiple stages',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'works as expected for CollectionGroupSource stage',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'works as expected for DatabaseSource stage',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'works as expected for DocumentsSource stage',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'works as expected for eqAny and arrays',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'returns true for identical pipelines',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'returns false for pipelines with different stages',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'returns false for pipelines with different parameters within a stage',
    () {},
    skip: noCanonicalPipeline,
  );
  test(
    'returns false for pipelines with different order of stages',
    () {},
    skip: noCanonicalPipeline,
  );
}
