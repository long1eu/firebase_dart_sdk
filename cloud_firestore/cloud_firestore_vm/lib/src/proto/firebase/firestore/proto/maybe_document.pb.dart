///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/maybe_document.proto
//
// @dart = 2.7
// ignore_for_file: annotate_overrides,camel_case_types,unnecessary_const,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type,unnecessary_this,prefer_final_fields

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/protobuf/timestamp.pb.dart' as $4;
import '../../../google/firestore/v1/document.pb.dart' as $1;

class NoDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'NoDocument', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'firestore.client'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOM<$4.Timestamp>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'readTime', subBuilder: $4.Timestamp.create)
    ..hasRequiredFields = false
  ;

  NoDocument._() : super();
  factory NoDocument({
    $core.String name,
    $4.Timestamp readTime,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (readTime != null) {
      _result.readTime = readTime;
    }
    return _result;
  }
  factory NoDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NoDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NoDocument clone() => NoDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NoDocument copyWith(void Function(NoDocument) updates) => super.copyWith((message) => updates(message as NoDocument)); // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static NoDocument create() => NoDocument._();
  NoDocument createEmptyInstance() => create();
  static $pb.PbList<NoDocument> createRepeated() => $pb.PbList<NoDocument>();
  @$core.pragma('dart2js:noInline')
  static NoDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NoDocument>(create);
  static NoDocument _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $4.Timestamp get readTime => $_getN(1);
  @$pb.TagNumber(2)
  set readTime($4.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasReadTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearReadTime() => clearField(2);
  @$pb.TagNumber(2)
  $4.Timestamp ensureReadTime() => $_ensure(1);
}

class UnknownDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'UnknownDocument', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'firestore.client'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOM<$4.Timestamp>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'version', subBuilder: $4.Timestamp.create)
    ..hasRequiredFields = false
  ;

  UnknownDocument._() : super();
  factory UnknownDocument({
    $core.String name,
    $4.Timestamp version,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (version != null) {
      _result.version = version;
    }
    return _result;
  }
  factory UnknownDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UnknownDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UnknownDocument clone() => UnknownDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UnknownDocument copyWith(void Function(UnknownDocument) updates) => super.copyWith((message) => updates(message as UnknownDocument)); // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static UnknownDocument create() => UnknownDocument._();
  UnknownDocument createEmptyInstance() => create();
  static $pb.PbList<UnknownDocument> createRepeated() => $pb.PbList<UnknownDocument>();
  @$core.pragma('dart2js:noInline')
  static UnknownDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UnknownDocument>(create);
  static UnknownDocument _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $4.Timestamp get version => $_getN(1);
  @$pb.TagNumber(2)
  set version($4.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => clearField(2);
  @$pb.TagNumber(2)
  $4.Timestamp ensureVersion() => $_ensure(1);
}

enum MaybeDocument_DocumentType {
  noDocument, 
  document, 
  unknownDocument, 
  notSet
}

class MaybeDocument extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, MaybeDocument_DocumentType> _MaybeDocument_DocumentTypeByTag = {
    1 : MaybeDocument_DocumentType.noDocument,
    2 : MaybeDocument_DocumentType.document,
    3 : MaybeDocument_DocumentType.unknownDocument,
    0 : MaybeDocument_DocumentType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'MaybeDocument', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'firestore.client'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..aOM<NoDocument>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'noDocument', subBuilder: NoDocument.create)
    ..aOM<$1.Document>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'document', subBuilder: $1.Document.create)
    ..aOM<UnknownDocument>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'unknownDocument', subBuilder: UnknownDocument.create)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'hasCommittedMutations')
    ..hasRequiredFields = false
  ;

  MaybeDocument._() : super();
  factory MaybeDocument({
    NoDocument noDocument,
    $1.Document document,
    UnknownDocument unknownDocument,
    $core.bool hasCommittedMutations,
  }) {
    final _result = create();
    if (noDocument != null) {
      _result.noDocument = noDocument;
    }
    if (document != null) {
      _result.document = document;
    }
    if (unknownDocument != null) {
      _result.unknownDocument = unknownDocument;
    }
    if (hasCommittedMutations != null) {
      _result.hasCommittedMutations = hasCommittedMutations;
    }
    return _result;
  }
  factory MaybeDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MaybeDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MaybeDocument clone() => MaybeDocument()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MaybeDocument copyWith(void Function(MaybeDocument) updates) => super.copyWith((message) => updates(message as MaybeDocument)); // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MaybeDocument create() => MaybeDocument._();
  MaybeDocument createEmptyInstance() => create();
  static $pb.PbList<MaybeDocument> createRepeated() => $pb.PbList<MaybeDocument>();
  @$core.pragma('dart2js:noInline')
  static MaybeDocument getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MaybeDocument>(create);
  static MaybeDocument _defaultInstance;

  MaybeDocument_DocumentType whichDocumentType() => _MaybeDocument_DocumentTypeByTag[$_whichOneof(0)];
  void clearDocumentType() => clearField($_whichOneof(0));

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

  @$pb.TagNumber(4)
  $core.bool get hasCommittedMutations => $_getBF(3);
  @$pb.TagNumber(4)
  set hasCommittedMutations($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHasCommittedMutations() => $_has(3);
  @$pb.TagNumber(4)
  void clearHasCommittedMutations() => clearField(4);
}

