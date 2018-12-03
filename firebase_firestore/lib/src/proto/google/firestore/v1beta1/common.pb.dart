///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/common.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../protobuf/timestamp.pb.dart' as $0;

class DocumentMask extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DocumentMask', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pPS(1, 'fieldPaths')
    ..hasRequiredFields = false
  ;

  DocumentMask() : super();
  DocumentMask.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DocumentMask.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DocumentMask clone() => new DocumentMask()..mergeFromMessage(this);
  DocumentMask copyWith(void Function(DocumentMask) updates) => super.copyWith((message) => updates(message as DocumentMask));
  $pb.BuilderInfo get info_ => _i;
  static DocumentMask create() => new DocumentMask();
  static $pb.PbList<DocumentMask> createRepeated() => new $pb.PbList<DocumentMask>();
  static DocumentMask getDefault() => _defaultInstance ??= create()..freeze();
  static DocumentMask _defaultInstance;
  static void $checkItem(DocumentMask v) {
    if (v is! DocumentMask) $pb.checkItemFailed(v, _i.messageName);
  }

  List<String> get fieldPaths => $_getList(0);
}

class Precondition extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Precondition', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOB(1, 'exists')
    ..a<$0.Timestamp>(2, 'updateTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  Precondition() : super();
  Precondition.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Precondition.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Precondition clone() => new Precondition()..mergeFromMessage(this);
  Precondition copyWith(void Function(Precondition) updates) => super.copyWith((message) => updates(message as Precondition));
  $pb.BuilderInfo get info_ => _i;
  static Precondition create() => new Precondition();
  static $pb.PbList<Precondition> createRepeated() => new $pb.PbList<Precondition>();
  static Precondition getDefault() => _defaultInstance ??= create()..freeze();
  static Precondition _defaultInstance;
  static void $checkItem(Precondition v) {
    if (v is! Precondition) $pb.checkItemFailed(v, _i.messageName);
  }

  bool get exists => $_get(0, false);
  set exists(bool v) { $_setBool(0, v); }
  bool hasExists() => $_has(0);
  void clearExists() => clearField(1);

  $0.Timestamp get updateTime => $_getN(1);
  set updateTime($0.Timestamp v) { setField(2, v); }
  bool hasUpdateTime() => $_has(1);
  void clearUpdateTime() => clearField(2);
}

class TransactionOptions_ReadWrite extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('TransactionOptions.ReadWrite', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<List<int>>(1, 'retryTransaction', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  TransactionOptions_ReadWrite() : super();
  TransactionOptions_ReadWrite.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  TransactionOptions_ReadWrite.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  TransactionOptions_ReadWrite clone() => new TransactionOptions_ReadWrite()..mergeFromMessage(this);
  TransactionOptions_ReadWrite copyWith(void Function(TransactionOptions_ReadWrite) updates) => super.copyWith((message) => updates(message as TransactionOptions_ReadWrite));
  $pb.BuilderInfo get info_ => _i;
  static TransactionOptions_ReadWrite create() => new TransactionOptions_ReadWrite();
  static $pb.PbList<TransactionOptions_ReadWrite> createRepeated() => new $pb.PbList<TransactionOptions_ReadWrite>();
  static TransactionOptions_ReadWrite getDefault() => _defaultInstance ??= create()..freeze();
  static TransactionOptions_ReadWrite _defaultInstance;
  static void $checkItem(TransactionOptions_ReadWrite v) {
    if (v is! TransactionOptions_ReadWrite) $pb.checkItemFailed(v, _i.messageName);
  }

  List<int> get retryTransaction => $_getN(0);
  set retryTransaction(List<int> v) { $_setBytes(0, v); }
  bool hasRetryTransaction() => $_has(0);
  void clearRetryTransaction() => clearField(1);
}

class TransactionOptions_ReadOnly extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('TransactionOptions.ReadOnly', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$0.Timestamp>(2, 'readTime', $pb.PbFieldType.OM, $0.Timestamp.getDefault, $0.Timestamp.create)
    ..hasRequiredFields = false
  ;

  TransactionOptions_ReadOnly() : super();
  TransactionOptions_ReadOnly.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  TransactionOptions_ReadOnly.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  TransactionOptions_ReadOnly clone() => new TransactionOptions_ReadOnly()..mergeFromMessage(this);
  TransactionOptions_ReadOnly copyWith(void Function(TransactionOptions_ReadOnly) updates) => super.copyWith((message) => updates(message as TransactionOptions_ReadOnly));
  $pb.BuilderInfo get info_ => _i;
  static TransactionOptions_ReadOnly create() => new TransactionOptions_ReadOnly();
  static $pb.PbList<TransactionOptions_ReadOnly> createRepeated() => new $pb.PbList<TransactionOptions_ReadOnly>();
  static TransactionOptions_ReadOnly getDefault() => _defaultInstance ??= create()..freeze();
  static TransactionOptions_ReadOnly _defaultInstance;
  static void $checkItem(TransactionOptions_ReadOnly v) {
    if (v is! TransactionOptions_ReadOnly) $pb.checkItemFailed(v, _i.messageName);
  }

  $0.Timestamp get readTime => $_getN(0);
  set readTime($0.Timestamp v) { setField(2, v); }
  bool hasReadTime() => $_has(0);
  void clearReadTime() => clearField(2);
}

class TransactionOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('TransactionOptions', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<TransactionOptions_ReadOnly>(2, 'readOnly', $pb.PbFieldType.OM, TransactionOptions_ReadOnly.getDefault, TransactionOptions_ReadOnly.create)
    ..a<TransactionOptions_ReadWrite>(3, 'readWrite', $pb.PbFieldType.OM, TransactionOptions_ReadWrite.getDefault, TransactionOptions_ReadWrite.create)
    ..hasRequiredFields = false
  ;

  TransactionOptions() : super();
  TransactionOptions.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  TransactionOptions.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  TransactionOptions clone() => new TransactionOptions()..mergeFromMessage(this);
  TransactionOptions copyWith(void Function(TransactionOptions) updates) => super.copyWith((message) => updates(message as TransactionOptions));
  $pb.BuilderInfo get info_ => _i;
  static TransactionOptions create() => new TransactionOptions();
  static $pb.PbList<TransactionOptions> createRepeated() => new $pb.PbList<TransactionOptions>();
  static TransactionOptions getDefault() => _defaultInstance ??= create()..freeze();
  static TransactionOptions _defaultInstance;
  static void $checkItem(TransactionOptions v) {
    if (v is! TransactionOptions) $pb.checkItemFailed(v, _i.messageName);
  }

  TransactionOptions_ReadOnly get readOnly => $_getN(0);
  set readOnly(TransactionOptions_ReadOnly v) { setField(2, v); }
  bool hasReadOnly() => $_has(0);
  void clearReadOnly() => clearField(2);

  TransactionOptions_ReadWrite get readWrite => $_getN(1);
  set readWrite(TransactionOptions_ReadWrite v) { setField(3, v); }
  bool hasReadWrite() => $_has(1);
  void clearReadWrite() => clearField(3);
}

