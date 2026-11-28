import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'caller.dart';

const String _callerKey = 'relay_guard.caller';
const String _bodyKey = 'relay_guard.body';

/// The [Caller] that [relayGuard] proved for [request].
Caller callerOf(Request request) => request.context[_callerKey]! as Caller;

/// The body that [relayGuard] read for [request] (at most its `maxBodyBytes`).
Uint8List bodyOf(Request request) => request.context[_bodyKey]! as Uint8List;

/// Middleware that refuses a request unless it is a `POST` of JSON of at most [maxBodyBytes], to [path] when
/// given, with the tokens [verifier] accepts, within the rate limits. See the library documentation.
///
/// Answers, with no detail for the caller (the reason goes to [log]) and `Connection: close`:
///
/// | Status | When |
/// | --- | --- |
/// | 404 | not [path] |
/// | 405 | not a `POST` |
/// | 415 | not `application/json` |
/// | 413 | the body is larger than [maxBodyBytes] |
/// | 408 | the body did not arrive within [bodyTimeout] |
/// | 400 | the body broke off |
/// | 401 | a token is missing or not valid |
/// | 429 | a rate limit was reached (with `Retry-After: 60`) |
/// | 503 | the verifier could not check a token (the keys could not be fetched; with `Retry-After: 30`) |
///
/// Rate limits, each a window of one minute, all of which must have room:
///
/// * [maxPerCallerPerMinute] per App Check token and per user (both apply when both are present), so a caller
///   cannot multiply its budget with many accounts;
/// * [maxPerAppPerMinute] per app id;
/// * [maxPerMinute] for everything this middleware sees;
/// * without an App Check token (only with `requireAppCheck: false`), [maxPerCallerPerMinute] per address.
///   Behind a proxy (Cloud Run's front end, a load balancer) the address of the connection is the proxy's: set
///   [trustedProxyHops] to the number of proxies that append to `X-Forwarded-For`, and the address is read from
///   that many entries from the right. IPv6 addresses count per /64.
///
/// The limits are per process: with several instances each counts on its own. [clock] is for tests.
Middleware relayGuard({
  required CallerVerifier verifier,
  String? path,
  bool requireAppCheck = true,
  bool requireUser = false,
  int maxBodyBytes = 64 * 1024,
  Duration bodyTimeout = const Duration(seconds: 10),
  int maxPerCallerPerMinute = 60,
  int maxPerAppPerMinute = 3000,
  int maxPerMinute = 10000,
  int trustedProxyHops = 0,
  DateTime Function()? clock,
  void Function(String message)? log,
}) {
  final _RateLimit limit = _RateLimit(clock ?? DateTime.now);
  final void Function(String) note = log ?? (_) {};
  Response refuse(
    int status, [
    Map<String, String> headers = const <String, String>{},
  ]) => Response(
    status,
    headers: <String, String>{...headers, 'connection': 'close'},
  );

  return (Handler inner) => (Request request) async {
    if (path != null && request.url.path != path) {
      return refuse(404);
    }
    if (request.method != 'POST') {
      return refuse(405, <String, String>{'allow': 'POST'});
    }
    if (request.mimeType != 'application/json') {
      return refuse(415);
    }
    final int? declared = request.contentLength;
    if (declared != null && declared > maxBodyBytes) {
      return refuse(413);
    }

    final String? appCheck = request.headers['x-firebase-appcheck'];
    String? appId;
    String? uid;
    try {
      if (appCheck != null && appCheck.isNotEmpty) {
        appId = await verifier.appIdOf(appCheck);
      } else if (requireAppCheck) {
        throw const CallerRejected('no App Check token');
      }
      final String? authorization = request.headers['authorization'];
      if (authorization != null && authorization.isNotEmpty) {
        if (!authorization.startsWith('Bearer ')) {
          throw const CallerRejected(
            'the Authorization header is not a bearer token',
          );
        }
        uid = await verifier.uidOf(authorization.substring(7));
      } else if (requireUser) {
        throw const CallerRejected('no ID token');
      }
    } on CallerRejected catch (e) {
      note('refused: ${e.reason}');
      return refuse(401);
    } on Object catch (e) {
      note('could not check the tokens (${e.runtimeType})');
      return refuse(503, <String, String>{'retry-after': '30'});
    }

    final List<(String, int)> buckets = <(String, int)>[
      ('all', maxPerMinute),
      if (appId != null) ('app:$appId', maxPerAppPerMinute),
      if (appCheck != null && appCheck.isNotEmpty)
        ('token:${_hash(appCheck)}', maxPerCallerPerMinute),
      if (uid != null) ('user:$uid', maxPerCallerPerMinute),
      if (appCheck == null || appCheck.isEmpty)
        ('addr:${_address(request, trustedProxyHops)}', maxPerCallerPerMinute),
    ];
    final String? full = limit.admit(buckets);
    if (full != null) {
      note('rate limited: $full');
      return refuse(429, <String, String>{'retry-after': '60'});
    }

    final Uint8List? body;
    try {
      body = await _read(request, maxBodyBytes).timeout(bodyTimeout);
    } on TimeoutException {
      note('the body did not arrive in time');
      return refuse(408);
    } on Object catch (e) {
      note('the body broke off (${e.runtimeType})');
      return refuse(400);
    }
    if (body == null) {
      return refuse(413);
    }
    return inner(
      request.change(
        context: <String, Object>{
          _callerKey: Caller(appId: appId, uid: uid),
          _bodyKey: body,
        },
      ),
    );
  };
}

