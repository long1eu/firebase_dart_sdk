import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app.dart';
import '../credential.dart';
import '../exception.dart';
import 'exception.dart';
import 'jwt.dart';
import 'records.dart';
import 'rsa.dart';

/// The Firebase Auth admin calls of one [FirebaseAdminApp]: custom tokens, users, custom claims, revocation and
/// ID token verification. Pure Dart; it talks to the Identity Toolkit REST API.
///
/// Get it with `FirebaseAuthAdmin(app)` or `app.auth()` (the same object for the same app).
///
/// **For trusted code only: servers, CLIs, CI jobs and integration tests.** Admin calls and service account
/// credentials bypass security rules, and whoever can mint a custom token can sign in as any user. Never put a
/// service account key in an app, a web page, a Flutter asset of a release build or a repository; on Google
/// Cloud prefer Application Default Credentials with [AdminCredential.iam], which holds no key.
///
/// ```dart
/// import 'package:firebase_admin_dart/auth.dart';
///
/// Future<String> tokenForTester(FirebaseAdminApp app) async {
///   final AdminUser user = await app.auth().createUser(
///     customClaims: <String, Object?>{'role': 'tester'},
///   );
///   return app.auth().createCustomToken(
///     user.uid,
///     claims: <String, Object?>{'tier': 'pro'},
///   );
/// }
/// ```
///
/// With [FirebaseAdminApp.emulator] the calls go to the Auth emulator: requests carry
/// `Authorization: Bearer owner`, custom tokens are unsigned and [verifyIdToken] accepts the emulator's unsigned
/// ID tokens. Nothing else turns that on.
class FirebaseAuthAdmin {
  /// The auth admin calls of [app]: the same object for the same app.
  factory FirebaseAuthAdmin(FirebaseAdminApp app) =>
      _instances[app] ??= FirebaseAuthAdmin._(app);

  FirebaseAuthAdmin._(this.app);

  static final Expando<FirebaseAuthAdmin> _instances =
      Expando<FirebaseAuthAdmin>('FirebaseAuthAdmin');

  /// The app the calls are made for.
  final FirebaseAdminApp app;

  /// The project the calls are for (the one of [app]).
  String get projectId => app.projectId;

  /// Whether the calls go to the Auth emulator.
  bool get isEmulator => app.isEmulator;

  /// The audience of a custom token.
  static const String customTokenAudience =
      'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit';

  /// Where Google publishes the certificates of the keys that sign ID tokens (the source the Firebase
  /// documentation and the Admin SDKs use).
  static final Uri idTokenCertificatesUri = Uri.parse(
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
  );

  /// The default clock skew [verifyIdToken] allows: 10 seconds.
  static const Duration defaultClockSkew = Duration(seconds: 10);

  /// The largest clock skew [verifyIdToken] accepts: 5 minutes.
  static const Duration maxClockSkew = Duration(minutes: 5);

  /// Claim names a custom token or the custom claims of a user may not use: the reserved names of the Firebase
  /// documentation and of the Node Admin SDK.
  static const Set<String> reservedClaims = <String>{
    'acr', 'amr', 'at_hash', 'aud', 'auth_time', 'azp', 'cnf', 'c_hash', //
    'exp', 'firebase', 'iat', 'iss', 'jti', 'nbf', 'nonce', 'sub', 'user_id',
  };

  // ---------------------------------------------------------------------------------------------------------
  // Custom tokens

