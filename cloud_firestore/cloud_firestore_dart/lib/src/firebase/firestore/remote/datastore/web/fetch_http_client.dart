// The HTTP layer of the web transport in browsers: `fetch` with a streamed
// response body. Only compiles for the web.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:web/web.dart' as web;

// The global `fetch`, which exists in windows and in workers.
@JS('fetch')
external JSPromise<web.Response> _fetch(JSString url, web.RequestInit init);

/// A [WebHttpClient] on top of the Fetch API.
class FetchHttpClient implements WebHttpClient {
  final Set<_FetchRequest> _requests = <_FetchRequest>{};

  @override
  WebHttpRequest send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    bool includeCredentials = false,
  }) {
    final _FetchRequest request = _FetchRequest(
      method,
      url,
      headers,
      body,
      includeCredentials,
    );
    _requests.add(request);
    request._done.future.whenComplete(() => _requests.remove(request));
    return request;
  }

  @override
  void close() {
    for (final _FetchRequest request in _requests.toList()) {
      request.abort();
    }
  }
}

class _FetchRequest implements WebHttpRequest {
  _FetchRequest(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
    bool includeCredentials,
  ) {
    response = _send(method, url, headers, body, includeCredentials);
    // The caller may have stopped listening after an abort.
    response.ignore();
  }

  final web.AbortController _abort = web.AbortController();
  final Completer<void> _done = Completer<void>();

  @override
  late final Future<WebHttpResponse> response;

  Future<WebHttpResponse> _send(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
    bool includeCredentials,
  ) async {
    final web.Headers requestHeaders = web.Headers();
    headers.forEach((String name, String value) {
      requestHeaders.append(name, value);
    });
    final web.RequestInit init = web.RequestInit(
      method: method,
      headers: requestHeaders,
      signal: _abort.signal,
      // No cookies: the session is carried in the URL. A Cloud Workstations
      // host needs them, see RestClient.forwardCloudWorkstationCredentials.
      credentials: includeCredentials ? 'include' : 'omit',
      // A redirect would send the request, with its credentials, to wherever
      // the response says. Firestore never redirects.
      redirect: 'error',
      cache: 'no-store',
    );
    if (body != null) {
      init.body = body.toJS;
    }

    final web.Response response;
    try {
      response = await _fetch(url.toString().toJS, init).toDart;
    } catch (_) {
      _finish();
      rethrow;
    }

    final Map<String, String> responseHeaders = <String, String>{};
    // Only the names the client reads: `Headers` cannot be iterated through
    // the typed bindings.
    for (final String name in const <String>[
      'x-http-session-id',
      'x-client-wire-protocol',
      'content-type',
      'date',
    ]) {
      final String? value = response.headers.get(name);
      if (value != null) {
        responseHeaders[name] = value;
      }
    }
    return WebHttpResponse(
      response.status,
      responseHeaders,
      _readBody(response),
    );
  }

  Stream<String> _readBody(web.Response response) {
    final StreamController<String> controller = StreamController<String>();
    final web.ReadableStream? body = response.body;

    Future<void> pump() async {
      if (body == null) {
        return;
      }
      final web.ReadableStreamDefaultReader reader =
          body.getReader() as web.ReadableStreamDefaultReader;
      // Chunked, so that a character split over two reads is put together.
      final Sink<List<int>> decoder = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(_StringSink(controller));
      while (true) {
        final web.ReadableStreamReadResult result = await reader.read().toDart;
        if (result.done) {
          break;
        }
        final JSAny? value = result.value;
        if (value != null && !controller.isClosed) {
          decoder.add((value as JSUint8Array).toDart);
        }
      }
      decoder.close();
    }

    controller.onListen = () {
      pump()
          .catchError((Object error, StackTrace stackTrace) {
            // An abort ends the body quietly, anything else is an error.
            if (!_abort.signal.aborted && !controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          })
          .whenComplete(() {
            _finish();
            if (!controller.isClosed) {
              controller.close();
            }
          });
    };
    controller.onCancel = abort;
    return controller.stream;
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  void abort() {
    if (!_abort.signal.aborted) {
      _abort.abort();
    }
    _finish();
  }
}

/// Forwards the decoded text to a stream controller.
class _StringSink implements Sink<String> {
  _StringSink(this._controller);

  final StreamController<String> _controller;

  @override
  void add(String data) {
    if (data.isNotEmpty && !_controller.isClosed) {
      _controller.add(data);
    }
  }

  @override
  void close() {}
}
