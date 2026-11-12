// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/maybe_document.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use noDocumentDescriptor instead')
const NoDocument$json = {
  '1': 'NoDocument',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'read_time',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'readTime'
    },
  ],
};

/// Descriptor for `NoDocument`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List noDocumentDescriptor = $convert.base64Decode(
    'CgpOb0RvY3VtZW50EhIKBG5hbWUYASABKAlSBG5hbWUSNwoJcmVhZF90aW1lGAIgASgLMhouZ2'
    '9vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIIcmVhZFRpbWU=');

@$core.Deprecated('Use unknownDocumentDescriptor instead')
const UnknownDocument$json = {
  '1': 'UnknownDocument',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'version',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'version'
    },
  ],
};

/// Descriptor for `UnknownDocument`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List unknownDocumentDescriptor = $convert.base64Decode(
    'Cg9Vbmtub3duRG9jdW1lbnQSEgoEbmFtZRgBIAEoCVIEbmFtZRI0Cgd2ZXJzaW9uGAIgASgLMh'
    'ouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIHdmVyc2lvbg==');

@$core.Deprecated('Use maybeDocumentDescriptor instead')
const MaybeDocument$json = {
  '1': 'MaybeDocument',
  '2': [
    {
      '1': 'no_document',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.firestore.client.NoDocument',
      '9': 0,
      '10': 'noDocument'
    },
    {
      '1': 'document',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.firestore.v1.Document',
      '9': 0,
      '10': 'document'
    },
    {
      '1': 'unknown_document',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.firestore.client.UnknownDocument',
      '9': 0,
      '10': 'unknownDocument'
    },
    {
      '1': 'has_committed_mutations',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'hasCommittedMutations'
    },
  ],
  '8': [
    {'1': 'document_type'},
  ],
};

/// Descriptor for `MaybeDocument`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List maybeDocumentDescriptor = $convert.base64Decode(
    'Cg1NYXliZURvY3VtZW50Ej8KC25vX2RvY3VtZW50GAEgASgLMhwuZmlyZXN0b3JlLmNsaWVudC'
    '5Ob0RvY3VtZW50SABSCm5vRG9jdW1lbnQSOwoIZG9jdW1lbnQYAiABKAsyHS5nb29nbGUuZmly'
    'ZXN0b3JlLnYxLkRvY3VtZW50SABSCGRvY3VtZW50Ek4KEHVua25vd25fZG9jdW1lbnQYAyABKA'
    'syIS5maXJlc3RvcmUuY2xpZW50LlVua25vd25Eb2N1bWVudEgAUg91bmtub3duRG9jdW1lbnQS'
    'NgoXaGFzX2NvbW1pdHRlZF9tdXRhdGlvbnMYBCABKAhSFWhhc0NvbW1pdHRlZE11dGF0aW9uc0'
    'IPCg1kb2N1bWVudF90eXBl');
