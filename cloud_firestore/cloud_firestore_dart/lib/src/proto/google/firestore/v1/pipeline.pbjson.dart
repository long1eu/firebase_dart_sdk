//
//  Generated code. Do not modify.
//  source: google/firestore/v1/pipeline.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use structuredPipelineDescriptor instead')
const StructuredPipeline$json = {
  '1': 'StructuredPipeline',
  '2': [
    {'1': 'pipeline', '3': 1, '4': 1, '5': 11, '6': '.google.firestore.v1.Pipeline', '8': {}, '10': 'pipeline'},
    {'1': 'options', '3': 2, '4': 3, '5': 11, '6': '.google.firestore.v1.StructuredPipeline.OptionsEntry', '8': {}, '10': 'options'},
  ],
  '3': [StructuredPipeline_OptionsEntry$json],
};

@$core.Deprecated('Use structuredPipelineDescriptor instead')
const StructuredPipeline_OptionsEntry$json = {
  '1': 'OptionsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.Value', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `StructuredPipeline`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredPipelineDescriptor = $convert.base64Decode(
    'ChJTdHJ1Y3R1cmVkUGlwZWxpbmUSPwoIcGlwZWxpbmUYASABKAsyHS5nb29nbGUuZmlyZXN0b3'
    'JlLnYxLlBpcGVsaW5lQgTiQQECUghwaXBlbGluZRJUCgdvcHRpb25zGAIgAygLMjQuZ29vZ2xl'
    'LmZpcmVzdG9yZS52MS5TdHJ1Y3R1cmVkUGlwZWxpbmUuT3B0aW9uc0VudHJ5QgTiQQEBUgdvcH'
    'Rpb25zGlYKDE9wdGlvbnNFbnRyeRIQCgNrZXkYASABKAlSA2tleRIwCgV2YWx1ZRgCIAEoCzIa'
    'Lmdvb2dsZS5maXJlc3RvcmUudjEuVmFsdWVSBXZhbHVlOgI4AQ==');

