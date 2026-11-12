// This is a generated file - do not edit.
//
// Generated from google/firestore/admin/v1/index.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Query Scope defines the scope at which a query is run. This is specified on
/// a StructuredQuery's `from` field.
class Index_QueryScope extends $pb.ProtobufEnum {
  /// The query scope is unspecified. Not a valid option.
  static const Index_QueryScope QUERY_SCOPE_UNSPECIFIED =
      Index_QueryScope._(0, _omitEnumNames ? '' : 'QUERY_SCOPE_UNSPECIFIED');

  /// Indexes with a collection query scope specified allow queries
  /// against a collection that is the child of a specific document, specified
  /// at query time, and that has the collection id specified by the index.
  static const Index_QueryScope COLLECTION =
      Index_QueryScope._(1, _omitEnumNames ? '' : 'COLLECTION');

  /// Indexes with a collection group query scope specified allow queries
  /// against all collections that has the collection id specified by the
  /// index.
  static const Index_QueryScope COLLECTION_GROUP =
      Index_QueryScope._(2, _omitEnumNames ? '' : 'COLLECTION_GROUP');

  static const $core.List<Index_QueryScope> values = <Index_QueryScope>[
    QUERY_SCOPE_UNSPECIFIED,
    COLLECTION,
    COLLECTION_GROUP,
  ];

  static final $core.List<Index_QueryScope?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Index_QueryScope? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Index_QueryScope._(super.value, super.name);
}

/// The state of an index. During index creation, an index will be in the
/// `CREATING` state. If the index is created successfully, it will transition
/// to the `READY` state. If the index creation encounters a problem, the index
/// will transition to the `NEEDS_REPAIR` state.
class Index_State extends $pb.ProtobufEnum {
  /// The state is unspecified.
  static const Index_State STATE_UNSPECIFIED =
      Index_State._(0, _omitEnumNames ? '' : 'STATE_UNSPECIFIED');

  /// The index is being created.
  /// There is an active long-running operation for the index.
  /// The index is updated when writing a document.
  /// Some index data may exist.
  static const Index_State CREATING =
      Index_State._(1, _omitEnumNames ? '' : 'CREATING');

  /// The index is ready to be used.
  /// The index is updated when writing a document.
  /// The index is fully populated from all stored documents it applies to.
  static const Index_State READY =
      Index_State._(2, _omitEnumNames ? '' : 'READY');

  /// The index was being created, but something went wrong.
  /// There is no active long-running operation for the index,
  /// and the most recently finished long-running operation failed.
  /// The index is not updated when writing a document.
  /// Some index data may exist.
  /// Use the google.longrunning.Operations API to determine why the operation
  /// that last attempted to create this index failed, then re-create the
  /// index.
  static const Index_State NEEDS_REPAIR =
      Index_State._(3, _omitEnumNames ? '' : 'NEEDS_REPAIR');

  static const $core.List<Index_State> values = <Index_State>[
    STATE_UNSPECIFIED,
    CREATING,
    READY,
    NEEDS_REPAIR,
  ];

  static final $core.List<Index_State?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Index_State? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Index_State._(super.value, super.name);
}

/// The supported orderings.
class Index_IndexField_Order extends $pb.ProtobufEnum {
  /// The ordering is unspecified. Not a valid option.
  static const Index_IndexField_Order ORDER_UNSPECIFIED =
      Index_IndexField_Order._(0, _omitEnumNames ? '' : 'ORDER_UNSPECIFIED');

  /// The field is ordered by ascending field value.
  static const Index_IndexField_Order ASCENDING =
      Index_IndexField_Order._(1, _omitEnumNames ? '' : 'ASCENDING');

  /// The field is ordered by descending field value.
  static const Index_IndexField_Order DESCENDING =
      Index_IndexField_Order._(2, _omitEnumNames ? '' : 'DESCENDING');

  static const $core.List<Index_IndexField_Order> values =
      <Index_IndexField_Order>[
    ORDER_UNSPECIFIED,
    ASCENDING,
    DESCENDING,
  ];

  static final $core.List<Index_IndexField_Order?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Index_IndexField_Order? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Index_IndexField_Order._(super.value, super.name);
}

/// The supported array value configurations.
class Index_IndexField_ArrayConfig extends $pb.ProtobufEnum {
  /// The index does not support additional array queries.
  static const Index_IndexField_ArrayConfig ARRAY_CONFIG_UNSPECIFIED =
      Index_IndexField_ArrayConfig._(
          0, _omitEnumNames ? '' : 'ARRAY_CONFIG_UNSPECIFIED');

  /// The index supports array containment queries.
  static const Index_IndexField_ArrayConfig CONTAINS =
      Index_IndexField_ArrayConfig._(1, _omitEnumNames ? '' : 'CONTAINS');

  static const $core.List<Index_IndexField_ArrayConfig> values =
      <Index_IndexField_ArrayConfig>[
    ARRAY_CONFIG_UNSPECIFIED,
    CONTAINS,
  ];

  static final $core.List<Index_IndexField_ArrayConfig?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static Index_IndexField_ArrayConfig? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Index_IndexField_ArrayConfig._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
