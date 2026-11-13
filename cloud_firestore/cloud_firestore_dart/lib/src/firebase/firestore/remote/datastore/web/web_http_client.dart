// The HTTP layer the web transport is written against. In a browser it is
// backed by `fetch` (fetch_http_client.dart); tests replay recorded exchanges
// through a fake.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';

/// Sends HTTP requests and streams the response bodies.
abstract class WebHttpClient {
  /// Starts a request. [body] is sent as UTF-8 text. With
  /// [includeCredentials] the browser sends its cookies for [url] (the fetch
  /// `credentials: 'include'`), otherwise none.
  WebHttpRequest send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    bool includeCredentials = false,
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

  /// The longest body [readAll] accepts by default, in UTF-16 code units: 256 Mi, the same bound as one WebChannel
  /// chunk (`WebChannelChunkParser.maxChunkLength`). A REST response holds every response message of a call (a
  /// query returns all its documents in one body), so the bound is not per message like the 17 MiB of the gRPC
  /// clients of the other SDKs: it allows 16 documents of 16 MiB, or hundreds of ordinary ones, and stops a server
  /// (or something in between) from making the client buffer without end.
  static const int maxBodyLength = 256 * 1024 * 1024;

  /// Reads the whole body. Fails with a RESOURCE_EXHAUSTED [GrpcError] as soon as it gets longer than [maxLength]
  /// characters, without reading the rest; the caller should abort the request.
  Future<String> readAll({int maxLength = maxBodyLength}) async {
    final StringBuffer buffer = StringBuffer();
    int length = 0;
    await for (final String piece in body) {
      length += piece.length;
      if (length > maxLength) {
        throw GrpcError.resourceExhausted(
          'The response is larger than the limit of $maxLength characters',
        );
      }
      buffer.write(piece);
    }
    return buffer.toString();
  }
}
