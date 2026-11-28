import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A response read with a cap on its body.
final class CappedResponse {
  /// A response with [statusCode], [headers] (lowercase names) and [body].
  const CappedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.truncated = false,
  });

  /// The HTTP status.
  final int statusCode;

  /// The response headers, names in lowercase.
  final Map<String, String> headers;

  /// The body bytes, at most the cap they were read with.
  final Uint8List body;

  /// True when a non-2xx body was cut at errorCap (the status stays meaningful).
  final bool truncated;

  /// True for a 2xx status.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// A 2xx body longer than its cap. Installations maps it to `invalid-response`.
final class CapExceededException implements Exception {
  /// The body was longer than [cap] bytes.
  const CapExceededException(this.cap);

  /// The cap in bytes.
  final int cap;

  @override
  String toString() =>
      'CapExceededException: the body is longer than $cap bytes';
}

/// Sends the request [build] makes and reads its body with caps.
///
/// Builds the request with an abort future (so it can be an `AbortableRequest`), sets followRedirects
/// to false, sends it with [deadline], and reads the body: a 2xx body past [successCap] aborts and throws
/// [CapExceededException]; a non-2xx body is cut at [errorCap] and returned with truncated = true. Past
/// the deadline it aborts and throws [TimeoutException].
Future<CappedResponse> sendCapped(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build, {
  required int successCap,
  required int errorCap,
  required Duration deadline,
}) async {
  final Completer<void> abort = Completer<void>();
  final _CappedReader reader = _CappedReader(
    abort,
    successCap: successCap,
    errorCap: errorCap,
  );
  final Timer timer = Timer(deadline, () {
    reader.fail(
      TimeoutException('The request took longer than its deadline', deadline),
      StackTrace.current,
    );
  });
  try {
    final http.BaseRequest request = build(abort.future)
      ..followRedirects = false;
    unawaited(client.send(request).then(reader.start, onError: reader.fail));
    return await reader.result.future;
  } finally {
    timer.cancel();
  }
}

/// Realtime: builds the AbortableRequest with [abort], sets followRedirects to false, sends it with no
/// deadline and returns the streamed response; a non-200 body is read by the caller with [readCapped].
Future<http.StreamedResponse> sendStreaming(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build,
  Future<void> abort,
) {
  final http.BaseRequest request = build(abort)..followRedirects = false;
  return client.send(request);
}

/// Reads the body of [response] up to [cap] bytes; a longer body is cut and marked truncated. It never
/// throws for size.
Future<CappedResponse> readCapped(
  http.StreamedResponse response, {
  required int cap,
}) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  bool truncated = false;
  await for (final List<int> chunk in response.stream) {
    final int room = cap - builder.length;
    if (chunk.length > room) {
      builder.add(chunk.sublist(0, room));
      truncated = true;
      break;
    }
    builder.add(chunk);
  }
  return CappedResponse(
    statusCode: response.statusCode,
    headers: response.headers,
    body: builder.takeBytes(),
    truncated: truncated,
  );
}

/// The UTF-8 bytes of server text kept: 1 KiB.
const int _serverTextCap = 1024;

/// [text] with control characters (C0, DEL and C1) removed, cut to at most 1 KiB of UTF-8 at a
/// character boundary.
String sanitizeServerText(String text) {
  final StringBuffer buffer = StringBuffer();
  int bytes = 0;
  for (final int rune in text.runes) {
    if (rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)) {
      continue;
    }
    final int size = rune < 0x80
        ? 1
        : rune < 0x800
        ? 2
        : rune < 0x10000
        ? 3
        : 4;
    if (bytes + size > _serverTextCap) {
      break;
    }
    bytes += size;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// [origin] reduced to scheme, host and port, after checking it.
///
/// It must be `https`, or `http` to a loopback host (`127.0.0.0/8`, `::1`, `localhost`), with a host and
/// no user info, path (other than `/`), query or fragment. Throws [ArgumentError] otherwise; its text
/// names only the scheme and the host (user info may hold a password).
Uri checkOrigin(Uri origin) {
  final String scheme = origin.scheme.toLowerCase();
  final String host = origin.host.toLowerCase();
  if (host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      (origin.path.isNotEmpty && origin.path != '/') ||
      origin.hasQuery ||
      origin.hasFragment) {
    throw ArgumentError.value(
      '${origin.scheme}://${origin.host}',
      'origin',
      'must be a scheme, a host and an optional port, with no path, query, fragment or user info',
    );
  }
  if (scheme != 'https' && !(scheme == 'http' && _isLoopback(host))) {
    throw ArgumentError.value(
      '${origin.scheme}://${origin.host}',
      'origin',
      'must use https, or http to a loopback host',
    );
  }
  return Uri(
    scheme: scheme,
    host: host,
    port: origin.hasPort ? origin.port : null,
  );
}

final RegExp _decimalPart = RegExp(r'^[0-9]{1,3}$');

bool _isLoopback(String host) {
  if (host == 'localhost' || host == '::1') {
    return true;
  }
  final List<String> parts = host.split('.');
  if (parts.length != 4 || parts.first != '127') {
    return false;
  }
  for (final String part in parts) {
    if (!_decimalPart.hasMatch(part) || int.parse(part) > 255) {
      return false;
    }
  }
  return true;
}

/// Reads one response body against the caps of [sendCapped] and completes [result] once.
final class _CappedReader {
  _CappedReader(
    this._abort, {
    required this.successCap,
    required this.errorCap,
  });

  final Completer<void> _abort;
  final int successCap;
  final int errorCap;
  final Completer<CappedResponse> result = Completer<CappedResponse>();
  final BytesBuilder _builder = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? _subscription;
  http.StreamedResponse? _response;

  void start(http.StreamedResponse response) {
    if (result.isCompleted) {
      unawaited(response.stream.listen(null).cancel());
      return;
    }
    _response = response;
    _subscription = response.stream.listen(
      _onChunk,
      onError: fail,
      onDone: () => _complete(truncated: false),
      cancelOnError: true,
    );
  }

  bool get _success {
    final int status = _response!.statusCode;
    return status >= 200 && status < 300;
  }

  void _onChunk(List<int> chunk) {
    if (result.isCompleted) {
      return;
    }
    final int cap = _success ? successCap : errorCap;
    final int room = cap - _builder.length;
    if (chunk.length <= room) {
      _builder.add(chunk);
      return;
    }
    if (_success) {
      fail(CapExceededException(successCap), StackTrace.current);
      return;
    }
    _builder.add(chunk.sublist(0, room));
    _stop();
    _complete(truncated: true);
  }

  void _complete({required bool truncated}) {
    if (result.isCompleted) {
      return;
    }
    final http.StreamedResponse response = _response!;
    result.complete(
      CappedResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: _builder.takeBytes(),
        truncated: truncated,
      ),
    );
  }

  /// Completes [result] with [error] unless it is already complete, then aborts the request. The first
  /// failure wins: the deadline's timeout is recorded before the abort, so the failure the abort causes
  /// later is ignored.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!result.isCompleted) {
      result.completeError(error, stackTrace);
    }
    _stop();
  }

  void _stop() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }
}

/// Decodes [bytes] as UTF-8, replacing malformed sequences.
String decodeUtf8Lenient(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);
