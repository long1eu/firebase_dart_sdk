// The one-shot HTTP server on the loopback interface that every presenter of this package runs a
// flow on. Needs dart:io; not exported.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:secure_flow/src/deadline.dart';
import 'package:secure_flow/src/errors.dart';
import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/pages.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/secrets.dart';

/// The largest form body taken: a reCAPTCHA token is a few kilobytes.
const int maxFormBytes = 64 * 1024;

/// Runs [flow] on a new loopback server: [presenter] shows the URL, and the server is closed when
/// this returns or throws, whatever the reason. See [SecureFlow.run].
Future<T> runOnLoopback<T>(
  SecureFlow<T> flow,
  LoopbackPresenter presenter, {
  required Duration timeout,
  Future<void>? cancel,
}) async {
  final LoopbackServer server = await LoopbackServer.bind(
    port: flow.port,
    alsoIPv6: flow.host == SecureFlowHost.localhost,
  );
  try {
    final SecureFlowSession session = SecureFlowSession(
      host: flow.host,
      port: server.port,
      path: flow.answer.path ?? '/${randomUnreservedString()}',
      state: flow.state ?? randomUnreservedString(),
    );
    final _Round<T> round = _Round<T>(flow, session);
    server.listen(round.handle);
    return await round.run(
      show: presenter.show,
      timeout: timeout,
      cancel: cancel,
      hint: presenter.timeoutHint(session),
    );
  } finally {
    await server.close();
  }
}

/// One run of a flow: which requests answer it and when it ends.
final class _Round<T> {
  _Round(this.flow, this.session);

  final SecureFlow<T> flow;
  final SecureFlowSession session;
  final Completer<T> _result = Completer<T>();

  /// An answer is being parsed; other answers wait for its outcome by getting a 404.
  bool _busy = false;

  /// The timeout passed while an answer was being parsed: a rejection of it ends the run.
  SecureFlowTimeout? _expired;

