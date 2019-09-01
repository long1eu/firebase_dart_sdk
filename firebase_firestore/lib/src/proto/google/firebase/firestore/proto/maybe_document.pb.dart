///
//  Generated code. Do not modify.
//  source: google/firebase/firestore/proto/maybe_document.proto
///
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name

import 'dart:core' as $core show bool, Deprecated, double, int, List, Map, override, pragma, String;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../../protobuf/timestamp.pb.dart' as $0;
import '../../../firestore/v1beta1/document.pb.dart' as $1;

class NoDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('NoDocument', package: const $pb.PackageName('firestore.client'))
    ..aOS(1, 'name')
    ..a<$0.Timestamp>(2, 'readTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  NoDocument._() : super();
  factory NoDocument() => create();
  factory NoDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NoDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  NoDocument clone() => NoDocument()..mergeFromMessage(this);
  NoDocument copyWith(void Function(NoDocument) updates) => super.copyWith((message) => updates(message as NoDocument));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static NoDocument create() => NoDocument._();
  NoDocument createEmptyInstance() => create();
  static $pb.PbList<NoDocument> createRepeated() => $pb.PbList<NoDocument>();
  static NoDocument getDefault() => _defaultInstance ??= create()..freeze();
  static NoDocument _defaultInstance;

  $core.String get name => $_getS(0, '');
  set name($core.String v) { $_setString(0, v); }
  $core.bool hasName() => $_has(0);
  void clearName() => clearField(1);

  $0.Timestamp get readTime => $_getN(1);
  set readTime($0.Timestamp v) { setField(2, v); }
  $core.bool hasReadTime() => $_has(1);
  void clearReadTime() => clearField(2);
}

class UnknownDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('UnknownDocument', package: const $pb.PackageName('firestore.client'))
    ..aOS(1, 'name')
    ..a<$0.Timestamp>(2, 'version', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  UnknownDocument._() : super();
  factory UnknownDocument() => create();
  factory UnknownDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UnknownDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  UnknownDocument clone() => UnknownDocument()..mergeFromMessage(this);
  UnknownDocument copyWith(void Function(UnknownDocument) updates) => super.copyWith((message) => updates(message as UnknownDocument));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static UnknownDocument create() => UnknownDocument._();
  UnknownDocument createEmptyInstance() => create();
  static $pb.PbList<UnknownDocument> createRepeated() => $pb.PbList<UnknownDocument>();
  static UnknownDocument getDefault() => _defaultInstance ??= create()..freeze();
  static UnknownDocument _defaultInstance;

  $core.String get name => $_getS(0, '');
  set name($core.String v) { $_setString(0, v); }
  $core.bool hasName() => $_has(0);
  void clearName() => clearField(1);

  $0.Timestamp get version => $_getN(1);
  set version($0.Timestamp v) { setField(2, v); }
  $core.bool hasVersion() => $_has(1);
  void clearVersion() => clearField(2);
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
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('MaybeDocument', package: const $pb.PackageName('firestore.client'))
    ..oo(0, [1, 2, 3])
    ..a<NoDocument>(1, 'noDocument', $pb.PbFieldType.OM, NoDocument.getDefault, NoDocument.create)
    ..a<$1.Document>(2, 'document', $pb.PbFieldType.OM, $1.Document.getDefault, $1.Document.create)
    ..a<UnknownDocument>(3, 'unknownDocument', $pb.PbFieldType.OM, UnknownDocument.getDefault, UnknownDocument.create)
    ..aOB(4, 'hasCommittedMutations')
    ..hasRequiredFields = false
  ;

  MaybeDocument._() : super();
  factory MaybeDocument() => create();
  factory MaybeDocument.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MaybeDocument.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  MaybeDocument clone() => MaybeDocument()..mergeFromMessage(this);
  MaybeDocument copyWith(void Function(MaybeDocument) updates) => super.copyWith((message) => updates(message as MaybeDocument));
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MaybeDocument create() => MaybeDocument._();
  MaybeDocument createEmptyInstance() => create();
  static $pb.PbList<MaybeDocument> createRepeated() => $pb.PbList<MaybeDocument>();
  static MaybeDocument getDefault() => _defaultInstance ??= create()..freeze();
  static MaybeDocument _defaultInstance;

  MaybeDocument_DocumentType whichDocumentType() => _MaybeDocument_DocumentTypeByTag[$_whichOneof(0)];
  void clearDocumentType() => clearField($_whichOneof(0));

  NoDocument get noDocument => $_getN(0);
  set noDocument(NoDocument v) { setField(1, v); }
  $core.bool hasNoDocument() => $_has(0);
  void clearNoDocument() => clearField(1);

  $1.Document get document => $_getN(1);
  set document($1.Document v) { setField(2, v); }
  $core.bool hasDocument() => $_has(1);
  void clearDocument() => clearField(2);

  UnknownDocument get unknownDocument => $_getN(2);
  set unknownDocument(UnknownDocument v) { setField(3, v); }
  $core.bool hasUnknownDocument() => $_has(2);
  void clearUnknownDocument() => clearField(3);

  $core.bool get hasCommittedMutations => $_get(3, false);
  set hasCommittedMutations($core.bool v) { $_setBool(3, v); }
  $core.bool hasHasCommittedMutations() => $_has(3);
  void clearHasCommittedMutations() => clearField(4);
}

