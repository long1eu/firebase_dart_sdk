//
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/bundle.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// If the query is a limit query, should the limit be applied to the beginning or
/// the end of results.
class BundledQuery_LimitType extends $pb.ProtobufEnum {
  static const BundledQuery_LimitType FIRST = BundledQuery_LimitType._(0, _omitEnumNames ? '' : 'FIRST');
  static const BundledQuery_LimitType LAST = BundledQuery_LimitType._(1, _omitEnumNames ? '' : 'LAST');

  static const $core.List<BundledQuery_LimitType> values = <BundledQuery_LimitType> [
    FIRST,
    LAST,
  ];

  static final $core.Map<$core.int, BundledQuery_LimitType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static BundledQuery_LimitType? valueOf($core.int value) => _byValue[value];

  const BundledQuery_LimitType._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
