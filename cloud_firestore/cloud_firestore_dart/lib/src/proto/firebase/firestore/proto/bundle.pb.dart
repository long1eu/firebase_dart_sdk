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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/firestore/v1/document.pb.dart' as $1;
import '../../../google/firestore/v1/query.pb.dart' as $7;
import '../../../google/protobuf/timestamp.pb.dart' as $3;
import 'bundle.pbenum.dart';

export 'bundle.pbenum.dart';

enum BundledQuery_QueryType {
  structuredQuery, 
  notSet
}

/// Encodes a query saved in the bundle.
class BundledQuery extends $pb.GeneratedMessage {
  factory BundledQuery({
    $core.String? parent,
    $7.StructuredQuery? structuredQuery,
    BundledQuery_LimitType? limitType,
  }) {
    final $result = create();
    if (parent != null) {
      $result.parent = parent;
    }
    if (structuredQuery != null) {
      $result.structuredQuery = structuredQuery;
    }
    if (limitType != null) {
      $result.limitType = limitType;
    }
    return $result;
  }
  BundledQuery._() : super();
  factory BundledQuery.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BundledQuery.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, BundledQuery_QueryType> _BundledQuery_QueryTypeByTag = {
    2 : BundledQuery_QueryType.structuredQuery,
    0 : BundledQuery_QueryType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BundledQuery', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'), createEmptyInstance: create)
    ..oo(0, [2])
    ..aOS(1, _omitFieldNames ? '' : 'parent')
    ..aOM<$7.StructuredQuery>(2, _omitFieldNames ? '' : 'structuredQuery', subBuilder: $7.StructuredQuery.create)
    ..e<BundledQuery_LimitType>(3, _omitFieldNames ? '' : 'limitType', $pb.PbFieldType.OE, defaultOrMaker: BundledQuery_LimitType.FIRST, valueOf: BundledQuery_LimitType.valueOf, enumValues: BundledQuery_LimitType.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BundledQuery clone() => BundledQuery()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BundledQuery copyWith(void Function(BundledQuery) updates) => super.copyWith((message) => updates(message as BundledQuery)) as BundledQuery;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BundledQuery create() => BundledQuery._();
  BundledQuery createEmptyInstance() => create();
  static $pb.PbList<BundledQuery> createRepeated() => $pb.PbList<BundledQuery>();
  @$core.pragma('dart2js:noInline')
  static BundledQuery getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundledQuery>(create);
  static BundledQuery? _defaultInstance;

  BundledQuery_QueryType whichQueryType() => _BundledQuery_QueryTypeByTag[$_whichOneof(0)]!;
  void clearQueryType() => clearField($_whichOneof(0));

  /// The parent resource name.
  @$pb.TagNumber(1)
  $core.String get parent => $_getSZ(0);
  @$pb.TagNumber(1)
  set parent($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasParent() => $_has(0);
  @$pb.TagNumber(1)
  void clearParent() => clearField(1);

  /// A structured query.
  @$pb.TagNumber(2)
  $7.StructuredQuery get structuredQuery => $_getN(1);
  @$pb.TagNumber(2)
  set structuredQuery($7.StructuredQuery v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasStructuredQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearStructuredQuery() => clearField(2);
  @$pb.TagNumber(2)
  $7.StructuredQuery ensureStructuredQuery() => $_ensure(1);

  @$pb.TagNumber(3)
  BundledQuery_LimitType get limitType => $_getN(2);
  @$pb.TagNumber(3)
  set limitType(BundledQuery_LimitType v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLimitType() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimitType() => clearField(3);
}

/// A Query associated with a name, created as part of the bundle file, and can be read
/// by client SDKs once the bundle containing them is loaded.
class NamedQuery extends $pb.GeneratedMessage {
  factory NamedQuery({
    $core.String? name,
    BundledQuery? bundledQuery,
    $3.Timestamp? readTime,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (bundledQuery != null) {
      $result.bundledQuery = bundledQuery;
    }
    if (readTime != null) {
      $result.readTime = readTime;
    }
    return $result;
  }
  NamedQuery._() : super();
  factory NamedQuery.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NamedQuery.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NamedQuery', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<BundledQuery>(2, _omitFieldNames ? '' : 'bundledQuery', subBuilder: BundledQuery.create)
    ..aOM<$3.Timestamp>(3, _omitFieldNames ? '' : 'readTime', subBuilder: $3.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NamedQuery clone() => NamedQuery()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NamedQuery copyWith(void Function(NamedQuery) updates) => super.copyWith((message) => updates(message as NamedQuery)) as NamedQuery;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NamedQuery create() => NamedQuery._();
  NamedQuery createEmptyInstance() => create();
  static $pb.PbList<NamedQuery> createRepeated() => $pb.PbList<NamedQuery>();
  @$core.pragma('dart2js:noInline')
  static NamedQuery getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NamedQuery>(create);
  static NamedQuery? _defaultInstance;

  /// Name of the query, such that client can use the name to load this query
  /// from bundle, and resume from when the query results are materialized
  /// into this bundle.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// The query saved in the bundle.
  @$pb.TagNumber(2)
  BundledQuery get bundledQuery => $_getN(1);
  @$pb.TagNumber(2)
  set bundledQuery(BundledQuery v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasBundledQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearBundledQuery() => clearField(2);
  @$pb.TagNumber(2)
  BundledQuery ensureBundledQuery() => $_ensure(1);

  /// The read time of the query, when it is used to build the bundle. This is useful to
  /// resume the query from the bundle, once it is loaded by client SDKs.
  @$pb.TagNumber(3)
  $3.Timestamp get readTime => $_getN(2);
  @$pb.TagNumber(3)
  set readTime($3.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasReadTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearReadTime() => clearField(3);
  @$pb.TagNumber(3)
  $3.Timestamp ensureReadTime() => $_ensure(2);
}

/// Metadata describing a Firestore document saved in the bundle.
class BundledDocumentMetadata extends $pb.GeneratedMessage {
  factory BundledDocumentMetadata({
    $core.String? name,
    $3.Timestamp? readTime,
    $core.bool? exists,
    $core.Iterable<$core.String>? queries,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (readTime != null) {
      $result.readTime = readTime;
    }
    if (exists != null) {
      $result.exists = exists;
    }
    if (queries != null) {
      $result.queries.addAll(queries);
    }
    return $result;
  }
  BundledDocumentMetadata._() : super();
  factory BundledDocumentMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BundledDocumentMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BundledDocumentMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'readTime', subBuilder: $3.Timestamp.create)
    ..aOB(3, _omitFieldNames ? '' : 'exists')
    ..pPS(4, _omitFieldNames ? '' : 'queries')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BundledDocumentMetadata clone() => BundledDocumentMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BundledDocumentMetadata copyWith(void Function(BundledDocumentMetadata) updates) => super.copyWith((message) => updates(message as BundledDocumentMetadata)) as BundledDocumentMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BundledDocumentMetadata create() => BundledDocumentMetadata._();
  BundledDocumentMetadata createEmptyInstance() => create();
  static $pb.PbList<BundledDocumentMetadata> createRepeated() => $pb.PbList<BundledDocumentMetadata>();
  @$core.pragma('dart2js:noInline')
  static BundledDocumentMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundledDocumentMetadata>(create);
  static BundledDocumentMetadata? _defaultInstance;

  /// The document key of a bundled document.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// The snapshot version of the document data bundled.
  @$pb.TagNumber(2)
  $3.Timestamp get readTime => $_getN(1);
  @$pb.TagNumber(2)
  set readTime($3.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasReadTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearReadTime() => clearField(2);
  @$pb.TagNumber(2)
  $3.Timestamp ensureReadTime() => $_ensure(1);

  /// Whether the document exists.
  @$pb.TagNumber(3)
  $core.bool get exists => $_getBF(2);
  @$pb.TagNumber(3)
  set exists($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasExists() => $_has(2);
  @$pb.TagNumber(3)
  void clearExists() => clearField(3);

  /// The names of the queries in this bundle that this document matches to.
  @$pb.TagNumber(4)
  $core.List<$core.String> get queries => $_getList(3);
}

/// Metadata describing the bundle file/stream.
class BundleMetadata extends $pb.GeneratedMessage {
  factory BundleMetadata({
    $core.String? id,
    $3.Timestamp? createTime,
    $core.int? version,
    $core.int? totalDocuments,
    $fixnum.Int64? totalBytes,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (createTime != null) {
      $result.createTime = createTime;
    }
    if (version != null) {
      $result.version = version;
    }
    if (totalDocuments != null) {
      $result.totalDocuments = totalDocuments;
    }
    if (totalBytes != null) {
      $result.totalBytes = totalBytes;
    }
    return $result;
  }
  BundleMetadata._() : super();
  factory BundleMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BundleMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BundleMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'createTime', subBuilder: $3.Timestamp.create)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'totalDocuments', $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'totalBytes', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BundleMetadata clone() => BundleMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BundleMetadata copyWith(void Function(BundleMetadata) updates) => super.copyWith((message) => updates(message as BundleMetadata)) as BundleMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BundleMetadata create() => BundleMetadata._();
  BundleMetadata createEmptyInstance() => create();
  static $pb.PbList<BundleMetadata> createRepeated() => $pb.PbList<BundleMetadata>();
  @$core.pragma('dart2js:noInline')
  static BundleMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundleMetadata>(create);
  static BundleMetadata? _defaultInstance;

  /// The ID of the bundle.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Time at which the documents snapshot is taken for this bundle.
  @$pb.TagNumber(2)
  $3.Timestamp get createTime => $_getN(1);
  @$pb.TagNumber(2)
  set createTime($3.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCreateTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearCreateTime() => clearField(2);
  @$pb.TagNumber(2)
  $3.Timestamp ensureCreateTime() => $_ensure(1);

  /// The schema version of the bundle.
  @$pb.TagNumber(3)
  $core.int get version => $_getIZ(2);
  @$pb.TagNumber(3)
  set version($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearVersion() => clearField(3);

  /// The number of documents in the bundle.
  @$pb.TagNumber(4)
  $core.int get totalDocuments => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalDocuments($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalDocuments() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalDocuments() => clearField(4);

  /// The size of the bundle in bytes, excluding this `BundleMetadata`.
  @$pb.TagNumber(5)
  $fixnum.Int64 get totalBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set totalBytes($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTotalBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalBytes() => clearField(5);
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
    $1.Document? document,
  }) {
    final $result = create();
    if (metadata != null) {
      $result.metadata = metadata;
    }
    if (namedQuery != null) {
      $result.namedQuery = namedQuery;
    }
    if (documentMetadata != null) {
      $result.documentMetadata = documentMetadata;
    }
    if (document != null) {
      $result.document = document;
    }
    return $result;
  }
  BundleElement._() : super();
  factory BundleElement.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BundleElement.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, BundleElement_ElementType> _BundleElement_ElementTypeByTag = {
    1 : BundleElement_ElementType.metadata,
    2 : BundleElement_ElementType.namedQuery,
    3 : BundleElement_ElementType.documentMetadata,
    4 : BundleElement_ElementType.document,
    0 : BundleElement_ElementType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BundleElement', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<BundleMetadata>(1, _omitFieldNames ? '' : 'metadata', subBuilder: BundleMetadata.create)
    ..aOM<NamedQuery>(2, _omitFieldNames ? '' : 'namedQuery', subBuilder: NamedQuery.create)
    ..aOM<BundledDocumentMetadata>(3, _omitFieldNames ? '' : 'documentMetadata', subBuilder: BundledDocumentMetadata.create)
    ..aOM<$1.Document>(4, _omitFieldNames ? '' : 'document', subBuilder: $1.Document.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BundleElement clone() => BundleElement()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BundleElement copyWith(void Function(BundleElement) updates) => super.copyWith((message) => updates(message as BundleElement)) as BundleElement;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BundleElement create() => BundleElement._();
  BundleElement createEmptyInstance() => create();
  static $pb.PbList<BundleElement> createRepeated() => $pb.PbList<BundleElement>();
  @$core.pragma('dart2js:noInline')
  static BundleElement getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundleElement>(create);
  static BundleElement? _defaultInstance;

  BundleElement_ElementType whichElementType() => _BundleElement_ElementTypeByTag[$_whichOneof(0)]!;
  void clearElementType() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  BundleMetadata get metadata => $_getN(0);
  @$pb.TagNumber(1)
  set metadata(BundleMetadata v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasMetadata() => $_has(0);
  @$pb.TagNumber(1)
  void clearMetadata() => clearField(1);
  @$pb.TagNumber(1)
  BundleMetadata ensureMetadata() => $_ensure(0);

  @$pb.TagNumber(2)
  NamedQuery get namedQuery => $_getN(1);
  @$pb.TagNumber(2)
  set namedQuery(NamedQuery v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasNamedQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearNamedQuery() => clearField(2);
  @$pb.TagNumber(2)
  NamedQuery ensureNamedQuery() => $_ensure(1);

  @$pb.TagNumber(3)
  BundledDocumentMetadata get documentMetadata => $_getN(2);
  @$pb.TagNumber(3)
  set documentMetadata(BundledDocumentMetadata v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasDocumentMetadata() => $_has(2);
  @$pb.TagNumber(3)
  void clearDocumentMetadata() => clearField(3);
  @$pb.TagNumber(3)
  BundledDocumentMetadata ensureDocumentMetadata() => $_ensure(2);

  @$pb.TagNumber(4)
  $1.Document get document => $_getN(3);
  @$pb.TagNumber(4)
  set document($1.Document v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasDocument() => $_has(3);
  @$pb.TagNumber(4)
  void clearDocument() => clearField(4);
  @$pb.TagNumber(4)
  $1.Document ensureDocument() => $_ensure(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
