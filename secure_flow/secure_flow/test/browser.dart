// A simulated browser for the loopback tests: plain HTTP requests, with the headers a browser
// would send. No browser and no remote script run.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:secure_flow/secure_flow.dart';

/// What the simulated browser got back.
class Answer {
  Answer(this.status, this.body, this.headers);

  final int status;
  final String body;
  final HttpHeaders headers;
}

/// One request as a browser would send it. [address] replaces the host the connection goes to
/// (127.0.0.1 or ::1) while the Host header stays the one of [url] unless [hostHeader] is given.
Future<Answer> send(
  String method,
  Uri url, {
  String? address,
  String? hostHeader,
  Map<String, String> headers = const <String, String>{},
  String? body,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Uri target = address == null ? url : url.replace(host: address);
    final HttpClientRequest request = await client.openUrl(method, target);
    request.headers.set(
      HttpHeaders.hostHeader,
      hostHeader ?? '${url.host}:${url.port}',
    );
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final HttpClientResponse response = await request.close();
    return Answer(
      response.statusCode,
      await utf8.decodeStream(response),
      response.headers,
    );
  } finally {
    client.close(force: true);
  }
}

/// Posts a form to the path of [url] (without its query), as the form of a page would.
Future<Answer> postForm(
  Uri url,
  Map<String, String> fields, {
  String? origin,
  String contentType = 'application/x-www-form-urlencoded',
  String? hostHeader,
  String? rawBody,
}) => send(
  'POST',
  url.replace(query: ''),
  hostHeader: hostHeader,
  headers: <String, String>{
    HttpHeaders.contentTypeHeader: contentType,
    'origin': ?origin,
  },
  body: rawBody ?? Uri(queryParameters: fields).query,
);

/// Whether anything still answers HTTP at the port of [url] on [address] with a page of the flow
/// (one whose body contains [marker]). A bare connect is not enough: a closed ephemeral port can
/// be bound again at once by another test.
Future<bool> answers(Uri url, String address, String marker) async {
  try {
    final Answer answer = await send(
      'GET',
      url.replace(path: '/not-the-flow', query: ''),
      address: address,
    ).timeout(const Duration(seconds: 5));
    return answer.body.contains(marker);
  } on SocketException {
    return false;
  } on HttpException {
    return false;
  } on TimeoutException {
    return false;
  }
}

/// Whether ::1 can be bound on this machine.
Future<bool> hasIPv6() async {
  try {
    final ServerSocket socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv6,
      0,
    );
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

/// `presenter.run(flow)` for the tests: [SecureFlow.run] with this presenter.
extension RunWithPresenter on SecurePresenter {
  Future<T> run<T>(
    SecureFlow<T> flow, {
    Duration timeout = const Duration(minutes: 5),
    Future<void>? cancel,
  }) => flow.run(presenter: this, timeout: timeout, cancel: cancel);
}
