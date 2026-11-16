// A fake of the Google endpoints the package calls, behind an http.Client: it records every request and
// answers from handlers keyed by host and path. Nothing leaves the process.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef Handler = Future<http.Response> Function(http.Request request);

class FakeBackend {
  FakeBackend() {
    // OAuth token endpoint of the service account credential.
    on('oauth2.googleapis.com', '/token', (http.Request request) async {
      tokensIssued++;
      return json(<String, Object?>{
        'access_token': 'ya29.fake-$tokensIssued',
        'expires_in': 3599,
        'token_type': 'Bearer',
      });
    });
  }

  final List<http.Request> requests = <http.Request>[];
  final Map<String, Handler> _handlers = <String, Handler>{};
  int tokensIssued = 0;

  void on(String host, String path, Handler handler) =>
      _handlers['$host$path'] = handler;

  /// An Identity Toolkit method of the project demo-test (`accounts:lookup`, ...).
  void onToolkit(String method, Handler handler) => on(
    'identitytoolkit.googleapis.com',
    '/v1/projects/demo-test/$method',
    handler,
  );

  late final http.Client client = MockClient((http.Request request) async {
    requests.add(request);
    final Handler? handler =
        _handlers['${request.url.host}${request.url.path}'];
    if (handler == null) {
      return http.Response('no fake for ${request.url}', 404);
    }
    return handler(request);
  });

  /// The requests sent to [host], in order.
  List<http.Request> to(String host) =>
      requests.where((http.Request r) => r.url.host == host).toList();

  List<http.Request> get toolkit => to('identitytoolkit.googleapis.com');

  static http.Response json(
    Object body, [
    int status = 200,
    Map<String, String>? headers,
  ]) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json', ...?headers},
  );

  /// An error of the Identity Toolkit API.
  static http.Response error(String message, [int status = 400]) =>
      json(<String, Object?>{
        'error': <String, Object?>{'code': status, 'message': message},
      }, status);
}

Map<String, Object?> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;
