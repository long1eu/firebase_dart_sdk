import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:protobuf/protobuf.dart';

/// A [FirestoreTransport] for fakes that override every call they use: it
/// fails the test if a call reaches the wire.
class UnusedTransport implements FirestoreTransport {
  @override
  ResponseStream<Res> startCall<Req extends GeneratedMessage,
          Res extends GeneratedMessage>(
      FirestoreRpc<Req, Res> rpc, Stream<Req> requests,
      {CallOptions? options}) {
    throw StateError('Unexpected ${rpc.name} call on the transport');
  }

  @override
  Future<void> shutdown() async {}
}
