//
//  Generated code. Do not modify.
//  source: google/firestore/v1/common.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../protobuf/timestamp.pb.dart' as $3;
import 'common.pbenum.dart';

export 'common.pbenum.dart';

/// A set of field paths on a document.
/// Used to restrict a get or update operation on a document to a subset of its
/// fields.
/// This is different from standard field masks, as this is always scoped to a
/// [Document][google.firestore.v1.Document], and takes in account the dynamic
/// nature of [Value][google.firestore.v1.Value].
class DocumentMask extends $pb.GeneratedMessage {
  factory DocumentMask({
    $core.Iterable<$core.String>? fieldPaths,
  }) {
    final $result = create();
    if (fieldPaths != null) {
      $result.fieldPaths.addAll(fieldPaths);
    }
    return $result;
  }
  DocumentMask._() : super();
  factory DocumentMask.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DocumentMask.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DocumentMask', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'fieldPaths')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DocumentMask clone() => DocumentMask()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DocumentMask copyWith(void Function(DocumentMask) updates) => super.copyWith((message) => updates(message as DocumentMask)) as DocumentMask;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DocumentMask create() => DocumentMask._();
  DocumentMask createEmptyInstance() => create();
  static $pb.PbList<DocumentMask> createRepeated() => $pb.PbList<DocumentMask>();
  @$core.pragma('dart2js:noInline')
  static DocumentMask getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DocumentMask>(create);
  static DocumentMask? _defaultInstance;

  /// The list of field paths in the mask. See
  /// [Document.fields][google.firestore.v1.Document.fields] for a field path
  /// syntax reference.
  @$pb.TagNumber(1)
  $core.List<$core.String> get fieldPaths => $_getList(0);
}

enum Precondition_ConditionType {
  exists, 
  updateTime, 
  notSet
}

