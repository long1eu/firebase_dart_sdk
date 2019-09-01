///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/write.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../protobuf/timestamp.pb.dart' as $2;
import 'common.pb.dart' as $1;
import 'document.pb.dart' as $0;
import 'write.pbenum.dart';

export 'write.pbenum.dart';

class Write extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Write', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$0.Document>(1, 'update', $pb.PbFieldType.OM, $0.Document.getDefault, $0.Document.create)
    ..aOS(2, 'delete')
    ..a<$1.DocumentMask>(3, 'updateMask', $pb.PbFieldType.OM, $1.DocumentMask.getDefault, $1.DocumentMask.create)
    ..a<$1.Precondition>(4, 'currentDocument', $pb.PbFieldType.OM, $1.Precondition.getDefault, $1.Precondition.create)
    ..a<DocumentTransform>(6, 'transform', $pb.PbFieldType.OM, DocumentTransform.getDefault, DocumentTransform.create)
    ..hasRequiredFields = false
  ;

  Write() : super();
  Write.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Write.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Write clone() => new Write()..mergeFromMessage(this);
  Write copyWith(void Function(Write) updates) => super.copyWith((message) => updates(message as Write));
  $pb.BuilderInfo get info_ => _i;
  static Write create() => new Write();
  static $pb.PbList<Write> createRepeated() => new $pb.PbList<Write>();
  static Write getDefault() => _defaultInstance ??= create()..freeze();
  static Write _defaultInstance;
  static void $checkItem(Write v) {
    if (v is! Write) $pb.checkItemFailed(v, _i.messageName);
  }

  $0.Document get update => $_getN(0);
  set update($0.Document v) { setField(1, v); }
  bool hasUpdate() => $_has(0);
  void clearUpdate() => clearField(1);

  String get delete => $_getS(1, '');
  set delete(String v) { $_setString(1, v); }
  bool hasDelete() => $_has(1);
  void clearDelete() => clearField(2);

  $1.DocumentMask get updateMask => $_getN(2);
  set updateMask($1.DocumentMask v) { setField(3, v); }
  bool hasUpdateMask() => $_has(2);
  void clearUpdateMask() => clearField(3);

  $1.Precondition get currentDocument => $_getN(3);
  set currentDocument($1.Precondition v) { setField(4, v); }
  bool hasCurrentDocument() => $_has(3);
  void clearCurrentDocument() => clearField(4);

  DocumentTransform get transform => $_getN(4);
  set transform(DocumentTransform v) { setField(6, v); }
  bool hasTransform() => $_has(4);
  void clearTransform() => clearField(6);
}

class DocumentTransform_FieldTransform extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DocumentTransform.FieldTransform', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'fieldPath')
    ..e<DocumentTransform_FieldTransform_ServerValue>(2, 'setToServerValue', $pb.PbFieldType.OE, DocumentTransform_FieldTransform_ServerValue.SERVER_VALUE_UNSPECIFIED, DocumentTransform_FieldTransform_ServerValue.valueOf, DocumentTransform_FieldTransform_ServerValue.values)
    ..a<$0.ArrayValue>(6, 'appendMissingElements', $pb.PbFieldType.OM, $0.ArrayValue.getDefault, $0.ArrayValue.create)
    ..a<$0.ArrayValue>(7, 'removeAllFromArray', $pb.PbFieldType.OM, $0.ArrayValue.getDefault, $0.ArrayValue.create)
    ..hasRequiredFields = false
  ;

  DocumentTransform_FieldTransform() : super();
  DocumentTransform_FieldTransform.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DocumentTransform_FieldTransform.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DocumentTransform_FieldTransform clone() => new DocumentTransform_FieldTransform()..mergeFromMessage(this);
  DocumentTransform_FieldTransform copyWith(void Function(DocumentTransform_FieldTransform) updates) => super.copyWith((message) => updates(message as DocumentTransform_FieldTransform));
  $pb.BuilderInfo get info_ => _i;
  static DocumentTransform_FieldTransform create() => new DocumentTransform_FieldTransform();
  static $pb.PbList<DocumentTransform_FieldTransform> createRepeated() => new $pb.PbList<DocumentTransform_FieldTransform>();
  static DocumentTransform_FieldTransform getDefault() => _defaultInstance ??= create()..freeze();
  static DocumentTransform_FieldTransform _defaultInstance;
  static void $checkItem(DocumentTransform_FieldTransform v) {
    if (v is! DocumentTransform_FieldTransform) $pb.checkItemFailed(v, _i.messageName);
  }

  String get fieldPath => $_getS(0, '');
  set fieldPath(String v) { $_setString(0, v); }
  bool hasFieldPath() => $_has(0);
  void clearFieldPath() => clearField(1);

  DocumentTransform_FieldTransform_ServerValue get setToServerValue => $_getN(1);
  set setToServerValue(DocumentTransform_FieldTransform_ServerValue v) { setField(2, v); }
  bool hasSetToServerValue() => $_has(1);
  void clearSetToServerValue() => clearField(2);

  $0.ArrayValue get appendMissingElements => $_getN(2);
  set appendMissingElements($0.ArrayValue v) { setField(6, v); }
  bool hasAppendMissingElements() => $_has(2);
  void clearAppendMissingElements() => clearField(6);

  $0.ArrayValue get removeAllFromArray => $_getN(3);
  set removeAllFromArray($0.ArrayValue v) { setField(7, v); }
  bool hasRemoveAllFromArray() => $_has(3);
  void clearRemoveAllFromArray() => clearField(7);
}

