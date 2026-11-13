// Test-only proxies in front of a Firestore emulator that record the credentials of every request (the
// `authorization` and `x-firebase-appcheck` headers) and can refuse a request with UNAUTHENTICATED, the way the
// production backend refuses an expired ID token or an App Check token it does not accept. The emulator itself does
// neither: it accepts any well-formed (even expired) ID token and ignores App Check.
//
// * [GrpcCredentialsProxy] is a gRPC server that forwards every Firestore RPC, as raw bytes, to the emulator.
// * [HttpCredentialsProxy] is an HTTP/1.1 reverse proxy for the web transport: REST requests carry the credentials
//   as HTTP headers, the WebChannel handshake carries them in its form body (`headers=`), like the JS SDK.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';

/// A request that carried credentials, as the proxy saw it.
class RecordedRequest {
  RecordedRequest(this.transport, this.method, this.headers, this.rejection);

  /// `grpc`, `rest` or `webchannel`.
  final String transport;

  /// The RPC: `Listen`, `Write`, `Commit`, `BatchGetDocuments`, ...
  final String method;

  /// The request headers, with lower case names.
  final Map<String, String> headers;

  /// Why the proxy refused the request, or null when it was forwarded.
  final String? rejection;

  String? get appCheck => headers['x-firebase-appcheck'];

  String? get authorization => headers['authorization'];

  bool get rejected => rejection != null;

  @override
  String toString() =>
      '$transport $method appCheck=$appCheck auth=${authorization == null ? null : '${authorization!.substring(0, authorization!.length.clamp(0, 16))}...'}'
      '${rejected ? ' REJECTED' : ''}';
}

/// Decides whether a request is refused: returns the message of the UNAUTHENTICATED error, or null to forward it.
typedef CredentialsCheck = String? Function(Map<String, String> headers);

mixin _Recording {
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Applied to every request that carries credentials. Null forwards everything.
  CredentialsCheck? check;

  String? _record(String transport, String method, Map<String, String> raw) {
    final Map<String, String> headers = <String, String>{
      for (final MapEntry<String, String> e in raw.entries)
        e.key.toLowerCase(): e.value,
    };
    final String? rejection = check?.call(headers);
    requests.add(RecordedRequest(transport, method, headers, rejection));
    return rejection;
  }

  List<RecordedRequest> get accepted =>
      requests.where((RecordedRequest r) => !r.rejected).toList();

  List<RecordedRequest> get rejected =>
      requests.where((RecordedRequest r) => r.rejected).toList();
}

/// The methods of `google.firestore.v1.Firestore`.
const List<String> firestoreMethods = <String>[
  'GetDocument',
  'ListDocuments',
  'UpdateDocument',
  'DeleteDocument',
  'BatchGetDocuments',
  'BeginTransaction',
  'Commit',
  'Rollback',
  'RunQuery',
  'ExecutePipeline',
  'RunAggregationQuery',
  'PartitionQuery',
  'Write',
  'Listen',
  'ListCollectionIds',
  'BatchWrite',
  'CreateDocument',
];

List<int> _identity(List<int> bytes) => bytes;

class _RawClient extends Client {
  _RawClient(super.channel);

  ResponseStream<List<int>> call(
    String method,
    Stream<List<int>> requests,
    Map<String, String> metadata,
  ) => $createStreamingCall(
    ClientMethod<List<int>, List<int>>(
      '/google.firestore.v1.Firestore/$method',
      _identity,
      _identity,
    ),
    requests,
    options: CallOptions(metadata: metadata),
  );
}

class _ForwardingService extends Service {
  _ForwardingService(GrpcCredentialsProxy proxy) {
    for (final String method in firestoreMethods) {
      // Every method is declared streaming in both directions: the frames on the wire are the same, and the
      // client of a unary RPC simply sends and receives one message.
      $addMethod(
        ServiceMethod<List<int>, List<int>>(
          method,
          (ServiceCall call, Stream<List<int>> requests) =>
              proxy._forward(method, call, requests),
          true,
          true,
          _identity,
          _identity,
        ),
      );
    }
  }

  @override
  String get $name => 'google.firestore.v1.Firestore';
}

/// A gRPC proxy (plaintext HTTP/2) in front of the emulator at [upstreamHost]:[upstreamPort].
class GrpcCredentialsProxy with _Recording {
  GrpcCredentialsProxy._(this._channel) : _client = _RawClient(_channel);

  static Future<GrpcCredentialsProxy> start(
    String upstreamHost,
    int upstreamPort,
  ) async {
    final GrpcCredentialsProxy proxy = GrpcCredentialsProxy._(
      ClientChannel(
        upstreamHost,
        port: upstreamPort,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      ),
    );
    proxy._server = Server.create(
      services: <Service>[_ForwardingService(proxy)],
    );
    // The gRPC server of package:grpc adds the next message of a client stream to the request stream even after
    // the handler refused the call ("Cannot add event after closing", uncaught, in the zone of `serve`). The client
    // just sees the refusal; only that error is ignored.
    final Completer<void> serving = Completer<void>();
    runZonedGuarded(
      () => proxy._server
          .serve(address: InternetAddress.loopbackIPv4, port: 0)
          .then(serving.complete, onError: serving.completeError),
      (Object error, StackTrace stackTrace) {
        if (error is StateError &&
            error.message == 'Cannot add event after closing') {
          return;
        }
        proxy.serverErrors.add(error);
      },
    );
    await serving.future;
    return proxy;
  }

