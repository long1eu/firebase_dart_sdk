// The transport for platforms without sockets (browsers): REST/JSON for the
// unary and server-streaming RPCs and WebChannel for Listen and Write, like
// the JS SDK. Platform neutral: the HTTP layer is injected.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/proto3_json.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/write_send_ahead.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';

/// A [FirestoreTransport] that only needs HTTP requests with streamed
/// responses. Messages are exchanged as proto3 JSON.
class WebChannelTransport implements FirestoreTransport {
  WebChannelTransport(
    this._http,
    DatabaseInfo databaseInfo,
    this._options, {
    Duration unaryTimeout = RestClient.defaultTimeout,
    this.longPollingDetectionTimeout = const Duration(seconds: 10),
  }) : _forceLongPolling = databaseInfo.forceLongPolling,
       _autoDetectLongPolling = databaseInfo.autoDetectLongPolling,
       _baseUrl =
           '${databaseInfo.sslEnabled ? 'https' : 'http'}://'
           '${databaseInfo.host}:${databaseInfo.port}',
       _database =
           'projects/${databaseInfo.databaseId.projectId}'
           '/databases/${databaseInfo.databaseId.databaseId}' {
    checkProto3JsonNames();
    _rest = RestClient(
      _http,
      _baseUrl,
      timeout: unaryTimeout,
      apiKey: _options.apiKey,
    );
  }

  final bool _forceLongPolling;
  final bool _autoDetectLongPolling;

  /// See [WebChannelStream.longPollingDetectionTimeout].
  final Duration longPollingDetectionTimeout;

  /// The web transport exchanges proto3 JSON, which is built from the field
  /// and enum names of the generated messages. An application compiled with
  /// `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`
  /// has no names, and every request would be silently wrong. Fails with a
  /// clear error instead.
  static void checkProto3JsonNames({
    Object? Function()? encodeRequest,
    Object? Function()? encodeEnum,
  }) {
    final Object? request =
        (encodeRequest ??
        () => (proto.ListenRequest()..database = 'd').toProto3Json())();
    final Object? change =
        (encodeEnum ??
        () =>
            (proto.TargetChange()
                  ..targetChangeType =
                      proto.TargetChange_TargetChangeType.REMOVE)
                .toProto3Json())();
    final bool fieldNames = request is Map && request['database'] == 'd';
    final bool enumNames =
        change is Map && change['targetChangeType'] == 'REMOVE';
    if (!fieldNames || !enumNames) {
      throw UnsupportedError(
        'Cloud Firestore on the web needs the ${fieldNames ? 'enum' : 'field'} '
        'names of its protobuf messages to talk to the backend (proto3 JSON). '
        'Do not compile with -Dprotobuf.omit_field_names=true or '
        '-Dprotobuf.omit_enum_names=true.',
      );
    }
  }

  final WebHttpClient _http;
  final ChannelOptionsProvider _options;
  final String _baseUrl;
  final String _database;
  late final RestClient _rest;

  final Set<_WebCall> _calls = <_WebCall>{};

  /// The sessions that are not over on the server yet.
  final Set<WebChannelStream> _sessions = <WebChannelStream>{};
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

  /// The headers a stream sends with its handshake, from the request
  /// [metadata]: those of the JS SDK's WebChannelConnection
  /// (`modifyHeadersForRequest()`), the client, `Content-Type: text/plain`, the
  /// app id, the credentials and the API key. The routing headers are left
  /// out: JS sends them only with unary calls, a stream is routed by its
  /// `database` URL parameter.
  @visibleForTesting
  static Map<String, String> streamHeaders(Map<String, String> metadata) {
    return <String, String>{
      for (final MapEntry<String, String> header in metadata.entries)
        if (!_unaryOnlyHeaders.contains(header.key.toLowerCase()))
          header.key: header.value,
      'Content-Type': 'text/plain',
    };
  }

  static const Set<String> _unaryOnlyHeaders = <String>{
    'google-cloud-resource-prefix',
    'x-goog-request-params',
  };

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
        (toFirestoreProto3Json(request)! as Map<Object?, Object?>)
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
        if (call.shutDown) {
          // As over gRPC: the end of the stream alone would read as a
          // complete answer (a lookup without its documents, a commit
          // without a result).
          responses.addError(
            const GrpcError.unavailable('The transport is shut down'),
          );
        }
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
      streamHeaders(headers),
      forceLongPolling: _forceLongPolling,
      autoDetectLongPolling: _autoDetectLongPolling,
      longPollingDetectionTimeout: longPollingDetectionTimeout,
    );
    _sessions.add(channel);
    unawaited(channel.released.then((_) => _sessions.remove(channel)));
    late final StreamSubscription<Req> requestSub;
    call.onCancel = () {
      unawaited(requestSub.cancel());
      unawaited(channel.close());
    };
    unawaited(channel.handshakeHeaders.then(call.completeHeaders));

    // The Write RPC answers every request with one response. A write is sent
    // before the responses to the earlier ones arrived only when it can be
    // applied twice without harm, see [WriteSendAheadGate]: the backend may
    // apply writes that were sent ahead of a failed one, and the client sends
    // those again.
    final WriteSendAheadGate? gate = identical(rpc, FirestoreRpc.write)
        ? WriteSendAheadGate()
        : null;
    final Queue<Req> waiting = Queue<Req>();
    void sendNext() {
      while (waiting.isNotEmpty) {
        final Req request = waiting.first;
        if (gate != null) {
          final proto.WriteRequest write = request as proto.WriteRequest;
          if (!gate.canSend(write)) {
            return;
          }
          gate.sent(write);
        }
        waiting.removeFirst();
        channel.send(jsonEncode(toFirestoreProto3Json(request)));
      }
    }

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
        if (gate != null) {
          gate.responseReceived();
          sendNext();
        }
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
      (Req request) {
        waiting.add(request);
        sendNext();
      },
      // The client is done with the stream (the half-close of gRPC): deliver
      // what was queued and end the session, which also ends the responses.
      //
      // A gRPC call is not cancelled at this point, because resetting an HTTP/2
      // stream that the backend is finishing can break the whole connection
      // (see CallReleaser). There is no such hazard here: the session is a set
      // of independent HTTP requests, ending it is a request of its own, and
      // aborting the back channel request only concerns that one request,
      // whose connection handling belongs to the browser. Waiting for the
      // grace period of CallReleaser would only keep the back channel request
      // open, and a browser allows few connections per host over HTTP/1.1.
      onDone: () {
        // What was not sent stays with the caller (the writes are still in
        // its queue and go out on its next stream).
        waiting.clear();
        channel.closeWhenFlushed();
      },
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
      call.shutDown = true;
      await call.cancel();
    }
    // The sessions are terminated on the server before the HTTP client goes
    // away, see [WebChannelStream.released]. Each of them gives up by itself.
    await Future.wait(
      _sessions.map((WebChannelStream session) => session.released).toList(),
    );
    _http.close();
  }
}

/// The handle of a call: its response headers and the way to cancel it.
class _WebCall implements Response {
  final Completer<Map<String, String>> _headers =
      Completer<Map<String, String>>();
  final Completer<void> _done = Completer<void>();

  bool isCancelled = false;

  /// Whether the call was cancelled because the transport shut down, not by
  /// its caller.
  bool shutDown = false;
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