  /// Mints a custom token for [uid]: the client signs in with it (`FirebaseUserAuth.signInWithCustomToken`), and
  /// [claims] then appear in the user's ID tokens and in `request.auth.token` of the security rules.
  ///
  /// The token is a JWT (RS256, base64url) issued by the service account, for the Identity Toolkit audience, and
  /// valid for one hour. It is signed locally with [AdminCredential.serviceAccount], by the IAM Credentials API
  /// (`signBlob`) with [AdminCredential.iam], and not at all in emulator mode (`alg: none`, which only the
  /// emulator accepts). [tenantId] adds `tenant_id`, for projects with multi-tenancy.
  ///
  /// Throws a [FirebaseAuthAdminException] with code `argument-error` if [uid] is empty or longer than 128
  /// characters, or [claims] use a reserved name ([reservedClaims]) or are not JSON.
  ///
  /// The token is a credential for one hour: send it to the one client that signs in with it, never log it.
  Future<String> createCustomToken(
    String uid, {
    Map<String, Object?>? claims,
    String? tenantId,
  }) async {
    _checkOpen();
    if (uid.isEmpty || uid.length > 128) {
      throw const FirebaseAuthAdminException(
        code: 'argument-error',
        message:
            'The uid must be a non-empty string of at most 128 characters.',
      );
    }
    if (tenantId != null && tenantId.isEmpty) {
      throw const FirebaseAuthAdminException(
        code: 'argument-error',
        message: 'The tenant id must be a non-empty string.',
      );
    }
    if (claims != null) {
      for (final String name in claims.keys) {
        if (reservedClaims.contains(name)) {
          throw FirebaseAuthAdminException(
            code: 'argument-error',
            message:
                'Developer claim "$name" is reserved and cannot be specified.',
          );
        }
      }
      _encodeClaims(claims, 'argument-error');
    }

    final String issuer = await _guard(() => app.signerEmail('auth'));
    final int now = app.now().millisecondsSinceEpoch ~/ 1000;
    final Map<String, Object?> payload = <String, Object?>{
      'aud': customTokenAudience,
      'iat': now,
      'exp': now + 3600,
      'iss': issuer,
      'sub': issuer,
      'uid': uid,
      'tenant_id': ?tenantId,
      if (claims != null && claims.isNotEmpty) 'claims': claims,
    };
    final String header = encodeJsonSegment(<String, Object?>{
      'alg': isEmulator ? 'none' : 'RS256',
      'typ': 'JWT',
    });
    final String input = '$header.${encodeJsonSegment(payload)}';
    if (isEmulator) {
      return '$input.';
    }
    final List<int> signature = await _guard(
      () => app.signRs256(ascii.encode(input), issuer, 'auth'),
    );
    return '$input.${base64UrlNoPadding(signature)}';
  }

  // ---------------------------------------------------------------------------------------------------------
  // Users

  /// Creates a user and returns it as stored.
  ///
  /// Without [uid] the backend picks one. [password] needs at least 6 characters, [phoneNumber] the E.164 format
  /// (`+15555550100`). [customClaims] are set by a second request (`setCustomUserClaims`), checked before the
  /// user is created; if that request fails the user is deleted again and the error is thrown.
  ///
  /// Throws `uid-already-exists`, `email-already-exists`, `phone-number-already-exists`, and `invalid-uid`,
  /// `invalid-email`, `invalid-password`, `invalid-phone-number`, `invalid-photo-url` or
  /// `invalid-display-name` for an argument refused before the request.
  Future<AdminUser> createUser({
    String? uid,
    String? email,
    String? password,
    bool emailVerified = false,
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    bool disabled = false,
    Map<String, Object?>? customClaims,
  }) async {
    _checkOpen();
    if (uid != null) {
      _checkUid(uid);
    }
    _checkProperties(
      email: email,
      password: password,
      displayName: displayName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
    );
    final String? encodedClaims = customClaims == null
        ? null
        : _checkUserClaims(customClaims);
    final Map<String, Object?> response =
        await _identityToolkit('accounts', <String, Object?>{
          'localId': ?uid,
          'email': ?email,
          'password': ?password,
          'emailVerified': emailVerified,
          'displayName': ?displayName,
          'photoUrl': ?photoUrl,
          'phoneNumber': ?phoneNumber,
          'disabled': disabled,
        });
    final Object? created = response['localId'];
    if (created is! String || created.isEmpty) {
      throw const FirebaseAuthAdminException(
        code: 'internal-error',
        message: 'The backend did not return the uid of the new user.',
      );
    }
    if (encodedClaims != null) {
      try {
        await _identityToolkit('accounts:update', <String, Object?>{
          'localId': created,
          'customAttributes': encodedClaims,
        });
      } on Object {
        try {
          await _identityToolkit('accounts:delete', <String, Object?>{
            'localId': created,
          });
        } on Object {
          // The error of the claims is the one to report.
        }
        rethrow;
      }
    }
    return getUser(created);
  }

  /// The user with [uid]. Throws a [FirebaseAuthAdminException] `user-not-found` if there is none.
  Future<AdminUser> getUser(String uid) async {
    _checkOpen();
    _checkUid(uid);
    final AdminUser? user = await _lookup(<String, Object?>{
      'localId': <String>[uid],
    });
    if (user == null) {
      throw const FirebaseAuthAdminException(
        code: 'user-not-found',
        message:
            'There is no user record corresponding to the provided identifier.',
        serverCode: 'USER_NOT_FOUND',
      );
    }
    return user;
  }

