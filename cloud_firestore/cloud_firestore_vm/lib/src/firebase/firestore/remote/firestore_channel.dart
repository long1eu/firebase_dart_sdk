// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:async';
import 'dart:io';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/firebase_client_grpc_metadata_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/firestore_call_credentials.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/incoming_stream_observer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

/// Wrapper class around io.grpc.Channel that adds headers, exception handling and simplifies invoking RPCs.
class FirestoreChannel {
  factory FirestoreChannel({
    @required AsyncQueue asyncQueue,
    @required CredentialsProvider credentialsProvider,
    @required ClientChannel channel,
    @required DatabaseId databaseId,
    @required GrpcMetadataProvider metadataProvider,
  }) {
    final CallOptions options = CallOptions(
      providers: <MetadataProvider>[
        FirestoreCallCredentials(credentialsProvider).getRequestMetadata,
        (Map<String, String> map, String url) => metadataProvider?.call(map),
        (Map<String, String> map, String url) {
          map.addAll(<String, String>{
            _xGoogApiClientHeader: _xGoogApiClientValue,
            // This header is used to improve routing and project isolation by the backend.
            _resourcePrefixHeader: 'projects/${databaseId.projectId}/databases/${databaseId.databaseId}',
          });
        }
      ],
    );

    return FirestoreChannel._(asyncQueue, credentialsProvider, channel, options);
  }

  FirestoreChannel._(this.asyncQueue, this._credentialsProvider, this._channel, this._callOptions);

  static const String _xGoogApiClientHeader = 'x-goog-api-client';

  static const String _resourcePrefixHeader = 'google-cloud-resource-prefix';

  static final String _xGoogApiClientValue =
      'gl-dart/${kIsWeb ? 'js' : Platform.version} fire/${Version.sdkVersion} grpc/${Version.grpcVersion}';

  /// The async worker queue that is used to dispatch events.
  final AsyncQueue asyncQueue;

  final CredentialsProvider _credentialsProvider;

  /// The underlying gRPC channel.
  final ClientChannel _channel;

  /// Call options to be used when invoking RPCs.
  final CallOptions _callOptions;

  /// Shuts down the grpc channel. This is not reversible and renders the FirestoreChannel unusable.
  Future<void> shutdown() async {
    try {
      await _channel.shutdown().timeout(const Duration(seconds: 1));
    } on TimeoutException catch (_) {
      Log.d('FirestoreChannel',
          'Unable to gracefully shutdown the gRPC ManagedChannel. Will attempt an immediate shutdown.');
      try {
        await _channel.terminate().timeout(const Duration(minutes: 1));
      } on TimeoutException catch (_) {
        // Something bad has happened. We could assert, but this is just resource cleanup for a resource that is likely
        // only released at the end of the execution. So instead, we'll just log the error.
        Log.w('FirestoreChannel', 'Unable to forcefully shutdown the gRPC ManagedChannel.');
      }
    } catch (e) {
      // (Re-)Cancel if current thread also interrupted
      await _channel.terminate();
      // Similar to above, something bad happened, but it's not worth asserting. Just log it.
      Log.w('FirestoreChannel', 'Interrupted while shutting down the gRPC Managed Channel');
    }
  }

  /// Creates and starts a new bi-directional streaming RPC.
  BidiChannel<ReqT, RespT> runBidiStreamingRpc<ReqT, RespT>(
      ClientMethod<ReqT, RespT> method, IncomingStreamObserver<RespT> observer) {
    // ignore: close_sinks
    final StreamController<ReqT> controller = StreamController<ReqT>();

    final ClientCall<ReqT, RespT> call = _channel.createCall(method, controller.stream, _callOptions)
      ..headers.then((Map<String, String> headers) {
        _catchError(() => observer.onHeaders(headers));
      })
      ..response.listen(
        (RespT data) => _catchError(() => observer.onNext(data)),
        onDone: () => _catchError(() => observer.onClose(GrpcError.ok())),
        onError: (dynamic e, StackTrace s) {
          return _catchError(() => observer.onClose(e));
        },
      );

    observer.onOpen();

    return BidiChannel<ReqT, RespT>(controller, call);
  }

  /// Creates and starts a streaming response RPC.
  Future<List<RespT>> runStreamingResponseRpc<ReqT, RespT>(ClientMethod<ReqT, RespT> method, ReqT request) async {
    final Completer<List<RespT>> completer = Completer<List<RespT>>();
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call = _channel.createCall(method, controller.stream, _callOptions);

    bool hadError = false;
    final List<RespT> results = <RespT>[];
    call.response.listen(
      results.add,
      onDone: () {
        assert((hadError && completer.isCompleted) || !hadError && !completer.isCompleted);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
        controller.close();
      },
      onError: (dynamic status) {
        hadError = true;
        controller.close();
        completer.completeError(exceptionFromStatus(status));
      },
    );

    controller.add(request);
    await controller.close();

    return completer.future;
  }

  /// Creates and starts a single response RPC.
  Future<RespT> runRpc<ReqT, RespT>(ClientMethod<ReqT, RespT> method, ReqT request) async {
    final Completer<RespT> completer = Completer<RespT>();
    final StreamController<ReqT> controller = StreamController<ReqT>();
    final ClientCall<ReqT, RespT> call = _channel.createCall(method, controller.stream, _callOptions);

    call.response.listen(
      (RespT message) {
        completer.complete(message);
        controller.close();
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
              FirestoreError('Received onClose with status OK, but no message.', FirestoreErrorCode.internal));
        }
      },
      onError: (dynamic status) {
        controller.close();
        completer.completeError(exceptionFromStatus(status));
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
  const BidiChannel(this._sink, this._call);

  final Sink<ReqT> _sink;
  final ClientCall<ReqT, RespT> _call;

  void add(ReqT data) => _sink.add(data);

  void listen(void Function(RespT event) onData, {Function onError, void Function() onDone, bool cancelOnError}) {
    _call.response.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  void cancel() => _sink.close();
}