  Future<T> run({
    required ShowUrl show,
    required Duration timeout,
    required Future<void>? cancel,
    required String? hint,
  }) async {
    final SecureFlowTimeout timedOut = timeoutError(timeout, hint);
    final Timer timer = Timer(timeout, () {
      if (_busy) {
        _expired = timedOut;
      } else {
        _fail(timedOut, StackTrace.current);
      }
    });
    if (cancel != null) {
      void cancelled([Object? _]) =>
          _fail(const SecureFlowCancelled(), StackTrace.current);
      unawaited(cancel.then<void>(cancelled, onError: cancelled));
    }
    // Not awaited before the wait: a presenter may return only once the browser is done.
    unawaited(
      Future<void>.sync(
        () => show(flow.start(session)),
      ).then<void>((_) {}, onError: _fail),
    );
    try {
      return await _result.future;
    } finally {
      timer.cancel();
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (!_result.isCompleted) {
      _result.completeError(error, stackTrace);
    }
  }

  void handle(HttpRequest request) => unawaited(_dispatch(request));

  Future<void> _dispatch(HttpRequest request) async {
    if (request.uri.path != session.path || _result.isCompleted || _busy) {
      return _respond(request, HttpStatus.notFound, flow.notFoundPage);
    }
    if (request.headers.value(HttpHeaders.hostHeader)?.toLowerCase() !=
        session.hostHeader) {
      return _reject(request);
    }
    final SecureAnswer answer = flow.answer;
    if (request.method == 'GET') {
      final Map<String, String>? query = _queryOf(request.uri);
      if (answer.encoding == SecureAnswerEncoding.query) {
        return _take(request, query);
      }
      final SecurePage? page = flow.page(session);
      if (page == null) {
        return _respond(request, HttpStatus.notFound, flow.notFoundPage);
      }
      if (!_carriesState(query)) {
        return _reject(request);
      }
      return _respond(request, HttpStatus.ok, page);
    }
    if (request.method == 'POST' &&
        answer.encoding == SecureAnswerEncoding.form) {
      return _takeForm(request);
    }
    return _respond(request, HttpStatus.notFound, flow.notFoundPage);
  }

  Future<void> _takeForm(HttpRequest request) async {
    final String? origin = request.headers.value('origin');
    if ((origin != null && origin.toLowerCase() != session.origin) ||
        request.headers.contentType?.mimeType !=
            'application/x-www-form-urlencoded') {
      return _reject(request);
    }
    final Uint8List? body = await _readBody(request);
    if (body == null) {
      return _respond(
        request,
        HttpStatus.requestEntityTooLarge,
        const SecurePage.message(
          title: 'Too large',
          text: 'The answer is too large. Return to the app and try again.',
        ),
      );
    }
    Map<String, String>? form;
    try {
      form = Uri.splitQueryString(utf8.decode(body));
    } on FormatException {
      form = null;
    } on ArgumentError {
      form = null;
    }
    return _take(request, form);
  }

  /// Parses an answer that carries the state; the first one that is not rejected ends the run.
  Future<void> _take(
    HttpRequest request,
    Map<String, String>? parameters,
  ) async {
    if (!_carriesState(parameters)) {
      return _reject(request);
    }
    if (_busy || _result.isCompleted) {
      return _respond(request, HttpStatus.notFound, flow.notFoundPage);
    }
    _busy = true;
    final Map<String, String> answer = Map<String, String>.of(parameters!)
      ..remove('state');
    final T value;
    try {
      value = await flow.parse(answer, session);
    } on SecureAnswerRejected catch (rejection) {
      _busy = false;
      await _respond(request, HttpStatus.badRequest, rejection.page);
      final SecureFlowTimeout? expired = _expired;
      if (expired != null) {
        _fail(expired, StackTrace.current);
      }
      return;
    } on Object catch (error, stackTrace) {
      await _respond(request, HttpStatus.badRequest, flow.failedPage);
      _fail(error, stackTrace);
      return;
    }
    await _respond(request, HttpStatus.ok, flow.donePage);
    if (!_result.isCompleted) {
      _result.complete(value);
    }
  }

  bool _carriesState(Map<String, String>? parameters) =>
      parameters != null &&
      constantTimeEquals(parameters['state'] ?? '', session.state);

  Future<void> _reject(HttpRequest request) =>
      _respond(request, HttpStatus.badRequest, flow.rejectedPage);

  Future<void> _respond(
    HttpRequest request,
    int status,
    SecurePage page,
  ) async {
    final ({String html, String contentSecurityPolicy}) rendered = renderPage(
      page,
    );
    try {
      final HttpResponse response = request.response
        ..statusCode = status
        ..headers.contentType = ContentType.html
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('referrer-policy', page.referrerPolicy)
        ..headers.set('x-content-type-options', 'nosniff')
        ..headers.set('x-frame-options', 'DENY')
        ..headers.set('content-security-policy', rendered.contentSecurityPolicy)
        ..write(rendered.html);
      await response.close();
    } on Object {
      // The browser went away, or the server was closed; nothing to tell it.
    }
  }
}

/// The query parameters of [uri], or null when they do not decode (an invalid UTF-8 escape).
Map<String, String>? _queryOf(Uri uri) {
  try {
    return uri.queryParameters;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// The body of [request], or null when it is larger than [maxFormBytes].
Future<Uint8List?> _readBody(HttpRequest request) async {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  try {
    await for (final Uint8List chunk in request) {
      bytes.add(chunk);
      if (bytes.length > maxFormBytes) {
        return null;
      }
    }
  } on HttpException {
    return null;
  }
  return bytes.takeBytes();
}

/// A one-shot HTTP server on the loopback interface: bound by [bind], closed by [close].
final class LoopbackServer {
  LoopbackServer._(this._servers);

  final List<HttpServer> _servers;

  /// The port of the server (the same on every address it is bound to).
  int get port => _servers.first.port;

  /// The number of addresses bound: 1 (127.0.0.1) or 2 (127.0.0.1 and ::1).
  int get addressCount => _servers.length;

  /// Binds 127.0.0.1 on [port] (0: any free port), never another interface.
  ///
  /// With [alsoIPv6], ::1 is bound on the same port too, so that a browser that resolves
  /// `localhost` to ::1 first reaches this server and not another process that holds ::1 on that
  /// port. When the machine has no IPv6 loopback at all, only 127.0.0.1 is bound (nothing can
  /// listen on ::1 then). When ::1 is taken on the port that 127.0.0.1 got, another port is tried,
  /// up to five times; with a fixed [port] the [SocketException] is rethrown.
  static Future<LoopbackServer> bind({
    int port = 0,
    bool alsoIPv6 = false,
  }) async {
    for (int attempt = 1; ; attempt++) {
      final HttpServer ipv4 = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      if (!alsoIPv6) {
        return LoopbackServer._(<HttpServer>[ipv4]);
      }
      try {
        final HttpServer ipv6 = await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          ipv4.port,
          v6Only: true,
        );
        return LoopbackServer._(<HttpServer>[ipv4, ipv6]);
      } on SocketException {
        if (!await hasIPv6Loopback()) {
          return LoopbackServer._(<HttpServer>[ipv4]);
        }
        await ipv4.close(force: true);
        if (port != 0 || attempt == 5) {
          rethrow;
        }
      }
    }
  }

  /// Sends every request of every address to [onRequest]. Errors of the connections are dropped.
  void listen(void Function(HttpRequest request) onRequest) {
    for (final HttpServer server in _servers) {
      server.listen(onRequest, onError: (Object _) {});
    }
  }

  /// Closes every address at once, dropping open connections.
  Future<void> close() => Future.wait(<Future<void>>[
    for (final HttpServer server in _servers) server.close(force: true),
  ]);
}

/// Whether ::1 can be bound at all on this machine.
Future<bool> hasIPv6Loopback() async {
  try {
    final ServerSocket probe = await ServerSocket.bind(
      InternetAddress.loopbackIPv6,
      0,
      v6Only: true,
    );
    await probe.close();
    return true;
  } on SocketException {
    return false;
  }
}
