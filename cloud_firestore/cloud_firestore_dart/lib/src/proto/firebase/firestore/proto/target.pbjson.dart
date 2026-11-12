// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/target.proto.

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

@$core.Deprecated('Use targetDescriptor instead')
const Target$json = {
  '1': 'Target',
  '2': [
    {'1': 'target_id', '3': 1, '4': 1, '5': 5, '10': 'targetId'},
    {
      '1': 'snapshot_version',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'snapshotVersion'
    },
    {'1': 'resume_token', '3': 3, '4': 1, '5': 12, '10': 'resumeToken'},
    {
      '1': 'last_listen_sequence_number',
      '3': 4,
      '4': 1,
      '5': 3,
      '10': 'lastListenSequenceNumber'
    },
    {
      '1': 'query',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.firestore.v1.Target.QueryTarget',
      '9': 0,
      '10': 'query'
    },
    {
      '1': 'documents',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.google.firestore.v1.Target.DocumentsTarget',
      '9': 0,
      '10': 'documents'
    },
    {
      '1': 'last_limbo_free_snapshot_version',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastLimboFreeSnapshotVersion'
    },
  ],
  '8': [
    {'1': 'target_type'},
  ],
};

/// Descriptor for `Target`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List targetDescriptor = $convert.base64Decode(
    'CgZUYXJnZXQSGwoJdGFyZ2V0X2lkGAEgASgFUgh0YXJnZXRJZBJFChBzbmFwc2hvdF92ZXJzaW'
    '9uGAIgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIPc25hcHNob3RWZXJzaW9uEiEK'
    'DHJlc3VtZV90b2tlbhgDIAEoDFILcmVzdW1lVG9rZW4SPQobbGFzdF9saXN0ZW5fc2VxdWVuY2'
    'VfbnVtYmVyGAQgASgDUhhsYXN0TGlzdGVuU2VxdWVuY2VOdW1iZXISPwoFcXVlcnkYBSABKAsy'
    'Jy5nb29nbGUuZmlyZXN0b3JlLnYxLlRhcmdldC5RdWVyeVRhcmdldEgAUgVxdWVyeRJLCglkb2'
    'N1bWVudHMYBiABKAsyKy5nb29nbGUuZmlyZXN0b3JlLnYxLlRhcmdldC5Eb2N1bWVudHNUYXJn'
    'ZXRIAFIJZG9jdW1lbnRzEmIKIGxhc3RfbGltYm9fZnJlZV9zbmFwc2hvdF92ZXJzaW9uGAcgAS'
    'gLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIcbGFzdExpbWJvRnJlZVNuYXBzaG90VmVy'
    'c2lvbkINCgt0YXJnZXRfdHlwZQ==');

@$core.Deprecated('Use targetGlobalDescriptor instead')
const TargetGlobal$json = {
  '1': 'TargetGlobal',
  '2': [
    {'1': 'highest_target_id', '3': 1, '4': 1, '5': 5, '10': 'highestTargetId'},
    {
      '1': 'highest_listen_sequence_number',
      '3': 2,
      '4': 1,
      '5': 3,
      '10': 'highestListenSequenceNumber'
    },
    {
      '1': 'last_remote_snapshot_version',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastRemoteSnapshotVersion'
    },
    {'1': 'target_count', '3': 4, '4': 1, '5': 5, '10': 'targetCount'},
  ],
};

/// Descriptor for `TargetGlobal`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List targetGlobalDescriptor = $convert.base64Decode(
    'CgxUYXJnZXRHbG9iYWwSKgoRaGlnaGVzdF90YXJnZXRfaWQYASABKAVSD2hpZ2hlc3RUYXJnZX'
    'RJZBJDCh5oaWdoZXN0X2xpc3Rlbl9zZXF1ZW5jZV9udW1iZXIYAiABKANSG2hpZ2hlc3RMaXN0'
    'ZW5TZXF1ZW5jZU51bWJlchJbChxsYXN0X3JlbW90ZV9zbmFwc2hvdF92ZXJzaW9uGAMgASgLMh'
    'ouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIZbGFzdFJlbW90ZVNuYXBzaG90VmVyc2lvbhIh'
    'Cgx0YXJnZXRfY291bnQYBCABKAVSC3RhcmdldENvdW50');
