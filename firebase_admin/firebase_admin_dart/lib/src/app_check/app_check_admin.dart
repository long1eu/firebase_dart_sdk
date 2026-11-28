import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app.dart';
import '../auth/jwt.dart';
import '../auth/rsa.dart';
import 'exception.dart';

/// Checks Firebase App Check tokens: the server side of App Check, for a backend of your own (a relay, an API)
/// that the official SDKs' enforcement does not cover.
///
/// Get it with `FirebaseAppCheckAdmin(app)` or `app.appCheck()` (the same object for the same app).
///
/// ```dart
/// import 'package:firebase_admin_dart/app_check.dart';
///
/// Future<String?> appIdOf(FirebaseAdminApp app, String? header) async {
///   if (header == null) {
///     return null;
///   }
///   try {
///     final VerifiedAppCheckToken token = await app.appCheck().verifyToken(header);
///     return token.appId;
///   } on FirebaseAppCheckAdminException {
///     return null;
///   }
/// }
/// ```
///
/// Replay protection (`consumeAppCheckToken` of the Node SDK, which marks a token as used on the App Check
/// backend) is not implemented yet.
class FirebaseAppCheckAdmin {
  /// The App Check checks of [app]: the same object for the same app.
  factory FirebaseAppCheckAdmin(FirebaseAdminApp app) =>
      _instances[app] ??= FirebaseAppCheckAdmin._(app);

  FirebaseAppCheckAdmin._(this.app);

  static final Expando<FirebaseAppCheckAdmin> _instances =
      Expando<FirebaseAppCheckAdmin>('FirebaseAppCheckAdmin');

  /// The app whose project the tokens must belong to.
  final FirebaseAdminApp app;

  /// Where the public keys that sign App Check tokens are published, as a JSON Web Key Set.
  static final Uri jwksUri = Uri.parse(
    'https://firebaseappcheck.googleapis.com/v1/jwks',
  );

  /// The issuer of App Check tokens, followed by the project number.
  static const String issuerPrefix = 'https://firebaseappcheck.googleapis.com/';

  /// How long the public keys are kept: six hours, as in the Node and Python Admin SDKs.
  static const Duration keysLifetime = Duration(hours: 6);

  /// The default clock skew [verifyToken] allows: 10 seconds, as `verifyIdToken`.
  static const Duration defaultClockSkew = Duration(seconds: 10);

  /// The largest clock skew [verifyToken] accepts: 5 minutes.
  static const Duration maxClockSkew = Duration(minutes: 5);

  /// The longest token read. App Check tokens are well under 2 KiB.
  static const int maxTokenLength = 16 * 1024;

  /// The largest key set read.
  static const int _maxKeysBytes = 1024 * 1024;

  _Keys? _keys;
  Future<_Keys>? _keysPending;