  /// The user with the email address [email], or null if there is none.
  Future<AdminUser?> findUserByEmail(String email) async {
    _checkOpen();
    _checkProperties(email: email);
    return _lookup(<String, Object?>{
      'email': <String>[email],
    });
  }

  Future<AdminUser?> _lookup(Map<String, Object?> request) async {
    final Map<String, Object?> response = await _identityToolkit(
      'accounts:lookup',
      request,
    );
    final Object? users = response['users'];
    if (users is List &&
        users.isNotEmpty &&
        users.first is Map<String, Object?>) {
      return AdminUser.fromJson(users.first as Map<String, Object?>);
    }
    return null;
  }

  /// Changes the given properties of the user [uid] and returns the user as stored. A null argument leaves the
  /// property as it is. Throws `user-not-found` and the errors of [createUser].
  Future<AdminUser> updateUser(
    String uid, {
    String? email,
    String? password,
    bool? emailVerified,
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    bool? disabled,
  }) async {
    _checkOpen();
    _checkUid(uid);
    _checkProperties(
      email: email,
      password: password,
      displayName: displayName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
    );
    await _identityToolkit('accounts:update', <String, Object?>{
      'localId': uid,
      'email': ?email,
      'password': ?password,
      'emailVerified': ?emailVerified,
      'displayName': ?displayName,
      'photoUrl': ?photoUrl,
      'phoneNumber': ?phoneNumber,
      'disableUser': ?disabled,
    });
    return getUser(uid);
  }

  /// Deletes the user [uid]. Throws `user-not-found` if there is none.
  Future<void> deleteUser(String uid) async {
    _checkOpen();
    _checkUid(uid);
    await _identityToolkit('accounts:delete', <String, Object?>{
      'localId': uid,
    });
  }

  /// The number of uids [deleteUsers] sends per request: the limit of the backend.
  static const int deleteUsersBatchSize = 1000;

  /// Deletes the users [uids], [deleteUsersBatchSize] per request, even when they are not disabled.
  ///
  /// A uid without a user counts as deleted, as in the Admin SDKs. The uids that could not be deleted are in
  /// [DeleteUsersResult.errors]. Every uid is checked before the first request (`invalid-uid`); an error of a
  /// request stops at that batch and is thrown.
  Future<DeleteUsersResult> deleteUsers(Iterable<String> uids) async {
    _checkOpen();
    final List<String> all = uids.toList();
    all.forEach(_checkUid);
    final List<DeleteUserError> errors = <DeleteUserError>[];
    for (int start = 0; start < all.length; start += deleteUsersBatchSize) {
      final List<String> batch = all.sublist(
        start,
        start + deleteUsersBatchSize < all.length
            ? start + deleteUsersBatchSize
            : all.length,
      );
      final Map<String, Object?> response = await _identityToolkit(
        'accounts:batchDelete',
        <String, Object?>{'localIds': batch, 'force': true},
      );
      final Object? failures = response['errors'];
      if (failures is List) {
        for (final Object? failure in failures) {
          if (failure is! Map) {
            continue;
          }
          final Object? index = failure['index'];
          final int position = index is num ? index.toInt() : 0;
          errors.add(
            DeleteUserError(
              index: start + position,
              uid: failure['localId'] is String
                  ? failure['localId']! as String
                  : (position < batch.length ? batch[position] : ''),
              message: failure['message'] is String
                  ? failure['message']! as String
                  : 'not deleted',
            ),
          );
        }
      }
    }
    return DeleteUsersResult(
      successCount: all.length - errors.length,
      errors: List<DeleteUserError>.unmodifiable(errors),
    );
  }

  /// Sets the custom claims of the user [uid], which replace the previous ones; null or an empty map clears them.
  ///
  /// The claims reach the ID tokens the user gets from now on (the client sees them after a token refresh), and
  /// `request.auth.token` of the security rules. They are at most 1000 bytes of JSON and appear in every ID
  /// token: no secrets, no large data.
  ///
  /// Throws `forbidden-claim` for a reserved name ([reservedClaims]), `claims-too-large` over 1000 bytes,
  /// `invalid-claims` for something that is not JSON, and `user-not-found`.
  Future<void> setCustomUserClaims(
    String uid,
    Map<String, Object?>? claims,
  ) async {
    _checkOpen();
    _checkUid(uid);
    final String encoded = _checkUserClaims(
      claims ?? const <String, Object?>{},
    );
    await _identityToolkit('accounts:update', <String, Object?>{
      'localId': uid,
      'customAttributes': encoded,
    });
  }

