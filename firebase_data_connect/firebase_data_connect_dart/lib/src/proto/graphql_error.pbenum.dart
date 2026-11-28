// This is a generated file - do not edit.
//
// Generated from graphql_error.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// WarningLevel describes the severity and required action to suppress this
/// warning when Firebase CLI run into it.
class WarningLevel extends $pb.ProtobufEnum {
  /// Warning level is not specified.
  static const WarningLevel WARNING_LEVEL_UNKNOWN =
      WarningLevel._(0, _omitEnumNames ? '' : 'WARNING_LEVEL_UNKNOWN');

  /// Display a warning without action needed.
  static const WarningLevel LOG_ONLY =
      WarningLevel._(1, _omitEnumNames ? '' : 'LOG_ONLY');

  /// Request a confirmation in interactive deployment flow.
  static const WarningLevel INTERACTIVE_ACK =
      WarningLevel._(2, _omitEnumNames ? '' : 'INTERACTIVE_ACK');

  /// Require an explicit confirmation in all deployment flows.
  static const WarningLevel REQUIRE_ACK =
      WarningLevel._(3, _omitEnumNames ? '' : 'REQUIRE_ACK');

  /// Require --force in all deployment flows.
  static const WarningLevel REQUIRE_FORCE =
      WarningLevel._(4, _omitEnumNames ? '' : 'REQUIRE_FORCE');

  static const $core.List<WarningLevel> values = <WarningLevel>[
    WARNING_LEVEL_UNKNOWN,
    LOG_ONLY,
    INTERACTIVE_ACK,
    REQUIRE_ACK,
    REQUIRE_FORCE,
  ];

  static final $core.List<WarningLevel?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static WarningLevel? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const WarningLevel._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