  final ClientChannel _channel;
  final _RawClient _client;

  /// Other uncaught errors of the server; a test checks that there are none.
  final List<Object> serverErrors = <Object>[];
  late final Server _server;

  String get host => InternetAddress.loopbackIPv4.address;

  int get port => _server.port!;

  static bool _isTransportHeader(String name) =>
      name.startsWith(':') ||
      name == 'content-type' ||
      name == 'te' ||
      name == 'user-agent' ||
      name.startsWith('grpc-');

  Stream<List<int>> _forward(
    String method,
    ServiceCall call,
    Stream<List<int>> requests,
  ) {
    final Map<String, String> metadata = <String, String>{
      for (final MapEntry<String, String> e
          in (call.clientMetadata ?? const <String, String>{}).entries)
        if (!_isTransportHeader(e.key)) e.key: e.value,
    };
    final String? rejection = _record('grpc', method, metadata);
    if (rejection != null) {
      return Stream<List<int>>.error(GrpcError.unauthenticated(rejection));
    }
    return _client.call(method, requests, metadata);
  }

  Future<void> close() async {
    await _server.shutdown();
    await _channel.terminate();
  }
}

/// An HTTP/1.1 reverse proxy for the REST and WebChannel transports, in front of the emulator at
/// [upstreamHost]:[upstreamPort].
class HttpCredentialsProxy with _Recording {
  HttpCredentialsProxy._(this._server, this._upstreamHost, this._upstreamPort);

  static Future<HttpCredentialsProxy> start(
    String upstreamHost,
    int upstreamPort,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final HttpCredentialsProxy proxy = HttpCredentialsProxy._(
      server,
      upstreamHost,
      upstreamPort,
    );
    server.listen((HttpRequest request) {
      unawaited(
        proxy._handle(request).catchError((Object _) {
          // The client went away (an aborted long poll): nothing to answer.
        }),
      );
    });
    return proxy;
  }

  final HttpServer _server;
  final String _upstreamHost;
  final int _upstreamPort;
  final HttpClient _client = HttpClient();

  String get host => InternetAddress.loopbackIPv4.address;

  int get port => _server.port;

  static const Set<String> _hopByHop = <String>{
    'host',
    'connection',
    'content-length',
    'transfer-encoding',
    'keep-alive',
  };

  /// `name:value\r\n` lines, the form in which the WebChannel handshake carries its headers.
  static Map<String, String> _headerLines(String text) {
    final Map<String, String> headers = <String, String>{};
    for (final String line in text.split('\r\n')) {
      final int colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon)] = line.substring(colon + 1);
      }
    }
    return headers;
  }

  Future<void> _handle(HttpRequest request) async {
    final List<int> body = await request.fold<List<int>>(
      <int>[],
      (List<int> all, List<int> chunk) => all..addAll(chunk),
    );
    final String path = request.uri.path;
    String? rejection;
    if (path.endsWith('/channel')) {
      // WebChannel: only the handshake (no SID yet) carries the credentials, in its form body.
      if (request.method == 'POST' &&
          !request.uri.queryParameters.containsKey('SID')) {
        final Map<String, String> form = Uri.splitQueryString(
          utf8.decode(body),
        );
        final List<String> segments = request.uri.pathSegments;
        rejection = _record(
          'webchannel',
          segments[segments.length - 2],
          _headerLines(form['headers'] ?? ''),
        );
      }
    } else {
      final Map<String, String> headers = <String, String>{};
      request.headers.forEach((String name, List<String> values) {
        if (!_hopByHop.contains(name)) {
          headers[name] = values.join(', ');
        }
      });
      final String last = request.uri.pathSegments.last;
      final int colon = last.lastIndexOf(':');
      rejection = _record(
        'rest',
        // `documents:runAggregationQuery` is the RPC RunAggregationQuery.
        colon < 0
            ? request.method
            : '${last[colon + 1].toUpperCase()}${last.substring(colon + 2)}',
        headers,
      );
    }

    if (rejection != null) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': HttpStatus.unauthorized,
              'message': rejection,
              'status': 'UNAUTHENTICATED',
            },
          }),
        );
      await request.response.close();
      return;
    }

    final HttpClientRequest upstream = await _client.openUrl(
      request.method,
      Uri(
        scheme: 'http',
        host: _upstreamHost,
        port: _upstreamPort,
        path: path,
        query: request.uri.hasQuery ? request.uri.query : null,
      ),
    );
    upstream.persistentConnection = false;
    request.headers.forEach((String name, List<String> values) {
      if (!_hopByHop.contains(name)) {
        upstream.headers.set(name, values);
      }
    });
    upstream.contentLength = body.length;
    upstream.add(body);
    final HttpClientResponse response = await upstream.close();
    request.response.statusCode = response.statusCode;
    response.headers.forEach((String name, List<String> values) {
      if (!_hopByHop.contains(name)) {
        request.response.headers.set(name, values);
      }
    });
    // Each chunk of a WebChannel back channel must reach the client when it arrives.
    request.response.bufferOutput = false;
    try {
      await request.response.addStream(response);
    } finally {
      await request.response.close();
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    _client.close(force: true);
  }
}