  /// Revokes the refresh tokens of the user [uid]: the sessions of the user end at their next token refresh.
  ///
  /// ID tokens already issued stay valid until they expire (at most an hour) unless the verifier passes
  /// `checkRevoked: true` to [verifyIdToken], or the security rules compare `auth_time`. The cut-off is the
  /// current second: a token issued in the same second still passes.
  Future<void> revokeRefreshTokens(String uid) async {
    _checkOpen();
    _checkUid(uid);
    await _identityToolkit('accounts:update', <String, Object?>{
      'localId': uid,
      'validSince': '${app.now().millisecondsSinceEpoch ~/ 1000}',
    });
  }

  // ---------------------------------------------------------------------------------------------------------
  // ID tokens

  _KeySet? _keys;
  Future<_KeySet>? _keysPending;

  /// Verifies the Firebase ID token [idToken] of a user and returns its claims.
  ///
  /// Checks, as the Firebase documentation lists them: the header (`alg` RS256, a `kid` among Google's current
  /// keys), the RS256 signature, `aud` (the project id), `iss` (`https://securetoken.google.com/<projectId>`),
  /// `sub` (non-empty, at most 128 characters), `exp` in the future, `iat` and `auth_time` in the past. Times
  /// may be off by [clockSkew] (default [defaultClockSkew], at most [maxClockSkew]).
  ///
  /// The keys are fetched from [idTokenCertificatesUri] and kept for the `max-age` of its `Cache-Control`
  /// header.
  ///
  /// With [checkRevoked] the user is looked up too (one more request): `user-disabled` if the account is
  /// disabled, `id-token-revoked` if [revokeRefreshTokens] was called after the user signed in.
  ///
  /// In emulator mode ([FirebaseAdminApp.emulator]) the token must be unsigned (`alg: none`), as the emulator
  /// issues them; the claims are checked the same way. Outside emulator mode an unsigned token is refused.
  ///
  /// Throws a [FirebaseAuthAdminException]: `id-token-expired`, `argument-error` for any other failed check,
  /// `internal-error` if the keys cannot be fetched, and the errors of [getUser] with [checkRevoked].
  Future<VerifiedIdToken> verifyIdToken(
    String idToken, {
    bool checkRevoked = false,
    Duration clockSkew = defaultClockSkew,
  }) async {
    _checkOpen();
    if (clockSkew.isNegative || clockSkew > maxClockSkew) {
      throw ArgumentError.value(
        clockSkew,
        'clockSkew',
        'Must be between zero and $maxClockSkew',
      );
    }
    Never invalid(String why) => throw FirebaseAuthAdminException(
      code: 'argument-error',
      message: 'The Firebase ID token is not valid: $why.',
    );

    final List<String> parts = idToken.split('.');
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
    if (isEmulator) {
      if (alg != 'none' || signature.isNotEmpty) {
        invalid(
          'in emulator mode the token must be unsigned (alg "none"), as the emulator issues them',
        );
      }
    } else {
      if (alg == 'none') {
        invalid(
          'it is unsigned (alg "none"); only the Auth emulator issues such tokens',
        );
      }
      if (alg != 'RS256') {
        invalid('the algorithm must be RS256');
      }
      final Object? kid = header['kid'];
      if (kid is! String || kid.isEmpty) {
        invalid('it has no "kid" header');
      }
      final RsaPublicKey? key = (await _publicKeys()).keys[kid];
      if (key == null) {
        invalid('its "kid" does not match a current Google public key');
      }
      if (!key.verifyRs256(
        ascii.encode('${parts[0]}.${parts[1]}'),
        signature,
      )) {
        invalid('its signature is invalid');
      }
    }

    if (payload['aud'] != projectId) {
      invalid('its audience ("aud") is not the project "$projectId"');
    }
    if (payload['iss'] != 'https://securetoken.google.com/$projectId') {
      invalid(
        'its issuer ("iss") is not https://securetoken.google.com/$projectId',
      );
    }
    final Object? sub = payload['sub'];
    if (sub is! String || sub.isEmpty || sub.length > 128) {
      invalid(
        'its subject ("sub") must be a non-empty string of at most 128 characters',
      );
    }
    final Object? exp = payload['exp'];
    final Object? iat = payload['iat'];
    final Object? authTime = payload['auth_time'];
    if (exp is! num || iat is! num || authTime is! num) {
      invalid('"exp", "iat" and "auth_time" must be numbers');
    }
    final double now = app.now().millisecondsSinceEpoch / 1000;
    final int skew = clockSkew.inSeconds;
    if (exp <= now - skew) {
      throw const FirebaseAuthAdminException(
        code: 'id-token-expired',
        message:
            'The Firebase ID token has expired. Get a fresh token from your client and try again.',
      );
    }
    if (iat > now + skew) {
      invalid('it was issued in the future ("iat")');
    }
    if (authTime > now + skew) {
      invalid('its "auth_time" is in the future');
    }

    final VerifiedIdToken token = VerifiedIdToken(payload);
    if (checkRevoked) {
      final AdminUser user = await getUser(sub);
      if (user.disabled) {
        throw const FirebaseAuthAdminException(
          code: 'user-disabled',
          message: 'The user record is disabled.',
        );
      }
      final DateTime? validAfter = user.tokensValidAfter;
      if (validAfter != null &&
          authTime * 1000 < validAfter.millisecondsSinceEpoch) {
        throw const FirebaseAuthAdminException(
          code: 'id-token-revoked',
          message: 'The Firebase ID token has been revoked.',
        );
      }
    }
    return token;
  }

