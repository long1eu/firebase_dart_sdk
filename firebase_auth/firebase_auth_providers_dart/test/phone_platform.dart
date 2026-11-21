// A fake of the phone methods of the Identity Toolkit API, shared by the tests of this package and
// of firebase_auth_dart_platform: SMS codes (accounts:sendVerificationCode), phone sign-in, link,
// update and reauthentication (accounts:signInWithPhoneNumber), and SMS second factors (the v2
// multi-factor methods with their phone fields). Each test backend plugs in how it stores accounts
// and issues tokens.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The code of every SMS the fake "sends".
const String smsCode = '123456';

/// The reCAPTCHA v2 site key `v1/recaptchaParams` returns.
const String recaptchaSiteKey = 'fake-site-key';

/// An answer of the fake, taking the decoded body.
typedef PhoneHandler = http.Response Function(Map<String, Object?> body);

/// The phone methods of the Identity Toolkit API over the accounts of a test backend.
class PhonePlatform {
  /// Creates the fake.
  ///
  /// [uidOf] reads the uid of an ID token; [ownerOf] returns the account that has a phone number
  /// (or null) and [setPhone] gives an account a phone number; [readFactors] and [writeFactors]
  /// keep the `mfaInfo` entries of an account; [tokensFor] answers a successful call for an account
  /// with new tokens (`idToken`, `refreshToken`; `stage` is `phone`, `enrolled` or
  /// `second-factor`). With [requireProof] a request without a reCAPTCHA field is refused with
  /// `MISSING_APP_CREDENTIAL`, as a real project does.
  PhonePlatform({
    required this.uidOf,
    required this.ownerOf,
    required this.setPhone,
    required this.readFactors,
    required this.writeFactors,
    required this.tokensFor,
    this.requireProof = true,
  });

  final String Function(String idToken) uidOf;
  final String? Function(String phoneNumber) ownerOf;
  final void Function(String uid, String phoneNumber) setPhone;
  final List<Map<String, Object?>> Function(String uid) readFactors;
  final void Function(String uid, List<Map<String, Object?>> factors)
  writeFactors;
  final Map<String, Object?> Function(String uid, String stage) tokensFor;
  bool requireProof;

  /// The phone number of each verification id handed out, until it is used.
  final Map<String, String> sessions = <String, String>{};

  int _counter = 0;

  /// The answers by method (the last path segment). The multi-factor methods answer the requests
  /// with phone fields and hand the others to [others] (the TOTP fake), so that both kinds of
  /// factor work on one backend.
  Map<String, PhoneHandler> handlersOver([
    Map<String, PhoneHandler> others = const <String, PhoneHandler>{},
  ]) {
    PhoneHandler either(String method, String field, PhoneHandler phone) =>
        (Map<String, Object?> body) => body.containsKey(field)
        ? phone(body)
        : (others[method] ?? (_) => _error('UNEXPECTED_REQUEST'))(body);
    return <String, PhoneHandler>{
      ...others,
      'recaptchaParams': (_) =>
          _json(<String, Object?>{'recaptchaSiteKey': recaptchaSiteKey}),
      'accounts:sendVerificationCode': _sendVerificationCode,
      'accounts:signInWithPhoneNumber': _signInWithPhoneNumber,
      'mfaEnrollment:start': either(
        'mfaEnrollment:start',
        'phoneEnrollmentInfo',
        _startEnrollment,
      ),
      'mfaEnrollment:finalize': either(
        'mfaEnrollment:finalize',
        'phoneVerificationInfo',
        _finalizeEnrollment,
      ),
      'mfaSignIn:start': either(
        'mfaSignIn:start',
        'phoneSignInInfo',
        _startSignIn,
      ),
      'mfaSignIn:finalize': either(
        'mfaSignIn:finalize',
        'phoneVerificationInfo',
        _finalizeSignIn,
      ),
    };
  }

