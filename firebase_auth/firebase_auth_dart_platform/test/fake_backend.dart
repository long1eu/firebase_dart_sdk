// A fake Firebase Auth backend for the unit tests: answers the Identity
// Toolkit and Secure Token requests the client sends, with unsigned ID tokens
// in the shape of the Auth emulator's. Never contacts a real project.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _encode(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An unsigned ID token for [uid].
String idToken(
  String uid, {
  String provider = 'anonymous',
  String? email,
  int serial = 0,
}) {
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${_encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
      '${_encode(<String, Object?>{
        'user_id': uid,
        'sub': uid,
        'email': ?email,
        'auth_time': now,
        'iat': now,
        'exp': now + 3600,
        'serial': serial,
        'firebase': <String, Object?>{'sign_in_provider': provider},
      })}.';
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

http.Response errorResponse(String message, [int status = 400]) =>
    jsonResponse(<String, Object?>{
      'error': <String, Object?>{'code': status, 'message': message},
    }, status);

class FakeBackend {
  final List<http.Request> requests = <http.Request>[];

  /// Answers the next request instead of the default backend, when set.
  http.Response? Function(http.Request request)? override;

  /// The second factors of each account (`mfaInfo` entries), by uid. A
  /// password sign-in of an account with factors answers with the pending
  /// credential `pending:<uid>`.
  final Map<String, List<Map<String, Object?>>> factors =
      <String, List<Map<String, Object?>>>{};

  /// The code the TOTP endpoints accept.
  static const String totpCode = '123456';

  int _serial = 0;
  int _enrolled = 0;

  late final MockClient client = MockClient((http.Request request) async {
    requests.add(request);
    return override?.call(request) ?? _answer(request);
  });

  /// The paths of the requests, without the host.
  List<String> get paths => <String>[
    for (final http.Request r in requests) r.url.path,
  ];

  Map<String, Object?> bodyOf(String pathEnd) =>
      jsonDecode(requests.lastWhere((r) => r.url.path.endsWith(pathEnd)).body)
          as Map<String, Object?>;

  http.Response _answer(http.Request request) {
    final String path = request.url.path;
    if (path.endsWith('/token')) {
      final String refreshToken = request.bodyFields['refresh_token']!;
      final String uid = refreshToken.split(':')[1];
      return jsonResponse(<String, Object?>{
        'id_token': idToken(uid, serial: ++_serial),
        'refresh_token': refreshToken,
        'expires_in': '3600',
        'user_id': uid,
      });
    }
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    final http.Response? multiFactor = _multiFactor(path, body);
    if (multiFactor != null) {
      return multiFactor;
    }
    if (path.endsWith('accounts:lookup')) {
      final Map<String, dynamic> claims = _claims(body['idToken']! as String);
      final String? email = claims['email'] as String?;
      return jsonResponse(<String, Object?>{
        'users': <Object?>[
          <String, Object?>{
            'localId': claims['sub'],
            'email': ?email,
            'displayName': 'Ada',
            'createdAt': '1700000000000',
            'lastLoginAt': '1700000001000',
            if (factors[claims['sub']]?.isNotEmpty ?? false)
              'mfaInfo': factors[claims['sub']],
            if (email != null) 'passwordHash': 'hash',
            if (email != null)
              'providerUserInfo': <Object?>[
                <String, Object?>{
                  'providerId': 'password',
                  'rawId': email,
                  'email': email,
                },
              ],
          },
        ],
      });
    }
    if (path.endsWith('accounts:update')) {
      return jsonResponse(<String, Object?>{
        'localId': 'whoever',
        'idToken': body['idToken'],
        'refreshToken': 'refresh:whoever',
        'expiresIn': '3600',
      });
    }
    if (path.endsWith('accounts:sendOobCode')) {
      return jsonResponse(<String, Object?>{'email': body['email']});
    }
    if (path.endsWith('accounts:resetPassword')) {
      return jsonResponse(<String, Object?>{
        'email': 'a@example.com',
        'requestType': 'PASSWORD_RESET',
      });
    }
    final String? email = body['email'] as String?;
    final bool idp = path.endsWith('accounts:signInWithIdp');
    final String uid = idp
        ? 'google-user'
        : email == null
        ? 'anon-user'
        : 'uid-of-$email';
    return jsonResponse(<String, Object?>{
      if (path.endsWith('accounts:signUp'))
        'kind': 'identitytoolkit#SignupNewUserResponse',
      'localId': uid,
      'email': ?email,
      if (idp) 'providerId': 'google.com',
      if (idp) 'oauthIdToken': 'returned-id-token',
      'idToken': idToken(
        uid,
        provider: idp
            ? 'google.com'
            : email == null
            ? 'anonymous'
            : 'password',
        email: email,
        serial: ++_serial,
      ),
      'refreshToken': 'refresh:$uid',
      'expiresIn': '3600',
    });
  }

