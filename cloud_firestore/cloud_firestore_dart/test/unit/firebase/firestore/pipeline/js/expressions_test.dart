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
// packages/firestore/test/unit/api/expressions.test.ts
//
// The two `snippet` cases are commented out in JS (search has no backend
// support); only the active case is ported.

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:test/test.dart';

import '../pipeline_test_util.dart';

void main() {
  group('expressions', () {
    group('serialization', () {
      test('serializes generic FunctionExpression without options', () {
        final FunctionExpression snippetExpression = FunctionExpression(
          'name',
          <Expression>[constant(1)],
        );

        expect(encode(snippetExpression), fn('name', <pb.Value>[integer(1)]));
      });
    });
  });
}
