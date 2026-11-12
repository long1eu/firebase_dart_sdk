// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/mutation.proto.

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

@$core.Deprecated('Use mutationQueueDescriptor instead')
const MutationQueue$json = {
  '1': 'MutationQueue',
  '2': [
    {
      '1': 'last_acknowledged_batch_id',
      '3': 1,
      '4': 1,
      '5': 5,
      '10': 'lastAcknowledgedBatchId'
    },
    {
      '1': 'last_stream_token',
      '3': 2,
      '4': 1,
      '5': 12,
      '10': 'lastStreamToken'
    },
  ],
};

/// Descriptor for `MutationQueue`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mutationQueueDescriptor = $convert.base64Decode(
    'Cg1NdXRhdGlvblF1ZXVlEjsKGmxhc3RfYWNrbm93bGVkZ2VkX2JhdGNoX2lkGAEgASgFUhdsYX'
    'N0QWNrbm93bGVkZ2VkQmF0Y2hJZBIqChFsYXN0X3N0cmVhbV90b2tlbhgCIAEoDFIPbGFzdFN0'
    'cmVhbVRva2Vu');

@$core.Deprecated('Use writeBatchDescriptor instead')
const WriteBatch$json = {
  '1': 'WriteBatch',
  '2': [
    {'1': 'batch_id', '3': 1, '4': 1, '5': 5, '10': 'batchId'},
    {
      '1': 'writes',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.google.firestore.v1.Write',
      '10': 'writes'
    },
    {
      '1': 'local_write_time',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'localWriteTime'
    },
    {
      '1': 'base_writes',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.google.firestore.v1.Write',
      '10': 'baseWrites'
    },
  ],
};

/// Descriptor for `WriteBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List writeBatchDescriptor = $convert.base64Decode(
    'CgpXcml0ZUJhdGNoEhkKCGJhdGNoX2lkGAEgASgFUgdiYXRjaElkEjIKBndyaXRlcxgCIAMoCz'
    'IaLmdvb2dsZS5maXJlc3RvcmUudjEuV3JpdGVSBndyaXRlcxJEChBsb2NhbF93cml0ZV90aW1l'
    'GAMgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIObG9jYWxXcml0ZVRpbWUSOwoLYm'
    'FzZV93cml0ZXMYBCADKAsyGi5nb29nbGUuZmlyZXN0b3JlLnYxLldyaXRlUgpiYXNlV3JpdGVz');
