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
// packages/firestore/test/unit/core/structured_pipeline.test.ts
//
// JS builds a StructuredPipeline from a mocked pipeline and
// StructuredPipelineOptions(known options, raw options). Dart builds the
// StructuredPipeline in `Pipeline.toExecuteRequest(encoder, indexMode:,
// rawOptions:)`; the cases use an empty pipeline (a `database()` source)
// and check its options. JS's check that the mock was serialized once has
// no counterpart.

// ignore_for_file: invalid_use_of_internal_member

import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../pipeline_test_util.dart';

proto.StructuredPipeline structured({
  PipelineIndexMode? indexMode,
  Map<String, Object?>? rawOptions,
}) {
  final Pipeline pipeline = source().database();
  final proto.StructuredPipeline result = pipeline
      .toExecuteRequest(encoder(), indexMode: indexMode, rawOptions: rawOptions)
      .structuredPipeline;
  expect(result.pipeline, pipeline.toProto(encoder()));
  return result;
}

void main() {
  test('should serialize the pipeline argument', () {
    expect(structured().options, isEmpty);
  });

  test('should support known options', () {
    expect(
      structured(indexMode: PipelineIndexMode.recommended).options,
      <String, pb.Value>{'index_mode': str('recommended')},
    );
  });

  test('should support unknown options', () {
    expect(
      structured(rawOptions: <String, Object?>{'foo_bar': 'baz'}).options,
      <String, pb.Value>{'foo_bar': str('baz')},
    );
  });

  test(
    'should support unknown nested options',
    () {},
    skip:
        'JS reads a raw option key as a dotted field path ("foo.bar" sets '
        'bar inside foo, OptionsUtil.getOptionsProto). Dart sends raw option '
        'keys as they are, as documented and as Android\'s InternalOptions '
        'do.',
  );

  test('should support options override', () {
    expect(
      structured(
        indexMode: PipelineIndexMode.recommended,
        rawOptions: <String, Object?>{'index_mode': 'baz'},
      ).options,
      <String, pb.Value>{'index_mode': str('baz')},
    );
  });
}
