//
//  Generated code. Do not modify.
//  source: google/firestore/v1/common.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// The type of concurrency control mode for transactions.
class TransactionOptions_ConcurrencyMode extends $pb.ProtobufEnum {
  static const TransactionOptions_ConcurrencyMode CONCURRENCY_MODE_UNSPECIFIED = TransactionOptions_ConcurrencyMode._(0, _omitEnumNames ? '' : 'CONCURRENCY_MODE_UNSPECIFIED');
  static const TransactionOptions_ConcurrencyMode OPTIMISTIC = TransactionOptions_ConcurrencyMode._(1, _omitEnumNames ? '' : 'OPTIMISTIC');
  static const TransactionOptions_ConcurrencyMode PESSIMISTIC = TransactionOptions_ConcurrencyMode._(2, _omitEnumNames ? '' : 'PESSIMISTIC');

  static const $core.List<TransactionOptions_ConcurrencyMode> values = <TransactionOptions_ConcurrencyMode> [
    CONCURRENCY_MODE_UNSPECIFIED,
    OPTIMISTIC,
    PESSIMISTIC,
  ];

  static final $core.Map<$core.int, TransactionOptions_ConcurrencyMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TransactionOptions_ConcurrencyMode? valueOf($core.int value) => _byValue[value];

  const TransactionOptions_ConcurrencyMode._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