class DocumentTransform extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DocumentTransform', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'document')
    ..pp<DocumentTransform_FieldTransform>(2, 'fieldTransforms', $pb.PbFieldType.PM, DocumentTransform_FieldTransform.$checkItem, DocumentTransform_FieldTransform.create)
    ..hasRequiredFields = false
  ;

  DocumentTransform() : super();
  DocumentTransform.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DocumentTransform.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DocumentTransform clone() => new DocumentTransform()..mergeFromMessage(this);
  DocumentTransform copyWith(void Function(DocumentTransform) updates) => super.copyWith((message) => updates(message as DocumentTransform));
  $pb.BuilderInfo get info_ => _i;
  static DocumentTransform create() => new DocumentTransform();
  static $pb.PbList<DocumentTransform> createRepeated() => new $pb.PbList<DocumentTransform>();
  static DocumentTransform getDefault() => _defaultInstance ??= create()..freeze();
  static DocumentTransform _defaultInstance;
  static void $checkItem(DocumentTransform v) {
    if (v is! DocumentTransform) $pb.checkItemFailed(v, _i.messageName);
  }

  String get document => $_getS(0, '');
  set document(String v) { $_setString(0, v); }
  bool hasDocument() => $_has(0);
  void clearDocument() => clearField(1);

  List<DocumentTransform_FieldTransform> get fieldTransforms => $_getList(1);
}

class WriteResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('WriteResult', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$2.Timestamp>(1, 'updateTime', $pb.PbFieldType.OM, $2.Timestamp.getDefault, $2.Timestamp.create)
    ..pp<$0.Value>(2, 'transformResults', $pb.PbFieldType.PM, $0.Value.$checkItem, $0.Value.create)
    ..hasRequiredFields = false
  ;

  WriteResult() : super();
  WriteResult.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  WriteResult.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  WriteResult clone() => new WriteResult()..mergeFromMessage(this);
  WriteResult copyWith(void Function(WriteResult) updates) => super.copyWith((message) => updates(message as WriteResult));
  $pb.BuilderInfo get info_ => _i;
  static WriteResult create() => new WriteResult();
  static $pb.PbList<WriteResult> createRepeated() => new $pb.PbList<WriteResult>();
  static WriteResult getDefault() => _defaultInstance ??= create()..freeze();
  static WriteResult _defaultInstance;
  static void $checkItem(WriteResult v) {
    if (v is! WriteResult) $pb.checkItemFailed(v, _i.messageName);
  }

  $2.Timestamp get updateTime => $_getN(0);
  set updateTime($2.Timestamp v) { setField(1, v); }
  bool hasUpdateTime() => $_has(0);
  void clearUpdateTime() => clearField(1);

  List<$0.Value> get transformResults => $_getList(1);
}

class DocumentChange extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DocumentChange', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$0.Document>(1, 'document', $pb.PbFieldType.OM, $0.Document.getDefault, $0.Document.create)
    ..p<int>(5, 'targetIds', $pb.PbFieldType.P3)
    ..p<int>(6, 'removedTargetIds', $pb.PbFieldType.P3)
    ..hasRequiredFields = false
  ;

  DocumentChange() : super();
  DocumentChange.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DocumentChange.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DocumentChange clone() => new DocumentChange()..mergeFromMessage(this);
  DocumentChange copyWith(void Function(DocumentChange) updates) => super.copyWith((message) => updates(message as DocumentChange));
  $pb.BuilderInfo get info_ => _i;
  static DocumentChange create() => new DocumentChange();
  static $pb.PbList<DocumentChange> createRepeated() => new $pb.PbList<DocumentChange>();
  static DocumentChange getDefault() => _defaultInstance ??= create()..freeze();
  static DocumentChange _defaultInstance;
  static void $checkItem(DocumentChange v) {
    if (v is! DocumentChange) $pb.checkItemFailed(v, _i.messageName);
  }

  $0.Document get document => $_getN(0);
  set document($0.Document v) { setField(1, v); }
  bool hasDocument() => $_has(0);
  void clearDocument() => clearField(1);

  List<int> get targetIds => $_getList(1);

  List<int> get removedTargetIds => $_getList(2);
}

