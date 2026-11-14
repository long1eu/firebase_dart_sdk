import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';

/// A [WebHttpClient] on top of `dart:io`, to run the web transport (REST and
/// WebChannel) on the VM against the emulator.
class IoWebHttpClient implements WebHttpClient {
  final HttpClient _client = HttpClient();

  /// Every request that was sent, as `METHOD path`.
  final List<String> log = <String>[];

  /// The WebChannel sessions of this isolate: how many were opened (handshake requests), and how the requests that
  /// terminate them ended.
  static int sessionsOpened = 0;
  static int terminatesAnswered = 0;
  static int terminatesFailed = 0;

  @override
  WebHttpRequest send(String method, Uri url,
      {Map<String, String> headers = const <String, String>{},
      String? body,
      // Cookies are a browser concept; dart:io sends none either way.
      bool includeCredentials = false}) {
    log.add('$method ${url.path}');
    final _IoRequest request = _IoRequest(_client, method, url, headers, body);
    if (url.path.endsWith('/channel')) {
      final Map<String, String> query = url.queryParameters;
      if (query['TYPE'] == 'terminate') {
        unawaited(request.response.then(
            (WebHttpResponse response) => response.statusCode == 200
                ? terminatesAnswered++
                : terminatesFailed++,
            onError: (Object _) => terminatesFailed++));
      } else if (!query.containsKey('SID')) {
        sessionsOpened++;
      }
    }
    return request;
  }

  @override
  void close() => _client.close(force: true);
}

class _IoRequest implements WebHttpRequest {
  _IoRequest(HttpClient client, String method, Uri url,
      Map<String, String> headers, String? body) {
    response = _send(client, method, url, headers, body);
    // The caller may have stopped listening after an abort.
    response.ignore();
  }

  HttpClientRequest? _request;
  bool _aborted = false;

  /// The body handed to the caller, and the subscription that feeds it.
  StreamController<String>? _body;
  StreamSubscription<String>? _bodySubscription;

  @override
  late final Future<WebHttpResponse> response;

  Future<WebHttpResponse> _send(HttpClient client, String method, Uri url,
      Map<String, String> headers, String? body) async {
    final HttpClientRequest request = await client.openUrl(method, url);
    _request = request;
    if (_aborted) {
      request.abort();
    }
    // The emulator closes connections after some error responses; a reused
    // connection then fails with a broken pipe. Browsers retry that case
    // themselves, `dart:io` does not.
    request.persistentConnection = false;
    headers.forEach(request.headers.set);
    if (body != null) {
      final List<int> bytes = utf8.encode(body);
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }
    final HttpClientResponse response = await request.close();
    final Map<String, String> responseHeaders = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      responseHeaders[name.toLowerCase()] = values.join(', ');
    });
    // [abort] ends the body, as the WebHttpRequest contract asks: dart:io
    // does not end the body of a response that already started when its
    // request is aborted (Dart 3.12), a stalled body would stay open.
    final StreamController<String> received = StreamController<String>();
    _body = received;
    received
      ..onListen = () {
        _bodySubscription = response.transform(utf8.decoder).listen(
              received.add,
              // An aborted body ends with an error; the stream just ends.
              onError: (Object _) {},
              onDone: () {
                if (!received.isClosed) {
                  unawaited(received.close());
                }
              },
            );
      }
      ..onCancel = () => _bodySubscription?.cancel();
    if (_aborted) {
      unawaited(received.close());
    }
    return WebHttpResponse(response.statusCode, responseHeaders, received.stream);
  }

  @override
  void abort() {
    _aborted = true;
    _request?.abort();
    unawaited(_bodySubscription?.cancel());
    final StreamController<String>? body = _body;
    if (body != null && !body.isClosed) {
      unawaited(body.close());
    }
  }
}