  /// The answer of a v2 multi-factor endpoint, or of a password sign-in of an
  /// account with factors; null for any other request.
  http.Response? _multiFactor(String path, Map<String, Object?> body) {
    if (path.endsWith('accounts:signInWithPassword')) {
      final String uid = 'uid-of-${body['email']}';
      final List<Map<String, Object?>>? enrolled = factors[uid];
      if (enrolled == null || enrolled.isEmpty) {
        return null;
      }
      return jsonResponse(<String, Object?>{
        'localId': uid,
        'email': body['email'],
        'mfaPendingCredential': 'pending:$uid',
        'mfaInfo': enrolled,
      });
    }
    if (path.endsWith('mfaEnrollment:start')) {
      return jsonResponse(<String, Object?>{
        'totpSessionInfo': <String, Object?>{
          'sharedSecretKey': 'GEZDGNBVGY3TQOJQ',
          'verificationCodeLength': 6,
          'hashingAlgorithm': 'SHA1',
          'periodSec': 30,
          'sessionInfo': 'enrollment-session',
          'finalizeEnrollmentTime': '2026-01-01T12:10:00Z',
        },
      });
    }
    if (path.endsWith('mfaEnrollment:finalize')) {
      final Map<String, Object?> info =
          body['totpVerificationInfo']! as Map<String, Object?>;
      if (info['verificationCode'] != totpCode) {
        return errorResponse('INVALID_CODE');
      }
      final Map<String, dynamic> claims = _claims(body['idToken']! as String);
      (factors[claims['sub'] as String] ??= <Map<String, Object?>>[])
          .add(<String, Object?>{
            'mfaEnrollmentId': 'totp-${++_enrolled}',
            'displayName': body['displayName'],
            'totpInfo': <String, Object?>{},
            'enrolledAt': '2026-01-01T12:00:00Z',
          });
      return _tokensOf(claims);
    }
    if (path.endsWith('mfaEnrollment:withdraw')) {
      final Map<String, dynamic> claims = _claims(body['idToken']! as String);
      final List<Map<String, Object?>>? enrolled = factors[claims['sub']];
      final int before = enrolled?.length ?? 0;
      enrolled?.removeWhere(
        (Map<String, Object?> f) =>
            f['mfaEnrollmentId'] == body['mfaEnrollmentId'],
      );
      if ((enrolled?.length ?? 0) == before) {
        return errorResponse('MFA_ENROLLMENT_NOT_FOUND');
      }
      return _tokensOf(claims);
    }
    if (path.endsWith('mfaSignIn:finalize')) {
      final String uid = (body['mfaPendingCredential']! as String).substring(
        'pending:'.length,
      );
      final Map<String, Object?> info =
          body['totpVerificationInfo']! as Map<String, Object?>;
      if (info['verificationCode'] != totpCode) {
        return errorResponse('INVALID_CODE');
      }
      return _tokensOf(<String, dynamic>{
        'sub': uid,
        'email': uid.substring('uid-of-'.length),
      });
    }
    return null;
  }

  /// New tokens for the account of [claims], as the v2 endpoints return them.
  http.Response _tokensOf(Map<String, dynamic> claims) {
    final String uid = claims['sub'] as String;
    return jsonResponse(<String, Object?>{
      'idToken': idToken(
        uid,
        provider: 'password',
        email: claims['email'] as String?,
        serial: ++_serial,
      ),
      'refreshToken': 'refresh:$uid',
    });
  }

  static Map<String, dynamic> _claims(String token) {
    final String payload = token.split('.')[1];
    return jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(payload))),
        )
        as Map<String, dynamic>;
  }
}
