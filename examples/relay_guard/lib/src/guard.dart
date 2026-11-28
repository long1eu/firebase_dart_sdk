import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'caller.dart';

const String _callerKey = 'relay_guard.caller';
const String _bodyKey = 'relay_guard.body';

/// The [Caller] that [relayGuard] proved for [request].
Caller callerOf(Request request) => request.context[_callerKey]! as Caller;

/// The body that [relayGuard] read for [request] (at most its `maxBodyBytes`).
Uint8List bodyOf(Request request) => request.context[_bodyKey]! as Uint8List;

/// Middleware that refuses a request unless it is a `POST` of JSON of at most [maxBodyBytes], with the tokens
/// [verifier] accepts, from a caller under [maxPerMinute] requests a minute. See the library documentation.
///
/// Answers, with no detail for the caller (the reason goes to [log]):
///
/// | Status | When |
/// | --- | --- |
/// | 405 | not a `POST` |
/// | 415 | not `application/json` |
/// | 413 | the body is larger than [maxBodyBytes] |
/// | 401 | a token is missing or not valid |
/// | 429 | the caller passed [maxPerMinute] (with `Retry-After: 60`) |
/// | 503 | the verifier could not check a token (the keys could not be fetched; with `Retry-After: 30`) |
///
/// The rate limit counts per user when an ID token is present, else per app and address of the connection,
/// else per address. [clock] is for tests.
Middleware relayGuard({
  required CallerVerifier verifier,
  bool requireAppCheck = true,
  bool requireUser = false,
  int maxBodyBytes = 64 * 1024,
  int maxPerMinute = 60,
  DateTime Function()? clock,
  void Function(String message)? log,
}) {
  final _RateLimit limit = _RateLimit(maxPerMinute, clock ?? DateTime.now);
  final void Function(String) note = log ?? (_) {};
  return (Handler inner) => (Request request) async {
    if (request.method != 'POST') {
      return Response(405, headers: <String, String>{'allow': 'POST'});
    }
    if (request.mimeType != 'application/json') {
      return Response(415);
    }
    final int? declared = request.contentLength;
    if (declared != null && declared > maxBodyBytes) {
      return Response(413);
    }

    String? appId;
    String? uid;
    try {
      final String? appCheck = request.headers['x-firebase-appcheck'];
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
      return Response(401);
    } on Object catch (e) {
      note('could not check the tokens (${e.runtimeType})');
      return Response(503, headers: <String, String>{'retry-after': '30'});
    }

    final String address = _address(request);
    final String key = uid != null
        ? 'user:$uid'
        : appId != null
        ? 'app:$appId:$address'
        : 'addr:$address';
    if (!limit.admit(key)) {
      note('rate limited: $key');
      return Response(429, headers: <String, String>{'retry-after': '60'});
    }

    final Uint8List? body = await _read(request, maxBodyBytes);
    if (body == null) {
      return Response(413);
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

String _address(Request request) {
  final Object? info = request.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
}

/// A sliding window of one minute per key, with at most [_maxKeys] keys kept.
final class _RateLimit {
  _RateLimit(this.perMinute, this.clock);

  final int perMinute;
  final DateTime Function() clock;
  final Map<String, List<DateTime>> _times = <String, List<DateTime>>{};
  static const int _maxKeys = 100000;

  bool admit(String key) {
    final DateTime now = clock();
    final DateTime since = now.subtract(const Duration(minutes: 1));
    if (_times.length >= _maxKeys) {
      _times.removeWhere((String _, List<DateTime> times) {
        times.removeWhere((DateTime t) => !t.isAfter(since));
        return times.isEmpty;
      });
    }
    final List<DateTime> times = _times.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere((DateTime t) => !t.isAfter(since));
    if (times.length >= perMinute) {
      return false;
    }
    times.add(now);
    return true;
  }
}
