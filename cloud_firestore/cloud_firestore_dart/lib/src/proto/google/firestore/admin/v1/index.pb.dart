//
//  Generated code. Do not modify.
//  source: google/firestore/admin/v1/index.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'index.pbenum.dart';

export 'index.pbenum.dart';

enum Index_IndexField_ValueMode {
  order, 
  arrayConfig, 
  notSet
}

/// A field in an index.
/// The field_path describes which field is indexed, the value_mode describes
/// how the field value is indexed.
class Index_IndexField extends $pb.GeneratedMessage {
  factory Index_IndexField({
    $core.String? fieldPath,
    Index_IndexField_Order? order,
    Index_IndexField_ArrayConfig? arrayConfig,
  }) {
    final $result = create();
    if (fieldPath != null) {
      $result.fieldPath = fieldPath;
    }
    if (order != null) {
      $result.order = order;
    }
    if (arrayConfig != null) {
      $result.arrayConfig = arrayConfig;
    }
    return $result;
  }
  Index_IndexField._() : super();
  factory Index_IndexField.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Index_IndexField.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, Index_IndexField_ValueMode> _Index_IndexField_ValueModeByTag = {
    2 : Index_IndexField_ValueMode.order,
    3 : Index_IndexField_ValueMode.arrayConfig,
    0 : Index_IndexField_ValueMode.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Index.IndexField', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.admin.v1'), createEmptyInstance: create)
    ..oo(0, [2, 3])
    ..aOS(1, _omitFieldNames ? '' : 'fieldPath')
    ..e<Index_IndexField_Order>(2, _omitFieldNames ? '' : 'order', $pb.PbFieldType.OE, defaultOrMaker: Index_IndexField_Order.ORDER_UNSPECIFIED, valueOf: Index_IndexField_Order.valueOf, enumValues: Index_IndexField_Order.values)
    ..e<Index_IndexField_ArrayConfig>(3, _omitFieldNames ? '' : 'arrayConfig', $pb.PbFieldType.OE, defaultOrMaker: Index_IndexField_ArrayConfig.ARRAY_CONFIG_UNSPECIFIED, valueOf: Index_IndexField_ArrayConfig.valueOf, enumValues: Index_IndexField_ArrayConfig.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Index_IndexField clone() => Index_IndexField()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Index_IndexField copyWith(void Function(Index_IndexField) updates) => super.copyWith((message) => updates(message as Index_IndexField)) as Index_IndexField;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Index_IndexField create() => Index_IndexField._();
  Index_IndexField createEmptyInstance() => create();
  static $pb.PbList<Index_IndexField> createRepeated() => $pb.PbList<Index_IndexField>();
  @$core.pragma('dart2js:noInline')
  static Index_IndexField getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Index_IndexField>(create);
  static Index_IndexField? _defaultInstance;

  Index_IndexField_ValueMode whichValueMode() => _Index_IndexField_ValueModeByTag[$_whichOneof(0)]!;
  void clearValueMode() => clearField($_whichOneof(0));

  /// Can be __name__.
  /// For single field indexes, this must match the name of the field or may
  /// be omitted.
  @$pb.TagNumber(1)
  $core.String get fieldPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set fieldPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFieldPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearFieldPath() => clearField(1);

  /// Indicates that this field supports ordering by the specified order or
  /// comparing using =, <, <=, >, >=.
  @$pb.TagNumber(2)
  Index_IndexField_Order get order => $_getN(1);
  @$pb.TagNumber(2)
  set order(Index_IndexField_Order v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOrder() => $_has(1);
  @$pb.TagNumber(2)
  void clearOrder() => clearField(2);

  /// Indicates that this field supports operations on `array_value`s.
  @$pb.TagNumber(3)
  Index_IndexField_ArrayConfig get arrayConfig => $_getN(2);
  @$pb.TagNumber(3)
  set arrayConfig(Index_IndexField_ArrayConfig v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasArrayConfig() => $_has(2);
  @$pb.TagNumber(3)
  void clearArrayConfig() => clearField(3);
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
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (queryScope != null) {
      $result.queryScope = queryScope;
    }
    if (fields != null) {
      $result.fields.addAll(fields);
    }
    if (state != null) {
      $result.state = state;
    }
    return $result;
  }
  Index._() : super();
  factory Index.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Index.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Index', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.admin.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..e<Index_QueryScope>(2, _omitFieldNames ? '' : 'queryScope', $pb.PbFieldType.OE, defaultOrMaker: Index_QueryScope.QUERY_SCOPE_UNSPECIFIED, valueOf: Index_QueryScope.valueOf, enumValues: Index_QueryScope.values)
    ..pc<Index_IndexField>(3, _omitFieldNames ? '' : 'fields', $pb.PbFieldType.PM, subBuilder: Index_IndexField.create)
    ..e<Index_State>(4, _omitFieldNames ? '' : 'state', $pb.PbFieldType.OE, defaultOrMaker: Index_State.STATE_UNSPECIFIED, valueOf: Index_State.valueOf, enumValues: Index_State.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Index clone() => Index()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Index copyWith(void Function(Index) updates) => super.copyWith((message) => updates(message as Index)) as Index;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Index create() => Index._();
  Index createEmptyInstance() => create();
  static $pb.PbList<Index> createRepeated() => $pb.PbList<Index>();
  @$core.pragma('dart2js:noInline')
  static Index getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Index>(create);
  static Index? _defaultInstance;

  /// Output only. A server defined name for this index.
  /// The form of this name for composite indexes will be:
  /// `projects/{project_id}/databases/{database_id}/collectionGroups/{collection_id}/indexes/{composite_index_id}`
  /// For single field indexes, this field will be empty.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  ///  Indexes with a collection query scope specified allow queries
  ///  against a collection that is the child of a specific document, specified at
  ///  query time, and that has the same collection id.
  ///
  ///  Indexes with a collection group query scope specified allow queries against
  ///  all collections descended from a specific document, specified at query
  ///  time, and that have the same collection id as this index.
  @$pb.TagNumber(2)
  Index_QueryScope get queryScope => $_getN(1);
  @$pb.TagNumber(2)
  set queryScope(Index_QueryScope v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasQueryScope() => $_has(1);
  @$pb.TagNumber(2)
  void clearQueryScope() => clearField(2);

  ///  The fields supported by this index.
  ///
  ///  For composite indexes, this is always 2 or more fields.
  ///  The last field entry is always for the field path `__name__`. If, on
  ///  creation, `__name__` was not specified as the last field, it will be added
  ///  automatically with the same direction as that of the last field defined. If
  ///  the final field in a composite index is not directional, the `__name__`
  ///  will be ordered ASCENDING (unless explicitly specified).
  ///
  ///  For single field indexes, this will always be exactly one entry with a
  ///  field path equal to the field path of the associated field.
  @$pb.TagNumber(3)
  $core.List<Index_IndexField> get fields => $_getList(2);

  /// Output only. The serving state of the index.
  @$pb.TagNumber(4)
  Index_State get state => $_getN(3);
  @$pb.TagNumber(4)
  set state(Index_State v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasState() => $_has(3);
  @$pb.TagNumber(4)
  void clearState() => clearField(4);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
