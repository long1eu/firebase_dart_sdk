// The fake backend of the phone tests: FakeBackend with the phone methods of PhonePlatform and the
// multi-factor methods of TotpPlatform, over the same accounts.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';
import 'phone_platform.dart';
import 'totp_platform.dart';

/// The email address of the password account of the tests.
const String email = 'ada@example.com';

/// Its uid.
const String uid = 'uid-of-$email';

/// A phone number of the tests.
const String phone = '+15555550100';

/// What `v1/recaptchaParams` returns, re-exported for the tests.
const String siteKey = recaptchaSiteKey;

/// The code of every SMS.
const String code = smsCode;

/// [FakeBackend] with phone sign-in and SMS and TOTP second factors.
class PhoneBackend {
  PhoneBackend() {
    totp = TotpPlatform(
      uidOf: _uidOf,
      readFactors: factorsOf,
      writeFactors: _writeFactors,
      tokensFor: _tokensFor,
      now: () => backend.clock.now,
    );
    platform = PhonePlatform(
      uidOf: _uidOf,
      ownerOf: ownerOf,
      setPhone: _setPhone,
      readFactors: factorsOf,
      writeFactors: _writeFactors,
      tokensFor: _tokensFor,
    );
    platform.handlersOver(totp.handlers).forEach(backend.on);
    backend.on('accounts:signInWithPassword', _signInWithPassword);
  }

  final FakeBackend backend = FakeBackend();
  late final TotpPlatform totp;
  late final PhonePlatform platform;

  static String _uidOf(String idToken) =>
      GetTokenResult(idToken).claims['sub']! as String;

  Map<String, Object?> _tokensFor(String user, String stage) =>
      <String, Object?>{
        ...backend.tokensFor(
          user,
          provider: stage == 'phone' ? 'phone' : 'password',
        ),
        'refreshToken': 'refresh:$user:$stage',
      };

  /// The account that has [number], or null.
  String? ownerOf(String number) {
    for (final MapEntry<String, Map<String, Object?>> entry
        in backend.accounts.entries) {
      if (entry.value['phoneNumber'] == number) {
        return entry.key;
      }
    }
    return null;
  }

  void _setPhone(String user, String number) {
    final Map<String, Object?> account = <String, Object?>{
      ...?backend.accounts[user],
    };
    final List<Object?> providers = <Object?>[
      for (final Object? p
          in (account['providerUserInfo'] as List<Object?>?) ??
              const <Object?>[])
        if ((p! as Map<String, Object?>)['providerId'] != 'phone') p,
      <String, Object?>{
        'providerId': 'phone',
        'rawId': number,
        'phoneNumber': number,
      },
    ];
    backend.accounts[user] = <String, Object?>{
      ...account,
      'phoneNumber': number,
      'providerUserInfo': providers,
    };
  }

  List<Map<String, Object?>> factorsOf(String user) => <Map<String, Object?>>[
    for (final Object? f
        in (backend.accounts[user]?['mfaInfo'] as List<Object?>?) ??
            const <Object?>[])
      f! as Map<String, Object?>,
  ];

  void _writeFactors(String user, List<Map<String, Object?>> factors) {
    final Map<String, Object?> account = <String, Object?>{
      ...?backend.accounts[user],
    };
    if (factors.isEmpty) {
      account.remove('mfaInfo');
    } else {
      account['mfaInfo'] = factors;
    }
    backend.accounts[user] = account;
  }

  /// Adds an SMS factor of [number] to the password account.
  void addPhoneFactor(String number, {String id = 'phone-1'}) =>
      totp.addFactor(uid, <String, Object?>{
        'mfaEnrollmentId': id,
        'phoneInfo': number,
        'enrolledAt': '2026-01-01T12:00:00Z',
      });

  http.Response _signInWithPassword(Map<String, Object?> body) {
    backend.accounts[uid] ??= <String, Object?>{
      'email': email,
      'emailVerified': true,
      'passwordHash': 'hash',
      'providerUserInfo': <Object?>[
        <String, Object?>{
          'providerId': 'password',
          'rawId': email,
          'email': email,
        },
      ],
    };
    final Map<String, Object?>? challenge = totp.challengeFor(uid);
    return jsonResponse(<String, Object?>{
      'kind': 'identitytoolkit#VerifyPasswordResponse',
      'email': email,
      'registered': true,
      if (challenge == null) ...backend.tokensFor(uid, email: email),
      if (challenge != null) 'localId': uid,
      ...?challenge,
    });
  }
}
