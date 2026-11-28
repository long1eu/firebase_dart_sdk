// The three Firebase services the adapter talks to, behind one streaming
// MockClient: Installations (create and token), the Remote Config fetch and
// the realtime stream, with enough of each for the tests of the mapping.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String installationsHost = 'firebaseinstallations.googleapis.com';
const String fetchHost = 'firebaseremoteconfig.googleapis.com';
const String realtimeHost = 'firebaseremoteconfigrealtime.googleapis.com';

/// One request as the backend received it.
class RecordedRequest {
  RecordedRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  String get host => url.host;

  /// The body decoded as a JSON object.
  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;

  /// The header [name], whatever its case.
  String? header(String name) {
    for (final MapEntry<String, String> entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }
}

class FakeBackend {
  FakeBackend() {
    client = MockClient.streaming(_handle);
  }

  late final http.Client client;

  /// Every request, in order.
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// The entries of the template the fetch answers with.
  Map<String, String> entries = <String, String>{};

  /// The version of that template.
  int templateVersion = 1;

  /// A status to answer the fetches with, instead of the template.
  int? fetchStatus;

  /// Makes the fetches fail before a response, as a lost connection does.
  bool fetchUnreachable = false;

  /// Makes the Installations requests fail before a response.
  bool installationsUnreachable = false;

  /// A status to answer the Installations requests with.
  int? installationsStatus;

  /// Completes the response of each fetch; null answers at once. A test sets
  /// it to hold a fetch past its timeout.
  Completer<void>? fetchGate;

  /// A status to answer the realtime requests with, instead of a stream.
  int? realtimeStatus;

  /// The text the realtime stream sends as soon as it opens; it then stays
  /// open until the client aborts it.
  String? realtimeFirstChunk;

  /// The realtime streams still open.
  final List<StreamController<List<int>>> openStreams =
      <StreamController<List<int>>>[];

  int _fids = 0;

  void reset() {
    requests.clear();
    entries = <String, String>{};
    templateVersion = 1;
    fetchStatus = null;
    fetchUnreachable = false;
    installationsUnreachable = false;
    installationsStatus = null;
    final Completer<void>? gate = fetchGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    fetchGate = null;
    realtimeStatus = null;
    realtimeFirstChunk = null;
    for (final StreamController<List<int>> stream in openStreams) {
      unawaited(stream.close());
    }
    openStreams.clear();
  }

  /// The requests sent to [host].
  List<RecordedRequest> to(String host) => <RecordedRequest>[
    for (final RecordedRequest request in requests)
      if (request.host == host) request,
  ];

  /// The fetch requests.
  List<RecordedRequest> get fetches => to(fetchHost);

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream bodyStream,
  ) async {
    final String body = utf8.decode(await bodyStream.toBytes());
    final RecordedRequest recorded = RecordedRequest(
      request.method,
      request.url,
      Map<String, String>.of(request.headers),
      body,
    );
    requests.add(recorded);
    switch (request.url.host) {
      case installationsHost:
        return _installations(request, recorded);
      case fetchHost:
        return _fetch(request);
      case realtimeHost:
        return _realtime(request);
    }
    return _text('Not found', 404);
  }

  http.StreamedResponse _installations(
    http.BaseRequest request,
    RecordedRequest recorded,
  ) {
    if (installationsUnreachable) {
      throw http.ClientException('Connection refused', request.url);
    }
    final int? status = installationsStatus;
    if (status != null) {
      return _error(status);
    }
    final Map<String, Object?> token = <String, Object?>{
      'token': 'auth-token-${_fids++}',
      'expiresIn': '604800s',
    };
    if (request.url.pathSegments.last == 'installations') {
      return _json(<String, Object?>{
        'fid': recorded.json['fid'],
        'refreshToken': 'refresh-token',
        'authToken': token,
      });
    }
    return _json(token);
  }

  Future<http.StreamedResponse> _fetch(http.BaseRequest request) async {
    final Completer<void>? gate = fetchGate;
    if (gate != null) {
      await gate.future;
    }
    if (fetchUnreachable) {
      throw http.ClientException('Connection reset', request.url);
    }
    final int? status = fetchStatus;
    if (status != null) {
      return _error(status);
    }
    return _json(
      <String, Object?>{
        'entries': entries,
        'state': 'UPDATE',
        'templateVersion': '$templateVersion',
      },
      headers: <String, String>{'etag': 'etag-$templateVersion'},
    );
  }

  http.StreamedResponse _realtime(http.BaseRequest request) {
    final int? status = realtimeStatus;
    if (status != null) {
      return _error(status);
    }
    final StreamController<List<int>> stream = StreamController<List<int>>();
    openStreams.add(stream);
    final String? first = realtimeFirstChunk;
    if (first != null) {
      stream.add(utf8.encode(first));
    }
    if (request is http.Abortable) {
      final Future<void>? abort = request.abortTrigger;
      unawaited(
        abort?.then((void _) {
          if (!stream.isClosed) {
            stream.addError(http.RequestAbortedException(request.url));
            unawaited(stream.close());
          }
          openStreams.remove(stream);
        }),
      );
    }
    return http.StreamedResponse(
      stream.stream,
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  static http.StreamedResponse _error(int status) => _json(<String, Object?>{
    'error': <String, Object?>{
      'code': status,
      'status': 'FAILURE',
      'message': 'Failure',
    },
  }, status: status);

  static http.StreamedResponse _text(String text, int status) =>
      http.StreamedResponse(Stream<List<int>>.value(utf8.encode(text)), status);

  static http.StreamedResponse _json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: <String, String>{'content-type': 'application/json', ...headers},
  );
}
