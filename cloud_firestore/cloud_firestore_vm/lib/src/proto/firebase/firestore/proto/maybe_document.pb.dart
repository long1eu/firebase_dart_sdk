///
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/maybe_document.proto
//
// @dart = 2.3
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name,return_of_invalid_type

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/protobuf/timestamp.pb.dart' as $4;
import '../../../google/firestore/v1/document.pb.dart' as $1;

class NoDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('NoDocument',
      package: const $pb.PackageName('firestore.client'),
      createEmptyInstance: create)
    ..aOS(1, 'name')
    ..aOM<$4.Timestamp>(2, 'readTime', subBuilder: $4.Timestamp.create)
    ..hasRequiredFields = false;

  NoDocument._() : super();
  factory NoDocument() => create();
  factory NoDocument.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory NoDocument.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);
  NoDocument clone() => NoDocument()..mergeFromMessage(this);
  NoDocument copyWith(void Function(NoDocument) updates) =>
      super.copyWith((message) => updates(message as NoDocument));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static NoDocument create() => NoDocument._();
  NoDocument createEmptyInstance() => create();
  static $pb.PbList<NoDocument> createRepeated() => $pb.PbList<NoDocument>();
  @$core.pragma('dart2js:noInline')
  static NoDocument getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NoDocument>(create);
  static NoDocument _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $4.Timestamp get readTime => $_getN(1);
  @$pb.TagNumber(2)
  set readTime($4.Timestamp v) {
    setField(2, v);
  }

  @$pb.TagNumber(2)
  $core.bool hasReadTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearReadTime() => clearField(2);
  @$pb.TagNumber(2)
  $4.Timestamp ensureReadTime() => $_ensure(1);
}

class UnknownDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('UnknownDocument',
      package: const $pb.PackageName('firestore.client'),
      createEmptyInstance: create)
    ..aOS(1, 'name')
    ..aOM<$4.Timestamp>(2, 'version', subBuilder: $4.Timestamp.create)
    ..hasRequiredFields = false;

  UnknownDocument._() : super();
  factory UnknownDocument() => create();
  factory UnknownDocument.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory UnknownDocument.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);
  UnknownDocument clone() => UnknownDocument()..mergeFromMessage(this);
  UnknownDocument copyWith(void Function(UnknownDocument) updates) =>
      super.copyWith((message) => updates(message as UnknownDocument));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static UnknownDocument create() => UnknownDocument._();
  UnknownDocument createEmptyInstance() => create();
  static $pb.PbList<UnknownDocument> createRepeated() =>
      $pb.PbList<UnknownDocument>();
  @$core.pragma('dart2js:noInline')
  static UnknownDocument getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UnknownDocument>(create);
  static UnknownDocument _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $4.Timestamp get version => $_getN(1);
  @$pb.TagNumber(2)
  set version($4.Timestamp v) {
    setField(2, v);
  }

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
  static const $core.Map<$core.int, MaybeDocument_DocumentType>
      _MaybeDocument_DocumentTypeByTag = {
    1: MaybeDocument_DocumentType.noDocument,
    2: MaybeDocument_DocumentType.document,
    3: MaybeDocument_DocumentType.unknownDocument,
    0: MaybeDocument_DocumentType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('MaybeDocument',
      package: const $pb.PackageName('firestore.client'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..aOM<NoDocument>(1, 'noDocument', subBuilder: NoDocument.create)
    ..aOM<$1.Document>(2, 'document', subBuilder: $1.Document.create)
    ..aOM<UnknownDocument>(3, 'unknownDocument',
        subBuilder: UnknownDocument.create)
    ..aOB(4, 'hasCommittedMutations')
    ..hasRequiredFields = false;

  MaybeDocument._() : super();
  factory MaybeDocument() => create();
  factory MaybeDocument.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory MaybeDocument.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);
  MaybeDocument clone() => MaybeDocument()..mergeFromMessage(this);
  MaybeDocument copyWith(void Function(MaybeDocument) updates) =>
      super.copyWith((message) => updates(message as MaybeDocument));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MaybeDocument create() => MaybeDocument._();
  MaybeDocument createEmptyInstance() => create();
  static $pb.PbList<MaybeDocument> createRepeated() =>
      $pb.PbList<MaybeDocument>();
  @$core.pragma('dart2js:noInline')
  static MaybeDocument getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MaybeDocument>(create);
  static MaybeDocument _defaultInstance;

  MaybeDocument_DocumentType whichDocumentType() =>
      _MaybeDocument_DocumentTypeByTag[$_whichOneof(0)];
  void clearDocumentType() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  NoDocument get noDocument => $_getN(0);
  @$pb.TagNumber(1)
  set noDocument(NoDocument v) {
    setField(1, v);
  }

  @$pb.TagNumber(1)
  $core.bool hasNoDocument() => $_has(0);
  @$pb.TagNumber(1)
  void clearNoDocument() => clearField(1);
  @$pb.TagNumber(1)
  NoDocument ensureNoDocument() => $_ensure(0);

  @$pb.TagNumber(2)
  $1.Document get document => $_getN(1);
  @$pb.TagNumber(2)
  set document($1.Document v) {
    setField(2, v);
  }

  @$pb.TagNumber(2)
  $core.bool hasDocument() => $_has(1);
  @$pb.TagNumber(2)
  void clearDocument() => clearField(2);
  @$pb.TagNumber(2)
  $1.Document ensureDocument() => $_ensure(1);

  @$pb.TagNumber(3)
  UnknownDocument get unknownDocument => $_getN(2);
  @$pb.TagNumber(3)
  set unknownDocument(UnknownDocument v) {
    setField(3, v);
  }

  @$pb.TagNumber(3)
  $core.bool hasUnknownDocument() => $_has(2);
  @$pb.TagNumber(3)
  void clearUnknownDocument() => clearField(3);
  @$pb.TagNumber(3)
  UnknownDocument ensureUnknownDocument() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get hasCommittedMutations => $_getBF(3);
  @$pb.TagNumber(4)
  set hasCommittedMutations($core.bool v) {
    $_setBool(3, v);
  }

  @$pb.TagNumber(4)
  $core.bool hasHasCommittedMutations() => $_has(3);
  @$pb.TagNumber(4)
  void clearHasCommittedMutations() => clearField(4);
}
