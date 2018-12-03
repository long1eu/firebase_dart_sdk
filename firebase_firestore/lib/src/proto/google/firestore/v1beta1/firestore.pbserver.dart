///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/firestore.proto
///
// ignore_for_file: non_constant_identifier_names,library_prefixes,unused_import

import 'dart:async';

import 'package:protobuf/protobuf.dart';

import 'firestore.pb.dart';
import 'document.pb.dart' as $2;
import '../../protobuf/empty.pb.dart' as $6;
import 'firestore.pbjson.dart';

export 'firestore.pb.dart';

abstract class FirestoreServiceBase extends GeneratedService {
  Future<$2.Document> getDocument(ServerContext ctx, GetDocumentRequest request);
  Future<ListDocumentsResponse> listDocuments(ServerContext ctx, ListDocumentsRequest request);
  Future<$2.Document> createDocument(ServerContext ctx, CreateDocumentRequest request);
  Future<$2.Document> updateDocument(ServerContext ctx, UpdateDocumentRequest request);
  Future<$6.Empty> deleteDocument(ServerContext ctx, DeleteDocumentRequest request);
  Future<BatchGetDocumentsResponse> batchGetDocuments(ServerContext ctx, BatchGetDocumentsRequest request);
  Future<BeginTransactionResponse> beginTransaction(ServerContext ctx, BeginTransactionRequest request);
  Future<CommitResponse> commit(ServerContext ctx, CommitRequest request);
  Future<$6.Empty> rollback(ServerContext ctx, RollbackRequest request);
  Future<RunQueryResponse> runQuery(ServerContext ctx, RunQueryRequest request);
  Future<WriteResponse> write(ServerContext ctx, WriteRequest request);
  Future<ListenResponse> listen(ServerContext ctx, ListenRequest request);
  Future<ListCollectionIdsResponse> listCollectionIds(ServerContext ctx, ListCollectionIdsRequest request);

  GeneratedMessage createRequest(String method) {
    switch (method) {
      case 'GetDocument': return new GetDocumentRequest();
      case 'ListDocuments': return new ListDocumentsRequest();
      case 'CreateDocument': return new CreateDocumentRequest();
      case 'UpdateDocument': return new UpdateDocumentRequest();
      case 'DeleteDocument': return new DeleteDocumentRequest();
      case 'BatchGetDocuments': return new BatchGetDocumentsRequest();
      case 'BeginTransaction': return new BeginTransactionRequest();
      case 'Commit': return new CommitRequest();
      case 'Rollback': return new RollbackRequest();
      case 'RunQuery': return new RunQueryRequest();
      case 'Write': return new WriteRequest();
      case 'Listen': return new ListenRequest();
      case 'ListCollectionIds': return new ListCollectionIdsRequest();
      default: throw new ArgumentError('Unknown method: $method');
    }
  }

  Future<GeneratedMessage> handleCall(ServerContext ctx, String method, GeneratedMessage request) {
    switch (method) {
      case 'GetDocument': return this.getDocument(ctx, request);
      case 'ListDocuments': return this.listDocuments(ctx, request);
      case 'CreateDocument': return this.createDocument(ctx, request);
      case 'UpdateDocument': return this.updateDocument(ctx, request);
      case 'DeleteDocument': return this.deleteDocument(ctx, request);
      case 'BatchGetDocuments': return this.batchGetDocuments(ctx, request);
      case 'BeginTransaction': return this.beginTransaction(ctx, request);
      case 'Commit': return this.commit(ctx, request);
      case 'Rollback': return this.rollback(ctx, request);
      case 'RunQuery': return this.runQuery(ctx, request);
      case 'Write': return this.write(ctx, request);
      case 'Listen': return this.listen(ctx, request);
      case 'ListCollectionIds': return this.listCollectionIds(ctx, request);
      default: throw new ArgumentError('Unknown method: $method');
    }
  }

  Map<String, dynamic> get $json => Firestore$json;
  Map<String, Map<String, dynamic>> get $messageJson => Firestore$messageJson;
}

