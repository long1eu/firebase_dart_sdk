///
//  Generated code. Do not modify.
//  source: google/firestore/v1beta1/firestore.proto
///
// ignore_for_file: camel_case_types,non_constant_identifier_names,library_prefixes,unused_import,unused_shown_name

import 'dart:async' as $async;

import 'package:protobuf/protobuf.dart' as $pb;

import 'dart:core' as $core show String, Map, ArgumentError, dynamic;
import 'firestore.pb.dart' as $11;
import 'document.pb.dart' as $4;
import '../../protobuf/empty.pb.dart' as $9;
import 'firestore.pbjson.dart';

export 'firestore.pb.dart';

abstract class FirestoreServiceBase extends $pb.GeneratedService {
  $async.Future<$4.Document> getDocument($pb.ServerContext ctx, $11.GetDocumentRequest request);
  $async.Future<$11.ListDocumentsResponse> listDocuments($pb.ServerContext ctx, $11.ListDocumentsRequest request);
  $async.Future<$4.Document> createDocument($pb.ServerContext ctx, $11.CreateDocumentRequest request);
  $async.Future<$4.Document> updateDocument($pb.ServerContext ctx, $11.UpdateDocumentRequest request);
  $async.Future<$9.Empty> deleteDocument($pb.ServerContext ctx, $11.DeleteDocumentRequest request);
  $async.Future<$11.BatchGetDocumentsResponse> batchGetDocuments($pb.ServerContext ctx, $11.BatchGetDocumentsRequest request);
  $async.Future<$11.BeginTransactionResponse> beginTransaction($pb.ServerContext ctx, $11.BeginTransactionRequest request);
  $async.Future<$11.CommitResponse> commit($pb.ServerContext ctx, $11.CommitRequest request);
  $async.Future<$9.Empty> rollback($pb.ServerContext ctx, $11.RollbackRequest request);
  $async.Future<$11.RunQueryResponse> runQuery($pb.ServerContext ctx, $11.RunQueryRequest request);
  $async.Future<$11.WriteResponse> write($pb.ServerContext ctx, $11.WriteRequest request);
  $async.Future<$11.ListenResponse> listen($pb.ServerContext ctx, $11.ListenRequest request);
  $async.Future<$11.ListCollectionIdsResponse> listCollectionIds($pb.ServerContext ctx, $11.ListCollectionIdsRequest request);

  $pb.GeneratedMessage createRequest($core.String method) {
    switch (method) {
      case 'GetDocument': return $11.GetDocumentRequest();
      case 'ListDocuments': return $11.ListDocumentsRequest();
      case 'CreateDocument': return $11.CreateDocumentRequest();
      case 'UpdateDocument': return $11.UpdateDocumentRequest();
      case 'DeleteDocument': return $11.DeleteDocumentRequest();
      case 'BatchGetDocuments': return $11.BatchGetDocumentsRequest();
      case 'BeginTransaction': return $11.BeginTransactionRequest();
      case 'Commit': return $11.CommitRequest();
      case 'Rollback': return $11.RollbackRequest();
      case 'RunQuery': return $11.RunQueryRequest();
      case 'Write': return $11.WriteRequest();
      case 'Listen': return $11.ListenRequest();
      case 'ListCollectionIds': return $11.ListCollectionIdsRequest();
      default: throw $core.ArgumentError('Unknown method: $method');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String method, $pb.GeneratedMessage request) {
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
      default: throw $core.ArgumentError('Unknown method: $method');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => FirestoreServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => FirestoreServiceBase$messageJson;
}

