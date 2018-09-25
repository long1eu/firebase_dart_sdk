// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/version.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/firestore_call_credentials.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/incoming_stream_observer.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';
import 'package:grpc/grpc.dart';

/// Wrapper class around io.grpc.Channel that adds headers, exception handling
/// and simplifies invoking RPCs.
class FirestoreChannel {
  static final String X_GOOG_API_CLIENT_HEADER = 'x-goog-api-client';

  static final String RESOURCE_PREFIX_HEADER = 'google-cloud-resource-prefix';

  // TODO: The gRPC version is determined using a package manifest, which is
  // not available to us at build time or runtime (it's empty when building in
  // google3). So for now we omit the version of grpc.
  static final String X_GOOG_API_CLIENT_VALUE =
      'gl-dart/ fire/${Version.sdkVersion} grpc/';

  final CredentialsProvider _credentialsProvider;

  /// The underlying gRPC channel.
  final ClientChannel _channel;

  /// Call options to be used when invoking RPCs.
  final CallOptions _callOptions;

  factory FirestoreChannel(CredentialsProvider credentialsProvider,
      ClientChannel channel, DatabaseId databaseId) {
    final CallOptions options = CallOptions(providers: [
      FirestoreCallCredentials(credentialsProvider).getRequestMetadata,
      (Map<String, String> map, String url) {
        map.addAll({
          X_GOOG_API_CLIENT_HEADER: X_GOOG_API_CLIENT_VALUE,
          // This header is used to improve routing and project isolation by the
          // backend.
          RESOURCE_PREFIX_HEADER:
              'projects/${databaseId.projectId}/databases/${databaseId.databaseId}',
        });
      }
    ]);

    return FirestoreChannel._(
      credentialsProvider,
      channel,
      options,
    );
  }

  FirestoreChannel._(
    this._credentialsProvider,
    this._channel,
    this._callOptions,
  );

  /// Creates and starts a new bi-directional streaming RPC.
  BidiChannel<ReqT, RespT> runBidiStreamingRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method,
      IncomingStreamObserver<RespT> observer) {
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call =
        _channel.createCall(method, controller.stream, _callOptions);

    call
      ..headers.then((Map<String, String> headers) {
        _catchError(() => observer.onHeaders(headers));
      })
      ..response.listen(
        (RespT data) => _catchError(() => observer.onNext(data)),
        onDone: () => _catchError(() => observer.onClose(GrpcError.ok())),
        onError: (dynamic e, StackTrace s) {
          return _catchError(() => observer.onClose(e as GrpcError));
        },
      );
    observer.onReady();

    return BidiChannel<ReqT, RespT>(controller, call);
  }

  /// Creates and starts a streaming response RPC.
  Future<List<RespT>> runStreamingResponseRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method, ReqT request) {
    final Completer<List<RespT>> completer = new Completer<List<RespT>>();
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call =
        _channel.createCall(method, controller.stream, _callOptions);

    final List<RespT> results = List<RespT>();

    call.response.listen(
      (RespT message) {
        results.add(message);
      },
      onDone: () {
        completer.complete(results);
      },
      onError: (GrpcError status) {
        completer.completeError(Util.exceptionFromStatus(status));
      },
    );

    controller.add(request);

    return completer.future;
  }

  /// Creates and starts a single response RPC.
  Future<RespT> runRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method, ReqT request) {
    final Completer<RespT> completer = Completer<RespT>();
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call =
        _channel.createCall(method, controller.stream, _callOptions);

    call.response.listen(
      (RespT message) {
        completer.complete(message);
        call.cancel();
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(new FirebaseFirestoreError(
              'Received onClose with status OK, but no message.',
              FirebaseFirestoreErrorCode.internal));
        }
      },
      onError: (GrpcError status) {
        completer.completeError(Util.exceptionFromStatus(status));
      },
    );

    controller.add(request);
    return completer.future.then((_) => call.cancel());
  }

  void invalidateToken() => _credentialsProvider.invalidateToken();

  static _catchError(Function function) {
    try {
      function();
    } catch (t) {
      AsyncQueue.panic(t);
    }
  }
}

class BidiChannel<ReqT, RespT> {
  final Sink<ReqT> _sink;
  final ClientCall<ReqT, RespT> _call;

  BidiChannel(this._sink, this._call);

  void add(ReqT data) => _sink.add(data);

  void listen(
    void onData(RespT event), {
    Function onError,
    void onDone(),
    bool cancelOnError,
  }) {
    _call.response.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<void> cancel() async {
    await _call.cancel();
    await _sink.close();
  }
}
