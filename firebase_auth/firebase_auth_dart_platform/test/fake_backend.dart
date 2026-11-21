// A fake Firebase Auth backend for the unit tests: answers the Identity
// Toolkit and Secure Token requests the client sends, with unsigned ID tokens
// in the shape of the Auth emulator's. Never contacts a real project.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The TOTP and phone fakes of firebase_auth_providers_dart, so that both
// packages test against the same backend behaviour.
import '../../firebase_auth_providers_dart/test/phone_platform.dart';
import '../../firebase_auth_providers_dart/test/totp_platform.dart';

String _encode(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An unsigned JWT with [claims].
String unsignedJwt(Map<String, Object?> claims) =>
    '${_encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
    '${_encode(claims)}.';

/// An unsigned ID token for [uid].
String idToken(
  String uid, {
  String provider = 'anonymous',
  String? email,
  int serial = 0,
}) {
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return unsignedJwt(<String, Object?>{
    'user_id': uid,
    'sub': uid,
    'email': ?email,
    'auth_time': now,
    'iat': now,
    'exp': now + 3600,
    'serial': serial,
    'firebase': <String, Object?>{'sign_in_provider': provider},
  });
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

/// The fake backend. Each request goes to the handler of its method (the last
/// path segment, such as `accounts:signUp`); a request with no handler is
/// recorded in [unhandled] and fails with a [StateError], so that a new or
/// misspelled endpoint cannot pass unnoticed.
class FakeBackend {
  FakeBackend() {
    totp = TotpPlatform(
      uidOf: (String token) => _claims(token)['sub'] as String,
      readFactors: (String uid) =>
          List<Map<String, Object?>>.of(factors[uid] ?? const []),
      writeFactors: (String uid, List<Map<String, Object?>> list) =>
          factors[uid] = list,
      tokensFor: (String uid, String stage) => _tokensOf(uid),
      now: DateTime.now,
      // The client runs on the real clock: accept the neighbouring steps, as
      // the real service does.
      window: 1,
    );
    phone = PhonePlatform(
      uidOf: (String token) => _claims(token)['sub'] as String,
      ownerOf: (String number) {
        for (final MapEntry<String, String> entry in phones.entries) {
          if (entry.value == number) {
            return entry.key;
          }
        }
        return null;
      },
      setPhone: (String uid, String number) => phones[uid] = number,
      readFactors: (String uid) =>
          List<Map<String, Object?>>.of(factors[uid] ?? const []),
      writeFactors: (String uid, List<Map<String, Object?>> list) =>
          factors[uid] = list,
      tokensFor: (String uid, String stage) =>
          _tokensOf(uid, provider: stage == 'phone' ? 'phone' : 'password'),
    );
    _handlers.addAll(phone.handlersOver(totp.handlers));
  }

  final List<http.Request> requests = <http.Request>[];

  /// The requests that had no handler.
  final List<String> unhandled = <String>[];

  /// Answers the next request instead of the default backend, when set.
  http.Response? Function(http.Request request)? override;

  /// The second factors of each account (`mfaInfo` entries), by uid. A
  /// password sign-in of an account with factors answers with the pending
  /// credential `pending:<uid>`.
  final Map<String, List<Map<String, Object?>>> factors =
      <String, List<Map<String, Object?>>>{};

  /// The TOTP methods, checking real RFC 6238 codes of [totpSecretKey].
  late final TotpPlatform totp;

  /// The phone methods: every SMS code is [smsCode].
  late final PhonePlatform phone;

  /// The phone number of each account that has one, by uid.
  final Map<String, String> phones = <String, String>{};

  /// The code an authenticator app shows now.
  String get totpCode => totp.codeNow();

  int _serial = 0;

  late final Map<String, http.Response Function(Map<String, Object?> body)>
  _handlers = <String, http.Response Function(Map<String, Object?> body)>{
    'accounts:lookup': _lookup,
    'accounts:update': (Map<String, Object?> body) =>
        jsonResponse(<String, Object?>{
          'localId': 'whoever',
          'idToken': body['idToken'],
          'refreshToken': 'refresh:whoever',
          'expiresIn': '3600',
        }),
    'accounts:sendOobCode': (Map<String, Object?> body) =>
        jsonResponse(<String, Object?>{'email': body['email']}),
    'accounts:resetPassword': (Map<String, Object?> body) =>
        jsonResponse(<String, Object?>{
          'email': 'a@example.com',
          'requestType': 'PASSWORD_RESET',
        }),
    'accounts:signUp': (Map<String, Object?> body) =>
        _signIn(body, signUp: true),
    'accounts:signInWithPassword': (Map<String, Object?> body) => _signIn(body),
    'accounts:signInWithCustomToken': (Map<String, Object?> body) =>
        _signIn(body),
    'accounts:signInWithEmailLink': (Map<String, Object?> body) =>
        _signIn(body),
    'accounts:signInWithIdp': (Map<String, Object?> body) =>
        _signIn(body, idp: true),
  };

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
    final String method = request.url.pathSegments.last;
    if (request.url.host == 'securetoken.googleapis.com' ||
        request.url.path.endsWith('/securetoken.googleapis.com/v1/token')) {
      return _refresh(request);
    }
    final http.Response Function(Map<String, Object?> body)? handler =
        _handlers[method];
    if (handler == null) {
      unhandled.add('${request.method} ${request.url}');
      throw StateError(
        'FakeBackend has no answer for ${request.method} ${request.url.path}: '
        'add a handler or set override.',
      );
    }
    return handler(
      request.method == 'GET'
          ? request.url.queryParameters
          : jsonDecode(request.body) as Map<String, Object?>,
    );
  }

  http.Response _refresh(http.Request request) {
    final String refreshToken = request.bodyFields['refresh_token']!;
    final String uid = refreshToken.split(':')[1];
    return jsonResponse(<String, Object?>{
      'id_token': idToken(uid, serial: ++_serial),
      'refresh_token': refreshToken,
      'expires_in': '3600',
      'user_id': uid,
    });
  }

  http.Response _lookup(Map<String, Object?> body) {
    final Map<String, dynamic> claims = _claims(body['idToken']! as String);
    final String? email = claims['email'] as String?;
    final String? number = phones[claims['sub']];
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
          'phoneNumber': ?number,
          'providerUserInfo': <Object?>[
            if (email != null)
              <String, Object?>{
                'providerId': 'password',
                'rawId': email,
                'email': email,
              },
            if (number != null)
              <String, Object?>{
                'providerId': 'phone',
                'rawId': number,
                'phoneNumber': number,
              },
          ],
        },
      ],
    });
  }

  /// A sign-in (or sign-up) answer; a password sign-in of an account with
  /// factors asks for the second factor instead.
  http.Response _signIn(
    Map<String, Object?> body, {
    bool signUp = false,
    bool idp = false,
  }) {
    final String? email = body['email'] as String?;
    final String uid = idp
        ? 'google-user'
        : email == null
        ? 'anon-user'
        : 'uid-of-$email';
    final Map<String, Object?>? challenge = idp || signUp
        ? null
        : totp.challengeFor(uid);
    if (challenge != null) {
      return jsonResponse(<String, Object?>{
        'localId': uid,
        'email': email,
        ...challenge,
      });
    }
    return jsonResponse(<String, Object?>{
      if (signUp) 'kind': 'identitytoolkit#SignupNewUserResponse',
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

  /// New tokens for the account [uid], as the v2 endpoints return them.
  Map<String, Object?> _tokensOf(String uid, {String provider = 'password'}) =>
      <String, Object?>{
        'idToken': idToken(
          uid,
          provider: provider,
          email: uid.startsWith('uid-of-') && uid.contains('@')
              ? uid.substring('uid-of-'.length)
              : null,
          serial: ++_serial,
        ),
        'refreshToken': 'refresh:$uid',
      };

  static Map<String, dynamic> _claims(String token) {
    final String payload = token.split('.')[1];
    return jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(payload))),
        )
        as Map<String, dynamic>;
  }
}
