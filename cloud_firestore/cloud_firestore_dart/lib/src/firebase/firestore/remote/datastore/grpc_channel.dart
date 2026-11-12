// The native gRPC channel of the Firestore client. Needs `dart:io`: only the
// io side of the transport may import this file.

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;

import 'keep_alive_transport.dart';

/// How often a keepalive ping is sent while there are active calls.
///
/// The Android SDK configures `ManagedChannelBuilder.keepAliveTime(30,
/// SECONDS)` "to ensure gRPC recovers from a dead connection (not typically
/// necessary, as the OS will usually notify gRPC when a connection dies, but
/// not always)". grpc-java defaults are kept for the other two settings, they
/// are also the defaults of grpc-dart: a 20 s ping timeout and no pings
/// without active calls (Firestore keeps the Listen stream open while it has
/// listeners and closes idle streams itself after one minute).
const Duration defaultKeepAlivePingInterval = Duration(seconds: 30);

/// How long to wait for the answer to a keepalive ping before the connection
/// is considered dead and shut down.
const Duration defaultKeepAliveTimeout = Duration(seconds: 20);

/// How long a connection attempt may take. The Android SDK resets the channel
/// when it stays in CONNECTING for 15 s instead of waiting for gRPC's own
/// timeout of several minutes.
const Duration defaultConnectTimeout = Duration(seconds: 15);

/// The options of the gRPC channel that talks to the backend.
ChannelOptions grpcChannelOptions({required bool sslEnabled}) {
  return ChannelOptions(
    credentials: sslEnabled
        ? const ChannelCredentials.secure()
        : const ChannelCredentials.insecure(),
    connectTimeout: defaultConnectTimeout,
  );
}

/// Creates the gRPC channel that talks to the backend, with keepalive pings
/// (see [KeepAliveTransportConnector]).
///
/// [keepAlivePingInterval] and [keepAliveTimeout] can be overridden for tests.
ClientChannelBase createGrpcChannel({
  required String host,
  required int port,
  required bool sslEnabled,
  Duration keepAlivePingInterval = defaultKeepAlivePingInterval,
  Duration keepAliveTimeout = defaultKeepAliveTimeout,
}) {
  final ChannelOptions options = grpcChannelOptions(sslEnabled: sslEnabled);
  return ClientTransportConnectorChannel(
    KeepAliveTransportConnector(
      host: host,
      port: port,
      credentials: options.credentials,
      pingInterval: keepAlivePingInterval,
      pingTimeout: keepAliveTimeout,
      connectTimeout: options.connectTimeout,
    ),
    options: options,
  );
}