class DocumentDelete extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DocumentDelete', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'document')
    ..a<$2.Timestamp>(4, 'readTime', $pb.PbFieldType.OM, $2.Timestamp.getDefault, $2.Timestamp.create)
    ..p<int>(6, 'removedTargetIds', $pb.PbFieldType.P3)
    ..hasRequiredFields = false
  ;

  DocumentDelete() : super();
  DocumentDelete.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DocumentDelete.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DocumentDelete clone() => new DocumentDelete()..mergeFromMessage(this);
  DocumentDelete copyWith(void Function(DocumentDelete) updates) => super.copyWith((message) => updates(message as DocumentDelete));
  $pb.BuilderInfo get info_ => _i;
  static DocumentDelete create() => new DocumentDelete();
  static $pb.PbList<DocumentDelete> createRepeated() => new $pb.PbList<DocumentDelete>();
  static DocumentDelete getDefault() => _defaultInstance ??= create()..freeze();
  static DocumentDelete _defaultInstance;
  static void $checkItem(DocumentDelete v) {
    if (v is! DocumentDelete) $pb.checkItemFailed(v, _i.messageName);
  }

  String get document => $_getS(0, '');
  set document(String v) { $_setString(0, v); }
  bool hasDocument() => $_has(0);
  void clearDocument() => clearField(1);

  $2.Timestamp get readTime => $_getN(1);
  set readTime($2.Timestamp v) { setField(4, v); }
  bool hasReadTime() => $_has(1);
  void clearReadTime() => clearField(4);

  List<int> get removedTargetIds => $_getList(2);
}

class DocumentRemove extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DocumentRemove', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'document')
    ..p<int>(2, 'removedTargetIds', $pb.PbFieldType.P3)
    ..a<$2.Timestamp>(4, 'readTime', $pb.PbFieldType.OM, $2.Timestamp.getDefault, $2.Timestamp.create)
    ..hasRequiredFields = false
  ;

  DocumentRemove() : super();
  DocumentRemove.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DocumentRemove.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DocumentRemove clone() => new DocumentRemove()..mergeFromMessage(this);
  DocumentRemove copyWith(void Function(DocumentRemove) updates) => super.copyWith((message) => updates(message as DocumentRemove));
  $pb.BuilderInfo get info_ => _i;
  static DocumentRemove create() => new DocumentRemove();
  static $pb.PbList<DocumentRemove> createRepeated() => new $pb.PbList<DocumentRemove>();
  static DocumentRemove getDefault() => _defaultInstance ??= create()..freeze();
  static DocumentRemove _defaultInstance;
  static void $checkItem(DocumentRemove v) {
    if (v is! DocumentRemove) $pb.checkItemFailed(v, _i.messageName);
  }

  String get document => $_getS(0, '');
  set document(String v) { $_setString(0, v); }
  bool hasDocument() => $_has(0);
  void clearDocument() => clearField(1);

  List<int> get removedTargetIds => $_getList(1);

  $2.Timestamp get readTime => $_getN(2);
  set readTime($2.Timestamp v) { setField(4, v); }
  bool hasReadTime() => $_has(2);
  void clearReadTime() => clearField(4);
}

class ExistenceFilter extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ExistenceFilter', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<int>(1, 'targetId', $pb.PbFieldType.O3)
    ..a<int>(2, 'count', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  ExistenceFilter() : super();
  ExistenceFilter.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ExistenceFilter.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ExistenceFilter clone() => new ExistenceFilter()..mergeFromMessage(this);
  ExistenceFilter copyWith(void Function(ExistenceFilter) updates) => super.copyWith((message) => updates(message as ExistenceFilter));
  $pb.BuilderInfo get info_ => _i;
  static ExistenceFilter create() => new ExistenceFilter();
  static $pb.PbList<ExistenceFilter> createRepeated() => new $pb.PbList<ExistenceFilter>();
  static ExistenceFilter getDefault() => _defaultInstance ??= create()..freeze();
  static ExistenceFilter _defaultInstance;
  static void $checkItem(ExistenceFilter v) {
    if (v is! ExistenceFilter) $pb.checkItemFailed(v, _i.messageName);
  }

  int get targetId => $_get(0, 0);
  set targetId(int v) { $_setSignedInt32(0, v); }
  bool hasTargetId() => $_has(0);
  void clearTargetId() => clearField(1);

  int get count => $_get(1, 0);
  set count(int v) { $_setSignedInt32(1, v); }
  bool hasCount() => $_has(1);
  void clearCount() => clearField(2);
}

