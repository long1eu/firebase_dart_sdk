/// Credentials for the emulator (owner U): the unsigned mock user token and the admin `owner`
/// credential (`rtdb_protocol.md` 2.4; threat model T3).
library;

import 'dart:convert';

import 'package:firebase_database_dart/src/realtime/server_message.dart';

/// The credential the admin SDKs send to the emulator, as `gauth` with `cred: "owner"` (2.4,
/// AuthTokenProvider.ts:108-111, PersistentConnection.ts:383).
const String ownerToken = 'owner';

/// An unsigned JWT for the emulator built from [claims] for [projectId] (2.4,
/// `util:src/emulator.ts:95-142`).
///
/// Header `{"alg":"none","type":"JWT"}` (`type`, not `typ`); payload `iss`
/// `https://securetoken.google.com/<projectId>`, `aud`, `iat` (default 0), `exp` = `iat` + 3600,
/// `auth_time`, `sub`, `user_id`, `firebase: {sign_in_provider: custom, identities: {}}`, then
/// [claims] on top in that key order; base64url without padding; empty signature. Because `iat` is
/// present the token is sent as `auth` (4.6). Throws [ArgumentError] when [claims] has neither
/// `sub` nor `user_id`, or has `uid`. Use only with an emulator (T3: refused otherwise by the
/// caller).
///
/// `sub` defaults to `user_id` (the emulator reads the uid from `sub` only, probe "Auth"). Also
/// throws [ArgumentError] for an empty [projectId], a non-string or empty `sub`/`user_id`, an
/// `iat` that is not a whole number (`wholeJsonNumber`: `1.0` is accepted and sent as `1` on every
/// compiler) and a claim value JSON cannot encode. Errors never quote a claim value.
String createMockUserToken(
  Map<String, Object?> claims, {
  required String projectId,
}) {
  if (projectId.isEmpty) {
    throw ArgumentError.value(projectId, 'projectId', 'must not be empty');
  }
  if (claims.containsKey('uid')) {
    throw ArgumentError(
      'mockUserToken: the "uid" claim is not supported; use "sub" for the user id',
      'claims',
    );
  }
  final Object? sub = claims['sub'] ?? claims['user_id'];
  if (sub is! String || sub.isEmpty) {
    throw ArgumentError(
      'mockUserToken must contain a "sub" or "user_id" string',
      'claims',
    );
  }
  final int? iat = wholeJsonNumber(claims['iat'] ?? 0);
  if (iat == null) {
    throw ArgumentError(
      'mockUserToken "iat" must be an integer (seconds)',
      'claims',
    );
  }
  final Map<String, Object?> payload = <String, Object?>{
    'iss': 'https://securetoken.google.com/$projectId',
    'aud': projectId,
    'iat': iat,
    'exp': iat + 3600,
    'auth_time': iat,
    'sub': sub,
    'user_id': sub,
    'firebase': <String, Object?>{
      'sign_in_provider': 'custom',
      'identities': <String, Object?>{},
    },
    ...claims,
  };
  // The claims may hold `iat` as `1.0`, which the VM encodes as `1.0` and dart2js as `1`; the
  // int keeps the claim's place and encodes as `1` on every compiler.
  payload['iat'] = iat;
  final String encodedPayload;
  try {
    encodedPayload = _base64UrlJson(payload);
  } on JsonUnsupportedObjectError {
    throw ArgumentError('mockUserToken claims must be JSON values', 'claims');
  }
  return '${_base64UrlJson(const <String, Object?>{'alg': 'none', 'type': 'JWT'})}'
      '.$encodedPayload.';
}

String _base64UrlJson(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
