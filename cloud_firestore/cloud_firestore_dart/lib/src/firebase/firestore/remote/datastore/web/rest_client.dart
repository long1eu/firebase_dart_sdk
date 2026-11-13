// The unary and server-streaming RPCs of Firestore over its REST/JSON
// endpoints, as the JS SDK calls them from browsers
// (packages/firestore/src/remote/rest_connection.ts).

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rpc_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';

/// Calls the REST endpoints of the Firestore service.
class RestClient {
  RestClient(
    this._http,
    this._baseUrl, {
    this.timeout = defaultTimeout,
    this.apiKey,
  });

  /// Sent as the `key` query parameter of every call, as the JS SDK does.
  final String? apiKey;

  /// The time a call may take, as in the JS SDK (`XHR_TIMEOUT_SECS`).
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// How long a call may take before it is aborted and fails with
  /// DEADLINE_EXCEEDED, which the callers treat as a transient error.
  final Duration timeout;

  final WebHttpClient _http;

  /// Scheme, host and port, without a trailing slash.
  final String _baseUrl;

  static const Map<String, String> _verbs = <String, String>{
    'BatchGetDocuments': 'batchGet',
    'Commit': 'commit',
    'BeginTransaction': 'beginTransaction',
    'Rollback': 'rollback',
    'RunQuery': 'runQuery',
    'RunAggregationQuery': 'runAggregationQuery',
    'ExecutePipeline': 'executePipeline',
  };

  /// The field of the request that names the resource. REST takes it from the
  /// URL, the body must not repeat it.
  static const Map<String, String> _pathFields = <String, String>{
    'BatchGetDocuments': 'database',
    'Commit': 'database',
    'BeginTransaction': 'database',
    'Rollback': 'database',
    'RunQuery': 'parent',
    'RunAggregationQuery': 'parent',
    'ExecutePipeline': 'database',
  };

  /// Whether [rpcName] can be sent over REST.
  static bool supports(String rpcName) => _verbs.containsKey(rpcName);

  /// The URL of [rpcName] for the proto3 JSON [request] (which still carries
  /// its `database` or `parent` field).
  Uri urlFor(String rpcName, Map<String, Object?> request) {
    String resource = request[_pathFields[rpcName]]! as String;
    if (_pathFields[rpcName] == 'database') {
      resource = '$resource/documents';
    }
    final List<String> segments = resource.split('/');
    // `.` and `..` are not valid ids for the backend, but in a URL they are
    // dot segments, which the URL parser and the browser resolve: the request
    // would go to another resource (even another project) with the
    // credentials of this one. gRPC sends the name as data and the backend
    // rejects it; do the same here.
    for (final String segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw GrpcError.invalidArgument(
          'Invalid resource name for $rpcName: path segments must not be '
          'empty, "." or ".."',
        );
      }
    }
    final String path = segments.map(Uri.encodeComponent).join('/');
    final String? key = apiKey;
    final String query = key == null || key.isEmpty
        ? ''
        : '?key=${Uri.encodeQueryComponent(key)}';
    return Uri.parse('$_baseUrl/v1/$path:${_verbs[rpcName]}$query');
  }

  /// Sends [request] (proto3 JSON) and returns the responses (proto3 JSON):
  /// one for Commit, any number for the server-streaming RPCs, which REST
  /// returns as one JSON array once the call finished.
  ///
  /// Fails with a [GrpcError].
  Future<List<Object?>> invoke(
    String rpcName,
    Map<String, Object?> request,
    Map<String, String> headers, {
    void Function(WebHttpRequest request)? onRequest,
  }) async {
    final Uri url = urlFor(rpcName, request);
    final Map<String, Object?> body = Map<String, Object?>.of(request)
      ..remove(_pathFields[rpcName]);

    final WebHttpRequest call = _http.send(
      'POST',
      url,
      headers: <String, String>{
        ...headers,
        // Not application/json: text/plain keeps the request "simple" for
        // CORS when there are no other custom headers, like the JS SDK does.
        'Content-Type': 'text/plain',
      },
      body: jsonEncode(body),
    );
    onRequest?.call(call);

    bool timedOut = false;
    final Timer timer = Timer(timeout, () {
      timedOut = true;
      call.abort();
    });
    final WebHttpResponse response;
    final String text;
    try {
      response = await call.response;
      text = await response.readAll();
    } on GrpcError {
      call.abort();
      rethrow;
    } catch (e) {
      if (timedOut) {
        throw const GrpcError.deadlineExceeded('Request time out');
      }
      throw GrpcError.unavailable('Request failed with error: $e');
    } finally {
      timer.cancel();
    }
    if (timedOut) {
      // The abort ended the body without an error.
      throw const GrpcError.deadlineExceeded('Request time out');
    }

    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final Map<String, Object?>? error = findErrorJson(json);
      if (error != null) {
        final GrpcError parsed = grpcErrorFromJson(error);
        if (parsed.code != StatusCode.ok) {
          throw parsed;
        }
      }
      throw GrpcError.custom(
        codeFromHttpStatus(response.statusCode),
        'Request failed with HTTP status ${response.statusCode}',
      );
    }

    if (json is List) {
      // A streaming call that failed part way reports the error as an element.
      for (final Object? element in json) {
        if (element is Map && element['error'] is Map) {
          throw grpcErrorFromJson(
            (element['error'] as Map<Object?, Object?>).cast<String, Object?>(),
          );
        }
      }
      return json;
    }
    if (json is Map) {
      return <Object?>[json];
    }
    if (text.trim().isEmpty) {
      // An empty message (the answer to a rollback) may come without a body.
      return <Object?>[<String, Object?>{}];
    }
    throw const GrpcError.internal('Unexpected response body');
  }
}
