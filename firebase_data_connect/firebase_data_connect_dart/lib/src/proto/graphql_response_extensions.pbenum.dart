// This is a generated file - do not edit.
//
// Generated from graphql_response_extensions.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Action indicates the operation type on the entity.
class Action extends $pb.ProtobufEnum {
  static const Action ACTION_UNSPECIFIED =
      Action._(0, _omitEnumNames ? '' : 'ACTION_UNSPECIFIED');
  static const Action GET = Action._(1, _omitEnumNames ? '' : 'GET');
  static const Action LIST = Action._(2, _omitEnumNames ? '' : 'LIST');
  static const Action CREATE = Action._(3, _omitEnumNames ? '' : 'CREATE');
  static const Action UPDATE = Action._(4, _omitEnumNames ? '' : 'UPDATE');
  static const Action UPSERT = Action._(5, _omitEnumNames ? '' : 'UPSERT');
  static const Action DELETE = Action._(6, _omitEnumNames ? '' : 'DELETE');

  static const $core.List<Action> values = <Action>[
    ACTION_UNSPECIFIED,
    GET,
    LIST,
    CREATE,
    UPDATE,
    UPSERT,
    DELETE,
  ];

  static final $core.List<Action?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static Action? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Action._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