  Future<_KeySet> _publicKeys() {
    final _KeySet? keys = _keys;
    if (keys != null && app.now().isBefore(keys.expiresAt)) {
      return Future<_KeySet>.value(keys);
    }
    return _keysPending ??= _fetchPublicKeys().whenComplete(
      () => _keysPending = null,
    );
  }

  Future<_KeySet> _fetchPublicKeys() async {
    const FirebaseAuthAdminException failure = FirebaseAuthAdminException(
      code: 'internal-error',
      message: 'Could not fetch the public keys that sign Firebase ID tokens.',
    );
    final http.Response response;
    try {
      response = await app.httpClient.get(idTokenCertificatesUri);
    } on Object {
      throw failure;
    }
    if (response.statusCode != 200) {
      throw FirebaseAuthAdminException(
        code: 'internal-error',
        message: '${failure.message} HTTP ${response.statusCode}.',
        httpStatus: response.statusCode,
      );
    }
    final Map<String, RsaPublicKey> keys = <String, RsaPublicKey>{};
    try {
      final Object? json = jsonDecode(response.body);
      if (json is! Map<String, Object?>) {
        throw const FormatException('Not a JSON object');
      }
      for (final MapEntry<String, Object?> entry in json.entries) {
        keys[entry.key] = RsaPublicKey.fromCertificatePem(
          entry.value! as String,
        );
      }
    } on Object {
      throw FirebaseAuthAdminException(
        code: 'internal-error',
        message: '${failure.message} The answer is not a map of certificates.',
        httpStatus: response.statusCode,
      );
    }
    final RegExpMatch? maxAge = RegExp(
      r'max-age=(\d+)',
    ).firstMatch(response.headers['cache-control'] ?? '');
    final int seconds = maxAge == null ? 0 : int.parse(maxAge.group(1)!);
    final _KeySet set = _KeySet(
      keys,
      app.now().add(Duration(seconds: seconds)),
    );
    _keys = set;
    return set;
  }

  void _checkOpen() => app.checkOpen();

