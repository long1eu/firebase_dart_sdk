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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $1;

import '../../../google/firestore/v1/document.pb.dart' as $2;
import '../../../google/firestore/v1/query.pb.dart' as $0;
import 'bundle.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'bundle.pbenum.dart';

enum BundledQuery_QueryType { structuredQuery, notSet }

/// Encodes a query saved in the bundle.
class BundledQuery extends $pb.GeneratedMessage {
  factory BundledQuery({
    $core.String? parent,
    $0.StructuredQuery? structuredQuery,
    BundledQuery_LimitType? limitType,
  }) {
    final result = BundledQuery._();
    if (parent != null) result.parent = parent;
    if (structuredQuery != null) result.structuredQuery = structuredQuery;
    if (limitType != null) result.limitType = limitType;
    return result;
  }

  BundledQuery._();

  factory BundledQuery.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundledQuery()..mergeFromBuffer(data, registry);
  factory BundledQuery.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundledQuery()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, BundledQuery_QueryType>
      _BundledQuery_QueryTypeByTag = {
    2: BundledQuery_QueryType.structuredQuery,
    0: BundledQuery_QueryType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BundledQuery',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'),
      createEmptyInstance: BundledQuery.$_createMessage)
    ..oo(0, [2])
    ..aOS(1, _omitFieldNames ? '' : 'parent')
    ..aOM<$0.StructuredQuery>(2, _omitFieldNames ? '' : 'structuredQuery',
        subBuilder: $0.StructuredQuery.$_createMessage)
    ..aE<BundledQuery_LimitType>(3, _omitFieldNames ? '' : 'limitType',
        enumValues: BundledQuery_LimitType.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundledQuery clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundledQuery copyWith(void Function(BundledQuery) updates) =>
      super.copyWith((message) => updates(message as BundledQuery))
          as BundledQuery;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BundledQuery() / BundledQuery.new instead')
  static BundledQuery create() => BundledQuery._();
  static $pb.GeneratedMessage $_createMessage() => BundledQuery._();
  @$core.override
  BundledQuery createEmptyInstance() => BundledQuery._();
  @$core.pragma('dart2js:noInline')
  static BundledQuery getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundledQuery>(
          BundledQuery.$_createMessage);
  static BundledQuery? _defaultInstance;

  @$pb.TagNumber(2)
  BundledQuery_QueryType whichQueryType() =>
      _BundledQuery_QueryTypeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  void clearQueryType() => $_clearField($_whichOneof(0));

  /// The parent resource name.
  @$pb.TagNumber(1)
  $core.String get parent => $_getSZ(0);
  @$pb.TagNumber(1)
  set parent($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasParent() => $_has(0);
  @$pb.TagNumber(1)
  void clearParent() => $_clearField(1);

  /// A structured query.
  @$pb.TagNumber(2)
  $0.StructuredQuery get structuredQuery => $_getN(1);
  @$pb.TagNumber(2)
  set structuredQuery($0.StructuredQuery value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStructuredQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearStructuredQuery() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.StructuredQuery ensureStructuredQuery() => $_ensure(1);

  @$pb.TagNumber(3)
  BundledQuery_LimitType get limitType => $_getN(2);
  @$pb.TagNumber(3)
  set limitType(BundledQuery_LimitType value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLimitType() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimitType() => $_clearField(3);
}

/// A Query associated with a name, created as part of the bundle file, and can be read
/// by client SDKs once the bundle containing them is loaded.
class NamedQuery extends $pb.GeneratedMessage {
  factory NamedQuery({
    $core.String? name,
    BundledQuery? bundledQuery,
    $1.Timestamp? readTime,
  }) {
    final result = NamedQuery._();
    if (name != null) result.name = name;
    if (bundledQuery != null) result.bundledQuery = bundledQuery;
    if (readTime != null) result.readTime = readTime;
    return result;
  }

  NamedQuery._();

  factory NamedQuery.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NamedQuery()..mergeFromBuffer(data, registry);
  factory NamedQuery.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NamedQuery()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NamedQuery',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'),
      createEmptyInstance: NamedQuery.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<BundledQuery>(2, _omitFieldNames ? '' : 'bundledQuery',
        subBuilder: BundledQuery.$_createMessage)
    ..aOM<$1.Timestamp>(3, _omitFieldNames ? '' : 'readTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NamedQuery clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NamedQuery copyWith(void Function(NamedQuery) updates) =>
      super.copyWith((message) => updates(message as NamedQuery)) as NamedQuery;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NamedQuery() / NamedQuery.new instead')
  static NamedQuery create() => NamedQuery._();
  static $pb.GeneratedMessage $_createMessage() => NamedQuery._();
  @$core.override
  NamedQuery createEmptyInstance() => NamedQuery._();
  @$core.pragma('dart2js:noInline')
  static NamedQuery getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NamedQuery>(NamedQuery.$_createMessage);
  static NamedQuery? _defaultInstance;

  /// Name of the query, such that client can use the name to load this query
  /// from bundle, and resume from when the query results are materialized
  /// into this bundle.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The query saved in the bundle.
  @$pb.TagNumber(2)
  BundledQuery get bundledQuery => $_getN(1);
  @$pb.TagNumber(2)
  set bundledQuery(BundledQuery value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasBundledQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearBundledQuery() => $_clearField(2);
  @$pb.TagNumber(2)
  BundledQuery ensureBundledQuery() => $_ensure(1);

  /// The read time of the query, when it is used to build the bundle. This is useful to
  /// resume the query from the bundle, once it is loaded by client SDKs.
  @$pb.TagNumber(3)
  $1.Timestamp get readTime => $_getN(2);
  @$pb.TagNumber(3)
  set readTime($1.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasReadTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearReadTime() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.Timestamp ensureReadTime() => $_ensure(2);
}

/// Metadata describing a Firestore document saved in the bundle.
class BundledDocumentMetadata extends $pb.GeneratedMessage {
  factory BundledDocumentMetadata({
    $core.String? name,
    $1.Timestamp? readTime,
    $core.bool? exists,
    $core.Iterable<$core.String>? queries,
  }) {
    final result = BundledDocumentMetadata._();
    if (name != null) result.name = name;
    if (readTime != null) result.readTime = readTime;
    if (exists != null) result.exists = exists;
    if (queries != null) result.queries.addAll(queries);
    return result;
  }

  BundledDocumentMetadata._();

  factory BundledDocumentMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundledDocumentMetadata()..mergeFromBuffer(data, registry);
  factory BundledDocumentMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundledDocumentMetadata()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BundledDocumentMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'),
      createEmptyInstance: BundledDocumentMetadata.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'readTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOB(3, _omitFieldNames ? '' : 'exists')
    ..pPS(4, _omitFieldNames ? '' : 'queries')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundledDocumentMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundledDocumentMetadata copyWith(
          void Function(BundledDocumentMetadata) updates) =>
      super.copyWith((message) => updates(message as BundledDocumentMetadata))
          as BundledDocumentMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use BundledDocumentMetadata() / BundledDocumentMetadata.new instead')
  static BundledDocumentMetadata create() => BundledDocumentMetadata._();
  static $pb.GeneratedMessage $_createMessage() => BundledDocumentMetadata._();
  @$core.override
  BundledDocumentMetadata createEmptyInstance() => BundledDocumentMetadata._();
  @$core.pragma('dart2js:noInline')
  static BundledDocumentMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BundledDocumentMetadata>(
          BundledDocumentMetadata.$_createMessage);
  static BundledDocumentMetadata? _defaultInstance;

  /// The document key of a bundled document.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The snapshot version of the document data bundled.
  @$pb.TagNumber(2)
  $1.Timestamp get readTime => $_getN(1);
  @$pb.TagNumber(2)
  set readTime($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReadTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearReadTime() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureReadTime() => $_ensure(1);

  /// Whether the document exists.
  @$pb.TagNumber(3)
  $core.bool get exists => $_getBF(2);
  @$pb.TagNumber(3)
  set exists($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExists() => $_has(2);
  @$pb.TagNumber(3)
  void clearExists() => $_clearField(3);

  /// The names of the queries in this bundle that this document matches to.
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get queries => $_getList(3);
}

/// Metadata describing the bundle file/stream.
class BundleMetadata extends $pb.GeneratedMessage {
  factory BundleMetadata({
    $core.String? id,
    $1.Timestamp? createTime,
    $core.int? version,
    $core.int? totalDocuments,
    $fixnum.Int64? totalBytes,
  }) {
    final result = BundleMetadata._();
    if (id != null) result.id = id;
    if (createTime != null) result.createTime = createTime;
    if (version != null) result.version = version;
    if (totalDocuments != null) result.totalDocuments = totalDocuments;
    if (totalBytes != null) result.totalBytes = totalBytes;
    return result;
  }

  BundleMetadata._();

  factory BundleMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundleMetadata()..mergeFromBuffer(data, registry);
  factory BundleMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundleMetadata()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BundleMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'),
      createEmptyInstance: BundleMetadata.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'createTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aI(3, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'totalDocuments',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'totalBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundleMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundleMetadata copyWith(void Function(BundleMetadata) updates) =>
      super.copyWith((message) => updates(message as BundleMetadata))
          as BundleMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BundleMetadata() / BundleMetadata.new instead')
  static BundleMetadata create() => BundleMetadata._();
  static $pb.GeneratedMessage $_createMessage() => BundleMetadata._();
  @$core.override
  BundleMetadata createEmptyInstance() => BundleMetadata._();
  @$core.pragma('dart2js:noInline')
  static BundleMetadata getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundleMetadata>(
          BundleMetadata.$_createMessage);
  static BundleMetadata? _defaultInstance;

  /// The ID of the bundle.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Time at which the documents snapshot is taken for this bundle.
  @$pb.TagNumber(2)
  $1.Timestamp get createTime => $_getN(1);
  @$pb.TagNumber(2)
  set createTime($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCreateTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearCreateTime() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureCreateTime() => $_ensure(1);

  /// The schema version of the bundle.
  @$pb.TagNumber(3)
  $core.int get version => $_getIZ(2);
  @$pb.TagNumber(3)
  set version($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearVersion() => $_clearField(3);

  /// The number of documents in the bundle.
  @$pb.TagNumber(4)
  $core.int get totalDocuments => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalDocuments($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalDocuments() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalDocuments() => $_clearField(4);

  /// The size of the bundle in bytes, excluding this `BundleMetadata`.
  @$pb.TagNumber(5)
  $fixnum.Int64 get totalBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set totalBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalBytes() => $_clearField(5);
}

enum BundleElement_ElementType {
  metadata,
  namedQuery,
  documentMetadata,
  document,
  notSet
}

/// A Firestore bundle is a length-prefixed stream of JSON representations of
/// `BundleElement`.
/// Only one `BundleMetadata` is expected, and it should be the first element.
/// The named queries follow after `metadata`. Every `document_metadata` is
/// immediately followed by a `document`.
class BundleElement extends $pb.GeneratedMessage {
  factory BundleElement({
    BundleMetadata? metadata,
    NamedQuery? namedQuery,
    BundledDocumentMetadata? documentMetadata,
    $2.Document? document,
  }) {
    final result = BundleElement._();
    if (metadata != null) result.metadata = metadata;
    if (namedQuery != null) result.namedQuery = namedQuery;
    if (documentMetadata != null) result.documentMetadata = documentMetadata;
    if (document != null) result.document = document;
    return result;
  }

  BundleElement._();

  factory BundleElement.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundleElement()..mergeFromBuffer(data, registry);
  factory BundleElement.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundleElement()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, BundleElement_ElementType>
      _BundleElement_ElementTypeByTag = {
    1: BundleElement_ElementType.metadata,
    2: BundleElement_ElementType.namedQuery,
    3: BundleElement_ElementType.documentMetadata,
    4: BundleElement_ElementType.document,
    0: BundleElement_ElementType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BundleElement',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'),
      createEmptyInstance: BundleElement.$_createMessage)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<BundleMetadata>(1, _omitFieldNames ? '' : 'metadata',
        subBuilder: BundleMetadata.$_createMessage)
    ..aOM<NamedQuery>(2, _omitFieldNames ? '' : 'namedQuery',
        subBuilder: NamedQuery.$_createMessage)
    ..aOM<BundledDocumentMetadata>(3, _omitFieldNames ? '' : 'documentMetadata',
        subBuilder: BundledDocumentMetadata.$_createMessage)
    ..aOM<$2.Document>(4, _omitFieldNames ? '' : 'document',
        subBuilder: $2.Document.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundleElement clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundleElement copyWith(void Function(BundleElement) updates) =>
      super.copyWith((message) => updates(message as BundleElement))
          as BundleElement;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BundleElement() / BundleElement.new instead')
  static BundleElement create() => BundleElement._();
  static $pb.GeneratedMessage $_createMessage() => BundleElement._();
  @$core.override
  BundleElement createEmptyInstance() => BundleElement._();
  @$core.pragma('dart2js:noInline')
  static BundleElement getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundleElement>(
          BundleElement.$_createMessage);
  static BundleElement? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  BundleElement_ElementType whichElementType() =>
      _BundleElement_ElementTypeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearElementType() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  BundleMetadata get metadata => $_getN(0);
  @$pb.TagNumber(1)
  set metadata(BundleMetadata value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMetadata() => $_has(0);
  @$pb.TagNumber(1)
  void clearMetadata() => $_clearField(1);
  @$pb.TagNumber(1)
  BundleMetadata ensureMetadata() => $_ensure(0);

  @$pb.TagNumber(2)
  NamedQuery get namedQuery => $_getN(1);
  @$pb.TagNumber(2)
  set namedQuery(NamedQuery value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasNamedQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearNamedQuery() => $_clearField(2);
  @$pb.TagNumber(2)
  NamedQuery ensureNamedQuery() => $_ensure(1);

  @$pb.TagNumber(3)
  BundledDocumentMetadata get documentMetadata => $_getN(2);
  @$pb.TagNumber(3)
  set documentMetadata(BundledDocumentMetadata value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDocumentMetadata() => $_has(2);
  @$pb.TagNumber(3)
  void clearDocumentMetadata() => $_clearField(3);
  @$pb.TagNumber(3)
  BundledDocumentMetadata ensureDocumentMetadata() => $_ensure(2);

  @$pb.TagNumber(4)
  $2.Document get document => $_getN(3);
  @$pb.TagNumber(4)
  set document($2.Document value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasDocument() => $_has(3);
  @$pb.TagNumber(4)
  void clearDocument() => $_clearField(4);
  @$pb.TagNumber(4)
  $2.Document ensureDocument() => $_ensure(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
