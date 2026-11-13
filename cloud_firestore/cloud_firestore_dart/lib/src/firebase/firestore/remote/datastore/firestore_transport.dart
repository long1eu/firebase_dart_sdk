// The seam between the Firestore client and the wire. The native transport
// speaks gRPC over HTTP/2 (grpc_transport.dart); other platforms plug in their
// own implementation through transport_factory.dart.

import 'dart:async';

import 'package:async/async.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';

/// Describes one RPC of the `google.firestore.v1.Firestore` service.
class FirestoreRpc<Req extends GeneratedMessage, Res extends GeneratedMessage> {
  const FirestoreRpc._(
    this.name,
    this.newResponse, {
    this.clientStreaming = false,
  });

  /// The method name, for example `Commit`.
  final String name;

  /// Creates an empty response message, to decode into.
  final Res Function() newResponse;

  /// Whether the client sends more than one request (Listen and Write).
  final bool clientStreaming;

  /// The gRPC path of the method.
  String get path => '/google.firestore.v1.Firestore/$name';

  static const FirestoreRpc<
    proto.BatchGetDocumentsRequest,
    proto.BatchGetDocumentsResponse
  >
  batchGetDocuments =
      FirestoreRpc<
        proto.BatchGetDocumentsRequest,
        proto.BatchGetDocumentsResponse
      >._('BatchGetDocuments', proto.BatchGetDocumentsResponse.create);

  static const FirestoreRpc<proto.RunQueryRequest, proto.RunQueryResponse>
  runQuery = FirestoreRpc<proto.RunQueryRequest, proto.RunQueryResponse>._(
    'RunQuery',
    proto.RunQueryResponse.create,
  );

  static const FirestoreRpc<
    proto.RunAggregationQueryRequest,
    proto.RunAggregationQueryResponse
  >
  runAggregationQuery =
      FirestoreRpc<
        proto.RunAggregationQueryRequest,
        proto.RunAggregationQueryResponse
      >._('RunAggregationQuery', proto.RunAggregationQueryResponse.create);

  static const FirestoreRpc<
    proto.ExecutePipelineRequest,
    proto.ExecutePipelineResponse
  >
  executePipeline =
      FirestoreRpc<
        proto.ExecutePipelineRequest,
        proto.ExecutePipelineResponse
      >._('ExecutePipeline', proto.ExecutePipelineResponse.create);

  static const FirestoreRpc<
    proto.BeginTransactionRequest,
    proto.BeginTransactionResponse
  >
  beginTransaction =
      FirestoreRpc<
        proto.BeginTransactionRequest,
        proto.BeginTransactionResponse
      >._('BeginTransaction', proto.BeginTransactionResponse.create);

  static const FirestoreRpc<proto.RollbackRequest, Empty> rollback =
      FirestoreRpc<proto.RollbackRequest, Empty>._('Rollback', Empty.new);

  static const FirestoreRpc<proto.CommitRequest, proto.CommitResponse> commit =
      FirestoreRpc<proto.CommitRequest, proto.CommitResponse>._(
        'Commit',
        proto.CommitResponse.create,
      );

  static const FirestoreRpc<proto.ListenRequest, proto.ListenResponse> listen =
      FirestoreRpc<proto.ListenRequest, proto.ListenResponse>._(
        'Listen',
        proto.ListenResponse.create,
        clientStreaming: true,
      );

  static const FirestoreRpc<proto.WriteRequest, proto.WriteResponse> write =
      FirestoreRpc<proto.WriteRequest, proto.WriteResponse>._(
        'Write',
        proto.WriteResponse.create,
        clientStreaming: true,
      );
}

/// Sends the RPCs of the Firestore service to the backend.
///
/// Failures are reported as [GrpcError]s on the returned stream, whatever the
/// wire protocol is.
abstract class FirestoreTransport {
  /// Starts [rpc]. The call is returned right away, without waiting for a
  /// connection: [requests] are buffered until it is up, and a failed
  /// connection is an error on the returned stream.
  ///
  /// [options] are merged over the default options of the transport (which
  /// carry the credentials).
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options});

  /// Terminates the transport. All open calls are terminated immediately, and
  /// no further calls may be made.
  Future<void> shutdown();
}

/// A gRPC response producing a stream of values.
class ResponseStream<R> extends DelegatingStream<R> implements Response {
  ResponseStream(this._response, Stream<R> response) : super(response);

  final Response _response;

  @override
  Future<Map<String, String>> get headers => _response.headers;

  @override
  Future<Map<String, String>> get trailers => _response.trailers;

  @override
  Future<void> cancel() => _response.cancel();
}

/// A gRPC response producing a single value.
class ResponseFuture<R> extends DelegatingFuture<R> implements Response {
  ResponseFuture(this._response, Future<R> future) : super(future);

  final Response _response;

  @override
  Future<Map<String, String>> get headers => _response.headers;

  @override
  Future<Map<String, String>> get trailers => _response.trailers;

  @override
  Future<void> cancel() => _response.cancel();
}
