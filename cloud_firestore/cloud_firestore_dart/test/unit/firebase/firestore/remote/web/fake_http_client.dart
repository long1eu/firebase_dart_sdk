import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';

/// A [WebHttpClient] whose requests are answered by the test.
class FakeHttpClient implements WebHttpClient {
  /// Every request that was sent, in order.
  final List<FakeRequest> requests = <FakeRequest>[];

  final Queue<FakeRequest> _unclaimed = Queue<FakeRequest>();
  final Queue<Completer<FakeRequest>> _waiting =
      Queue<Completer<FakeRequest>>();

  bool closed = false;

  /// The next request the test has not looked at yet, waiting for it if
  /// needed.
  Future<FakeRequest> next() {
    if (_unclaimed.isNotEmpty) {
      return Future<FakeRequest>.value(_unclaimed.removeFirst());
    }
    final Completer<FakeRequest> completer = Completer<FakeRequest>();
    _waiting.add(completer);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Whether a request is waiting to be claimed with [next].
  bool get hasUnclaimed => _unclaimed.isNotEmpty;

  @override
  WebHttpRequest send(String method, Uri url,
      {Map<String, String> headers = const <String, String>{},
      String? body,
      bool includeCredentials = false}) {
    final FakeRequest request = FakeRequest(method, url, headers, body,
        includeCredentials: includeCredentials);
    requests.add(request);
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(request);
    } else {
      _unclaimed.add(request);
    }
    return request;
  }

  @override
  void close() => closed = true;
}

class FakeRequest implements WebHttpRequest {
  FakeRequest(this.method, this.url, this.headers, this.body,
      {this.includeCredentials = false});

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  /// Whether the request asked the browser to send its cookies.
  final bool includeCredentials;

  final Completer<WebHttpResponse> _response = Completer<WebHttpResponse>();
  final StreamController<String> _body = StreamController<String>();
  bool aborted = false;

  /// The query parameters, decoded.
  Map<String, String> get query => url.queryParameters;

  /// The form fields of the body, decoded.
  Map<String, String> get form => Uri.splitQueryString(body ?? '');

  /// Answers with a complete response.
  void respond(int status,
      {String body = '',
      Map<String, String> headers = const <String, String>{}}) {
    stream(status, headers: headers);
    if (body.isNotEmpty) {
      _body.add(body);
    }
    unawaited(_body.close());
  }

  /// Answers with the headers only; the body is fed with [add] and [end].
  void stream(int status,
      {Map<String, String> headers = const <String, String>{}}) {
    _response.complete(WebHttpResponse(status, headers, _body.stream));
  }

  void add(String text) => _body.add(text);

  void end() => _body.close();

  /// The request fails before any response, like a network error.
  void fail(Object error) => _response.completeError(error);

  /// The response body breaks off with an error, like a connection that is
  /// cut in the middle of a response.
  void cutBody() {
    _body.addError(StateError('connection cut'));
    unawaited(_body.close());
  }

  @override
  Future<WebHttpResponse> get response => _response.future;

  @override
  void abort() {
    if (aborted) {
      return;
    }
    aborted = true;
    if (!_response.isCompleted) {
      _response.completeError(StateError('aborted'));
      // Nobody may be listening any more.
      _response.future.ignore();
    }
    if (!_body.isClosed) {
      unawaited(_body.close());
    }
  }
}

/// Frames [json] as a WebChannel chunk: its length in UTF-16 code units, a
/// line feed and the text.
String chunk(String json) => '${json.length}\n$json';
