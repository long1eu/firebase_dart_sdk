// A transport that only knows the unary and server-streaming RPCs, over the
// REST/JSON endpoints: what Firestore Lite needs on platforms without sockets.
// It leaves WebChannel (Listen and Write) out of the program. Platform
// neutral: the HTTP layer is injected.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/proto3_json.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:protobuf/protobuf.dart';

/// A [FirestoreTransport] for the RPCs that REST can carry. Messages are
/// exchanged as proto3 JSON. A client-streaming RPC (Listen, Write) fails with
/// UNIMPLEMENTED.
class RestTransport implements FirestoreTransport {
  RestTransport(
    this._http,
    DatabaseInfo databaseInfo,
    this._options, {
    Duration timeout = RestClient.defaultTimeout,
  }) : _baseUrl =
           '${databaseInfo.sslEnabled ? 'https' : 'http'}://'
           '${databaseInfo.host}:${databaseInfo.port}' {
    checkProto3JsonNames();
    _rest = RestClient(_http, _baseUrl, timeout: timeout);
  }

  /// Proto3 JSON is built from the field and enum names of the generated
  /// messages. An application compiled with
  /// `-Dprotobuf.omit_field_names=true` or `-Dprotobuf.omit_enum_names=true`
  /// has no names, and every request would be silently wrong. Fails with a
  /// clear error instead.
  static void checkProto3JsonNames({
    Object? Function()? encodeRequest,
    Object? Function()? encodeEnum,
  }) {
    final Object? request =
        (encodeRequest ??
        () => (proto.CommitRequest()..database = 'd').toProto3Json())();
    final Object? order =
        (encodeEnum ??
        () =>
            (proto.StructuredQuery_Order()
                  ..direction = proto.StructuredQuery_Direction.DESCENDING)
                .toProto3Json())();
    final bool fieldNames = request is Map && request['database'] == 'd';
    final bool enumNames = order is Map && order['direction'] == 'DESCENDING';
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
  late final RestClient _rest;

  final Set<_RestCall> _calls = <_RestCall>{};
  bool _shutdown = false;

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    final StreamController<Res> responses = StreamController<Res>();
    final _RestCall call = _RestCall();
    _calls.add(call);
    call.done.then((_) => _calls.remove(call));
    responses.onCancel = call.cancel;

    if (_shutdown) {
      responses
        ..addError(const GrpcError.unavailable('The transport is shut down'))
        ..close();
      call.finish();
    } else if (rpc.clientStreaming || !RestClient.supports(rpc.name)) {
      responses
        ..addError(
          GrpcError.unimplemented(
            '${rpc.name} is not available over the REST transport',
          ),
        )
        ..close();
      call.finish();
    } else {
      unawaited(_run(rpc, requests, options, call, responses));
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

  Future<void> _run<Req extends GeneratedMessage, Res extends GeneratedMessage>(
    FirestoreRpc<Req, Res> rpc,
    Stream<Req> requests,
    CallOptions? options,
    _RestCall call,
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
        _restoreNullValues(result);
        responses.add(
          rpc.newResponse()
            ..mergeFromProto3Json(result, ignoreUnknownFields: true),
        );
      }
    } catch (e, s) {
      if (!call.isCancelled) {
        responses.addError(
          e is GrpcError ? e : GrpcError.unknown(e.toString()),
          s,
        );
      }
    } finally {
      call.finish();
      if (!responses.isClosed) {
        unawaited(responses.close());
      }
    }
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

  @override
  Future<void> shutdown() async {
    _shutdown = true;
    for (final _RestCall call in _calls.toList()) {
      await call.cancel();
    }
    _http.close();
  }
}

/// The handle of a call: the way to cancel it. REST has no headers or trailers
/// worth reporting.
class _RestCall implements Response {
  final Completer<void> _done = Completer<void>();

  bool isCancelled = false;
  void Function()? onCancel;

  Future<void> get done => _done.future;

  /// The call is over, whatever the reason.
  void finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<Map<String, String>> get headers =>
      _done.future.then((_) => const <String, String>{});

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
