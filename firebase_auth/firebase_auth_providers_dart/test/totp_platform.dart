// A fake Identity Platform with authenticator app (TOTP) second factors, shared by the tests of this package and of
// firebase_auth_dart_platform: the v2 multi-factor methods in JSON, checked against real RFC 6238 codes of
// test/totp.dart. Each test backend plugs in how it stores factors and issues tokens.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'totp.dart';

/// The secret the fake hands out (base32 of "12345678901234567890", the key of RFC 6238's test vectors).
const String totpSecretKey = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

/// The session id of an enrolment started by `mfaEnrollment:start`.
const String totpEnrollmentSession = 'enrollment-session';

/// The TOTP methods of the Identity Toolkit API (`mfaEnrollment:start`, `mfaEnrollment:finalize`,
/// `mfaEnrollment:withdraw`, `mfaSignIn:finalize`) over the factors of a test backend.
///
/// A first-factor sign-in of an account with factors answers with [challengeFor]: the pending credential
/// `pending:<uid>` and the factors, phone numbers masked.
class TotpPlatform {
  /// Creates the fake.
  ///
  /// [uidOf] reads the uid of an ID token, [readFactors] and [writeFactors] keep the `mfaInfo` entries of an
  /// account, [tokensFor] answers a successful call for an account with new tokens (`idToken`, `refreshToken`;
  /// `stage` is `enrolled`, `withdrawn` or `second-factor`), and [now] is the time the codes are checked at.
  /// [window] is how many 30-second steps before and after [now] are accepted too: 0 for a fake clock, 1 for
  /// the real one, as the real service does.
  TotpPlatform({
    required this.uidOf,
    required this.readFactors,
    required this.writeFactors,
    required this.tokensFor,
    required this.now,
    this.window = 0,
  });

  final String Function(String idToken) uidOf;
  final List<Map<String, Object?>> Function(String uid) readFactors;
  final void Function(String uid, List<Map<String, Object?>> factors)
  writeFactors;
  final Map<String, Object?> Function(String uid, String stage) tokensFor;
  final DateTime Function() now;
  final int window;

  int _enrolled = 0;

  /// The code an authenticator app shows for [totpSecretKey] now.
  String codeNow() => totpCode(base32Decode(totpSecretKey), now());

  /// Whether [code] is the code of now or of an accepted step around it.
  bool accepts(Object? code) {
    for (int step = -window; step <= window; step++) {
      final DateTime at = now().add(Duration(seconds: 30 * step));
      if (code == totpCode(base32Decode(totpSecretKey), at)) {
        return true;
      }
    }
    return false;
  }

  /// Adds [factor] (an `mfaInfo` entry) to the account [uid].
  void addFactor(String uid, Map<String, Object?> factor) =>
      writeFactors(uid, <Map<String, Object?>>[...readFactors(uid), factor]);

  /// The fields of a first-factor sign-in answer that ask for the second factor, or null when [uid] has none.
  Map<String, Object?>? challengeFor(String uid) {
    final List<Map<String, Object?>> factors = readFactors(uid);
    if (factors.isEmpty) {
      return null;
    }
    return <String, Object?>{
      'mfaPendingCredential': 'pending:$uid',
      'mfaInfo': <Object?>[
        for (final Map<String, Object?> f in factors)
          <String, Object?>{
            ...f,
            if (f.containsKey('phoneInfo')) 'phoneInfo': '+*******0100',
          },
      ],
    };
  }

  /// The answers by method (the last path segment), taking the decoded body.
  Map<String, http.Response Function(Map<String, Object?> body)> get handlers =>
      <String, http.Response Function(Map<String, Object?> body)>{
        'mfaEnrollment:start': _start,
        'mfaEnrollment:finalize': _finalize,
        'mfaEnrollment:withdraw': _withdraw,
        'mfaSignIn:finalize': _finalizeSignIn,
      };

  http.Response _start(Map<String, Object?> body) {
    uidOf(body['idToken']! as String);
    return _json(<String, Object?>{
      'totpSessionInfo': <String, Object?>{
        'sharedSecretKey': totpSecretKey,
        'verificationCodeLength': 6,
        'hashingAlgorithm': 'SHA1',
        'periodSec': 30,
        'sessionInfo': totpEnrollmentSession,
        'finalizeEnrollmentTime': '2026-01-01T12:10:00.123456789Z',
      },
    });
  }

  http.Response _finalize(Map<String, Object?> body) {
    final String uid = uidOf(body['idToken']! as String);
    final Map<String, Object?> info =
        body['totpVerificationInfo']! as Map<String, Object?>;
    if (info['sessionInfo'] != totpEnrollmentSession) {
      return _error('INVALID_SESSION_INFO');
    }
    if (!accepts(info['verificationCode'])) {
      return _error('INVALID_CODE');
    }
    addFactor(uid, <String, Object?>{
      'mfaEnrollmentId': 'totp-${++_enrolled}',
      'displayName': ?body['displayName'],
      'totpInfo': <String, Object?>{},
      'enrolledAt': '2026-01-01T12:00:00Z',
    });
    return _json(tokensFor(uid, 'enrolled'));
  }

  http.Response _withdraw(Map<String, Object?> body) {
    final String uid = uidOf(body['idToken']! as String);
    final List<Map<String, Object?>> factors = readFactors(uid);
    final List<Map<String, Object?>> left = <Map<String, Object?>>[
      for (final Map<String, Object?> f in factors)
        if (f['mfaEnrollmentId'] != body['mfaEnrollmentId']) f,
    ];
    if (left.length == factors.length) {
      return _error('MFA_ENROLLMENT_NOT_FOUND');
    }
    writeFactors(uid, left);
    return _json(tokensFor(uid, 'withdrawn'));
  }

  http.Response _finalizeSignIn(Map<String, Object?> body) {
    final Object? pending = body['mfaPendingCredential'];
    if (pending is! String || !pending.startsWith('pending:')) {
      return _error('INVALID_MFA_PENDING_CREDENTIAL');
    }
    final String uid = pending.substring('pending:'.length);
    final bool known = readFactors(uid).any(
      (Map<String, Object?> f) =>
          f['mfaEnrollmentId'] == body['mfaEnrollmentId'],
    );
    if (!known) {
      return _error('MFA_ENROLLMENT_NOT_FOUND');
    }
    final Map<String, Object?> info =
        body['totpVerificationInfo']! as Map<String, Object?>;
    if (!accepts(info['verificationCode'])) {
      return _error('INVALID_CODE');
    }
    return _json(tokensFor(uid, 'second-factor'));
  }

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  static http.Response _error(String message) => _json(<String, Object?>{
    'error': <String, Object?>{'code': 400, 'message': message},
  }, 400);
}
