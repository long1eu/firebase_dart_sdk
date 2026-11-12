//
//  Generated code. Do not modify.
//  source: google/firestore/v1/common.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use documentMaskDescriptor instead')
const DocumentMask$json = {
  '1': 'DocumentMask',
  '2': [
    {'1': 'field_paths', '3': 1, '4': 3, '5': 9, '10': 'fieldPaths'},
  ],
};

/// Descriptor for `DocumentMask`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List documentMaskDescriptor = $convert.base64Decode(
    'CgxEb2N1bWVudE1hc2sSHwoLZmllbGRfcGF0aHMYASADKAlSCmZpZWxkUGF0aHM=');

@$core.Deprecated('Use preconditionDescriptor instead')
const Precondition$json = {
  '1': 'Precondition',
  '2': [
    {'1': 'exists', '3': 1, '4': 1, '5': 8, '9': 0, '10': 'exists'},
    {'1': 'update_time', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'updateTime'},
  ],
  '8': [
    {'1': 'condition_type'},
  ],
};

/// Descriptor for `Precondition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List preconditionDescriptor = $convert.base64Decode(
    'CgxQcmVjb25kaXRpb24SGAoGZXhpc3RzGAEgASgISABSBmV4aXN0cxI9Cgt1cGRhdGVfdGltZR'
    'gCIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBIAFIKdXBkYXRlVGltZUIQCg5jb25k'
    'aXRpb25fdHlwZQ==');

@$core.Deprecated('Use transactionOptionsDescriptor instead')
const TransactionOptions$json = {
  '1': 'TransactionOptions',
  '2': [
    {'1': 'read_only', '3': 2, '4': 1, '5': 11, '6': '.google.firestore.v1.TransactionOptions.ReadOnly', '9': 0, '10': 'readOnly'},
    {'1': 'read_write', '3': 3, '4': 1, '5': 11, '6': '.google.firestore.v1.TransactionOptions.ReadWrite', '9': 0, '10': 'readWrite'},
  ],
  '3': [TransactionOptions_ReadWrite$json, TransactionOptions_ReadOnly$json],
  '4': [TransactionOptions_ConcurrencyMode$json],
  '8': [
    {'1': 'mode'},
  ],
};

@$core.Deprecated('Use transactionOptionsDescriptor instead')
const TransactionOptions_ReadWrite$json = {
  '1': 'ReadWrite',
  '2': [
    {'1': 'retry_transaction', '3': 1, '4': 1, '5': 12, '10': 'retryTransaction'},
    {'1': 'concurrency_mode', '3': 2, '4': 1, '5': 14, '6': '.google.firestore.v1.TransactionOptions.ConcurrencyMode', '8': {}, '10': 'concurrencyMode'},
  ],
};

@$core.Deprecated('Use transactionOptionsDescriptor instead')
const TransactionOptions_ReadOnly$json = {
  '1': 'ReadOnly',
  '2': [
    {'1': 'read_time', '3': 2, '4': 1, '5': 11, '6': '.google.protobuf.Timestamp', '9': 0, '10': 'readTime'},
  ],
  '8': [
    {'1': 'consistency_selector'},
  ],
};

@$core.Deprecated('Use transactionOptionsDescriptor instead')
const TransactionOptions_ConcurrencyMode$json = {
  '1': 'ConcurrencyMode',
  '2': [
    {'1': 'CONCURRENCY_MODE_UNSPECIFIED', '2': 0},
    {'1': 'OPTIMISTIC', '2': 1},
    {'1': 'PESSIMISTIC', '2': 2},
  ],
};

/// Descriptor for `TransactionOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transactionOptionsDescriptor = $convert.base64Decode(
    'ChJUcmFuc2FjdGlvbk9wdGlvbnMSTwoJcmVhZF9vbmx5GAIgASgLMjAuZ29vZ2xlLmZpcmVzdG'
    '9yZS52MS5UcmFuc2FjdGlvbk9wdGlvbnMuUmVhZE9ubHlIAFIIcmVhZE9ubHkSUgoKcmVhZF93'
    'cml0ZRgDIAEoCzIxLmdvb2dsZS5maXJlc3RvcmUudjEuVHJhbnNhY3Rpb25PcHRpb25zLlJlYW'
    'RXcml0ZUgAUglyZWFkV3JpdGUaogEKCVJlYWRXcml0ZRIrChFyZXRyeV90cmFuc2FjdGlvbhgB'
    'IAEoDFIQcmV0cnlUcmFuc2FjdGlvbhJoChBjb25jdXJyZW5jeV9tb2RlGAIgASgOMjcuZ29vZ2'
    'xlLmZpcmVzdG9yZS52MS5UcmFuc2FjdGlvbk9wdGlvbnMuQ29uY3VycmVuY3lNb2RlQgTiQQEB'
    'Ug9jb25jdXJyZW5jeU1vZGUaXQoIUmVhZE9ubHkSOQoJcmVhZF90aW1lGAIgASgLMhouZ29vZ2'
    'xlLnByb3RvYnVmLlRpbWVzdGFtcEgAUghyZWFkVGltZUIWChRjb25zaXN0ZW5jeV9zZWxlY3Rv'
    'ciJUCg9Db25jdXJyZW5jeU1vZGUSIAocQ09OQ1VSUkVOQ1lfTU9ERV9VTlNQRUNJRklFRBAAEg'
    '4KCk9QVElNSVNUSUMQARIPCgtQRVNTSU1JU1RJQxACQgYKBG1vZGU=');

@$core.Deprecated('Use requestOptionsDescriptor instead')
const RequestOptions$json = {
  '1': 'RequestOptions',
  '2': [
    {'1': 'request_tags', '3': 1, '4': 3, '5': 9, '8': {}, '10': 'requestTags'},
  ],
};

/// Descriptor for `RequestOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List requestOptionsDescriptor = $convert.base64Decode(
    'Cg5SZXF1ZXN0T3B0aW9ucxInCgxyZXF1ZXN0X3RhZ3MYASADKAlCBOJBAQFSC3JlcXVlc3RUYW'
    'dz');

