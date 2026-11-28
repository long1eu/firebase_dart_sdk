import 'dart:async';

import 'package:http/http.dart' as http;

/// A response body the test feeds. It records what the code under test did with it.
final class FakeBody {
  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(
        onListen: () => listened = true,
        onPause: () => paused = true,
        onResume: () => paused = false,
        onCancel: () {
          cancelled = true;
          _feeder?.cancel();
        },
      );

  /// The body stream; [bytesRead] counts the bytes its listener received.
  late final Stream<List<int>> stream = _controller.stream.map((
    List<int> chunk,
  ) {
    bytesRead += chunk.length;
    return chunk;
  });

  /// True once the body was listened to.
  bool listened = false;

  /// True once the listener cancelled its subscription.
  bool cancelled = false;

  /// True while the listener holds the subscription paused.
  bool paused = false;

  /// The bytes delivered to the listener.
  int bytesRead = 0;

  Timer? _feeder;

  /// Adds [chunk] unless the body was closed.
  void add(List<int> chunk) {
    if (!_controller.isClosed) {
      _controller.add(chunk);
    }
  }

  /// Raises [error] on the body unless it was closed.
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
  }

  /// Ends the body.
  void close() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  /// Adds [chunk] every millisecond until the listener cancels: a body without end.
  void feedForever(List<int> chunk) {
    _feeder = Timer.periodic(
      const Duration(milliseconds: 1),
      (Timer _) => add(chunk),
    );
  }

  /// What the clients of `package:http` do on abort: raise `RequestAbortedException`, then close.
  void abort(Uri url) {
    addError(http.RequestAbortedException(url));
    close();
    _feeder?.cancel();
  }
}

/// A streamed response that carries the URL it came from, as the clients of `package:http` give.
final class FakeResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  /// A response from [url].
  FakeResponse(
    super.stream,
    super.statusCode, {
    required this.url,
    super.headers,
    super.request,
  });

  @override
  final Uri url;
}

/// An `http.Client` that answers every request with [statusCode], [headers] and [body], or fails
/// with [error].
///
/// It honours the abort trigger of an `http.Abortable` request the way the clients of
/// `package:http` do: before the headers, `send` fails with `RequestAbortedException`; after
/// them, the body raises it and closes. With `honourAbort: false` it only records the abort, so a
/// test can tell what the code under test stopped by itself.
final class FakeClient extends http.BaseClient {
  /// A client whose response comes from [responseUrl] (the request's URL when null), and whose
  /// headers wait for [releaseHeaders] when [holdHeaders] is true.
  FakeClient({
    this.statusCode = 200,
    this.headers = const <String, String>{},
    this.responseUrl,
    this.holdHeaders = false,
    this.error,
    this.errorTrace,
    this.honourAbort = true,
  });

  /// The status of the response.
  final int statusCode;

  /// The headers of the response.
  final Map<String, String> headers;

  /// The URL the response says it came from; the request's URL when null.
  final Uri? responseUrl;

  /// When true, the response waits for [releaseHeaders].
  final bool holdHeaders;

  /// When not null, `send` fails with it.
  final Object? error;

  /// The stack trace [error] is raised with.
  final StackTrace? errorTrace;

  /// When false, an abort is recorded in [aborted] and does nothing else.
  final bool honourAbort;

  /// The body of the response.
  final FakeBody body = FakeBody();

  /// Every request sent.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// True once the abort trigger of a request completed.
  bool aborted = false;

  Completer<http.StreamedResponse>? _pending;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    if (request case http.Abortable(:final Future<void>? abortTrigger)) {
      unawaited(abortTrigger?.then((void _) => _onAbort(request.url)));
    }
    final Object? error = this.error;
    if (error != null) {
      return Future<http.StreamedResponse>.error(
        error,
        errorTrace ?? StackTrace.current,
      );
    }
    final Completer<http.StreamedResponse> pending =
        Completer<http.StreamedResponse>();
    _pending = pending;
    if (!holdHeaders) {
      releaseHeaders();
    }
    return pending.future;
  }

  /// Answers the last request with its headers, unless it was aborted.
  void releaseHeaders() {
    final Completer<http.StreamedResponse> pending = _pending!;
    if (pending.isCompleted) {
      return;
    }
    final http.BaseRequest request = requests.last;
    pending.complete(
      FakeResponse(
        body.stream,
        statusCode,
        url: responseUrl ?? request.url,
        headers: headers,
        request: request,
      ),
    );
  }

  void _onAbort(Uri url) {
    aborted = true;
    if (!honourAbort) {
      return;
    }
    final Completer<http.StreamedResponse>? pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(http.RequestAbortedException(url));
    }
    body.abort(url);
  }
}

/// How a future ended, recorded without awaiting it (for use inside `fake_async`).
final class Outcome<T> {
  /// Watches [future].
  Outcome(Future<T> future) {
    unawaited(
      future.then<void>(
        (T result) {
          value = result;
          done = true;
        },
        onError: (Object caught, StackTrace stackTrace) {
          error = caught;
          trace = stackTrace;
          done = true;
        },
      ),
    );
  }

  /// True once the future completed.
  bool done = false;

  /// The value it completed with.
  T? value;

  /// The error it completed with.
  Object? error;

  /// The stack trace of [error].
  StackTrace? trace;
}

/// Listens to a body stream and records what it delivers.
final class BodyRecorder {
  /// Listens to [stream] at once.
  BodyRecorder(Stream<List<int>> stream) {
    subscription = stream.listen(
      chunks.add,
      onError: (Object error, StackTrace stackTrace) {
        errors.add(error);
        traces.add(stackTrace);
      },
      onDone: () => done = true,
    );
  }

  /// The subscription to the body.
  late final StreamSubscription<List<int>> subscription;

  /// The chunks received.
  final List<List<int>> chunks = <List<int>>[];

  /// The errors received.
  final List<Object> errors = <Object>[];

  /// The stack traces of [errors].
  final List<StackTrace> traces = <StackTrace>[];

  /// True once the stream ended.
  bool done = false;

  /// Every byte received, in order.
  List<int> get bytes => <int>[for (final List<int> chunk in chunks) ...chunk];
}