/// A precondition on a document, used for conditional operations.
class Precondition extends $pb.GeneratedMessage {
  factory Precondition({
    $core.bool? exists,
    $3.Timestamp? updateTime,
  }) {
    final $result = create();
    if (exists != null) {
      $result.exists = exists;
    }
    if (updateTime != null) {
      $result.updateTime = updateTime;
    }
    return $result;
  }
  Precondition._() : super();
  factory Precondition.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Precondition.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, Precondition_ConditionType> _Precondition_ConditionTypeByTag = {
    1 : Precondition_ConditionType.exists,
    2 : Precondition_ConditionType.updateTime,
    0 : Precondition_ConditionType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Precondition', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOB(1, _omitFieldNames ? '' : 'exists')
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'updateTime', subBuilder: $3.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Precondition clone() => Precondition()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Precondition copyWith(void Function(Precondition) updates) => super.copyWith((message) => updates(message as Precondition)) as Precondition;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Precondition create() => Precondition._();
  Precondition createEmptyInstance() => create();
  static $pb.PbList<Precondition> createRepeated() => $pb.PbList<Precondition>();
  @$core.pragma('dart2js:noInline')
  static Precondition getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Precondition>(create);
  static Precondition? _defaultInstance;

  Precondition_ConditionType whichConditionType() => _Precondition_ConditionTypeByTag[$_whichOneof(0)]!;
  void clearConditionType() => clearField($_whichOneof(0));

  /// When set to `true`, the target document must exist.
  /// When set to `false`, the target document must not exist.
  @$pb.TagNumber(1)
  $core.bool get exists => $_getBF(0);
  @$pb.TagNumber(1)
  set exists($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasExists() => $_has(0);
  @$pb.TagNumber(1)
  void clearExists() => clearField(1);

  /// When set, the target document must exist and have been last updated at
  /// that time. Timestamp must be microsecond aligned.
  @$pb.TagNumber(2)
  $3.Timestamp get updateTime => $_getN(1);
  @$pb.TagNumber(2)
  set updateTime($3.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasUpdateTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearUpdateTime() => clearField(2);
  @$pb.TagNumber(2)
  $3.Timestamp ensureUpdateTime() => $_ensure(1);
}

/// Options for a transaction that can be used to read and write documents.
class TransactionOptions_ReadWrite extends $pb.GeneratedMessage {
  factory TransactionOptions_ReadWrite({
    $core.List<$core.int>? retryTransaction,
    TransactionOptions_ConcurrencyMode? concurrencyMode,
  }) {
    final $result = create();
    if (retryTransaction != null) {
      $result.retryTransaction = retryTransaction;
    }
    if (concurrencyMode != null) {
      $result.concurrencyMode = concurrencyMode;
    }
    return $result;
  }
  TransactionOptions_ReadWrite._() : super();
  factory TransactionOptions_ReadWrite.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TransactionOptions_ReadWrite.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TransactionOptions.ReadWrite', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'retryTransaction', $pb.PbFieldType.OY)
    ..e<TransactionOptions_ConcurrencyMode>(2, _omitFieldNames ? '' : 'concurrencyMode', $pb.PbFieldType.OE, defaultOrMaker: TransactionOptions_ConcurrencyMode.CONCURRENCY_MODE_UNSPECIFIED, valueOf: TransactionOptions_ConcurrencyMode.valueOf, enumValues: TransactionOptions_ConcurrencyMode.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TransactionOptions_ReadWrite clone() => TransactionOptions_ReadWrite()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TransactionOptions_ReadWrite copyWith(void Function(TransactionOptions_ReadWrite) updates) => super.copyWith((message) => updates(message as TransactionOptions_ReadWrite)) as TransactionOptions_ReadWrite;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransactionOptions_ReadWrite create() => TransactionOptions_ReadWrite._();
  TransactionOptions_ReadWrite createEmptyInstance() => create();
  static $pb.PbList<TransactionOptions_ReadWrite> createRepeated() => $pb.PbList<TransactionOptions_ReadWrite>();
  @$core.pragma('dart2js:noInline')
  static TransactionOptions_ReadWrite getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TransactionOptions_ReadWrite>(create);
  static TransactionOptions_ReadWrite? _defaultInstance;

  /// An optional transaction to retry.
  @$pb.TagNumber(1)
  $core.List<$core.int> get retryTransaction => $_getN(0);
  @$pb.TagNumber(1)
  set retryTransaction($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRetryTransaction() => $_has(0);
  @$pb.TagNumber(1)
  void clearRetryTransaction() => clearField(1);

  ///  Optional. The concurrency control mode to use for this transaction.
  ///
  ///  A database is able to use different concurrency modes for different
  ///  transactions simultaneously.
  ///
  ///  3rd party auth requests are only allowed to create optimistic
  ///  read-write transactions and must specify that here even if the
  ///  database-level setting is already configured to optimistic.
  @$pb.TagNumber(2)
  TransactionOptions_ConcurrencyMode get concurrencyMode => $_getN(1);
  @$pb.TagNumber(2)
  set concurrencyMode(TransactionOptions_ConcurrencyMode v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasConcurrencyMode() => $_has(1);
  @$pb.TagNumber(2)
  void clearConcurrencyMode() => clearField(2);
}

enum TransactionOptions_ReadOnly_ConsistencySelector {
  readTime, 
  notSet
}

/// Options for a transaction that can only be used to read documents.
class TransactionOptions_ReadOnly extends $pb.GeneratedMessage {
  factory TransactionOptions_ReadOnly({
    $3.Timestamp? readTime,
  }) {
    final $result = create();
    if (readTime != null) {
      $result.readTime = readTime;
    }
    return $result;
  }
  TransactionOptions_ReadOnly._() : super();
  factory TransactionOptions_ReadOnly.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TransactionOptions_ReadOnly.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, TransactionOptions_ReadOnly_ConsistencySelector> _TransactionOptions_ReadOnly_ConsistencySelectorByTag = {
    2 : TransactionOptions_ReadOnly_ConsistencySelector.readTime,
    0 : TransactionOptions_ReadOnly_ConsistencySelector.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TransactionOptions.ReadOnly', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..oo(0, [2])
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'readTime', subBuilder: $3.Timestamp.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TransactionOptions_ReadOnly clone() => TransactionOptions_ReadOnly()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TransactionOptions_ReadOnly copyWith(void Function(TransactionOptions_ReadOnly) updates) => super.copyWith((message) => updates(message as TransactionOptions_ReadOnly)) as TransactionOptions_ReadOnly;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransactionOptions_ReadOnly create() => TransactionOptions_ReadOnly._();
  TransactionOptions_ReadOnly createEmptyInstance() => create();
  static $pb.PbList<TransactionOptions_ReadOnly> createRepeated() => $pb.PbList<TransactionOptions_ReadOnly>();
  @$core.pragma('dart2js:noInline')
  static TransactionOptions_ReadOnly getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TransactionOptions_ReadOnly>(create);
  static TransactionOptions_ReadOnly? _defaultInstance;

  TransactionOptions_ReadOnly_ConsistencySelector whichConsistencySelector() => _TransactionOptions_ReadOnly_ConsistencySelectorByTag[$_whichOneof(0)]!;
  void clearConsistencySelector() => clearField($_whichOneof(0));

  ///  Reads documents at the given time.
  ///
  ///  This must be a microsecond precision timestamp within the past one
  ///  hour, or if Point-in-Time Recovery is enabled, can additionally be a
  ///  whole minute timestamp within the past 7 days.
  @$pb.TagNumber(2)
  $3.Timestamp get readTime => $_getN(0);
  @$pb.TagNumber(2)
  set readTime($3.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasReadTime() => $_has(0);
  @$pb.TagNumber(2)
  void clearReadTime() => clearField(2);
  @$pb.TagNumber(2)
  $3.Timestamp ensureReadTime() => $_ensure(0);
}

enum TransactionOptions_Mode {
  readOnly, 
  readWrite, 
  notSet
}

/// Options for creating a new transaction.
class TransactionOptions extends $pb.GeneratedMessage {
  factory TransactionOptions({
    TransactionOptions_ReadOnly? readOnly,
    TransactionOptions_ReadWrite? readWrite,
  }) {
    final $result = create();
    if (readOnly != null) {
      $result.readOnly = readOnly;
    }
    if (readWrite != null) {
      $result.readWrite = readWrite;
    }
    return $result;
  }
  TransactionOptions._() : super();
  factory TransactionOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TransactionOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, TransactionOptions_Mode> _TransactionOptions_ModeByTag = {
    2 : TransactionOptions_Mode.readOnly,
    3 : TransactionOptions_Mode.readWrite,
    0 : TransactionOptions_Mode.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TransactionOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..oo(0, [2, 3])
    ..aOM<TransactionOptions_ReadOnly>(2, _omitFieldNames ? '' : 'readOnly', subBuilder: TransactionOptions_ReadOnly.create)
    ..aOM<TransactionOptions_ReadWrite>(3, _omitFieldNames ? '' : 'readWrite', subBuilder: TransactionOptions_ReadWrite.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TransactionOptions clone() => TransactionOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TransactionOptions copyWith(void Function(TransactionOptions) updates) => super.copyWith((message) => updates(message as TransactionOptions)) as TransactionOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransactionOptions create() => TransactionOptions._();
  TransactionOptions createEmptyInstance() => create();
  static $pb.PbList<TransactionOptions> createRepeated() => $pb.PbList<TransactionOptions>();
  @$core.pragma('dart2js:noInline')
  static TransactionOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TransactionOptions>(create);
  static TransactionOptions? _defaultInstance;

  TransactionOptions_Mode whichMode() => _TransactionOptions_ModeByTag[$_whichOneof(0)]!;
  void clearMode() => clearField($_whichOneof(0));

  /// The transaction can only be used for read operations.
  @$pb.TagNumber(2)
  TransactionOptions_ReadOnly get readOnly => $_getN(0);
  @$pb.TagNumber(2)
  set readOnly(TransactionOptions_ReadOnly v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasReadOnly() => $_has(0);
  @$pb.TagNumber(2)
  void clearReadOnly() => clearField(2);
  @$pb.TagNumber(2)
  TransactionOptions_ReadOnly ensureReadOnly() => $_ensure(0);

  /// The transaction can be used for both read and write operations.
  @$pb.TagNumber(3)
  TransactionOptions_ReadWrite get readWrite => $_getN(1);
  @$pb.TagNumber(3)
  set readWrite(TransactionOptions_ReadWrite v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasReadWrite() => $_has(1);
  @$pb.TagNumber(3)
  void clearReadWrite() => clearField(3);
  @$pb.TagNumber(3)
  TransactionOptions_ReadWrite ensureReadWrite() => $_ensure(1);
}

/// Options for a server request.
class RequestOptions extends $pb.GeneratedMessage {
  factory RequestOptions({
    $core.Iterable<$core.String>? requestTags,
  }) {
    final $result = create();
    if (requestTags != null) {
      $result.requestTags.addAll(requestTags);
    }
    return $result;
  }
  RequestOptions._() : super();
  factory RequestOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RequestOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RequestOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'google.firestore.v1'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'requestTags')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RequestOptions clone() => RequestOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RequestOptions copyWith(void Function(RequestOptions) updates) => super.copyWith((message) => updates(message as RequestOptions)) as RequestOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RequestOptions create() => RequestOptions._();
  RequestOptions createEmptyInstance() => create();
  static $pb.PbList<RequestOptions> createRepeated() => $pb.PbList<RequestOptions>();
  @$core.pragma('dart2js:noInline')
  static RequestOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RequestOptions>(create);
  static RequestOptions? _defaultInstance;

  /// The request tags for the request.
  @$pb.TagNumber(1)
  $core.List<$core.String> get requestTags => $_getList(0);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
