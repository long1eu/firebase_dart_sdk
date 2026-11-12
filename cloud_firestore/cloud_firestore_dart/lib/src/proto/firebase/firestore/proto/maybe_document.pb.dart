// This is a generated file - do not edit.
//
// Generated from firebase/firestore/proto/maybe_document.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import '../../../google/firestore/v1/document.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// A message indicating that the document is known to not exist.
class NoDocument extends $pb.GeneratedMessage {
  factory NoDocument({
    $core.String? name,
    $0.Timestamp? readTime,
  }) {
    final result = NoDocument._();
    if (name != null) result.name = name;
    if (readTime != null) result.readTime = readTime;
    return result;
  }

  NoDocument._();

  factory NoDocument.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NoDocument()..mergeFromBuffer(data, registry);
  factory NoDocument.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NoDocument()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NoDocument',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: NoDocument.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<$0.Timestamp>(2, _omitFieldNames ? '' : 'readTime',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NoDocument clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NoDocument copyWith(void Function(NoDocument) updates) =>
      super.copyWith((message) => updates(message as NoDocument)) as NoDocument;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NoDocument() / NoDocument.new instead')
  static NoDocument create() => NoDocument._();
  static $pb.GeneratedMessage $_createMessage() => NoDocument._();
  @$core.override
  NoDocument createEmptyInstance() => NoDocument._();
  @$core.pragma('dart2js:noInline')
  static NoDocument getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NoDocument>(NoDocument.$_createMessage);
  static NoDocument? _defaultInstance;

  /// The name of the document that does not exist, in the standard format:
  /// `projects/{project_id}/databases/{database_id}/documents/{document_path}`
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The time at which we observed that it does not exist.
  @$pb.TagNumber(2)
  $0.Timestamp get readTime => $_getN(1);
  @$pb.TagNumber(2)
  set readTime($0.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReadTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearReadTime() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Timestamp ensureReadTime() => $_ensure(1);
}

/// A message indicating that the document that is known to exist but its data
/// is unknown.
class UnknownDocument extends $pb.GeneratedMessage {
  factory UnknownDocument({
    $core.String? name,
    $0.Timestamp? version,
  }) {
    final result = UnknownDocument._();
    if (name != null) result.name = name;
    if (version != null) result.version = version;
    return result;
  }

  UnknownDocument._();

  factory UnknownDocument.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UnknownDocument()..mergeFromBuffer(data, registry);
  factory UnknownDocument.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UnknownDocument()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnknownDocument',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: UnknownDocument.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<$0.Timestamp>(2, _omitFieldNames ? '' : 'version',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnknownDocument clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnknownDocument copyWith(void Function(UnknownDocument) updates) =>
      super.copyWith((message) => updates(message as UnknownDocument))
          as UnknownDocument;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UnknownDocument() / UnknownDocument.new instead')
  static UnknownDocument create() => UnknownDocument._();
  static $pb.GeneratedMessage $_createMessage() => UnknownDocument._();
  @$core.override
  UnknownDocument createEmptyInstance() => UnknownDocument._();
  @$core.pragma('dart2js:noInline')
  static UnknownDocument getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UnknownDocument>(
          UnknownDocument.$_createMessage);
  static UnknownDocument? _defaultInstance;

  /// The name of the document that is known to exist, in the standard format:
  /// `projects/{project_id}/databases/{database_id}/documents/{document_path}`
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The version at which we know the document exists.
  @$pb.TagNumber(2)
  $0.Timestamp get version => $_getN(1);
  @$pb.TagNumber(2)
  set version($0.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Timestamp ensureVersion() => $_ensure(1);
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
    final result = MaybeDocument._();
    if (noDocument != null) result.noDocument = noDocument;
    if (document != null) result.document = document;
    if (unknownDocument != null) result.unknownDocument = unknownDocument;
    if (hasCommittedMutations != null)
      result.hasCommittedMutations = hasCommittedMutations;
    return result;
  }

  MaybeDocument._();

  factory MaybeDocument.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MaybeDocument()..mergeFromBuffer(data, registry);
  factory MaybeDocument.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MaybeDocument()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, MaybeDocument_DocumentType>
      _MaybeDocument_DocumentTypeByTag = {
    1: MaybeDocument_DocumentType.noDocument,
    2: MaybeDocument_DocumentType.document,
    3: MaybeDocument_DocumentType.unknownDocument,
    0: MaybeDocument_DocumentType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MaybeDocument',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'),
      createEmptyInstance: MaybeDocument.$_createMessage)
    ..oo(0, [1, 2, 3])
    ..aOM<NoDocument>(1, _omitFieldNames ? '' : 'noDocument',
        subBuilder: NoDocument.$_createMessage)
    ..aOM<$1.Document>(2, _omitFieldNames ? '' : 'document',
        subBuilder: $1.Document.$_createMessage)
    ..aOM<UnknownDocument>(3, _omitFieldNames ? '' : 'unknownDocument',
        subBuilder: UnknownDocument.$_createMessage)
    ..aOB(4, _omitFieldNames ? '' : 'hasCommittedMutations')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MaybeDocument clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MaybeDocument copyWith(void Function(MaybeDocument) updates) =>
      super.copyWith((message) => updates(message as MaybeDocument))
          as MaybeDocument;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MaybeDocument() / MaybeDocument.new instead')
  static MaybeDocument create() => MaybeDocument._();
  static $pb.GeneratedMessage $_createMessage() => MaybeDocument._();
  @$core.override
  MaybeDocument createEmptyInstance() => MaybeDocument._();
  @$core.pragma('dart2js:noInline')
  static MaybeDocument getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MaybeDocument>(
          MaybeDocument.$_createMessage);
  static MaybeDocument? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  MaybeDocument_DocumentType whichDocumentType() =>
      _MaybeDocument_DocumentTypeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearDocumentType() => $_clearField($_whichOneof(0));

  /// Used if the document is known to not exist.
  @$pb.TagNumber(1)
  NoDocument get noDocument => $_getN(0);
  @$pb.TagNumber(1)
  set noDocument(NoDocument value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasNoDocument() => $_has(0);
  @$pb.TagNumber(1)
  void clearNoDocument() => $_clearField(1);
  @$pb.TagNumber(1)
  NoDocument ensureNoDocument() => $_ensure(0);

  /// The document (if it exists).
  @$pb.TagNumber(2)
  $1.Document get document => $_getN(1);
  @$pb.TagNumber(2)
  set document($1.Document value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDocument() => $_has(1);
  @$pb.TagNumber(2)
  void clearDocument() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Document ensureDocument() => $_ensure(1);

  /// Used if the document is known to exist but its data is unknown.
  @$pb.TagNumber(3)
  UnknownDocument get unknownDocument => $_getN(2);
  @$pb.TagNumber(3)
  set unknownDocument(UnknownDocument value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasUnknownDocument() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnknownDocument() => $_clearField(3);
  @$pb.TagNumber(3)
  UnknownDocument ensureUnknownDocument() => $_ensure(2);

  /// `has_committed_mutations` marks documents that were written to the remote
  /// document store based on a write acknowledgment. These documents are
  /// potentially inconsistent with the backend's copy and use the write's
  /// commit version as their document version.
  @$pb.TagNumber(4)
  $core.bool get hasCommittedMutations => $_getBF(3);
  @$pb.TagNumber(4)
  set hasCommittedMutations($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHasCommittedMutations() => $_has(3);
  @$pb.TagNumber(4)
  void clearHasCommittedMutations() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
