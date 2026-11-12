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

import 'index.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'index.pbenum.dart';

enum Index_IndexField_ValueMode { order, arrayConfig, notSet }

/// A field in an index.
/// The field_path describes which field is indexed, the value_mode describes
/// how the field value is indexed.
class Index_IndexField extends $pb.GeneratedMessage {
  factory Index_IndexField({
    $core.String? fieldPath,
    Index_IndexField_Order? order,
    Index_IndexField_ArrayConfig? arrayConfig,
  }) {
    final result = Index_IndexField._();
    if (fieldPath != null) result.fieldPath = fieldPath;
    if (order != null) result.order = order;
    if (arrayConfig != null) result.arrayConfig = arrayConfig;
    return result;
  }

  Index_IndexField._();

  factory Index_IndexField.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Index_IndexField()..mergeFromBuffer(data, registry);
  factory Index_IndexField.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Index_IndexField()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Index_IndexField_ValueMode>
      _Index_IndexField_ValueModeByTag = {
    2: Index_IndexField_ValueMode.order,
    3: Index_IndexField_ValueMode.arrayConfig,
    0: Index_IndexField_ValueMode.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Index.IndexField',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firestore.admin.v1'),
      createEmptyInstance: Index_IndexField.$_createMessage)
    ..oo(0, [2, 3])
    ..aOS(1, _omitFieldNames ? '' : 'fieldPath')
    ..aE<Index_IndexField_Order>(2, _omitFieldNames ? '' : 'order',
        enumValues: Index_IndexField_Order.values)
    ..aE<Index_IndexField_ArrayConfig>(3, _omitFieldNames ? '' : 'arrayConfig',
        enumValues: Index_IndexField_ArrayConfig.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Index_IndexField clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Index_IndexField copyWith(void Function(Index_IndexField) updates) =>
      super.copyWith((message) => updates(message as Index_IndexField))
          as Index_IndexField;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Index_IndexField() / Index_IndexField.new instead')
  static Index_IndexField create() => Index_IndexField._();
  static $pb.GeneratedMessage $_createMessage() => Index_IndexField._();
  @$core.override
  Index_IndexField createEmptyInstance() => Index_IndexField._();
  @$core.pragma('dart2js:noInline')
  static Index_IndexField getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Index_IndexField>(
          Index_IndexField.$_createMessage);
  static Index_IndexField? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  Index_IndexField_ValueMode whichValueMode() =>
      _Index_IndexField_ValueModeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearValueMode() => $_clearField($_whichOneof(0));

  /// Can be __name__.
  /// For single field indexes, this must match the name of the field or may
  /// be omitted.
  @$pb.TagNumber(1)
  $core.String get fieldPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set fieldPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFieldPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearFieldPath() => $_clearField(1);

  /// Indicates that this field supports ordering by the specified order or
  /// comparing using =, <, <=, >, >=.
  @$pb.TagNumber(2)
  Index_IndexField_Order get order => $_getN(1);
  @$pb.TagNumber(2)
  set order(Index_IndexField_Order value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOrder() => $_has(1);
  @$pb.TagNumber(2)
  void clearOrder() => $_clearField(2);

  /// Indicates that this field supports operations on `array_value`s.
  @$pb.TagNumber(3)
  Index_IndexField_ArrayConfig get arrayConfig => $_getN(2);
  @$pb.TagNumber(3)
  set arrayConfig(Index_IndexField_ArrayConfig value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasArrayConfig() => $_has(2);
  @$pb.TagNumber(3)
  void clearArrayConfig() => $_clearField(3);
}

/// Cloud Firestore indexes enable simple and complex queries against
/// documents in a database.
class Index extends $pb.GeneratedMessage {
  factory Index({
    $core.String? name,
    Index_QueryScope? queryScope,
    $core.Iterable<Index_IndexField>? fields,
    Index_State? state,
  }) {
    final result = Index._();
    if (name != null) result.name = name;
    if (queryScope != null) result.queryScope = queryScope;
    if (fields != null) result.fields.addAll(fields);
    if (state != null) result.state = state;
    return result;
  }

  Index._();

  factory Index.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Index()..mergeFromBuffer(data, registry);
  factory Index.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Index()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Index',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'google.firestore.admin.v1'),
      createEmptyInstance: Index.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aE<Index_QueryScope>(2, _omitFieldNames ? '' : 'queryScope',
        enumValues: Index_QueryScope.values)
    ..pPM<Index_IndexField>(3, _omitFieldNames ? '' : 'fields',
        subBuilder: Index_IndexField.$_createMessage)
    ..aE<Index_State>(4, _omitFieldNames ? '' : 'state',
        enumValues: Index_State.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Index clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Index copyWith(void Function(Index) updates) =>
      super.copyWith((message) => updates(message as Index)) as Index;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Index() / Index.new instead')
  static Index create() => Index._();
  static $pb.GeneratedMessage $_createMessage() => Index._();
  @$core.override
  Index createEmptyInstance() => Index._();
  @$core.pragma('dart2js:noInline')
  static Index getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Index>(Index.$_createMessage);
  static Index? _defaultInstance;

  /// Output only. A server defined name for this index.
  /// The form of this name for composite indexes will be:
  /// `projects/{project_id}/databases/{database_id}/collectionGroups/{collection_id}/indexes/{composite_index_id}`
  /// For single field indexes, this field will be empty.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// Indexes with a collection query scope specified allow queries
  /// against a collection that is the child of a specific document, specified at
  /// query time, and that has the same collection id.
  ///
  /// Indexes with a collection group query scope specified allow queries against
  /// all collections descended from a specific document, specified at query
  /// time, and that have the same collection id as this index.
  @$pb.TagNumber(2)
  Index_QueryScope get queryScope => $_getN(1);
  @$pb.TagNumber(2)
  set queryScope(Index_QueryScope value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasQueryScope() => $_has(1);
  @$pb.TagNumber(2)
  void clearQueryScope() => $_clearField(2);

  /// The fields supported by this index.
  ///
  /// For composite indexes, this is always 2 or more fields.
  /// The last field entry is always for the field path `__name__`. If, on
  /// creation, `__name__` was not specified as the last field, it will be added
  /// automatically with the same direction as that of the last field defined. If
  /// the final field in a composite index is not directional, the `__name__`
  /// will be ordered ASCENDING (unless explicitly specified).
  ///
  /// For single field indexes, this will always be exactly one entry with a
  /// field path equal to the field path of the associated field.
  @$pb.TagNumber(3)
  $pb.PbList<Index_IndexField> get fields => $_getList(2);

  /// Output only. The serving state of the index.
  @$pb.TagNumber(4)
  Index_State get state => $_getN(3);
  @$pb.TagNumber(4)
  set state(Index_State value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasState() => $_has(3);
  @$pb.TagNumber(4)
  void clearState() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