  /// A new verification id for [phoneNumber], or the error of a request without a valid number or
  /// proof.
  http.Response _session(
    Object? phoneNumber,
    Map<String, Object?> proof,
    Map<String, Object?> Function(String sessionInfo) answer,
  ) {
    if (phoneNumber is! String || phoneNumber.isEmpty) {
      return _error('MISSING_PHONE_NUMBER');
    }
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phoneNumber)) {
      return _error('INVALID_PHONE_NUMBER : TOO_SHORT');
    }
    if (requireProof &&
        proof['recaptchaToken'] == null &&
        proof['captchaResponse'] == null) {
      return _error('MISSING_APP_CREDENTIAL');
    }
    final String sessionInfo = 'session-${++_counter}';
    sessions[sessionInfo] = phoneNumber;
    return _json(answer(sessionInfo));
  }

  /// The phone number of a verification [info] (`sessionInfo` and `code`), or the error for a wrong
  /// one. The id is used up by a right code.
  (String?, http.Response?) _verify(Map<String, Object?> info) {
    final Object? sessionInfo = info['sessionInfo'];
    if (sessionInfo is! String || sessionInfo.isEmpty) {
      return (null, _error('MISSING_SESSION_INFO'));
    }
    final Object? code = info['code'];
    if (code is! String || code.isEmpty) {
      return (null, _error('MISSING_CODE'));
    }
    final String? phone = sessions[sessionInfo];
    if (phone == null) {
      return (null, _error('INVALID_SESSION_INFO'));
    }
    if (code != smsCode) {
      return (null, _error('INVALID_CODE'));
    }
    sessions.remove(sessionInfo);
    return (phone, null);
  }

  http.Response _sendVerificationCode(Map<String, Object?> body) => _session(
    body['phoneNumber'],
    body,
    (String sessionInfo) => <String, Object?>{'sessionInfo': sessionInfo},
  );

  http.Response _signInWithPhoneNumber(Map<String, Object?> body) {
    final (String? phone, http.Response? error) = _verify(body);
    if (error != null) {
      return error;
    }
    final String number = phone!;
    final String? owner = ownerOf(number);
    final Object? idToken = body['idToken'];
    if (idToken is String) {
      final String uid = uidOf(idToken);
      if (owner != null && owner != uid) {
        return _json(<String, Object?>{
          'temporaryProof': 'proof-of-$number',
          'phoneNumber': number,
        });
      }
      setPhone(uid, number);
      return _json(<String, Object?>{
        ...tokensFor(uid, 'phone'),
        'localId': uid,
        'phoneNumber': number,
      });
    }
    if (body['operation'] == 'REAUTH') {
      if (owner == null) {
        return _error('USER_NOT_FOUND');
      }
      return _json(<String, Object?>{
        ...tokensFor(owner, 'phone'),
        'localId': owner,
        'phoneNumber': number,
      });
    }
    final String uid = owner ?? 'uid-of-$number';
    setPhone(uid, number);
    return _json(<String, Object?>{
      ...tokensFor(uid, 'phone'),
      'localId': uid,
      'phoneNumber': number,
      'isNewUser': owner == null,
    });
  }

  http.Response _startEnrollment(Map<String, Object?> body) {
    uidOf(body['idToken']! as String);
    final Map<String, Object?> info =
        body['phoneEnrollmentInfo']! as Map<String, Object?>;
    return _session(
      info['phoneNumber'],
      info,
      (String sessionInfo) => <String, Object?>{
        'phoneSessionInfo': <String, Object?>{'sessionInfo': sessionInfo},
      },
    );
  }

  http.Response _finalizeEnrollment(Map<String, Object?> body) {
    final String uid = uidOf(body['idToken']! as String);
    final (String? phone, http.Response? error) = _verify(
      body['phoneVerificationInfo']! as Map<String, Object?>,
    );
    if (error != null) {
      return error;
    }
    final List<Map<String, Object?>> factors = readFactors(uid);
    if (factors.any((Map<String, Object?> f) => f['phoneInfo'] == phone)) {
      return _error('SECOND_FACTOR_EXISTS');
    }
    writeFactors(uid, <Map<String, Object?>>[
      ...factors,
      <String, Object?>{
        'mfaEnrollmentId': 'phone-${++_counter}',
        'displayName': ?body['displayName'],
        'phoneInfo': phone,
        'enrolledAt': '2026-01-01T12:00:00Z',
      },
    ]);
    return _json(tokensFor(uid, 'enrolled'));
  }

  /// The account of a pending credential `pending:<uid>`, or null.
  static String? _pendingUid(Object? pending) =>
      pending is String && pending.startsWith('pending:')
      ? pending.substring('pending:'.length)
      : null;

  http.Response _startSignIn(Map<String, Object?> body) {
    final String? uid = _pendingUid(body['mfaPendingCredential']);
    if (uid == null) {
      return _error('INVALID_MFA_PENDING_CREDENTIAL');
    }
    final Map<String, Object?>? factor = readFactors(uid)
        .where(
          (Map<String, Object?> f) =>
              f['mfaEnrollmentId'] == body['mfaEnrollmentId'] &&
              f.containsKey('phoneInfo'),
        )
        .firstOrNull;
    if (factor == null) {
      return _error('MFA_ENROLLMENT_NOT_FOUND');
    }
    return _session(
      factor['phoneInfo'],
      body['phoneSignInInfo']! as Map<String, Object?>,
      (String sessionInfo) => <String, Object?>{
        'phoneResponseInfo': <String, Object?>{'sessionInfo': sessionInfo},
      },
    );
  }

  http.Response _finalizeSignIn(Map<String, Object?> body) {
    final String? uid = _pendingUid(body['mfaPendingCredential']);
    if (uid == null) {
      return _error('INVALID_MFA_PENDING_CREDENTIAL');
    }
    final (String? phone, http.Response? error) = _verify(
      body['phoneVerificationInfo']! as Map<String, Object?>,
    );
    if (error != null) {
      return error;
    }
    final bool enrolled = readFactors(
      uid,
    ).any((Map<String, Object?> f) => f['phoneInfo'] == phone);
    if (!enrolled) {
      return _error('MFA_ENROLLMENT_NOT_FOUND');
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
