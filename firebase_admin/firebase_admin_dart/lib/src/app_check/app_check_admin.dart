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

  /// How long a fetch of the keys may take.
  static const Duration _fetchTimeout = Duration(seconds: 10);

  /// After a failed fetch, how long checks fail without trying again, so that an outage of the key endpoint
  /// does not turn every incoming request into an outgoing one.
  static const Duration _retryAfterFailure = Duration(seconds: 30);

  /// How often a token signed with a key that is not in the cached set may cause the set to be fetched again
  /// (a key Google started using within the six hours).
  static const Duration _refetchOnUnknownKid = Duration(minutes: 5);

  /// The sizes of the RSA keys accepted, in bits.
  static const int _minKeyBits = 2048;
  static const int _maxKeyBits = 8192;

  _Keys? _keys;
  Future<_Keys>? _keysPending;
  DateTime? _failedAt;
  DateTime? _refetchedForKidAt;

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
    RsaPublicKey? key = (await _publicKeys()).byId[kid];
    if (key == null) {
      final DateTime now = app.now();
      final DateTime? last = _refetchedForKidAt;
      if (last == null || !now.isBefore(last.add(_refetchOnUnknownKid))) {
        _refetchedForKidAt = now;
        // Keep the current set until a new one has arrived: a failed refetch must not discard good keys.
        try {
          key = (await (_keysPending ??= _fetchKeysTracked())).byId[kid];
        } on FirebaseAppCheckAdminException {
          key = null;
        }
      }
    }
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
    // jsonDecode reads 1e999 as infinity: a token that never expires must not pass. The upper bound is the
    // last second a DateTime can hold.
    if (!_isTime(exp) || !_isTime(iat)) {
      invalid('"exp" and "iat" must be times in seconds');
    }
    exp as num;
    iat as num;
    if (exp <= iat) {
      invalid('it expires ("exp") before it was issued ("iat")');
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
    if (payload.containsKey('nbf')) {
      final Object? nbf = payload['nbf'];
      if (!_isTime(nbf)) {
        invalid('"nbf" must be a time in seconds');
      }
      if ((nbf as num) > now + skew) {
        invalid('it is not valid yet ("nbf")');
      }
    }
    return VerifiedAppCheckToken._(Map<String, Object?>.unmodifiable(payload));
  }

  Future<_Keys> _publicKeys() {
    final DateTime now = app.now();
    final _Keys? keys = _keys;
    if (keys != null && now.isBefore(keys.expiresAt)) {
      return Future<_Keys>.value(keys);
    }
    final DateTime? failedAt = _failedAt;
    if (failedAt != null && now.isBefore(failedAt.add(_retryAfterFailure))) {
      return Future<_Keys>.error(
        const FirebaseAppCheckAdminException(
          code: 'internal-error',
          message: '$_fetchFailure The last attempt failed moments ago.',
        ),
      );
    }
    return _keysPending ??= _fetchKeysTracked();
  }

  Future<_Keys> _fetchKeysTracked() {
    return _fetchKeys()
        .then(
          (_Keys keys) {
            _failedAt = null;
            return keys;
          },
          onError: (Object error, StackTrace stackTrace) {
            _failedAt = app.now();
            Error.throwWithStackTrace(error, stackTrace);
          },
        )
        .whenComplete(() => _keysPending = null);
  }

  static const String _fetchFailure =
      'Could not fetch the public keys that sign App Check tokens.';

  Future<_Keys> _fetchKeys() async {
    final int status;
    final Uint8List body;
    try {
      (status, body) = await _get().timeout(_fetchTimeout);
    } on FirebaseAppCheckAdminException {
      rethrow;
    } on Object {
      throw const FirebaseAppCheckAdminException(
        code: 'internal-error',
        message: _fetchFailure,
      );
    }
    if (status != 200) {
      throw FirebaseAppCheckAdminException(
        code: 'internal-error',
        message: '$_fetchFailure HTTP $status.',
        httpStatus: status,
      );
    }
    final Map<String, RsaPublicKey> byId = <String, RsaPublicKey>{};
    try {
      final Object? json = jsonDecode(utf8.decode(body));
      final Object? keys = json is Map<String, Object?> ? json['keys'] : null;
      if (keys is! List) {
        throw const FormatException('No "keys" list');
      }
      for (final Object? jwk in keys) {
        final ({String kid, RsaPublicKey key})? entry = _rsaKey(jwk);
        if (entry != null) {
          byId[entry.kid] = entry.key;
        }
      }
      if (byId.isEmpty) {
        throw const FormatException('No usable RSA signing key');
      }
    } on Object {
      throw FirebaseAppCheckAdminException(
        code: 'internal-error',
        message:
            '$_fetchFailure The answer is not a JSON Web Key Set with a usable RSA key.',
        httpStatus: status,
      );
    }
    final _Keys set = _Keys(byId, app.now().add(keysLifetime));
    _keys = set;
    return set;
  }

  /// Gets [jwksUri], reading at most [_maxKeysBytes] of the answer.
  Future<(int, Uint8List)> _get() async {
    final http.StreamedResponse response = await app.httpClient.send(
      http.Request('GET', jwksUri)..followRedirects = false,
    );
    final int? declared = response.contentLength;
    if (declared != null && declared > _maxKeysBytes) {
      unawaited(response.stream.listen(null, onError: (Object _) {}).cancel());
      throw FirebaseAppCheckAdminException(
        code: 'internal-error',
        message: '$_fetchFailure The answer is too large.',
        httpStatus: response.statusCode,
      );
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response.stream) {
      builder.add(chunk);
      if (builder.length > _maxKeysBytes) {
        throw FirebaseAppCheckAdminException(
          code: 'internal-error',
          message: '$_fetchFailure The answer is too large.',
          httpStatus: response.statusCode,
        );
      }
    }
    return (response.statusCode, builder.takeBytes());
  }

  /// The RS256 signing key of [jwk], or null for a key of another kind, algorithm or use, or with parameters
  /// out of bounds (a modulus of fewer than 2048 or more than 8192 bits, an exponent that is even, below 3 or
  /// above 2^32).
  static ({String kid, RsaPublicKey key})? _rsaKey(Object? jwk) {
    if (jwk is! Map<String, Object?>) {
      return null;
    }
    final Object? kid = jwk['kid'];
    final Object? n = jwk['n'];
    final Object? e = jwk['e'];
    if (jwk['kty'] != 'RSA' ||
        (jwk['alg'] != null && jwk['alg'] != 'RS256') ||
        (jwk['use'] != null && jwk['use'] != 'sig') ||
        kid is! String ||
        kid.isEmpty ||
        n is! String ||
        e is! String) {
      return null;
    }
    try {
      final Uint8List nBytes = decodeSegment(n);
      final Uint8List eBytes = decodeSegment(e);
      // Bound the sizes before any arithmetic: a huge modulus or exponent costs time on every check.
      if (nBytes.length > _maxKeyBits ~/ 8 + 1 ||
          eBytes.isEmpty ||
          eBytes.length > 4) {
        return null;
      }
      final BigInt modulus = _unsigned(nBytes);
      final BigInt exponent = _unsigned(eBytes);
      if (modulus.bitLength < _minKeyBits ||
          modulus.bitLength > _maxKeyBits ||
          exponent < BigInt.from(3) ||
          exponent.isEven) {
        return null;
      }
      return (kid: kid, key: RsaPublicKey(modulus, exponent));
    } on FormatException {
      return null;
    }
  }

  static bool _isTime(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 8640000000000;

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

  /// The audiences (`aud`) that are strings.
  List<String> get audience => <String>[
    for (final Object? value in claims['aud']! as List)
      if (value is String) value,
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
