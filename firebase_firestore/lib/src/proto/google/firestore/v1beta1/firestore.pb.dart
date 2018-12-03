///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/firestore.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

import 'dart:async';
// ignore: UNUSED_SHOWN_NAME
import 'dart:core' show int, bool, double, String, List, override;

import 'package:protobuf/protobuf.dart' as $pb;

import 'common.pb.dart' as $0;
import '../../protobuf/timestamp.pb.dart' as $1;
import 'document.pb.dart' as $2;
import 'write.pb.dart' as $3;
import 'query.pb.dart' as $4;
import '../../rpc/status.pb.dart' as $5;
import '../../protobuf/empty.pb.dart' as $6;

import 'firestore.pbenum.dart';

export 'firestore.pbenum.dart';

class GetDocumentRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('GetDocumentRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'name')
    ..a<$0.DocumentMask>(2, 'mask', $pb.PbFieldType.OM, $0.DocumentMask.getDefault, $0.DocumentMask.create)
    ..a<List<int>>(3, 'transaction', $pb.PbFieldType.OY)
    ..a<$1.Timestamp>(5, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  GetDocumentRequest() : super();
  GetDocumentRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  GetDocumentRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  GetDocumentRequest clone() => new GetDocumentRequest()..mergeFromMessage(this);
  GetDocumentRequest copyWith(void Function(GetDocumentRequest) updates) => super.copyWith((message) => updates(message as GetDocumentRequest));
  $pb.BuilderInfo get info_ => _i;
  static GetDocumentRequest create() => new GetDocumentRequest();
  static $pb.PbList<GetDocumentRequest> createRepeated() => new $pb.PbList<GetDocumentRequest>();
  static GetDocumentRequest getDefault() => _defaultInstance ??= create()..freeze();
  static GetDocumentRequest _defaultInstance;
  static void $checkItem(GetDocumentRequest v) {
    if (v is! GetDocumentRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get name => $_getS(0, '');
  set name(String v) { $_setString(0, v); }
  bool hasName() => $_has(0);
  void clearName() => clearField(1);

  $0.DocumentMask get mask => $_getN(1);
  set mask($0.DocumentMask v) { setField(2, v); }
  bool hasMask() => $_has(1);
  void clearMask() => clearField(2);

  List<int> get transaction => $_getN(2);
  set transaction(List<int> v) { $_setBytes(2, v); }
  bool hasTransaction() => $_has(2);
  void clearTransaction() => clearField(3);

  $1.Timestamp get readTime => $_getN(3);
  set readTime($1.Timestamp v) { setField(5, v); }
  bool hasReadTime() => $_has(3);
  void clearReadTime() => clearField(5);
}

class ListDocumentsRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListDocumentsRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'parent')
    ..aOS(2, 'collectionId')
    ..a<int>(3, 'pageSize', $pb.PbFieldType.O3)
    ..aOS(4, 'pageToken')
    ..aOS(6, 'orderBy')
    ..a<$0.DocumentMask>(7, 'mask', $pb.PbFieldType.OM, $0.DocumentMask.getDefault, $0.DocumentMask.create)
    ..a<List<int>>(8, 'transaction', $pb.PbFieldType.OY)
    ..a<$1.Timestamp>(10, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..aOB(12, 'showMissing')
    ..hasRequiredFields = false
  ;

  ListDocumentsRequest() : super();
  ListDocumentsRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListDocumentsRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListDocumentsRequest clone() => new ListDocumentsRequest()..mergeFromMessage(this);
  ListDocumentsRequest copyWith(void Function(ListDocumentsRequest) updates) => super.copyWith((message) => updates(message as ListDocumentsRequest));
  $pb.BuilderInfo get info_ => _i;
  static ListDocumentsRequest create() => new ListDocumentsRequest();
  static $pb.PbList<ListDocumentsRequest> createRepeated() => new $pb.PbList<ListDocumentsRequest>();
  static ListDocumentsRequest getDefault() => _defaultInstance ??= create()..freeze();
  static ListDocumentsRequest _defaultInstance;
  static void $checkItem(ListDocumentsRequest v) {
    if (v is! ListDocumentsRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get parent => $_getS(0, '');
  set parent(String v) { $_setString(0, v); }
  bool hasParent() => $_has(0);
  void clearParent() => clearField(1);

  String get collectionId => $_getS(1, '');
  set collectionId(String v) { $_setString(1, v); }
  bool hasCollectionId() => $_has(1);
  void clearCollectionId() => clearField(2);

  int get pageSize => $_get(2, 0);
  set pageSize(int v) { $_setSignedInt32(2, v); }
  bool hasPageSize() => $_has(2);
  void clearPageSize() => clearField(3);

  String get pageToken => $_getS(3, '');
  set pageToken(String v) { $_setString(3, v); }
  bool hasPageToken() => $_has(3);
  void clearPageToken() => clearField(4);

  String get orderBy => $_getS(4, '');
  set orderBy(String v) { $_setString(4, v); }
  bool hasOrderBy() => $_has(4);
  void clearOrderBy() => clearField(6);

  $0.DocumentMask get mask => $_getN(5);
  set mask($0.DocumentMask v) { setField(7, v); }
  bool hasMask() => $_has(5);
  void clearMask() => clearField(7);

  List<int> get transaction => $_getN(6);
  set transaction(List<int> v) { $_setBytes(6, v); }
  bool hasTransaction() => $_has(6);
  void clearTransaction() => clearField(8);

  $1.Timestamp get readTime => $_getN(7);
  set readTime($1.Timestamp v) { setField(10, v); }
  bool hasReadTime() => $_has(7);
  void clearReadTime() => clearField(10);

  bool get showMissing => $_get(8, false);
  set showMissing(bool v) { $_setBool(8, v); }
  bool hasShowMissing() => $_has(8);
  void clearShowMissing() => clearField(12);
}

class ListDocumentsResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListDocumentsResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pp<$2.Document>(1, 'documents', $pb.PbFieldType.PM, $2.Document.$checkItem, $2.Document.create)
    ..aOS(2, 'nextPageToken')
    ..hasRequiredFields = false
  ;

  ListDocumentsResponse() : super();
  ListDocumentsResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListDocumentsResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListDocumentsResponse clone() => new ListDocumentsResponse()..mergeFromMessage(this);
  ListDocumentsResponse copyWith(void Function(ListDocumentsResponse) updates) => super.copyWith((message) => updates(message as ListDocumentsResponse));
  $pb.BuilderInfo get info_ => _i;
  static ListDocumentsResponse create() => new ListDocumentsResponse();
  static $pb.PbList<ListDocumentsResponse> createRepeated() => new $pb.PbList<ListDocumentsResponse>();
  static ListDocumentsResponse getDefault() => _defaultInstance ??= create()..freeze();
  static ListDocumentsResponse _defaultInstance;
  static void $checkItem(ListDocumentsResponse v) {
    if (v is! ListDocumentsResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  List<$2.Document> get documents => $_getList(0);

  String get nextPageToken => $_getS(1, '');
  set nextPageToken(String v) { $_setString(1, v); }
  bool hasNextPageToken() => $_has(1);
  void clearNextPageToken() => clearField(2);
}

class CreateDocumentRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('CreateDocumentRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'parent')
    ..aOS(2, 'collectionId')
    ..aOS(3, 'documentId')
    ..a<$2.Document>(4, 'document', $pb.PbFieldType.OM, $2.Document.getDefault, $2.Document.create)
    ..a<$0.DocumentMask>(5, 'mask', $pb.PbFieldType.OM, $0.DocumentMask.getDefault, $0.DocumentMask.create)
    ..hasRequiredFields = false
  ;

  CreateDocumentRequest() : super();
  CreateDocumentRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  CreateDocumentRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  CreateDocumentRequest clone() => new CreateDocumentRequest()..mergeFromMessage(this);
  CreateDocumentRequest copyWith(void Function(CreateDocumentRequest) updates) => super.copyWith((message) => updates(message as CreateDocumentRequest));
  $pb.BuilderInfo get info_ => _i;
  static CreateDocumentRequest create() => new CreateDocumentRequest();
  static $pb.PbList<CreateDocumentRequest> createRepeated() => new $pb.PbList<CreateDocumentRequest>();
  static CreateDocumentRequest getDefault() => _defaultInstance ??= create()..freeze();
  static CreateDocumentRequest _defaultInstance;
  static void $checkItem(CreateDocumentRequest v) {
    if (v is! CreateDocumentRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get parent => $_getS(0, '');
  set parent(String v) { $_setString(0, v); }
  bool hasParent() => $_has(0);
  void clearParent() => clearField(1);

  String get collectionId => $_getS(1, '');
  set collectionId(String v) { $_setString(1, v); }
  bool hasCollectionId() => $_has(1);
  void clearCollectionId() => clearField(2);

  String get documentId => $_getS(2, '');
  set documentId(String v) { $_setString(2, v); }
  bool hasDocumentId() => $_has(2);
  void clearDocumentId() => clearField(3);

  $2.Document get document => $_getN(3);
  set document($2.Document v) { setField(4, v); }
  bool hasDocument() => $_has(3);
  void clearDocument() => clearField(4);

  $0.DocumentMask get mask => $_getN(4);
  set mask($0.DocumentMask v) { setField(5, v); }
  bool hasMask() => $_has(4);
  void clearMask() => clearField(5);
}

class UpdateDocumentRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('UpdateDocumentRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$2.Document>(1, 'document', $pb.PbFieldType.OM, $2.Document.getDefault, $2.Document.create)
    ..a<$0.DocumentMask>(2, 'updateMask', $pb.PbFieldType.OM, $0.DocumentMask.getDefault, $0.DocumentMask.create)
    ..a<$0.DocumentMask>(3, 'mask', $pb.PbFieldType.OM, $0.DocumentMask.getDefault, $0.DocumentMask.create)
    ..a<$0.Precondition>(4, 'currentDocument', $pb.PbFieldType.OM, $0.Precondition.getDefault, $0.Precondition.create)
    ..hasRequiredFields = false
  ;

  UpdateDocumentRequest() : super();
  UpdateDocumentRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  UpdateDocumentRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  UpdateDocumentRequest clone() => new UpdateDocumentRequest()..mergeFromMessage(this);
  UpdateDocumentRequest copyWith(void Function(UpdateDocumentRequest) updates) => super.copyWith((message) => updates(message as UpdateDocumentRequest));
  $pb.BuilderInfo get info_ => _i;
  static UpdateDocumentRequest create() => new UpdateDocumentRequest();
  static $pb.PbList<UpdateDocumentRequest> createRepeated() => new $pb.PbList<UpdateDocumentRequest>();
  static UpdateDocumentRequest getDefault() => _defaultInstance ??= create()..freeze();
  static UpdateDocumentRequest _defaultInstance;
  static void $checkItem(UpdateDocumentRequest v) {
    if (v is! UpdateDocumentRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  $2.Document get document => $_getN(0);
  set document($2.Document v) { setField(1, v); }
  bool hasDocument() => $_has(0);
  void clearDocument() => clearField(1);

  $0.DocumentMask get updateMask => $_getN(1);
  set updateMask($0.DocumentMask v) { setField(2, v); }
  bool hasUpdateMask() => $_has(1);
  void clearUpdateMask() => clearField(2);

  $0.DocumentMask get mask => $_getN(2);
  set mask($0.DocumentMask v) { setField(3, v); }
  bool hasMask() => $_has(2);
  void clearMask() => clearField(3);

  $0.Precondition get currentDocument => $_getN(3);
  set currentDocument($0.Precondition v) { setField(4, v); }
  bool hasCurrentDocument() => $_has(3);
  void clearCurrentDocument() => clearField(4);
}

class DeleteDocumentRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('DeleteDocumentRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'name')
    ..a<$0.Precondition>(2, 'currentDocument', $pb.PbFieldType.OM, $0.Precondition.getDefault, $0.Precondition.create)
    ..hasRequiredFields = false
  ;

  DeleteDocumentRequest() : super();
  DeleteDocumentRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  DeleteDocumentRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  DeleteDocumentRequest clone() => new DeleteDocumentRequest()..mergeFromMessage(this);
  DeleteDocumentRequest copyWith(void Function(DeleteDocumentRequest) updates) => super.copyWith((message) => updates(message as DeleteDocumentRequest));
  $pb.BuilderInfo get info_ => _i;
  static DeleteDocumentRequest create() => new DeleteDocumentRequest();
  static $pb.PbList<DeleteDocumentRequest> createRepeated() => new $pb.PbList<DeleteDocumentRequest>();
  static DeleteDocumentRequest getDefault() => _defaultInstance ??= create()..freeze();
  static DeleteDocumentRequest _defaultInstance;
  static void $checkItem(DeleteDocumentRequest v) {
    if (v is! DeleteDocumentRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get name => $_getS(0, '');
  set name(String v) { $_setString(0, v); }
  bool hasName() => $_has(0);
  void clearName() => clearField(1);

  $0.Precondition get currentDocument => $_getN(1);
  set currentDocument($0.Precondition v) { setField(2, v); }
  bool hasCurrentDocument() => $_has(1);
  void clearCurrentDocument() => clearField(2);
}

class BatchGetDocumentsRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('BatchGetDocumentsRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'database')
    ..pPS(2, 'documents')
    ..a<$0.DocumentMask>(3, 'mask', $pb.PbFieldType.OM, $0.DocumentMask.getDefault, $0.DocumentMask.create)
    ..a<List<int>>(4, 'transaction', $pb.PbFieldType.OY)
    ..a<$0.TransactionOptions>(5, 'newTransaction', $pb.PbFieldType.OM, $0.TransactionOptions.getDefault, $0.TransactionOptions.create)
    ..a<$1.Timestamp>(7, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  BatchGetDocumentsRequest() : super();
  BatchGetDocumentsRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  BatchGetDocumentsRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  BatchGetDocumentsRequest clone() => new BatchGetDocumentsRequest()..mergeFromMessage(this);
  BatchGetDocumentsRequest copyWith(void Function(BatchGetDocumentsRequest) updates) => super.copyWith((message) => updates(message as BatchGetDocumentsRequest));
  $pb.BuilderInfo get info_ => _i;
  static BatchGetDocumentsRequest create() => new BatchGetDocumentsRequest();
  static $pb.PbList<BatchGetDocumentsRequest> createRepeated() => new $pb.PbList<BatchGetDocumentsRequest>();
  static BatchGetDocumentsRequest getDefault() => _defaultInstance ??= create()..freeze();
  static BatchGetDocumentsRequest _defaultInstance;
  static void $checkItem(BatchGetDocumentsRequest v) {
    if (v is! BatchGetDocumentsRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get database => $_getS(0, '');
  set database(String v) { $_setString(0, v); }
  bool hasDatabase() => $_has(0);
  void clearDatabase() => clearField(1);

  List<String> get documents => $_getList(1);

  $0.DocumentMask get mask => $_getN(2);
  set mask($0.DocumentMask v) { setField(3, v); }
  bool hasMask() => $_has(2);
  void clearMask() => clearField(3);

  List<int> get transaction => $_getN(3);
  set transaction(List<int> v) { $_setBytes(3, v); }
  bool hasTransaction() => $_has(3);
  void clearTransaction() => clearField(4);

  $0.TransactionOptions get newTransaction => $_getN(4);
  set newTransaction($0.TransactionOptions v) { setField(5, v); }
  bool hasNewTransaction() => $_has(4);
  void clearNewTransaction() => clearField(5);

  $1.Timestamp get readTime => $_getN(5);
  set readTime($1.Timestamp v) { setField(7, v); }
  bool hasReadTime() => $_has(5);
  void clearReadTime() => clearField(7);
}

class BatchGetDocumentsResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('BatchGetDocumentsResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$2.Document>(1, 'found', $pb.PbFieldType.OM, $2.Document.getDefault, $2.Document.create)
    ..aOS(2, 'missing')
    ..a<List<int>>(3, 'transaction', $pb.PbFieldType.OY)
    ..a<$1.Timestamp>(4, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  BatchGetDocumentsResponse() : super();
  BatchGetDocumentsResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  BatchGetDocumentsResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  BatchGetDocumentsResponse clone() => new BatchGetDocumentsResponse()..mergeFromMessage(this);
  BatchGetDocumentsResponse copyWith(void Function(BatchGetDocumentsResponse) updates) => super.copyWith((message) => updates(message as BatchGetDocumentsResponse));
  $pb.BuilderInfo get info_ => _i;
  static BatchGetDocumentsResponse create() => new BatchGetDocumentsResponse();
  static $pb.PbList<BatchGetDocumentsResponse> createRepeated() => new $pb.PbList<BatchGetDocumentsResponse>();
  static BatchGetDocumentsResponse getDefault() => _defaultInstance ??= create()..freeze();
  static BatchGetDocumentsResponse _defaultInstance;
  static void $checkItem(BatchGetDocumentsResponse v) {
    if (v is! BatchGetDocumentsResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  $2.Document get found => $_getN(0);
  set found($2.Document v) { setField(1, v); }
  bool hasFound() => $_has(0);
  void clearFound() => clearField(1);

  String get missing => $_getS(1, '');
  set missing(String v) { $_setString(1, v); }
  bool hasMissing() => $_has(1);
  void clearMissing() => clearField(2);

  List<int> get transaction => $_getN(2);
  set transaction(List<int> v) { $_setBytes(2, v); }
  bool hasTransaction() => $_has(2);
  void clearTransaction() => clearField(3);

  $1.Timestamp get readTime => $_getN(3);
  set readTime($1.Timestamp v) { setField(4, v); }
  bool hasReadTime() => $_has(3);
  void clearReadTime() => clearField(4);
}

class BeginTransactionRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('BeginTransactionRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'database')
    ..a<$0.TransactionOptions>(2, 'options', $pb.PbFieldType.OM, $0.TransactionOptions.getDefault, $0.TransactionOptions.create)
    ..hasRequiredFields = false
  ;

  BeginTransactionRequest() : super();
  BeginTransactionRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  BeginTransactionRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  BeginTransactionRequest clone() => new BeginTransactionRequest()..mergeFromMessage(this);
  BeginTransactionRequest copyWith(void Function(BeginTransactionRequest) updates) => super.copyWith((message) => updates(message as BeginTransactionRequest));
  $pb.BuilderInfo get info_ => _i;
  static BeginTransactionRequest create() => new BeginTransactionRequest();
  static $pb.PbList<BeginTransactionRequest> createRepeated() => new $pb.PbList<BeginTransactionRequest>();
  static BeginTransactionRequest getDefault() => _defaultInstance ??= create()..freeze();
  static BeginTransactionRequest _defaultInstance;
  static void $checkItem(BeginTransactionRequest v) {
    if (v is! BeginTransactionRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get database => $_getS(0, '');
  set database(String v) { $_setString(0, v); }
  bool hasDatabase() => $_has(0);
  void clearDatabase() => clearField(1);

  $0.TransactionOptions get options => $_getN(1);
  set options($0.TransactionOptions v) { setField(2, v); }
  bool hasOptions() => $_has(1);
  void clearOptions() => clearField(2);
}

class BeginTransactionResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('BeginTransactionResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<List<int>>(1, 'transaction', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  BeginTransactionResponse() : super();
  BeginTransactionResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  BeginTransactionResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  BeginTransactionResponse clone() => new BeginTransactionResponse()..mergeFromMessage(this);
  BeginTransactionResponse copyWith(void Function(BeginTransactionResponse) updates) => super.copyWith((message) => updates(message as BeginTransactionResponse));
  $pb.BuilderInfo get info_ => _i;
  static BeginTransactionResponse create() => new BeginTransactionResponse();
  static $pb.PbList<BeginTransactionResponse> createRepeated() => new $pb.PbList<BeginTransactionResponse>();
  static BeginTransactionResponse getDefault() => _defaultInstance ??= create()..freeze();
  static BeginTransactionResponse _defaultInstance;
  static void $checkItem(BeginTransactionResponse v) {
    if (v is! BeginTransactionResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  List<int> get transaction => $_getN(0);
  set transaction(List<int> v) { $_setBytes(0, v); }
  bool hasTransaction() => $_has(0);
  void clearTransaction() => clearField(1);
}

class CommitRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('CommitRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'database')
    ..pp<$3.Write>(2, 'writes', $pb.PbFieldType.PM, $3.Write.$checkItem, $3.Write.create)
    ..a<List<int>>(3, 'transaction', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  CommitRequest() : super();
  CommitRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  CommitRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  CommitRequest clone() => new CommitRequest()..mergeFromMessage(this);
  CommitRequest copyWith(void Function(CommitRequest) updates) => super.copyWith((message) => updates(message as CommitRequest));
  $pb.BuilderInfo get info_ => _i;
  static CommitRequest create() => new CommitRequest();
  static $pb.PbList<CommitRequest> createRepeated() => new $pb.PbList<CommitRequest>();
  static CommitRequest getDefault() => _defaultInstance ??= create()..freeze();
  static CommitRequest _defaultInstance;
  static void $checkItem(CommitRequest v) {
    if (v is! CommitRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get database => $_getS(0, '');
  set database(String v) { $_setString(0, v); }
  bool hasDatabase() => $_has(0);
  void clearDatabase() => clearField(1);

  List<$3.Write> get writes => $_getList(1);

  List<int> get transaction => $_getN(2);
  set transaction(List<int> v) { $_setBytes(2, v); }
  bool hasTransaction() => $_has(2);
  void clearTransaction() => clearField(3);
}

class CommitResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('CommitResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pp<$3.WriteResult>(1, 'writeResults', $pb.PbFieldType.PM, $3.WriteResult.$checkItem, $3.WriteResult.create)
    ..a<$1.Timestamp>(2, 'commitTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  CommitResponse() : super();
  CommitResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  CommitResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  CommitResponse clone() => new CommitResponse()..mergeFromMessage(this);
  CommitResponse copyWith(void Function(CommitResponse) updates) => super.copyWith((message) => updates(message as CommitResponse));
  $pb.BuilderInfo get info_ => _i;
  static CommitResponse create() => new CommitResponse();
  static $pb.PbList<CommitResponse> createRepeated() => new $pb.PbList<CommitResponse>();
  static CommitResponse getDefault() => _defaultInstance ??= create()..freeze();
  static CommitResponse _defaultInstance;
  static void $checkItem(CommitResponse v) {
    if (v is! CommitResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  List<$3.WriteResult> get writeResults => $_getList(0);

  $1.Timestamp get commitTime => $_getN(1);
  set commitTime($1.Timestamp v) { setField(2, v); }
  bool hasCommitTime() => $_has(1);
  void clearCommitTime() => clearField(2);
}

class RollbackRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('RollbackRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'database')
    ..a<List<int>>(2, 'transaction', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  RollbackRequest() : super();
  RollbackRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  RollbackRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  RollbackRequest clone() => new RollbackRequest()..mergeFromMessage(this);
  RollbackRequest copyWith(void Function(RollbackRequest) updates) => super.copyWith((message) => updates(message as RollbackRequest));
  $pb.BuilderInfo get info_ => _i;
  static RollbackRequest create() => new RollbackRequest();
  static $pb.PbList<RollbackRequest> createRepeated() => new $pb.PbList<RollbackRequest>();
  static RollbackRequest getDefault() => _defaultInstance ??= create()..freeze();
  static RollbackRequest _defaultInstance;
  static void $checkItem(RollbackRequest v) {
    if (v is! RollbackRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get database => $_getS(0, '');
  set database(String v) { $_setString(0, v); }
  bool hasDatabase() => $_has(0);
  void clearDatabase() => clearField(1);

  List<int> get transaction => $_getN(1);
  set transaction(List<int> v) { $_setBytes(1, v); }
  bool hasTransaction() => $_has(1);
  void clearTransaction() => clearField(2);
}

class RunQueryRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('RunQueryRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'parent')
    ..a<$4.StructuredQuery>(2, 'structuredQuery', $pb.PbFieldType.OM, $4.StructuredQuery.getDefault, $4.StructuredQuery.create)
    ..a<List<int>>(5, 'transaction', $pb.PbFieldType.OY)
    ..a<$0.TransactionOptions>(6, 'newTransaction', $pb.PbFieldType.OM, $0.TransactionOptions.getDefault, $0.TransactionOptions.create)
    ..a<$1.Timestamp>(7, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  RunQueryRequest() : super();
  RunQueryRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  RunQueryRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  RunQueryRequest clone() => new RunQueryRequest()..mergeFromMessage(this);
  RunQueryRequest copyWith(void Function(RunQueryRequest) updates) => super.copyWith((message) => updates(message as RunQueryRequest));
  $pb.BuilderInfo get info_ => _i;
  static RunQueryRequest create() => new RunQueryRequest();
  static $pb.PbList<RunQueryRequest> createRepeated() => new $pb.PbList<RunQueryRequest>();
  static RunQueryRequest getDefault() => _defaultInstance ??= create()..freeze();
  static RunQueryRequest _defaultInstance;
  static void $checkItem(RunQueryRequest v) {
    if (v is! RunQueryRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get parent => $_getS(0, '');
  set parent(String v) { $_setString(0, v); }
  bool hasParent() => $_has(0);
  void clearParent() => clearField(1);

  $4.StructuredQuery get structuredQuery => $_getN(1);
  set structuredQuery($4.StructuredQuery v) { setField(2, v); }
  bool hasStructuredQuery() => $_has(1);
  void clearStructuredQuery() => clearField(2);

  List<int> get transaction => $_getN(2);
  set transaction(List<int> v) { $_setBytes(2, v); }
  bool hasTransaction() => $_has(2);
  void clearTransaction() => clearField(5);

  $0.TransactionOptions get newTransaction => $_getN(3);
  set newTransaction($0.TransactionOptions v) { setField(6, v); }
  bool hasNewTransaction() => $_has(3);
  void clearNewTransaction() => clearField(6);

  $1.Timestamp get readTime => $_getN(4);
  set readTime($1.Timestamp v) { setField(7, v); }
  bool hasReadTime() => $_has(4);
  void clearReadTime() => clearField(7);
}

class RunQueryResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('RunQueryResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<$2.Document>(1, 'document', $pb.PbFieldType.OM, $2.Document.getDefault, $2.Document.create)
    ..a<List<int>>(2, 'transaction', $pb.PbFieldType.OY)
    ..a<$1.Timestamp>(3, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..a<int>(4, 'skippedResults', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  RunQueryResponse() : super();
  RunQueryResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  RunQueryResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  RunQueryResponse clone() => new RunQueryResponse()..mergeFromMessage(this);
  RunQueryResponse copyWith(void Function(RunQueryResponse) updates) => super.copyWith((message) => updates(message as RunQueryResponse));
  $pb.BuilderInfo get info_ => _i;
  static RunQueryResponse create() => new RunQueryResponse();
  static $pb.PbList<RunQueryResponse> createRepeated() => new $pb.PbList<RunQueryResponse>();
  static RunQueryResponse getDefault() => _defaultInstance ??= create()..freeze();
  static RunQueryResponse _defaultInstance;
  static void $checkItem(RunQueryResponse v) {
    if (v is! RunQueryResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  $2.Document get document => $_getN(0);
  set document($2.Document v) { setField(1, v); }
  bool hasDocument() => $_has(0);
  void clearDocument() => clearField(1);

  List<int> get transaction => $_getN(1);
  set transaction(List<int> v) { $_setBytes(1, v); }
  bool hasTransaction() => $_has(1);
  void clearTransaction() => clearField(2);

  $1.Timestamp get readTime => $_getN(2);
  set readTime($1.Timestamp v) { setField(3, v); }
  bool hasReadTime() => $_has(2);
  void clearReadTime() => clearField(3);

  int get skippedResults => $_get(3, 0);
  set skippedResults(int v) { $_setSignedInt32(3, v); }
  bool hasSkippedResults() => $_has(3);
  void clearSkippedResults() => clearField(4);
}

class WriteRequest_LabelsEntry extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('WriteRequest.LabelsEntry', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'key')
    ..aOS(2, 'value')
    ..hasRequiredFields = false
  ;

  WriteRequest_LabelsEntry() : super();
  WriteRequest_LabelsEntry.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  WriteRequest_LabelsEntry.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  WriteRequest_LabelsEntry clone() => new WriteRequest_LabelsEntry()..mergeFromMessage(this);
  WriteRequest_LabelsEntry copyWith(void Function(WriteRequest_LabelsEntry) updates) => super.copyWith((message) => updates(message as WriteRequest_LabelsEntry));
  $pb.BuilderInfo get info_ => _i;
  static WriteRequest_LabelsEntry create() => new WriteRequest_LabelsEntry();
  static $pb.PbList<WriteRequest_LabelsEntry> createRepeated() => new $pb.PbList<WriteRequest_LabelsEntry>();
  static WriteRequest_LabelsEntry getDefault() => _defaultInstance ??= create()..freeze();
  static WriteRequest_LabelsEntry _defaultInstance;
  static void $checkItem(WriteRequest_LabelsEntry v) {
    if (v is! WriteRequest_LabelsEntry) $pb.checkItemFailed(v, _i.messageName);
  }

  String get key => $_getS(0, '');
  set key(String v) { $_setString(0, v); }
  bool hasKey() => $_has(0);
  void clearKey() => clearField(1);

  String get value => $_getS(1, '');
  set value(String v) { $_setString(1, v); }
  bool hasValue() => $_has(1);
  void clearValue() => clearField(2);
}

class WriteRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('WriteRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'database')
    ..aOS(2, 'streamId')
    ..pp<$3.Write>(3, 'writes', $pb.PbFieldType.PM, $3.Write.$checkItem, $3.Write.create)
    ..a<List<int>>(4, 'streamToken', $pb.PbFieldType.OY)
    ..pp<WriteRequest_LabelsEntry>(5, 'labels', $pb.PbFieldType.PM, WriteRequest_LabelsEntry.$checkItem, WriteRequest_LabelsEntry.create)
    ..hasRequiredFields = false
  ;

  WriteRequest() : super();
  WriteRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  WriteRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  WriteRequest clone() => new WriteRequest()..mergeFromMessage(this);
  WriteRequest copyWith(void Function(WriteRequest) updates) => super.copyWith((message) => updates(message as WriteRequest));
  $pb.BuilderInfo get info_ => _i;
  static WriteRequest create() => new WriteRequest();
  static $pb.PbList<WriteRequest> createRepeated() => new $pb.PbList<WriteRequest>();
  static WriteRequest getDefault() => _defaultInstance ??= create()..freeze();
  static WriteRequest _defaultInstance;
  static void $checkItem(WriteRequest v) {
    if (v is! WriteRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get database => $_getS(0, '');
  set database(String v) { $_setString(0, v); }
  bool hasDatabase() => $_has(0);
  void clearDatabase() => clearField(1);

  String get streamId => $_getS(1, '');
  set streamId(String v) { $_setString(1, v); }
  bool hasStreamId() => $_has(1);
  void clearStreamId() => clearField(2);

  List<$3.Write> get writes => $_getList(2);

  List<int> get streamToken => $_getN(3);
  set streamToken(List<int> v) { $_setBytes(3, v); }
  bool hasStreamToken() => $_has(3);
  void clearStreamToken() => clearField(4);

  List<WriteRequest_LabelsEntry> get labels => $_getList(4);
}

class WriteResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('WriteResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'streamId')
    ..a<List<int>>(2, 'streamToken', $pb.PbFieldType.OY)
    ..pp<$3.WriteResult>(3, 'writeResults', $pb.PbFieldType.PM, $3.WriteResult.$checkItem, $3.WriteResult.create)
    ..a<$1.Timestamp>(4, 'commitTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  WriteResponse() : super();
  WriteResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  WriteResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  WriteResponse clone() => new WriteResponse()..mergeFromMessage(this);
  WriteResponse copyWith(void Function(WriteResponse) updates) => super.copyWith((message) => updates(message as WriteResponse));
  $pb.BuilderInfo get info_ => _i;
  static WriteResponse create() => new WriteResponse();
  static $pb.PbList<WriteResponse> createRepeated() => new $pb.PbList<WriteResponse>();
  static WriteResponse getDefault() => _defaultInstance ??= create()..freeze();
  static WriteResponse _defaultInstance;
  static void $checkItem(WriteResponse v) {
    if (v is! WriteResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  String get streamId => $_getS(0, '');
  set streamId(String v) { $_setString(0, v); }
  bool hasStreamId() => $_has(0);
  void clearStreamId() => clearField(1);

  List<int> get streamToken => $_getN(1);
  set streamToken(List<int> v) { $_setBytes(1, v); }
  bool hasStreamToken() => $_has(1);
  void clearStreamToken() => clearField(2);

  List<$3.WriteResult> get writeResults => $_getList(2);

  $1.Timestamp get commitTime => $_getN(3);
  set commitTime($1.Timestamp v) { setField(4, v); }
  bool hasCommitTime() => $_has(3);
  void clearCommitTime() => clearField(4);
}

class ListenRequest_LabelsEntry extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListenRequest.LabelsEntry', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'key')
    ..aOS(2, 'value')
    ..hasRequiredFields = false
  ;

  ListenRequest_LabelsEntry() : super();
  ListenRequest_LabelsEntry.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListenRequest_LabelsEntry.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListenRequest_LabelsEntry clone() => new ListenRequest_LabelsEntry()..mergeFromMessage(this);
  ListenRequest_LabelsEntry copyWith(void Function(ListenRequest_LabelsEntry) updates) => super.copyWith((message) => updates(message as ListenRequest_LabelsEntry));
  $pb.BuilderInfo get info_ => _i;
  static ListenRequest_LabelsEntry create() => new ListenRequest_LabelsEntry();
  static $pb.PbList<ListenRequest_LabelsEntry> createRepeated() => new $pb.PbList<ListenRequest_LabelsEntry>();
  static ListenRequest_LabelsEntry getDefault() => _defaultInstance ??= create()..freeze();
  static ListenRequest_LabelsEntry _defaultInstance;
  static void $checkItem(ListenRequest_LabelsEntry v) {
    if (v is! ListenRequest_LabelsEntry) $pb.checkItemFailed(v, _i.messageName);
  }

  String get key => $_getS(0, '');
  set key(String v) { $_setString(0, v); }
  bool hasKey() => $_has(0);
  void clearKey() => clearField(1);

  String get value => $_getS(1, '');
  set value(String v) { $_setString(1, v); }
  bool hasValue() => $_has(1);
  void clearValue() => clearField(2);
}

class ListenRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListenRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'database')
    ..a<Target>(2, 'addTarget', $pb.PbFieldType.OM, Target.getDefault, Target.create)
    ..a<int>(3, 'removeTarget', $pb.PbFieldType.O3)
    ..pp<ListenRequest_LabelsEntry>(4, 'labels', $pb.PbFieldType.PM, ListenRequest_LabelsEntry.$checkItem, ListenRequest_LabelsEntry.create)
    ..hasRequiredFields = false
  ;

  ListenRequest() : super();
  ListenRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListenRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListenRequest clone() => new ListenRequest()..mergeFromMessage(this);
  ListenRequest copyWith(void Function(ListenRequest) updates) => super.copyWith((message) => updates(message as ListenRequest));
  $pb.BuilderInfo get info_ => _i;
  static ListenRequest create() => new ListenRequest();
  static $pb.PbList<ListenRequest> createRepeated() => new $pb.PbList<ListenRequest>();
  static ListenRequest getDefault() => _defaultInstance ??= create()..freeze();
  static ListenRequest _defaultInstance;
  static void $checkItem(ListenRequest v) {
    if (v is! ListenRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get database => $_getS(0, '');
  set database(String v) { $_setString(0, v); }
  bool hasDatabase() => $_has(0);
  void clearDatabase() => clearField(1);

  Target get addTarget => $_getN(1);
  set addTarget(Target v) { setField(2, v); }
  bool hasAddTarget() => $_has(1);
  void clearAddTarget() => clearField(2);

  int get removeTarget => $_get(2, 0);
  set removeTarget(int v) { $_setSignedInt32(2, v); }
  bool hasRemoveTarget() => $_has(2);
  void clearRemoveTarget() => clearField(3);

  List<ListenRequest_LabelsEntry> get labels => $_getList(3);
}

class ListenResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListenResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<TargetChange>(2, 'targetChange', $pb.PbFieldType.OM, TargetChange.getDefault, TargetChange.create)
    ..a<$3.DocumentChange>(3, 'documentChange', $pb.PbFieldType.OM, $3.DocumentChange.getDefault, $3.DocumentChange.create)
    ..a<$3.DocumentDelete>(4, 'documentDelete', $pb.PbFieldType.OM, $3.DocumentDelete.getDefault, $3.DocumentDelete.create)
    ..a<$3.ExistenceFilter>(5, 'filter', $pb.PbFieldType.OM, $3.ExistenceFilter.getDefault, $3.ExistenceFilter.create)
    ..a<$3.DocumentRemove>(6, 'documentRemove', $pb.PbFieldType.OM, $3.DocumentRemove.getDefault, $3.DocumentRemove.create)
    ..hasRequiredFields = false
  ;

  ListenResponse() : super();
  ListenResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListenResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListenResponse clone() => new ListenResponse()..mergeFromMessage(this);
  ListenResponse copyWith(void Function(ListenResponse) updates) => super.copyWith((message) => updates(message as ListenResponse));
  $pb.BuilderInfo get info_ => _i;
  static ListenResponse create() => new ListenResponse();
  static $pb.PbList<ListenResponse> createRepeated() => new $pb.PbList<ListenResponse>();
  static ListenResponse getDefault() => _defaultInstance ??= create()..freeze();
  static ListenResponse _defaultInstance;
  static void $checkItem(ListenResponse v) {
    if (v is! ListenResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  TargetChange get targetChange => $_getN(0);
  set targetChange(TargetChange v) { setField(2, v); }
  bool hasTargetChange() => $_has(0);
  void clearTargetChange() => clearField(2);

  $3.DocumentChange get documentChange => $_getN(1);
  set documentChange($3.DocumentChange v) { setField(3, v); }
  bool hasDocumentChange() => $_has(1);
  void clearDocumentChange() => clearField(3);

  $3.DocumentDelete get documentDelete => $_getN(2);
  set documentDelete($3.DocumentDelete v) { setField(4, v); }
  bool hasDocumentDelete() => $_has(2);
  void clearDocumentDelete() => clearField(4);

  $3.ExistenceFilter get filter => $_getN(3);
  set filter($3.ExistenceFilter v) { setField(5, v); }
  bool hasFilter() => $_has(3);
  void clearFilter() => clearField(5);

  $3.DocumentRemove get documentRemove => $_getN(4);
  set documentRemove($3.DocumentRemove v) { setField(6, v); }
  bool hasDocumentRemove() => $_has(4);
  void clearDocumentRemove() => clearField(6);
}

class Target_DocumentsTarget extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Target.DocumentsTarget', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pPS(2, 'documents')
    ..hasRequiredFields = false
  ;

  Target_DocumentsTarget() : super();
  Target_DocumentsTarget.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Target_DocumentsTarget.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Target_DocumentsTarget clone() => new Target_DocumentsTarget()..mergeFromMessage(this);
  Target_DocumentsTarget copyWith(void Function(Target_DocumentsTarget) updates) => super.copyWith((message) => updates(message as Target_DocumentsTarget));
  $pb.BuilderInfo get info_ => _i;
  static Target_DocumentsTarget create() => new Target_DocumentsTarget();
  static $pb.PbList<Target_DocumentsTarget> createRepeated() => new $pb.PbList<Target_DocumentsTarget>();
  static Target_DocumentsTarget getDefault() => _defaultInstance ??= create()..freeze();
  static Target_DocumentsTarget _defaultInstance;
  static void $checkItem(Target_DocumentsTarget v) {
    if (v is! Target_DocumentsTarget) $pb.checkItemFailed(v, _i.messageName);
  }

  List<String> get documents => $_getList(0);
}

class Target_QueryTarget extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Target.QueryTarget', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'parent')
    ..a<$4.StructuredQuery>(2, 'structuredQuery', $pb.PbFieldType.OM, $4.StructuredQuery.getDefault, $4.StructuredQuery.create)
    ..hasRequiredFields = false
  ;

  Target_QueryTarget() : super();
  Target_QueryTarget.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Target_QueryTarget.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Target_QueryTarget clone() => new Target_QueryTarget()..mergeFromMessage(this);
  Target_QueryTarget copyWith(void Function(Target_QueryTarget) updates) => super.copyWith((message) => updates(message as Target_QueryTarget));
  $pb.BuilderInfo get info_ => _i;
  static Target_QueryTarget create() => new Target_QueryTarget();
  static $pb.PbList<Target_QueryTarget> createRepeated() => new $pb.PbList<Target_QueryTarget>();
  static Target_QueryTarget getDefault() => _defaultInstance ??= create()..freeze();
  static Target_QueryTarget _defaultInstance;
  static void $checkItem(Target_QueryTarget v) {
    if (v is! Target_QueryTarget) $pb.checkItemFailed(v, _i.messageName);
  }

  String get parent => $_getS(0, '');
  set parent(String v) { $_setString(0, v); }
  bool hasParent() => $_has(0);
  void clearParent() => clearField(1);

  $4.StructuredQuery get structuredQuery => $_getN(1);
  set structuredQuery($4.StructuredQuery v) { setField(2, v); }
  bool hasStructuredQuery() => $_has(1);
  void clearStructuredQuery() => clearField(2);
}

class Target extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('Target', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..a<Target_QueryTarget>(2, 'query', $pb.PbFieldType.OM, Target_QueryTarget.getDefault, Target_QueryTarget.create)
    ..a<Target_DocumentsTarget>(3, 'documents', $pb.PbFieldType.OM, Target_DocumentsTarget.getDefault, Target_DocumentsTarget.create)
    ..a<List<int>>(4, 'resumeToken', $pb.PbFieldType.OY)
    ..a<int>(5, 'targetId', $pb.PbFieldType.O3)
    ..aOB(6, 'once')
    ..a<$1.Timestamp>(11, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  Target() : super();
  Target.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  Target.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  Target clone() => new Target()..mergeFromMessage(this);
  Target copyWith(void Function(Target) updates) => super.copyWith((message) => updates(message as Target));
  $pb.BuilderInfo get info_ => _i;
  static Target create() => new Target();
  static $pb.PbList<Target> createRepeated() => new $pb.PbList<Target>();
  static Target getDefault() => _defaultInstance ??= create()..freeze();
  static Target _defaultInstance;
  static void $checkItem(Target v) {
    if (v is! Target) $pb.checkItemFailed(v, _i.messageName);
  }

  Target_QueryTarget get query => $_getN(0);
  set query(Target_QueryTarget v) { setField(2, v); }
  bool hasQuery() => $_has(0);
  void clearQuery() => clearField(2);

  Target_DocumentsTarget get documents => $_getN(1);
  set documents(Target_DocumentsTarget v) { setField(3, v); }
  bool hasDocuments() => $_has(1);
  void clearDocuments() => clearField(3);

  List<int> get resumeToken => $_getN(2);
  set resumeToken(List<int> v) { $_setBytes(2, v); }
  bool hasResumeToken() => $_has(2);
  void clearResumeToken() => clearField(4);

  int get targetId => $_get(3, 0);
  set targetId(int v) { $_setSignedInt32(3, v); }
  bool hasTargetId() => $_has(3);
  void clearTargetId() => clearField(5);

  bool get once => $_get(4, false);
  set once(bool v) { $_setBool(4, v); }
  bool hasOnce() => $_has(4);
  void clearOnce() => clearField(6);

  $1.Timestamp get readTime => $_getN(5);
  set readTime($1.Timestamp v) { setField(11, v); }
  bool hasReadTime() => $_has(5);
  void clearReadTime() => clearField(11);
}

class TargetChange extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('TargetChange', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..e<TargetChange_TargetChangeType>(1, 'targetChangeType', $pb.PbFieldType.OE, TargetChange_TargetChangeType.NO_CHANGE, TargetChange_TargetChangeType.valueOf, TargetChange_TargetChangeType.values)
    ..p<int>(2, 'targetIds', $pb.PbFieldType.P3)
    ..a<$5.Status>(3, 'cause', $pb.PbFieldType.OM, $5.Status.getDefault, $5.Status.create)
    ..a<List<int>>(4, 'resumeToken', $pb.PbFieldType.OY)
    ..a<$1.Timestamp>(6, 'readTime', $pb.PbFieldType.OM, $1.Timestamp.getDefault, $1.Timestamp.create)
    ..hasRequiredFields = false
  ;

  TargetChange() : super();
  TargetChange.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  TargetChange.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  TargetChange clone() => new TargetChange()..mergeFromMessage(this);
  TargetChange copyWith(void Function(TargetChange) updates) => super.copyWith((message) => updates(message as TargetChange));
  $pb.BuilderInfo get info_ => _i;
  static TargetChange create() => new TargetChange();
  static $pb.PbList<TargetChange> createRepeated() => new $pb.PbList<TargetChange>();
  static TargetChange getDefault() => _defaultInstance ??= create()..freeze();
  static TargetChange _defaultInstance;
  static void $checkItem(TargetChange v) {
    if (v is! TargetChange) $pb.checkItemFailed(v, _i.messageName);
  }

  TargetChange_TargetChangeType get targetChangeType => $_getN(0);
  set targetChangeType(TargetChange_TargetChangeType v) { setField(1, v); }
  bool hasTargetChangeType() => $_has(0);
  void clearTargetChangeType() => clearField(1);

  List<int> get targetIds => $_getList(1);

  $5.Status get cause => $_getN(2);
  set cause($5.Status v) { setField(3, v); }
  bool hasCause() => $_has(2);
  void clearCause() => clearField(3);

  List<int> get resumeToken => $_getN(3);
  set resumeToken(List<int> v) { $_setBytes(3, v); }
  bool hasResumeToken() => $_has(3);
  void clearResumeToken() => clearField(4);

  $1.Timestamp get readTime => $_getN(4);
  set readTime($1.Timestamp v) { setField(6, v); }
  bool hasReadTime() => $_has(4);
  void clearReadTime() => clearField(6);
}

class ListCollectionIdsRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListCollectionIdsRequest', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..aOS(1, 'parent')
    ..a<int>(2, 'pageSize', $pb.PbFieldType.O3)
    ..aOS(3, 'pageToken')
    ..hasRequiredFields = false
  ;

  ListCollectionIdsRequest() : super();
  ListCollectionIdsRequest.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListCollectionIdsRequest.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListCollectionIdsRequest clone() => new ListCollectionIdsRequest()..mergeFromMessage(this);
  ListCollectionIdsRequest copyWith(void Function(ListCollectionIdsRequest) updates) => super.copyWith((message) => updates(message as ListCollectionIdsRequest));
  $pb.BuilderInfo get info_ => _i;
  static ListCollectionIdsRequest create() => new ListCollectionIdsRequest();
  static $pb.PbList<ListCollectionIdsRequest> createRepeated() => new $pb.PbList<ListCollectionIdsRequest>();
  static ListCollectionIdsRequest getDefault() => _defaultInstance ??= create()..freeze();
  static ListCollectionIdsRequest _defaultInstance;
  static void $checkItem(ListCollectionIdsRequest v) {
    if (v is! ListCollectionIdsRequest) $pb.checkItemFailed(v, _i.messageName);
  }

  String get parent => $_getS(0, '');
  set parent(String v) { $_setString(0, v); }
  bool hasParent() => $_has(0);
  void clearParent() => clearField(1);

  int get pageSize => $_get(1, 0);
  set pageSize(int v) { $_setSignedInt32(1, v); }
  bool hasPageSize() => $_has(1);
  void clearPageSize() => clearField(2);

  String get pageToken => $_getS(2, '');
  set pageToken(String v) { $_setString(2, v); }
  bool hasPageToken() => $_has(2);
  void clearPageToken() => clearField(3);
}

class ListCollectionIdsResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = new $pb.BuilderInfo('ListCollectionIdsResponse', package: const $pb.PackageName('google.firestore.v1beta1'))
    ..pPS(1, 'collectionIds')
    ..aOS(2, 'nextPageToken')
    ..hasRequiredFields = false
  ;

  ListCollectionIdsResponse() : super();
  ListCollectionIdsResponse.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromBuffer(i, r);
  ListCollectionIdsResponse.fromJson(String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) : super.fromJson(i, r);
  ListCollectionIdsResponse clone() => new ListCollectionIdsResponse()..mergeFromMessage(this);
  ListCollectionIdsResponse copyWith(void Function(ListCollectionIdsResponse) updates) => super.copyWith((message) => updates(message as ListCollectionIdsResponse));
  $pb.BuilderInfo get info_ => _i;
  static ListCollectionIdsResponse create() => new ListCollectionIdsResponse();
  static $pb.PbList<ListCollectionIdsResponse> createRepeated() => new $pb.PbList<ListCollectionIdsResponse>();
  static ListCollectionIdsResponse getDefault() => _defaultInstance ??= create()..freeze();
  static ListCollectionIdsResponse _defaultInstance;
  static void $checkItem(ListCollectionIdsResponse v) {
    if (v is! ListCollectionIdsResponse) $pb.checkItemFailed(v, _i.messageName);
  }

  List<String> get collectionIds => $_getList(0);

  String get nextPageToken => $_getS(1, '');
  set nextPageToken(String v) { $_setString(1, v); }
  bool hasNextPageToken() => $_has(1);
  void clearNextPageToken() => clearField(2);
}

class FirestoreApi {
  $pb.RpcClient _client;
  FirestoreApi(this._client);

  Future<$2.Document> getDocument($pb.ClientContext ctx, GetDocumentRequest request) {
    var emptyResponse = new $2.Document();
    return _client.invoke<$2.Document>(ctx, 'Firestore', 'GetDocument', request, emptyResponse);
  }
  Future<ListDocumentsResponse> listDocuments($pb.ClientContext ctx, ListDocumentsRequest request) {
    var emptyResponse = new ListDocumentsResponse();
    return _client.invoke<ListDocumentsResponse>(ctx, 'Firestore', 'ListDocuments', request, emptyResponse);
  }
  Future<$2.Document> createDocument($pb.ClientContext ctx, CreateDocumentRequest request) {
    var emptyResponse = new $2.Document();
    return _client.invoke<$2.Document>(ctx, 'Firestore', 'CreateDocument', request, emptyResponse);
  }
  Future<$2.Document> updateDocument($pb.ClientContext ctx, UpdateDocumentRequest request) {
    var emptyResponse = new $2.Document();
    return _client.invoke<$2.Document>(ctx, 'Firestore', 'UpdateDocument', request, emptyResponse);
  }
  Future<$6.Empty> deleteDocument($pb.ClientContext ctx, DeleteDocumentRequest request) {
    var emptyResponse = new $6.Empty();
    return _client.invoke<$6.Empty>(ctx, 'Firestore', 'DeleteDocument', request, emptyResponse);
  }
  Future<BatchGetDocumentsResponse> batchGetDocuments($pb.ClientContext ctx, BatchGetDocumentsRequest request) {
    var emptyResponse = new BatchGetDocumentsResponse();
    return _client.invoke<BatchGetDocumentsResponse>(ctx, 'Firestore', 'BatchGetDocuments', request, emptyResponse);
  }
  Future<BeginTransactionResponse> beginTransaction($pb.ClientContext ctx, BeginTransactionRequest request) {
    var emptyResponse = new BeginTransactionResponse();
    return _client.invoke<BeginTransactionResponse>(ctx, 'Firestore', 'BeginTransaction', request, emptyResponse);
  }
  Future<CommitResponse> commit($pb.ClientContext ctx, CommitRequest request) {
    var emptyResponse = new CommitResponse();
    return _client.invoke<CommitResponse>(ctx, 'Firestore', 'Commit', request, emptyResponse);
  }
  Future<$6.Empty> rollback($pb.ClientContext ctx, RollbackRequest request) {
    var emptyResponse = new $6.Empty();
    return _client.invoke<$6.Empty>(ctx, 'Firestore', 'Rollback', request, emptyResponse);
  }
  Future<RunQueryResponse> runQuery($pb.ClientContext ctx, RunQueryRequest request) {
    var emptyResponse = new RunQueryResponse();
    return _client.invoke<RunQueryResponse>(ctx, 'Firestore', 'RunQuery', request, emptyResponse);
  }
  Future<WriteResponse> write($pb.ClientContext ctx, WriteRequest request) {
    var emptyResponse = new WriteResponse();
    return _client.invoke<WriteResponse>(ctx, 'Firestore', 'Write', request, emptyResponse);
  }
  Future<ListenResponse> listen($pb.ClientContext ctx, ListenRequest request) {
    var emptyResponse = new ListenResponse();
    return _client.invoke<ListenResponse>(ctx, 'Firestore', 'Listen', request, emptyResponse);
  }
  Future<ListCollectionIdsResponse> listCollectionIds($pb.ClientContext ctx, ListCollectionIdsRequest request) {
    var emptyResponse = new ListCollectionIdsResponse();
    return _client.invoke<ListCollectionIdsResponse>(ctx, 'Firestore', 'ListCollectionIds', request, emptyResponse);
  }
}

