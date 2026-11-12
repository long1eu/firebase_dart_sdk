// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/bundle.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// If the query is a limit query, should the limit be applied to the beginning or
/// the end of results.
class BundledQuery_LimitType extends $pb.ProtobufEnum {
  static const BundledQuery_LimitType FIRST =
      BundledQuery_LimitType._(0, _omitEnumNames ? '' : 'FIRST');
  static const BundledQuery_LimitType LAST =
      BundledQuery_LimitType._(1, _omitEnumNames ? '' : 'LAST');

  static const $core.List<BundledQuery_LimitType> values =
      <BundledQuery_LimitType>[
    FIRST,
    LAST,
  ];

  static final $core.List<BundledQuery_LimitType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static BundledQuery_LimitType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const BundledQuery_LimitType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
