// The native transport: gRPC over HTTP/2. Needs `dart:io`, only the io side of
// transport_factory.dart (and tests) may import this file.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_channel.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:grpc/grpc.dart' hide ResponseStream, ResponseFuture;
import 'package:grpc/grpc.dart' as grpc show ResponseStream;
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;
import 'package:protobuf/protobuf.dart';

/// Creates the transport of this platform: gRPC over HTTP/2.
FirestoreTransport createTransport(
  DatabaseInfo databaseInfo,
  ChannelOptionsProvider optionsProvider,
) {
  return GrpcTransport(
    createGrpcChannel(
      host: databaseInfo.host,
      port: databaseInfo.port,
      sslEnabled: databaseInfo.sslEnabled,
    ),
    optionsProvider,
  );
}

/// A [FirestoreTransport] on top of a `package:grpc` channel.
class GrpcTransport extends Client implements FirestoreTransport {
  GrpcTransport(ClientChannelBase channel, ChannelOptionsProvider options)
    : _channel = channel,
      super(channel, options: options.callOptions) {
    _stateSub = channel.onConnectionStateChanged.listen(
      (ConnectionState state) => Log.d('FirestoreClient', state.toString()),
    );
  }

  final ClientChannelBase _channel;
  late final StreamSubscription<ConnectionState> _stateSub;

  final Map<String, ClientMethod<dynamic, dynamic>> _methods =
      <String, ClientMethod<dynamic, dynamic>>{};

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    final ClientMethod<Req, Res> method =
        (_methods[rpc.name] ??= ClientMethod<Req, Res>(
              rpc.path,
              (Req value) => value.writeToBuffer(),
              (List<int> bytes) => rpc.newResponse()..mergeFromBuffer(bytes),
            ))
            as ClientMethod<Req, Res>;

    final grpc.ResponseStream<Res> call = $createStreamingCall(
      method,
      requests,
      options: options,
    );
    return ResponseStream<Res>(call, call);
  }

  @override
  Future<void> shutdown() async {
    await _stateSub.cancel();
    await _channel.terminate();
  }
}