  /// Runs [action] and turns the exceptions of the app into [FirebaseAuthAdminException]s.
  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthAdminException {
      rethrow;
    } on FirebaseAdminException catch (e) {
      throw FirebaseAuthAdminException(
        code: e.code,
        message: e.message,
        serverCode: e.serverCode,
        httpStatus: e.httpStatus,
      );
    }
  }

  // ---------------------------------------------------------------------------------------------------------
  // Requests

  Uri _identityToolkitUri(String method) {
    final String path =
        '/v1/projects/${Uri.encodeComponent(projectId)}/$method';
    final String? emulator = app.authEmulatorOrigin;
    return emulator == null
        ? Uri.https('identitytoolkit.googleapis.com', path)
        : Uri.parse('$emulator/identitytoolkit.googleapis.com$path');
  }

  Future<Map<String, Object?>> _identityToolkit(
    String method,
    Map<String, Object?> body,
  ) => _post(_identityToolkitUri(method), body);

  Future<Map<String, Object?>> _post(Uri url, Map<String, Object?> body) async {
    final Map<String, String> headers = await _guard(
      () => app.authorizationHeaders('auth'),
    );
    final http.Response response;
    try {
      response = await app.httpClient.post(
        url,
        headers: <String, String>{
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } on Object {
      throw FirebaseAuthAdminException(
        code: 'network-error',
        message: 'The request to ${url.host} failed (network error).',
      );
    }
    Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      json = null;
    }
    if (response.statusCode == 200 && json is Map<String, Object?>) {
      return json;
    }
    final Object? error = json is Map<String, Object?> ? json['error'] : null;
    final Object? message = error is Map<String, Object?>
        ? error['message']
        : null;
    final Object? status = error is Map<String, Object?>
        ? error['status']
        : null;
    if (message is String && RegExp(r'^[A-Z_]+( : |$)').hasMatch(message)) {
      throw FirebaseAuthAdminException.fromServer(
        message,
        httpStatus: response.statusCode,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw FirebaseAuthAdminException(
        code: 'insufficient-permission',
        message:
            'The backend refused the credential (HTTP ${response.statusCode})'
            '${message is String ? ': $message' : ''}.',
        serverCode: status is String ? status : null,
        httpStatus: response.statusCode,
      );
    }
    throw FirebaseAuthAdminException(
      code: 'internal-error',
      message:
          'The backend answered with HTTP ${response.statusCode}'
          '${message is String ? ': $message' : ''}.',
      serverCode: status is String ? status : null,
      httpStatus: response.statusCode,
    );
  }

  // ---------------------------------------------------------------------------------------------------------
  // Checks

  static void _checkUid(String uid) {
    if (uid.isEmpty || uid.length > 128) {
      throw const FirebaseAuthAdminException(
        code: 'invalid-uid',
        message:
            'The uid must be a non-empty string with at most 128 characters.',
      );
    }
  }

  static final RegExp _email = RegExp(r'^[^@]+@[^@]+$');
  static final RegExp _phone = RegExp(r'^\+[\d\s\-()]*\d[\d\s\-()]*$');

  static void _checkProperties({
    String? email,
    String? password,
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
  }) {
    if (email != null && !_email.hasMatch(email)) {
      throw const FirebaseAuthAdminException(
        code: 'invalid-email',
        message: 'The email address is improperly formatted.',
      );
    }
    if (password != null && password.length < 6) {
      throw const FirebaseAuthAdminException(
        code: 'invalid-password',
        message: 'The password must be a string with at least 6 characters.',
      );
    }
    if (displayName != null && displayName.isEmpty) {
      throw const FirebaseAuthAdminException(
        code: 'invalid-display-name',
        message: 'The display name must be a non-empty string.',
      );
    }
    if (photoUrl != null && !(Uri.tryParse(photoUrl)?.hasScheme ?? false)) {
      throw const FirebaseAuthAdminException(
        code: 'invalid-photo-url',
        message: 'The photo URL must be a valid URL.',
      );
    }
    if (phoneNumber != null && !_phone.hasMatch(phoneNumber)) {
      throw const FirebaseAuthAdminException(
        code: 'invalid-phone-number',
        message:
            'The phone number must be a non-empty E.164 string (for example +15555550100).',
      );
    }
  }

  /// Checks the custom claims of a user and returns them as JSON.
  static String _checkUserClaims(Map<String, Object?> claims) {
    for (final String name in claims.keys) {
      if (reservedClaims.contains(name)) {
        throw FirebaseAuthAdminException(
          code: 'forbidden-claim',
          message:
              'Developer claim "$name" is reserved and cannot be specified.',
        );
      }
    }
    final String json = _encodeClaims(claims, 'invalid-claims');
    if (utf8.encode(json).length > 1000) {
      throw const FirebaseAuthAdminException(
        code: 'claims-too-large',
        message: 'The developer claims exceed the maximum size of 1000 bytes.',
      );
    }
    return json;
  }

  static String _encodeClaims(Map<String, Object?> claims, String code) {
    try {
      return jsonEncode(claims);
    } on JsonUnsupportedObjectError {
      throw FirebaseAuthAdminException(
        code: code,
        message:
            'The claims must be JSON: maps, lists, strings, numbers, booleans and null.',
      );
    }
  }
}

class _KeySet {
  _KeySet(this.keys, this.expiresAt);

  final Map<String, RsaPublicKey> keys;
  final DateTime expiresAt;
}

/// `app.auth()`: the Firebase Auth admin calls of a [FirebaseAdminApp].
extension FirebaseAdminAppAuth on FirebaseAdminApp {
  /// The [FirebaseAuthAdmin] of this app, the same object as `FirebaseAuthAdmin(app)`.
  FirebaseAuthAdmin auth() => FirebaseAuthAdmin(this);
}
