// A loopback server for the browser tests of firebase_installations_dart and firebase_remote_config_dart
// (tool/test_browser_remote_config.sh starts it). It listens on 127.0.0.1 on a port the system picks and
// prints that port, alone on one line, as the first line of its output.
//
// Every route answers with CORS headers, so a browser page served from another origin can call it:
//
//   OPTIONS <any path>                                           204
//   GET  /chunks                                                 {"n": 0} to {"n": 4}, one per second for 5 s, each flushed
//   POST /v1/projects/demo/installations                         a valid "create installation" answer
//   POST /v1/projects/demo/installations/<fid>/authTokens:generate   a valid "generate token" answer
//   DELETE /v1/projects/demo/installations/<fid>                 200 with {}
//   POST /v1/projects/demo/namespaces/firebase:fetch             UPDATE with one entry, flag = on
//
// Any other request gets 404. The server holds no state and reads no request bodies.
import 'dart:convert';
import 'dart:io';

const String _allowedHeaders =
    'Content-Type, Accept, Authorization, X-Goog-Api-Key, '
    'X-Goog-Firebase-Installations-Auth, X-Firebase-RC-Fetch-Type, If-None-Match, '
    'X-Android-Package, X-Android-Cert, X-Ios-Bundle-Identifier';

const String _installations = '/v1/projects/demo/installations';
const String _fetchPath = '/v1/projects/demo/namespaces/firebase:fetch';

const Map<String, Object?> _authToken = <String, Object?>{
  'token': 't',
  'expiresIn': '604800s',
};

Future<void> main() async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  stdout.writeln(server.port);
  await stdout.flush();
  await for (final HttpRequest request in server) {
    try {
      await _handle(request);
    } on Object catch (error) {
      stderr.writeln(
        'fake server: ${request.method} ${request.uri.path}: $error',
      );
      await request.response.close().catchError((Object _) => request.response);
    }
  }
}

Future<void> _handle(HttpRequest request) async {
  final HttpResponse response = request.response;
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    ..set('Access-Control-Allow-Headers', _allowedHeaders)
    ..set('Access-Control-Expose-Headers', 'etag');
  final String method = request.method;
  final String path = request.uri.path;

  if (method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
  } else if (method == 'GET' && path == '/chunks') {
    await _chunks(response);
  } else if (method == 'POST' && path == _installations) {
    await _json(response, <String, Object?>{
      'name': 'projects/demo/installations/fake',
      'refreshToken': 'r',
      'authToken': _authToken,
    });
  } else if (method == 'POST' &&
      _isFidPath(path, suffix: 'authTokens:generate')) {
    await _json(response, _authToken);
  } else if (method == 'DELETE' && _isFidPath(path)) {
    await _json(response, const <String, Object?>{});
  } else if (method == 'POST' && path == _fetchPath) {
    await _json(response, <String, Object?>{
      'state': 'UPDATE',
      'entries': <String, String>{'flag': 'on'},
      'templateVersion': '1',
    });
  } else {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }
}

bool _isFidPath(String path, {String? suffix}) {
  final List<String> expected = Uri.parse(_installations).pathSegments;
  final List<String> segments = Uri.parse(path).pathSegments;
  final int length = expected.length + (suffix == null ? 1 : 2);
  if (segments.length != length) {
    return false;
  }
  for (int i = 0; i < expected.length; i++) {
    if (segments[i] != expected[i]) {
      return false;
    }
  }
  return suffix == null || segments.last == suffix;
}

Future<void> _json(HttpResponse response, Object body) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<void> _chunks(HttpResponse response) async {
  response.headers.contentType = ContentType.json;
  response.bufferOutput = false;
  for (int i = 0; i < 5; i++) {
    response.write(jsonEncode(<String, Object?>{'n': i}));
    await response.flush();
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await response.close();
}
