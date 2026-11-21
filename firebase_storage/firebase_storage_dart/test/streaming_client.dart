import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An HTTP client whose responses stream their bodies, and which honours the `abortTrigger` of an
/// `http.Abortable` request the way `IOClient` does: an abort before the response fails the request, an
/// abort after it ends the body with an `http.RequestAbortedException`.
final class StreamingClient extends http.BaseClient {
  /// Answers each request with the response of the handler.
  StreamingClient(this._handler);

  /// Answers every request with [status] and a body made of [chunks].
  StreamingClient.chunks(List<String> chunks, {int status = 200})
    : this((_) => response(chunks, status));

  /// Answers with [status] and a body that the test feeds through [body]; [served] fires once the response
  /// is handed out.
  factory StreamingClient.open({int status = 200}) {
    late final StreamingClient client;
    client = StreamingClient((_) async {
      final StreamController<List<int>> body = StreamController<List<int>>(
        onCancel: () => client.bodyCanceled = true,
      );
      client.body = body;
      client._served.add(null);
      return http.StreamedResponse(body.stream, status);
    });
    return client;
  }

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  /// The requests received, in order.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// Whether the abort trigger of a request fired.
  bool aborted = false;

  /// Whether the body of a [StreamingClient.open] response was canceled.
  bool bodyCanceled = false;

  /// The body of the last [StreamingClient.open] response.
  late StreamController<List<int>> body;

  final StreamController<void> _served = StreamController<void>.broadcast();

  /// Fires each time a [StreamingClient.open] response is handed out.
  Stream<void> get served => _served.stream;

  /// A response with [status] whose body is [chunks].
  static Future<http.StreamedResponse> response(
    List<String> chunks,
    int status,
  ) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks.map(utf8.encode)),
      status,
    );
  }

  /// A 200 response whose body is [chunks] followed by [error].
  static Future<http.StreamedResponse> failing(
    List<String> chunks,
    Exception error,
  ) async {
    Stream<List<int>> body() async* {
      for (final String chunk in chunks) {
        yield utf8.encode(chunk);
      }
      throw error;
    }

    return http.StreamedResponse(body(), 200);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final Future<void>? trigger = request is http.Abortable
        ? request.abortTrigger
        : null;
    final Completer<http.StreamedResponse> result =
        Completer<http.StreamedResponse>();
    StreamController<List<int>>? forwarded;
    trigger?.then((_) {
      aborted = true;
      if (!result.isCompleted) {
        result.completeError(http.RequestAbortedException(request.url));
      }
      final StreamController<List<int>>? controller = forwarded;
      if (controller != null && !controller.isClosed) {
        controller
          ..addError(http.RequestAbortedException(request.url))
          ..close();
      }
    }).ignore();
    _handler(request).then((http.StreamedResponse response) {
      if (result.isCompleted) {
        return;
      }
      final StreamController<List<int>> controller =
          StreamController<List<int>>();
      forwarded = controller;
      late final StreamSubscription<List<int>> source;
      controller
        ..onListen = () {
          source = response.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        }
        ..onPause = (() => source.pause())
        ..onResume = (() => source.resume())
        ..onCancel = (() => source.cancel());
      result.complete(
        http.StreamedResponse(
          controller.stream,
          response.statusCode,
          headers: response.headers,
          request: request,
        ),
      );
    }, onError: result.completeError).ignore();
    return result.future;
  }
}
