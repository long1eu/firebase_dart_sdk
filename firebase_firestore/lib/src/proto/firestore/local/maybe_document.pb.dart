///
//  Generated code. Do not modify.
//  source: firestore/local/maybe_document.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../google/protobuf/timestamp.pb.dart' as $0;
import '../../google/firestore/v1beta1/document.pb.dart' as $1;

class NoDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('NoDocument', package: const $pb.PackageName('firestore.client'))
    ..aOS(1, 'name')
    ..a<$0.Timestamp>(2, 'readTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  NoDocument() : super();
  NoDocument.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  NoDocument.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  NoDocument clone() => new NoDocument()..mergeFromMessage(this);
  NoDocument copyWith(void Function(NoDocument) updates) => super.copyWith((message) => updates(message as NoDocument));
  $pb.BuilderInfo get info_ => _i;
  static NoDocument create() => new NoDocument();
  static $pb.PbList<NoDocument> createRepeated() => new $pb.PbList<NoDocument>();
  static NoDocument getDefault() => _defaultInstance ??= create()..freeze();
  static NoDocument _defaultInstance;
  static void $checkItem(NoDocument v) {
    if (v is! NoDocument) $pb.checkItemFailed(v, _i.messageName);
  }

  String get name => $_getS(0, '');
  set name(String v) { $_setString(0, v); }
  bool hasName() => $_has(0);
  void clearName() => clearField(1);

  $0.Timestamp get readTime => $_getN(1);
  set readTime($0.Timestamp v) { setField(2, v); }
  bool hasReadTime() => $_has(1);
  void clearReadTime() => clearField(2);
}

class UnknownDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('UnknownDocument', package: const $pb.PackageName('firestore.client'))
    ..aOS(1, 'name')
    ..a<$0.Timestamp>(2, 'version', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  UnknownDocument() : super();
  UnknownDocument.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  UnknownDocument.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  UnknownDocument clone() => new UnknownDocument()..mergeFromMessage(this);
  UnknownDocument copyWith(void Function(UnknownDocument) updates) => super.copyWith((message) => updates(message as UnknownDocument));
  $pb.BuilderInfo get info_ => _i;
  static UnknownDocument create() => new UnknownDocument();
  static $pb.PbList<UnknownDocument> createRepeated() => new $pb.PbList<UnknownDocument>();
  static UnknownDocument getDefault() => _defaultInstance ??= create()..freeze();
  static UnknownDocument _defaultInstance;
  static void $checkItem(UnknownDocument v) {
    if (v is! UnknownDocument) $pb.checkItemFailed(v, _i.messageName);
  }

  String get name => $_getS(0, '');
  set name(String v) { $_setString(0, v); }
  bool hasName() => $_has(0);
  void clearName() => clearField(1);

  $0.Timestamp get version => $_getN(1);
  set version($0.Timestamp v) { setField(2, v); }
  bool hasVersion() => $_has(1);
  void clearVersion() => clearField(2);
}

class MaybeDocument extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('MaybeDocument', package: const $pb.PackageName('firestore.client'))
    ..a<NoDocument>(1, 'noDocument', $pb.PbFieldType.OM, NoDocument.getDefault, NoDocument.create)
    ..a<$1.Document>(2, 'document', $pb.PbFieldType.OM, $1.Document.getDefault, $1.Document.create)
    ..a<UnknownDocument>(3, 'unknownDocument', $pb.PbFieldType.OM, UnknownDocument.getDefault, UnknownDocument.create)
    ..aOB(4, 'hasCommittedMutations')
    ..hasRequiredFields = false
  ;

  MaybeDocument() : super();
  MaybeDocument.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  MaybeDocument.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  MaybeDocument clone() => new MaybeDocument()..mergeFromMessage(this);
  MaybeDocument copyWith(void Function(MaybeDocument) updates) => super.copyWith((message) => updates(message as MaybeDocument));
  $pb.BuilderInfo get info_ => _i;
  static MaybeDocument create() => new MaybeDocument();
  static $pb.PbList<MaybeDocument> createRepeated() => new $pb.PbList<MaybeDocument>();
  static MaybeDocument getDefault() => _defaultInstance ??= create()..freeze();
  static MaybeDocument _defaultInstance;
  static void $checkItem(MaybeDocument v) {
    if (v is! MaybeDocument) $pb.checkItemFailed(v, _i.messageName);
  }

  NoDocument get noDocument => $_getN(0);
  set noDocument(NoDocument v) { setField(1, v); }
  bool hasNoDocument() => $_has(0);
  void clearNoDocument() => clearField(1);

  $1.Document get document => $_getN(1);
  set document($1.Document v) { setField(2, v); }
  bool hasDocument() => $_has(1);
  void clearDocument() => clearField(2);

  UnknownDocument get unknownDocument => $_getN(2);
  set unknownDocument(UnknownDocument v) { setField(3, v); }
  bool hasUnknownDocument() => $_has(2);
  void clearUnknownDocument() => clearField(3);

  bool get hasCommittedMutations => $_get(3, false);
  set hasCommittedMutations(bool v) { $_setBool(3, v); }
  bool hasHasCommittedMutations() => $_has(3);
  void clearHasCommittedMutations() => clearField(4);
}

