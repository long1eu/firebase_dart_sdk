// The transport for platforms without sockets (browsers): REST/JSON for the
// unary and server-streaming RPCs and WebChannel for Listen and Write, like
// the JS SDK. Platform neutral: the HTTP layer is injected.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:protobuf/protobuf.dart';

/// A [FirestoreTransport] that only needs HTTP requests with streamed
/// responses. Messages are exchanged as proto3 JSON.
class WebChannelTransport implements FirestoreTransport {
  WebChannelTransport(this._http, DatabaseInfo databaseInfo, this._options)
    : _baseUrl =
          '${databaseInfo.sslEnabled ? 'https' : 'http'}://'
          '${databaseInfo.host}:${databaseInfo.port}',
      _database =
          'projects/${databaseInfo.databaseId.projectId}'
          '/databases/${databaseInfo.databaseId.databaseId}' {
    _rest = RestClient(_http, _baseUrl);
  }

  final WebHttpClient _http;
  final ChannelOptionsProvider _options;
  final String _baseUrl;
  final String _database;
  late final RestClient _rest;

  final Set<_WebCall> _calls = <_WebCall>{};
  bool _shutdown = false;

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    final StreamController<Res> responses = StreamController<Res>();
    final _WebCall call = _WebCall();
    _calls.add(call);
    call.done.then((_) => _calls.remove(call));
    responses.onCancel = call.cancel;

    if (_shutdown) {
      responses
        ..addError(const GrpcError.unavailable('The transport is shut down'))
        ..close();
      call.finish();
    } else if (rpc.clientStreaming) {
      unawaited(_runStream(rpc, requests, options, call, responses));
    } else {
      unawaited(_runUnary(rpc, requests, options, call, responses));
    }
    return ResponseStream<Res>(call, responses.stream);
  }

  /// The request headers: credentials and routing, from the same metadata
  /// providers the gRPC transport uses.
  Future<Map<String, String>> _headers(CallOptions? options) async {
    final CallOptions merged = _options.callOptions.mergedWith(options);
    final Map<String, String> headers = <String, String>{};
    for (final MetadataProvider provider in merged.metadataProviders) {
      await provider(headers, _baseUrl);
    }
    return headers;
  }

  Future<void>
  _runUnary<Req extends GeneratedMessage, Res extends GeneratedMessage>(
    FirestoreRpc<Req, Res> rpc,
    Stream<Req> requests,
    CallOptions? options,
    _WebCall call,
    StreamController<Res> responses,
  ) async {
    try {
      final Req request = await requests.first;
      final Map<String, String> headers = await _headers(options);
      if (call.isCancelled) {
        return;
      }
      final List<Object?> results = await _rest.invoke(
        rpc.name,
        (request.toProto3Json()! as Map<Object?, Object?>)
            .cast<String, Object?>(),
        headers,
        onRequest: (WebHttpRequest http) => call.onCancel = http.abort,
      );
      for (final Object? result in results) {
        if (call.isCancelled) {
          return;
        }
        responses.add(_decode(rpc, result));
      }
    } catch (e, s) {
      if (!call.isCancelled) {
        responses.addError(_asGrpcError(e), s);
      }
    } finally {
      call.finish();
      if (!responses.isClosed) {
        unawaited(responses.close());
      }
    }
  }

  Future<void>
  _runStream<Req extends GeneratedMessage, Res extends GeneratedMessage>(
    FirestoreRpc<Req, Res> rpc,
    Stream<Req> requests,
    CallOptions? options,
    _WebCall call,
    StreamController<Res> responses,
  ) async {
    final Map<String, String> headers;
    try {
      headers = await _headers(options);
    } catch (e, s) {
      if (!call.isCancelled) {
        responses.addError(_asGrpcError(e), s);
        unawaited(responses.close());
      }
      call.finish();
      return;
    }
    if (call.isCancelled) {
      return;
    }

    final WebChannelStream channel = WebChannelStream(
      _http,
      '$_baseUrl${rpc.path}/channel',
      _database,
      headers,
    );
    late final StreamSubscription<Req> requestSub;
    call.onCancel = () {
      unawaited(requestSub.cancel());
      unawaited(channel.close());
    };
    unawaited(channel.handshakeHeaders.then(call.completeHeaders));

    channel.messages.listen(
      (Map<String, Object?> message) {
        final Res response;
        try {
          response = _decode(rpc, message);
        } catch (e, s) {
          responses.addError(
            GrpcError.internal('Malformed ${rpc.name} response: $e'),
            s,
          );
          call.cancel();
          return;
        }
        responses.add(response);
      },
      onError: (Object e, StackTrace s) {
        if (!responses.isClosed) {
          responses.addError(_asGrpcError(e), s);
        }
      },
      onDone: () {
        unawaited(requestSub.cancel());
        call.finish();
        if (!responses.isClosed) {
          unawaited(responses.close());
        }
      },
    );

    requestSub = requests.listen(
      (Req request) => channel.send(jsonEncode(request.toProto3Json())),
      // The client is done with the stream (it half-closes a gRPC call the same way): end the session, otherwise it
      // stays open, with its long poll, until the call is cancelled.
      onDone: channel.closeWhenFlushed,
    );
  }

  static Res _decode<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Object? json) {
    if (json is Map) {
      // `google.rpc.Status.details` holds `Any` messages, which proto3 JSON can
      // only decode with a registry of every possible type. The client never
      // reads them.
      final Object? targetChange = json['targetChange'];
      if (targetChange is Map && targetChange['cause'] is Map) {
        (targetChange['cause'] as Map<Object?, Object?>).remove('details');
      }
    }
    _restoreNullValues(json);
    return rpc.newResponse()
      ..mergeFromProto3Json(json, ignoreUnknownFields: true);
  }

  /// Proto3 JSON writes the null of a Firestore value as `{"nullValue":
  /// null}`, and a JSON null means "field not set" to the decoder: the value
  /// would come out empty. Spell it as the enum name instead.
  static void _restoreNullValues(Object? json) {
    if (json is Map) {
      if (json.containsKey('nullValue') && json['nullValue'] == null) {
        json['nullValue'] = 'NULL_VALUE';
      }
      json.values.forEach(_restoreNullValues);
    } else if (json is List) {
      json.forEach(_restoreNullValues);
    }
  }

  static GrpcError _asGrpcError(Object error) =>
      error is GrpcError ? error : GrpcError.unknown(error.toString());

  @override
  Future<void> shutdown() async {
    _shutdown = true;
    for (final _WebCall call in _calls.toList()) {
      await call.cancel();
    }
    _http.close();
  }
}

/// The handle of a call: its response headers and the way to cancel it.
class _WebCall implements Response {
  final Completer<Map<String, String>> _headers =
      Completer<Map<String, String>>();
  final Completer<void> _done = Completer<void>();

  bool isCancelled = false;
  void Function()? onCancel;

  Future<void> get done => _done.future;

  void completeHeaders(Map<String, String> headers) {
    if (!_headers.isCompleted) {
      _headers.complete(headers);
    }
  }

  /// The call is over, whatever the reason.
  void finish() {
    completeHeaders(const <String, String>{});
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<Map<String, String>> get headers => _headers.future;

  @override
  Future<Map<String, String>> get trailers =>
      _done.future.then((_) => const <String, String>{});

  @override
  Future<void> cancel() async {
    if (isCancelled) {
      return;
    }
    isCancelled = true;
    onCancel?.call();
    finish();
  }
}
