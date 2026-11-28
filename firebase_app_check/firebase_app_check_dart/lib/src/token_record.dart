import 'dart:convert';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:meta/meta.dart';

/// The longest stored value that is looked at, in characters.
const int _maxRecordLength = 16384;

/// The shortest and the longest lifetime a record may carry, in milliseconds: 60 s and 7 days,
/// the bounds every token of this package has.
const int _minTtlMs = 60000;
const int _maxTtlMs = 604800000;

/// The reason of a record whose token is past its expiry. It is the one reason that is not
/// logged: every record ends this way.
@internal
const String recordExpired = 'expired';

/// The key of the stored session token of [app]: one record per app name and app id.
@internal
String recordKey(FirebaseApp app) => 'app_check/${app.persistenceKey}/token';

/// The stored form of [token]: its text, its wall-clock issue time and its lifetime, both in
/// milliseconds. The monotonic reading is not stored: it means nothing to another process.
@internal
String encodeRecord(SessionToken token) => jsonEncode(<String, Object>{
  'v': 1,
  'token': token.token,
  'issuedAt': token.issuedWall.millisecondsSinceEpoch,
  'ttl': token.ttl.inMilliseconds,
});

/// What [parseRecord] made of a stored value: a [token], or the fixed [reason] it was rejected
/// for.
@internal
final class RecordParse {
  /// A stored value that holds [token].
  const RecordParse.valid(SessionToken this.token) : reason = null;

  /// A stored value rejected for [reason], one of the fixed texts of [parseRecord].
  const RecordParse.rejected(String this.reason) : token = null;

  /// The token of a valid record.
  final SessionToken? token;

  /// Why the value was rejected. Never a part of the value.
  final String? reason;
}

/// Reads the stored [value]. Every field is untrusted: another script of the page, or another
/// program of the user, may have written it.
///
/// A value is rejected with one of these reasons, checked in this order: `too long`, `not JSON`,
/// `unknown version`, `invalid token`, `invalid times`, `issued in the future`, `expired`. A valid
/// record becomes a token whose monotonic issue reading is now minus its wall-clock age, so both
/// clocks give it the same age from here on.
@internal
RecordParse parseRecord(String value, Clocks clocks) {
  if (value.length > _maxRecordLength) {
    return const RecordParse.rejected('too long');
  }
  final Map<Object?, Object?>? json = _decodeObject(value);
  if (json == null) {
    return const RecordParse.rejected('not JSON');
  }
  final Object? version = json['v'];
  if (version is! num || version != 1) {
    return const RecordParse.rejected('unknown version');
  }
  final Object? token = json['token'];
  if (token is! String || !isTokenText(token)) {
    return const RecordParse.rejected('invalid token');
  }
  final int? issuedAt = parseBoundedInt(
    json['issuedAt'],
    min: 0,
    max: maxSafeInteger,
  );
  final int? ttl = parseBoundedInt(json['ttl'], min: _minTtlMs, max: _maxTtlMs);
  if (issuedAt == null || ttl == null) {
    return const RecordParse.rejected('invalid times');
  }
  final int now = clocks.wallNow().millisecondsSinceEpoch;
  if (issuedAt > now) {
    return const RecordParse.rejected('issued in the future');
  }
  if (issuedAt + ttl <= now) {
    return const RecordParse.rejected(recordExpired);
  }
  return RecordParse.valid(
    SessionToken(
      token: token,
      issuedWall: DateTime.fromMillisecondsSinceEpoch(issuedAt, isUtc: true),
      issuedMono: clocks.monoNow() - Duration(milliseconds: now - issuedAt),
      ttl: Duration(milliseconds: ttl),
    ),
  );
}

/// [value] as a JSON object, or null when it is not one.
Map<Object?, Object?>? _decodeObject(String value) {
  try {
    final Object? decoded = decodeGuardedText(value);
    return decoded is Map<Object?, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
