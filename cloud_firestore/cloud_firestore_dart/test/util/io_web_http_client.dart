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

  @override
  WebHttpRequest send(String method, Uri url,
      {Map<String, String> headers = const <String, String>{}, String? body}) {
    log.add('$method ${url.path}');
    return _IoRequest(_client, method, url, headers, body);
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
    return WebHttpResponse(
      response.statusCode,
      responseHeaders,
      // An aborted body ends with an error; the stream just ends.
      response.transform(utf8.decoder).handleError((Object _) {}),
    );
  }

  @override
  void abort() {
    _aborted = true;
    _request?.abort();
  }
}