  /// Verifies the App Check token [token] (the `X-Firebase-AppCheck` header of a request) and returns its
  /// claims.
  ///
  /// Checks, as the Admin SDKs do: the header (`typ` JWT, `alg` RS256, a `kid` among the current keys of
  /// [jwksUri]), the RS256 signature, `iss` (`https://firebaseappcheck.googleapis.com/<project number>`), `aud`
  /// (a list holding `projects/<project id>`, or `projects/<projectNumber>` when [projectNumber] is given),
  /// `sub` (the app id, non-empty), `exp` in the future and `iat` in the past. Times may be off by [clockSkew]
  /// (default [defaultClockSkew], at most [maxClockSkew]).
  ///
  /// Without [projectNumber] the issuer must be the prefix followed by a number; with it, exactly that number.
  /// An unsigned token (`alg: none`) is always refused: App Check has no emulator that issues them.
  ///
  /// Throws a [FirebaseAppCheckAdminException]: `app-check-token-expired`, `invalid-argument` for any other
  /// failed check, `internal-error` if the keys cannot be fetched.
  Future<VerifiedAppCheckToken> verifyToken(
    String token, {
    String? projectNumber,
    Duration clockSkew = defaultClockSkew,
  }) async {
    app.checkOpen();
    if (clockSkew.isNegative || clockSkew > maxClockSkew) {
      throw ArgumentError.value(
        clockSkew,
        'clockSkew',
        'Must be between zero and $maxClockSkew',
      );
    }
    if (projectNumber != null &&
        !RegExp(r'^\d{1,30}$').hasMatch(projectNumber)) {
      throw ArgumentError.value(
        projectNumber,
        'projectNumber',
        'Not a project number',
      );
    }
    Never invalid(String why) => throw FirebaseAppCheckAdminException(
      code: 'invalid-argument',
      message: 'The App Check token is not valid: $why.',
    );

    if (token.isEmpty || token.length > maxTokenLength) {
      invalid('it is empty or too long');
    }
    final List<String> parts = token.split('.');
    if (parts.length != 3) {
      invalid('it is not a JWT');
    }
    final Map<String, Object?> header;
    final Map<String, Object?> payload;
    final Uint8List signature;
    try {
      header = decodeJsonSegment(parts[0]);
      payload = decodeJsonSegment(parts[1]);
      signature = decodeSegment(parts[2]);
    } on FormatException {
      invalid('it is not a well-formed JWT');
    }

    final Object? alg = header['alg'];
    if (alg == 'none' || signature.isEmpty) {
      invalid('it is unsigned');
    }
    if (alg != 'RS256') {
      invalid('the algorithm must be RS256');
    }
    if (header['typ'] != 'JWT') {
      invalid('its type ("typ") must be JWT');
    }
    final Object? kid = header['kid'];
    if (kid is! String || kid.isEmpty) {
      invalid('it has no "kid" header');
    }
    final RsaPublicKey? key = (await _publicKeys()).byId[kid];
    if (key == null) {
      invalid('its "kid" does not match a current App Check public key');
    }
    if (!key.verifyRs256(ascii.encode('${parts[0]}.${parts[1]}'), signature)) {
      invalid('its signature is invalid');
    }

    final Object? iss = payload['iss'];
    final String? number = iss is String && iss.startsWith(issuerPrefix)
        ? iss.substring(issuerPrefix.length)
        : null;
    if (number == null || !RegExp(r'^\d{1,30}$').hasMatch(number)) {
      invalid('its issuer ("iss") is not $issuerPrefix<project number>');
    }
    if (projectNumber != null && number != projectNumber) {
      invalid('its issuer ("iss") is not the project number $projectNumber');
    }
    final Object? aud = payload['aud'];
    final Set<String> accepted = <String>{
      'projects/${app.projectId}',
      if (projectNumber != null) 'projects/$projectNumber',
    };
    if (aud is! List || !aud.any(accepted.contains)) {
      invalid(
        'its audience ("aud") does not hold projects/${app.projectId}'
        '${projectNumber == null ? '' : ' or projects/$projectNumber'}',
      );
    }
    final Object? sub = payload['sub'];
    if (sub is! String || sub.isEmpty) {
      invalid('its subject ("sub", the app id) is missing or empty');
    }
    final Object? exp = payload['exp'];
    final Object? iat = payload['iat'];
    // jsonDecode reads 1e999 as infinity: a token that never expires must not pass.
    if (exp is! num || iat is! num || !exp.isFinite || !iat.isFinite) {
      invalid('"exp" and "iat" must be finite numbers');
    }
    final double now = app.now().millisecondsSinceEpoch / 1000;
    final int skew = clockSkew.inSeconds;
    if (exp <= now - skew) {
      throw const FirebaseAppCheckAdminException(
        code: 'app-check-token-expired',
        message: 'The App Check token has expired.',
      );
    }
    if (iat > now + skew) {
      invalid('it was issued in the future ("iat")');
    }
    return VerifiedAppCheckToken._(Map<String, Object?>.unmodifiable(payload));
  }

