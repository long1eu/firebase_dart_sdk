// The HTTP layer the web transport is written against. In a browser it is
// backed by `fetch` (fetch_http_client.dart); tests replay recorded exchanges
// through a fake.

import 'dart:async';

/// Sends HTTP requests and streams the response bodies.
abstract class WebHttpClient {
  /// Starts a request. [body] is sent as UTF-8 text.
  WebHttpRequest send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
  });

  /// Releases the resources of the client.
  void close();
}

/// A request in flight.
abstract class WebHttpRequest {
  /// Completes when the response headers arrived, or with an error when the
  /// request failed before that (network error or [abort]).
  Future<WebHttpResponse> get response;

  /// Cancels the request, including a response body that is still streaming.
  void abort();
}

/// The response to a [WebHttpRequest].
class WebHttpResponse {
  WebHttpResponse(this.statusCode, this.headers, this.body);

  final int statusCode;

  /// The response headers the platform exposes, with lower case names.
  final Map<String, String> headers;

  /// The body, decoded as UTF-8, in the pieces the network delivered. A
  /// single-subscription stream.
  final Stream<String> body;

  /// Reads the whole body.
  Future<String> readAll() => body.join();
}
