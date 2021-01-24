///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/bundle.proto
//
// @dart = 2.7
// ignore_for_file: annotate_overrides,camel_case_types,unnecessary_const,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type,unnecessary_this,prefer_final_fields

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class BundledQuery_LimitType extends $pb.ProtobufEnum {
  static const BundledQuery_LimitType FIRST = BundledQuery_LimitType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FIRST');
  static const BundledQuery_LimitType LAST = BundledQuery_LimitType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'LAST');

  static const $core.List<BundledQuery_LimitType> values = <BundledQuery_LimitType> [
    FIRST,
    LAST,
  ];

  static final $core.Map<$core.int, BundledQuery_LimitType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static BundledQuery_LimitType valueOf($core.int value) => _byValue[value];

  const BundledQuery_LimitType._($core.int v, $core.String n) : super(v, n);
}

