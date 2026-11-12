// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/bundle.proto.

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

@$core.Deprecated('Use bundledQueryDescriptor instead')
const BundledQuery$json = {
  '1': 'BundledQuery',
  '2': [
    {'1': 'parent', '3': 1, '4': 1, '5': 9, '10': 'parent'},
    {
      '1': 'structured_query',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.firestore.v1.StructuredQuery',
      '9': 0,
      '10': 'structuredQuery'
    },
    {
      '1': 'limit_type',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.firestore.BundledQuery.LimitType',
      '10': 'limitType'
    },
  ],
  '4': [BundledQuery_LimitType$json],
  '8': [
    {'1': 'query_type'},
  ],
};

@$core.Deprecated('Use bundledQueryDescriptor instead')
const BundledQuery_LimitType$json = {
  '1': 'LimitType',
  '2': [
    {'1': 'FIRST', '2': 0},
    {'1': 'LAST', '2': 1},
  ],
};

/// Descriptor for `BundledQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bundledQueryDescriptor = $convert.base64Decode(
    'CgxCdW5kbGVkUXVlcnkSFgoGcGFyZW50GAEgASgJUgZwYXJlbnQSUQoQc3RydWN0dXJlZF9xdW'
    'VyeRgCIAEoCzIkLmdvb2dsZS5maXJlc3RvcmUudjEuU3RydWN0dXJlZFF1ZXJ5SABSD3N0cnVj'
    'dHVyZWRRdWVyeRJACgpsaW1pdF90eXBlGAMgASgOMiEuZmlyZXN0b3JlLkJ1bmRsZWRRdWVyeS'
    '5MaW1pdFR5cGVSCWxpbWl0VHlwZSIgCglMaW1pdFR5cGUSCQoFRklSU1QQABIICgRMQVNUEAFC'
    'DAoKcXVlcnlfdHlwZQ==');

@$core.Deprecated('Use namedQueryDescriptor instead')
const NamedQuery$json = {
  '1': 'NamedQuery',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'bundled_query',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.firestore.BundledQuery',
      '10': 'bundledQuery'
    },
    {
      '1': 'read_time',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'readTime'
    },
  ],
};

/// Descriptor for `NamedQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List namedQueryDescriptor = $convert.base64Decode(
    'CgpOYW1lZFF1ZXJ5EhIKBG5hbWUYASABKAlSBG5hbWUSPAoNYnVuZGxlZF9xdWVyeRgCIAEoCz'
    'IXLmZpcmVzdG9yZS5CdW5kbGVkUXVlcnlSDGJ1bmRsZWRRdWVyeRI3CglyZWFkX3RpbWUYAyAB'
    'KAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUghyZWFkVGltZQ==');

@$core.Deprecated('Use bundledDocumentMetadataDescriptor instead')
const BundledDocumentMetadata$json = {
  '1': 'BundledDocumentMetadata',
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
    {'1': 'exists', '3': 3, '4': 1, '5': 8, '10': 'exists'},
    {'1': 'queries', '3': 4, '4': 3, '5': 9, '10': 'queries'},
  ],
};

/// Descriptor for `BundledDocumentMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bundledDocumentMetadataDescriptor = $convert.base64Decode(
    'ChdCdW5kbGVkRG9jdW1lbnRNZXRhZGF0YRISCgRuYW1lGAEgASgJUgRuYW1lEjcKCXJlYWRfdG'
    'ltZRgCIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBSCHJlYWRUaW1lEhYKBmV4aXN0'
    'cxgDIAEoCFIGZXhpc3RzEhgKB3F1ZXJpZXMYBCADKAlSB3F1ZXJpZXM=');

@$core.Deprecated('Use bundleMetadataDescriptor instead')
const BundleMetadata$json = {
  '1': 'BundleMetadata',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'create_time',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createTime'
    },
    {'1': 'version', '3': 3, '4': 1, '5': 13, '10': 'version'},
    {'1': 'total_documents', '3': 4, '4': 1, '5': 13, '10': 'totalDocuments'},
    {'1': 'total_bytes', '3': 5, '4': 1, '5': 4, '10': 'totalBytes'},
  ],
};

/// Descriptor for `BundleMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bundleMetadataDescriptor = $convert.base64Decode(
    'Cg5CdW5kbGVNZXRhZGF0YRIOCgJpZBgBIAEoCVICaWQSOwoLY3JlYXRlX3RpbWUYAiABKAsyGi'
    '5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgpjcmVhdGVUaW1lEhgKB3ZlcnNpb24YAyABKA1S'
    'B3ZlcnNpb24SJwoPdG90YWxfZG9jdW1lbnRzGAQgASgNUg50b3RhbERvY3VtZW50cxIfCgt0b3'
    'RhbF9ieXRlcxgFIAEoBFIKdG90YWxCeXRlcw==');

@$core.Deprecated('Use bundleElementDescriptor instead')
const BundleElement$json = {
  '1': 'BundleElement',
  '2': [
    {
      '1': 'metadata',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.firestore.BundleMetadata',
      '9': 0,
      '10': 'metadata'
    },
    {
      '1': 'named_query',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.firestore.NamedQuery',
      '9': 0,
      '10': 'namedQuery'
    },
    {
      '1': 'document_metadata',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.firestore.BundledDocumentMetadata',
      '9': 0,
      '10': 'documentMetadata'
    },
    {
      '1': 'document',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.firestore.v1.Document',
      '9': 0,
      '10': 'document'
    },
  ],
  '8': [
    {'1': 'element_type'},
  ],
};

/// Descriptor for `BundleElement`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bundleElementDescriptor = $convert.base64Decode(
    'Cg1CdW5kbGVFbGVtZW50EjcKCG1ldGFkYXRhGAEgASgLMhkuZmlyZXN0b3JlLkJ1bmRsZU1ldG'
    'FkYXRhSABSCG1ldGFkYXRhEjgKC25hbWVkX3F1ZXJ5GAIgASgLMhUuZmlyZXN0b3JlLk5hbWVk'
    'UXVlcnlIAFIKbmFtZWRRdWVyeRJRChFkb2N1bWVudF9tZXRhZGF0YRgDIAEoCzIiLmZpcmVzdG'
    '9yZS5CdW5kbGVkRG9jdW1lbnRNZXRhZGF0YUgAUhBkb2N1bWVudE1ldGFkYXRhEjsKCGRvY3Vt'
    'ZW50GAQgASgLMh0uZ29vZ2xlLmZpcmVzdG9yZS52MS5Eb2N1bWVudEgAUghkb2N1bWVudEIOCg'
    'xlbGVtZW50X3R5cGU=');
