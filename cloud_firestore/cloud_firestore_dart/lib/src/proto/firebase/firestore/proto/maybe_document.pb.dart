//
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/maybe_document.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/firestore/v1/document.pb.dart' as $1;
import '../../../google/protobuf/timestamp.pb.dart' as $3;

/// A message indicating that the document is known to not exist.
class NoDocument extends $pb.GeneratedMessage {
  factory NoDocument({
    $core.String? name,
    $3.Timestamp? readTime,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (readTime != null) {
      $result.readTime = readTime;
    }
    return $result;
  }
  NoDocument._() : super();
  factory NoDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NoDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NoDocument', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'readTime', subBuilder: $3.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NoDocument clone() => NoDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NoDocument copyWith(void Function(NoDocument) updates) => super.copyWith((message) => updates(message as NoDocument)) as NoDocument;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NoDocument create() => NoDocument._();
  NoDocument createEmptyInstance() => create();
  static $pb.PbList<NoDocument> createRepeated() => $pb.PbList<NoDocument>();
  @$core.pragma('dart2js:noInline')
  static NoDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NoDocument>(create);
  static NoDocument? _defaultInstance;

  /// The name of the document that does not exist, in the standard format:
  /// `projects/{project_id}/databases/{database_id}/documents/{document_path}`
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// The time at which we observed that it does not exist.
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
}

/// A message indicating that the document that is known to exist but its data
/// is unknown.
class UnknownDocument extends $pb.GeneratedMessage {
  factory UnknownDocument({
    $core.String? name,
    $3.Timestamp? version,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (version != null) {
      $result.version = version;
    }
    return $result;
  }
  UnknownDocument._() : super();
  factory UnknownDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UnknownDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UnknownDocument', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'version', subBuilder: $3.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UnknownDocument clone() => UnknownDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UnknownDocument copyWith(void Function(UnknownDocument) updates) => super.copyWith((message) => updates(message as UnknownDocument)) as UnknownDocument;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UnknownDocument create() => UnknownDocument._();
  UnknownDocument createEmptyInstance() => create();
  static $pb.PbList<UnknownDocument> createRepeated() => $pb.PbList<UnknownDocument>();
  @$core.pragma('dart2js:noInline')
  static UnknownDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UnknownDocument>(create);
  static UnknownDocument? _defaultInstance;

  /// The name of the document that is known to exist, in the standard format:
  /// `projects/{project_id}/databases/{database_id}/documents/{document_path}`
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// The version at which we know the document exists.
  @$pb.TagNumber(2)
  $3.Timestamp get version => $_getN(1);
  @$pb.TagNumber(2)
  set version($3.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => clearField(2);
  @$pb.TagNumber(2)
  $3.Timestamp ensureVersion() => $_ensure(1);
}

enum MaybeDocument_DocumentType {
  noDocument, 
  document, 
  unknownDocument, 
  notSet
}

/// Represents either an existing document, the explicitly known absence of a
/// document, or a document that is known to exist (at some version) but whose
/// contents are unknown.
class MaybeDocument extends $pb.GeneratedMessage {
  factory MaybeDocument({
    NoDocument? noDocument,
    $1.Document? document,
    UnknownDocument? unknownDocument,
    $core.bool? hasCommittedMutations,
  }) {
    final $result = create();
    if (noDocument != null) {
      $result.noDocument = noDocument;
    }
    if (document != null) {
      $result.document = document;
    }
    if (unknownDocument != null) {
      $result.unknownDocument = unknownDocument;
    }
    if (hasCommittedMutations != null) {
      $result.hasCommittedMutations = hasCommittedMutations;
    }
    return $result;
  }
  MaybeDocument._() : super();
  factory MaybeDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MaybeDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, MaybeDocument_DocumentType> _MaybeDocument_DocumentTypeByTag = {
    1 : MaybeDocument_DocumentType.noDocument,
    2 : MaybeDocument_DocumentType.document,
    3 : MaybeDocument_DocumentType.unknownDocument,
    0 : MaybeDocument_DocumentType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MaybeDocument', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..aOM<NoDocument>(1, _omitFieldNames ? '' : 'noDocument', subBuilder: NoDocument.create)
    ..aOM<$1.Document>(2, _omitFieldNames ? '' : 'document', subBuilder: $1.Document.create)
    ..aOM<UnknownDocument>(3, _omitFieldNames ? '' : 'unknownDocument', subBuilder: UnknownDocument.create)
    ..aOB(4, _omitFieldNames ? '' : 'hasCommittedMutations')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MaybeDocument clone() => MaybeDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MaybeDocument copyWith(void Function(MaybeDocument) updates) => super.copyWith((message) => updates(message as MaybeDocument)) as MaybeDocument;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MaybeDocument create() => MaybeDocument._();
  MaybeDocument createEmptyInstance() => create();
  static $pb.PbList<MaybeDocument> createRepeated() => $pb.PbList<MaybeDocument>();
  @$core.pragma('dart2js:noInline')
  static MaybeDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MaybeDocument>(create);
  static MaybeDocument? _defaultInstance;

  MaybeDocument_DocumentType whichDocumentType() => _MaybeDocument_DocumentTypeByTag[$_whichOneof(0)]!;
  void clearDocumentType() => clearField($_whichOneof(0));

  /// Used if the document is known to not exist.
  @$pb.TagNumber(1)
  NoDocument get noDocument => $_getN(0);
  @$pb.TagNumber(1)
  set noDocument(NoDocument v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasNoDocument() => $_has(0);
  @$pb.TagNumber(1)
  void clearNoDocument() => clearField(1);
  @$pb.TagNumber(1)
  NoDocument ensureNoDocument() => $_ensure(0);

  /// The document (if it exists).
  @$pb.TagNumber(2)
  $1.Document get document => $_getN(1);
  @$pb.TagNumber(2)
  set document($1.Document v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasDocument() => $_has(1);
  @$pb.TagNumber(2)
  void clearDocument() => clearField(2);
  @$pb.TagNumber(2)
  $1.Document ensureDocument() => $_ensure(1);

  /// Used if the document is known to exist but its data is unknown.
  @$pb.TagNumber(3)
  UnknownDocument get unknownDocument => $_getN(2);
  @$pb.TagNumber(3)
  set unknownDocument(UnknownDocument v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasUnknownDocument() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnknownDocument() => clearField(3);
  @$pb.TagNumber(3)
  UnknownDocument ensureUnknownDocument() => $_ensure(2);

  /// `has_committed_mutations` marks documents that were written to the remote
  /// document store based on a write acknowledgment. These documents are
  /// potentially inconsistent with the backend's copy and use the write's
  /// commit version as their document version.
  @$pb.TagNumber(4)
  $core.bool get hasCommittedMutations => $_getBF(3);
  @$pb.TagNumber(4)
  set hasCommittedMutations($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHasCommittedMutations() => $_has(3);
  @$pb.TagNumber(4)
  void clearHasCommittedMutations() => clearField(4);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