/// The body, or null when it passes [max] bytes.
Future<Uint8List?> _read(Request request, int max) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > max) {
      return null;
    }
  }
  return builder.takeBytes();
}

/// A short, stable name for a token in a rate-limit key and in the log, without the token itself.
String _hash(String token) =>
    sha256.convert(utf8.encode(token)).toString().substring(0, 32);

String _address(Request request, int trustedProxyHops) {
  String? address;
  if (trustedProxyHops > 0) {
    final List<String> hops = (request.headers['x-forwarded-for'] ?? '')
        .split(',')
        .map((String hop) => hop.trim())
        .where((String hop) => hop.isNotEmpty)
        .toList();
    if (hops.length >= trustedProxyHops) {
      address = hops[hops.length - trustedProxyHops];
    }
  } else {
    final Object? info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      address = info.remoteAddress.address;
    }
  }
  final InternetAddress? parsed = address == null
      ? null
      : InternetAddress.tryParse(address);
  if (parsed == null) {
    return 'unknown';
  }
  if (parsed.type == InternetAddressType.IPv6) {
    // One host usually has a whole /64.
    return parsed.rawAddress
        .sublist(0, 8)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
  return parsed.address;
}

/// Fixed one-minute windows per key, at most [_maxKeys] keys. When the table is full, expired windows are
/// removed (at most every ten seconds); if it is still full, requests that need a new key are refused.
final class _RateLimit {
  _RateLimit(this.clock);

  final DateTime Function() clock;
  final Map<String, _Window> _windows = <String, _Window>{};
  DateTime? _prunedAt;
  static const int _maxKeys = 100000;
  static const Duration _window = Duration(minutes: 1);

  /// Admits a request that counts against every bucket, or returns the key of a full one (nothing is counted
  /// then).
  String? admit(List<(String, int)> buckets) {
    final DateTime now = clock();
    final List<_Window> windows = <_Window>[];
    for (final (String key, int max) in buckets) {
      _Window? window = _windows[key];
      if (window != null && !now.isBefore(window.start.add(_window))) {
        window
          ..start = now
          ..count = 0;
      }
      if (window == null) {
        if (_windows.length >= _maxKeys) {
          _prune(now);
          if (_windows.length >= _maxKeys) {
            return key;
          }
        }
        window = _windows[key] = _Window(now);
      }
      if (window.count >= max) {
        return key;
      }
      windows.add(window);
    }
    for (final _Window window in windows) {
      window.count++;
    }
    return null;
  }

  void _prune(DateTime now) {
    final DateTime? last = _prunedAt;
    if (last != null && now.isBefore(last.add(const Duration(seconds: 10)))) {
      return;
    }
    _prunedAt = now;
    _windows.removeWhere(
      (String _, _Window w) => !now.isBefore(w.start.add(_window)),
    );
  }
}

final class _Window {
  _Window(this.start);

  DateTime start;
  int count = 0;
}
