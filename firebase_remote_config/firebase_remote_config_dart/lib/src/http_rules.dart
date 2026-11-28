import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A response read with a cap on its body.
final class CappedResponse {
  /// Creates a response; the package creates them.
  const CappedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.truncated = false,
  });

  /// The HTTP status.
  final int statusCode;

  /// The response headers, with lowercase names.
  final Map<String, String> headers;

  /// The body, at most the cap it was read with.
  final Uint8List body;

  /// True when a non-2xx body was cut at errorCap (the status stays meaningful).
  final bool truncated;
}

/// A 2xx body longer than its cap. Installations maps it to `invalid-response`, Remote Config to
/// `fetch-client-parse`.
final class CapExceededException implements Exception {
  /// Creates the exception for a body over [cap] bytes.
  const CapExceededException(this.cap);

  /// The cap, in bytes.
  final int cap;

  @override
  String toString() =>
      'CapExceededException: the body is longer than $cap bytes';
}

/// Builds the request with an abort future (so it can be an AbortableRequest), sets followRedirects to
/// false, sends it with [deadline], and reads the body: a 2xx body past [successCap] aborts and throws
/// CapExceededException; a non-2xx body is cut at [errorCap] and returned with truncated = true. Past the
/// deadline it aborts and throws TimeoutException.
Future<CappedResponse> sendCapped(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build, {
  required int successCap,
  required int errorCap,
  required Duration deadline,
}) async {
  final Completer<void> abort = Completer<void>();
  final Completer<CappedResponse> timedOut = Completer<CappedResponse>();
  final TimeoutException timeout = TimeoutException(
    'The request took longer than its deadline',
    deadline,
  );
  bool deadlinePassed = false;
  final Timer timer = Timer(deadline, () {
    deadlinePassed = true;
    timedOut.completeError(timeout);
    _complete(abort);
  });
  try {
    final http.BaseRequest request = build(abort.future)
      ..followRedirects = false;
    final Future<CappedResponse> work = _sendAndRead(
      client,
      request,
      abort,
      successCap: successCap,
      errorCap: errorCap,
    );
    // When the deadline wins, the aborted request fails later; that error is expected.
    work.ignore();
    return await Future.any(<Future<CappedResponse>>[work, timedOut.future]);
  } catch (error) {
    // The abort can fail the request synchronously, before the timeout reaches Future.any; past the
    // deadline every failure is the timeout.
    if (deadlinePassed) {
      throw timeout;
    }
    rethrow;
  } finally {
    timer.cancel();
  }
}

Future<CappedResponse> _sendAndRead(
  http.Client client,
  http.BaseRequest request,
  Completer<void> abort, {
  required int successCap,
  required int errorCap,
}) async {
  final http.StreamedResponse response = await client.send(request);
  final int status = response.statusCode;
  if (status >= 200 && status < 300) {
    final CappedResponse read = await readCapped(response, cap: successCap);
    if (read.truncated) {
      _complete(abort);
      throw CapExceededException(successCap);
    }
    return read;
  }
  return readCapped(response, cap: errorCap);
}

/// Realtime: builds the AbortableRequest with [abort], sets followRedirects to false, sends it with no
/// deadline and returns the streamed response; a non-200 body is read by the caller with
/// readCapped(errorCap).
Future<http.StreamedResponse> sendStreaming(
  http.Client client,
  http.BaseRequest Function(Future<void> abort) build,
  Future<void> abort,
) {
  final http.BaseRequest request = build(abort)..followRedirects = false;
  return client.send(request);
}

/// Reads the body of [response] up to [cap] bytes. A longer body is cut at [cap], the rest is not read,
/// and the result has `truncated` set; it never throws for size.
Future<CappedResponse> readCapped(
  http.StreamedResponse response, {
  required int cap,
}) async {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  bool truncated = false;
  await for (final List<int> chunk in response.stream) {
    final int room = cap - bytes.length;
    if (chunk.length > room) {
      bytes.add(chunk.sublist(0, room));
      truncated = true;
      break;
    }
    bytes.add(chunk);
  }
  return CappedResponse(
    statusCode: response.statusCode,
    headers: response.headers,
    body: bytes.takeBytes(),
    truncated: truncated,
  );
}

/// The largest server text, in UTF-8 bytes, that reaches a caller.
const int maxServerTextBytes = 1024;

/// Removes control characters from [text] and cuts it at 1 KiB of UTF-8, at a character boundary.
String sanitizeServerText(String text) {
  final StringBuffer buffer = StringBuffer();
  int length = 0;
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
    if (length + size > maxServerTextBytes) {
      break;
    }
    length += size;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// Checks an origin given to a constructor (5.11 rule 1) and returns it reduced to scheme, host and port.
///
/// Throws an [ArgumentError] unless [origin] has only a scheme, a host and an optional port (an empty
/// path or `/`), and the scheme is `https`, or `http` with a loopback host (`127.0.0.0/8`, `::1`,
/// `localhost`).
Uri checkOrigin(Uri origin) {
  final bool bare =
      origin.host.isNotEmpty &&
      (origin.path.isEmpty || origin.path == '/') &&
      !origin.hasQuery &&
      !origin.hasFragment &&
      origin.userInfo.isEmpty;
  if (!bare) {
    throw ArgumentError(
      'An origin has only a scheme, a host and a port: no path, query, fragment or user info.',
    );
  }
  final bool secure = origin.scheme == 'https';
  final bool loopback = origin.scheme == 'http' && _isLoopback(origin.host);
  if (!secure && !loopback) {
    throw ArgumentError(
      'An origin uses https, or http to a loopback host (127.0.0.0/8, ::1, localhost).',
    );
  }
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
  );
}

bool _isLoopback(String host) {
  final String lower = host.toLowerCase();
  if (lower == 'localhost' || lower == '::1') {
    return true;
  }
  final List<String> parts = lower.split('.');
  if (parts.length != 4 || parts.first != '127') {
    return false;
  }
  for (final String part in parts) {
    // Decimal digits only: int.tryParse alone accepts `+1` and `0x1`.
    final int? octet = _isDecimal(part) ? int.tryParse(part) : null;
    if (octet == null || octet > 255) {
      return false;
    }
  }
  return true;
}

bool _isDecimal(String text) {
  if (text.isEmpty || text.length > 3) {
    return false;
  }
  for (final int unit in text.codeUnits) {
    if (unit < 0x30 || unit > 0x39) {
      return false;
    }
  }
  return true;
}

void _complete(Completer<void> completer) {
  if (!completer.isCompleted) {
    completer.complete();
  }
}

/// Decodes a body as UTF-8, replacing malformed sequences.
String decodeLenient(Uint8List body) => utf8.decode(body, allowMalformed: true);
