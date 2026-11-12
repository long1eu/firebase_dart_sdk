// This is a generated file - do not edit.
//
// Generated from google/firestore/admin/v1/index.proto.

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

@$core.Deprecated('Use indexDescriptor instead')
const Index$json = {
  '1': 'Index',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'query_scope',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.google.firestore.admin.v1.Index.QueryScope',
      '10': 'queryScope'
    },
    {
      '1': 'fields',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.google.firestore.admin.v1.Index.IndexField',
      '10': 'fields'
    },
    {
      '1': 'state',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.google.firestore.admin.v1.Index.State',
      '10': 'state'
    },
  ],
  '3': [Index_IndexField$json],
  '4': [Index_QueryScope$json, Index_State$json],
};

@$core.Deprecated('Use indexDescriptor instead')
const Index_IndexField$json = {
  '1': 'IndexField',
  '2': [
    {'1': 'field_path', '3': 1, '4': 1, '5': 9, '10': 'fieldPath'},
    {
      '1': 'order',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.google.firestore.admin.v1.Index.IndexField.Order',
      '9': 0,
      '10': 'order'
    },
    {
      '1': 'array_config',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.google.firestore.admin.v1.Index.IndexField.ArrayConfig',
      '9': 0,
      '10': 'arrayConfig'
    },
  ],
  '4': [Index_IndexField_Order$json, Index_IndexField_ArrayConfig$json],
  '8': [
    {'1': 'value_mode'},
  ],
};

@$core.Deprecated('Use indexDescriptor instead')
const Index_IndexField_Order$json = {
  '1': 'Order',
  '2': [
    {'1': 'ORDER_UNSPECIFIED', '2': 0},
    {'1': 'ASCENDING', '2': 1},
    {'1': 'DESCENDING', '2': 2},
  ],
};

@$core.Deprecated('Use indexDescriptor instead')
const Index_IndexField_ArrayConfig$json = {
  '1': 'ArrayConfig',
  '2': [
    {'1': 'ARRAY_CONFIG_UNSPECIFIED', '2': 0},
    {'1': 'CONTAINS', '2': 1},
  ],
};

@$core.Deprecated('Use indexDescriptor instead')
const Index_QueryScope$json = {
  '1': 'QueryScope',
  '2': [
    {'1': 'QUERY_SCOPE_UNSPECIFIED', '2': 0},
    {'1': 'COLLECTION', '2': 1},
    {'1': 'COLLECTION_GROUP', '2': 2},
  ],
};

@$core.Deprecated('Use indexDescriptor instead')
const Index_State$json = {
  '1': 'State',
  '2': [
    {'1': 'STATE_UNSPECIFIED', '2': 0},
    {'1': 'CREATING', '2': 1},
    {'1': 'READY', '2': 2},
    {'1': 'NEEDS_REPAIR', '2': 3},
  ],
};

/// Descriptor for `Index`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List indexDescriptor = $convert.base64Decode(
    'CgVJbmRleBISCgRuYW1lGAEgASgJUgRuYW1lEkwKC3F1ZXJ5X3Njb3BlGAIgASgOMisuZ29vZ2'
    'xlLmZpcmVzdG9yZS5hZG1pbi52MS5JbmRleC5RdWVyeVNjb3BlUgpxdWVyeVNjb3BlEkMKBmZp'
    'ZWxkcxgDIAMoCzIrLmdvb2dsZS5maXJlc3RvcmUuYWRtaW4udjEuSW5kZXguSW5kZXhGaWVsZF'
    'IGZmllbGRzEjwKBXN0YXRlGAQgASgOMiYuZ29vZ2xlLmZpcmVzdG9yZS5hZG1pbi52MS5JbmRl'
    'eC5TdGF0ZVIFc3RhdGUa3AIKCkluZGV4RmllbGQSHQoKZmllbGRfcGF0aBgBIAEoCVIJZmllbG'
    'RQYXRoEkkKBW9yZGVyGAIgASgOMjEuZ29vZ2xlLmZpcmVzdG9yZS5hZG1pbi52MS5JbmRleC5J'
    'bmRleEZpZWxkLk9yZGVySABSBW9yZGVyElwKDGFycmF5X2NvbmZpZxgDIAEoDjI3Lmdvb2dsZS'
    '5maXJlc3RvcmUuYWRtaW4udjEuSW5kZXguSW5kZXhGaWVsZC5BcnJheUNvbmZpZ0gAUgthcnJh'
    'eUNvbmZpZyI9CgVPcmRlchIVChFPUkRFUl9VTlNQRUNJRklFRBAAEg0KCUFTQ0VORElORxABEg'
    '4KCkRFU0NFTkRJTkcQAiI5CgtBcnJheUNvbmZpZxIcChhBUlJBWV9DT05GSUdfVU5TUEVDSUZJ'
    'RUQQABIMCghDT05UQUlOUxABQgwKCnZhbHVlX21vZGUiTwoKUXVlcnlTY29wZRIbChdRVUVSWV'
    '9TQ09QRV9VTlNQRUNJRklFRBAAEg4KCkNPTExFQ1RJT04QARIUChBDT0xMRUNUSU9OX0dST1VQ'
    'EAIiSQoFU3RhdGUSFQoRU1RBVEVfVU5TUEVDSUZJRUQQABIMCghDUkVBVElORxABEgkKBVJFQU'
    'RZEAISEAoMTkVFRFNfUkVQQUlSEAM=');