  Future<_Keys> _publicKeys() {
    final _Keys? keys = _keys;
    if (keys != null && app.now().isBefore(keys.expiresAt)) {
      return Future<_Keys>.value(keys);
    }
    return _keysPending ??= _fetchKeys().whenComplete(
      () => _keysPending = null,
    );
  }

  Future<_Keys> _fetchKeys() async {
    const String failure =
        'Could not fetch the public keys that sign App Check tokens.';
    final http.Response response;
    try {
      response = await app.httpClient.get(jwksUri);
    } on Object {
      throw const FirebaseAppCheckAdminException(
        code: 'internal-error',
        message: failure,
      );
    }
    if (response.statusCode != 200) {
      throw FirebaseAppCheckAdminException(
        code: 'internal-error',
        message: '$failure HTTP ${response.statusCode}.',
        httpStatus: response.statusCode,
      );
    }
    final Map<String, RsaPublicKey> byId = <String, RsaPublicKey>{};
    try {
      if (response.bodyBytes.length > _maxKeysBytes) {
        throw const FormatException('Too large');
      }
      final Object? json = jsonDecode(response.body);
      final Object? keys = json is Map<String, Object?> ? json['keys'] : null;
      if (keys is! List) {
        throw const FormatException('No "keys" list');
      }
      for (final Object? jwk in keys) {
        if (jwk is! Map<String, Object?>) {
          continue;
        }
        final Object? kid = jwk['kid'];
        final Object? n = jwk['n'];
        final Object? e = jwk['e'];
        // Only RSA signing keys; a key that says it is for another algorithm is left out.
        if (jwk['kty'] != 'RSA' ||
            (jwk['alg'] != null && jwk['alg'] != 'RS256') ||
            (jwk['use'] != null && jwk['use'] != 'sig') ||
            kid is! String ||
            n is! String ||
            e is! String) {
          continue;
        }
        byId[kid] = RsaPublicKey(
          _unsigned(decodeSegment(n)),
          _unsigned(decodeSegment(e)),
        );
      }
      if (byId.isEmpty) {
        throw const FormatException('No RSA signing key');
      }
    } on Object {
      throw FirebaseAppCheckAdminException(
        code: 'internal-error',
        message: '$failure The answer is not a JSON Web Key Set of RSA keys.',
        httpStatus: response.statusCode,
      );
    }
    final _Keys set = _Keys(byId, app.now().add(keysLifetime));
    _keys = set;
    return set;
  }

  static BigInt _unsigned(List<int> bytes) {
    BigInt value = BigInt.zero;
    for (final int byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }
}

/// An App Check token that `FirebaseAppCheckAdmin.verifyToken` checked.
final class VerifiedAppCheckToken {
  VerifiedAppCheckToken._(this.claims);

  /// Every claim of the token.
  final Map<String, Object?> claims;

  /// The Firebase app id of the app that obtained the token (`sub`).
  String get appId => claims['sub']! as String;

  /// The project number from the issuer.
  String get projectNumber => (claims['iss']! as String).substring(
    FirebaseAppCheckAdmin.issuerPrefix.length,
  );

  /// The audiences (`aud`).
  List<String> get audience => <String>[
    for (final Object? value in claims['aud']! as List) '$value',
  ];

  /// When the token expires (`exp`).
  DateTime get expiresAt => _time(claims['exp']! as num);

  /// When the token was issued (`iat`).
  DateTime get issuedAt => _time(claims['iat']! as num);

  static DateTime _time(num seconds) => DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
    isUtc: true,
  );

  @override
  String toString() => 'VerifiedAppCheckToken(appId: $appId)';
}

final class _Keys {
  _Keys(this.byId, this.expiresAt);

  final Map<String, RsaPublicKey> byId;
  final DateTime expiresAt;
}

/// `app.appCheck()`.
extension FirebaseAdminAppAppCheck on FirebaseAdminApp {
  /// The App Check checks of this app: `FirebaseAppCheckAdmin(this)`.
  FirebaseAppCheckAdmin appCheck() => FirebaseAppCheckAdmin(this);
}
