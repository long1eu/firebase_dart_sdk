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
  static const String _xGoogApiClientHeader = 'x-goog-api-client';

  static const String _resourcePrefixHeader = 'google-cloud-resource-prefix';

  static const String _xGoogApiClientValue =
      'gl-dart/ fire/${Version.sdkVersion} grpc/${Version.grpcVersion}';

  /// The async worker queue that is used to dispatch events.
  final AsyncQueue asyncQueue;

  final CredentialsProvider _credentialsProvider;

  /// The underlying gRPC channel.
  final ClientChannel _channel;

  /// Call options to be used when invoking RPCs.
  final CallOptions _callOptions;

  factory FirestoreChannel(
      AsyncQueue asyncQueue,
      CredentialsProvider credentialsProvider,
      ClientChannel channel,
      DatabaseId databaseId) {
    final CallOptions options = CallOptions(providers: <MetadataProvider>[
      FirestoreCallCredentials(credentialsProvider).getRequestMetadata,
      (Map<String, String> map, String url) {
        map.addAll(<String, String>{
          _xGoogApiClientHeader: _xGoogApiClientValue,
          // This header is used to improve routing and project isolation by the
          // backend.
          _resourcePrefixHeader:
              'projects/${databaseId.projectId}/databases/${databaseId.databaseId}',
        });
      }
    ]);

    return FirestoreChannel._(
      asyncQueue,
      credentialsProvider,
      channel,
      options,
    );
  }

  FirestoreChannel._(
    this.asyncQueue,
    this._credentialsProvider,
    this._channel,
    this._callOptions,
  );

  /// Creates and starts a new bi-directional streaming RPC.
  BidiChannel<ReqT, RespT> runBidiStreamingRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method,
      IncomingStreamObserver<RespT> observer) {
    // ignore: close_sinks
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

    return BidiChannel<ReqT, RespT>(
        controller, call, () => _channel.terminate());
  }

  /// Creates and starts a streaming response RPC.
  Future<List<RespT>> runStreamingResponseRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method, ReqT request) async {
    final Completer<List<RespT>> completer = Completer<List<RespT>>();
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call =
        _channel.createCall(method, controller.stream, _callOptions);

    bool hadError = false;
    final List<RespT> results = <RespT>[];
    call.response.listen(
      (RespT message) {
        results.add(message);
      },
      onDone: () {
        assert((hadError && completer.isCompleted) ||
            !hadError && !completer.isCompleted);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
        controller.close();
      },
      onError: (dynamic status) {
        hadError = true;
        controller.close();
        completer.completeError(Util.exceptionFromStatus(status as GrpcError));
      },
    );

    controller.add(request);
    await controller.close();

    return completer.future;
  }

  /// Creates and starts a single response RPC.
  Future<RespT> runRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method, ReqT request) async {
    final Completer<RespT> completer = Completer<RespT>();
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call =
        _channel.createCall(method, controller.stream, _callOptions);

    call.response.listen(
      (RespT message) {
        completer.complete(message);
        controller.close();
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(FirebaseFirestoreError(
              'Received onClose with status OK, but no message.',
              FirebaseFirestoreErrorCode.internal));
        }
      },
      onError: (dynamic status) {
        controller.close();
        completer.completeError(Util.exceptionFromStatus(status as GrpcError));
      },
    );

    controller.add(request);
    return completer.future;
  }

  void invalidateToken() => _credentialsProvider.invalidateToken();

  static void _catchError(Function function) {
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
  final Future<void> Function() onClose;

  BidiChannel(this._sink, this._call, this.onClose);

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
    _sink.close();
    await onClose();
  }
}
