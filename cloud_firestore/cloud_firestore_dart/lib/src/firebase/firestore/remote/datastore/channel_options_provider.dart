// File created by
// Lung Razvan <long1eu>
// on 01/12/2019

import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;

import '../firestore_call_credentials.dart';
import 'keep_alive_transport.dart';

/// Helper class to provide the headers that gRPC needs
class ChannelOptionsProvider {
  const ChannelOptionsProvider({
    required DatabaseId databaseId,
    required CredentialsProvider credentialsProvider,
    AppCheckTokenProvider? appCheckProvider,
  })  : _databaseId = databaseId,
        _credentialsProvider = credentialsProvider,
        _appCheckProvider = appCheckProvider;

  final DatabaseId _databaseId;
  final CredentialsProvider _credentialsProvider;
  final AppCheckTokenProvider? _appCheckProvider;

  CallOptions get callOptions {
    return CallOptions(
      providers: <MetadataProvider>[
        _callCredentials.getRequestMetadata,
        (Map<String, String> map, String url) {
          map['x-goog-api-client'] = _xGoogApiClientValue;
          // These headers are used to improve routing and project isolation by
          // the backend. The resource prefix header is kept until emulators
          // support x-goog-request-params (see upstream firebase-android-sdk
          // #3498).
          map['google-cloud-resource-prefix'] = _resourcePrefix;
          map['x-goog-request-params'] = _resourcePrefix;
        }
      ],
    );
  }

  void invalidateToken() {
    _credentialsProvider.invalidateToken();
    _appCheckProvider?.invalidateToken();
  }

  FirestoreCallCredentials get _callCredentials => FirestoreCallCredentials(
      _credentialsProvider,
      appCheckProvider: _appCheckProvider);

  /// How often a keepalive ping is sent while there are active calls.
  ///
  /// The Android SDK configures `ManagedChannelBuilder.keepAliveTime(30,
  /// SECONDS)` "to ensure gRPC recovers from a dead connection (not typically
  /// necessary, as the OS will usually notify gRPC when a connection dies, but
  /// not always)". grpc-java defaults are kept for the other two settings, they
  /// are also the defaults of grpc-dart: a 20 s ping timeout and no pings
  /// without active calls (Firestore keeps the Listen stream open while it has
  /// listeners and closes idle streams itself after one minute).
  static const Duration defaultKeepAlivePingInterval = Duration(seconds: 30);

  /// How long to wait for the answer to a keepalive ping before the connection
  /// is considered dead and shut down.
  static const Duration defaultKeepAliveTimeout = Duration(seconds: 20);

  /// How long a connection attempt may take. The Android SDK resets the channel
  /// when it stays in CONNECTING for 15 s instead of waiting for gRPC's own
  /// timeout of several minutes.
  static const Duration defaultConnectTimeout = Duration(seconds: 15);

  /// The options of the gRPC channel that talks to the backend.
  static ChannelOptions channelOptions({required bool sslEnabled}) {
    return ChannelOptions(
      credentials: sslEnabled
          ? const ChannelCredentials.secure()
          : const ChannelCredentials.insecure(),
      connectTimeout: defaultConnectTimeout,
    );
  }

  /// Creates the gRPC channel that talks to the backend, with keepalive
  /// pings (see [KeepAliveTransportConnector]).
  ///
  /// [keepAlivePingInterval] and [keepAliveTimeout] can be overridden for
  /// tests.
  static ClientChannelBase createChannel({
    required String host,
    required int port,
    required bool sslEnabled,
    Duration keepAlivePingInterval = defaultKeepAlivePingInterval,
    Duration keepAliveTimeout = defaultKeepAliveTimeout,
  }) {
    final ChannelOptions options = channelOptions(sslEnabled: sslEnabled);
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

  // This header is used to improve routing and project isolation by the backend.
  String get _resourcePrefix =>
      'projects/${_databaseId.projectId}/databases/${_databaseId.databaseId}';

  static final String _xGoogApiClientValue =
      'gl-dart/${Platform.version} fire/${Version.sdkVersion} grpc/${Version.grpcVersion}';
}
