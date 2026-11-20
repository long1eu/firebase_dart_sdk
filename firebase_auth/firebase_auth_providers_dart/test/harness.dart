// A fake Identity Toolkit and Secure Token backend for the unit tests of the client features: it records the
// requests, answers sign-ins with emulator-style ID tokens, and keeps the accounts that accounts:lookup returns.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const String apiKey = 'test-api-key';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

http.Response errorResponse(String message, [int status = 400]) =>
    jsonResponse(<String, Object?>{
      'error': <String, Object?>{'code': status, 'message': message},
    }, status);

Matcher throwsAuth(Object code) => throwsA(
  isA<FirebaseAuthException>().having(
    (FirebaseAuthException e) => e.code,
    'code',
    code,
  ),
);

/// The fake backend. [handler] answers every request; by default [answer], which tests override per method with
/// [on].
class FakeBackend {
  FakeBackend() {
    handler = answer;
  }

  final FakeClock clock = FakeClock();
  final FakeTimers timers = FakeTimers();
  final InMemoryAuthStorage storage = InMemoryAuthStorage();
  final List<http.Request> requests = <http.Request>[];
  late Future<http.Response> Function(http.Request request) handler;

  /// Answers of [answer] by method (`accounts:signInWithIdp`, `passwordPolicy`, ...), taking the decoded body (the
  /// query parameters for a GET).
  final Map<String, FutureOr<http.Response> Function(Map<String, Object?> body)>
  overrides =
      <String, FutureOr<http.Response> Function(Map<String, Object?> body)>{};

  /// The accounts by uid: the fields `accounts:lookup` returns beyond the uid.
  final Map<String, Map<String, Object?>> accounts =
      <String, Map<String, Object?>>{};

  int _counter = 0;

  /// Answers [method] with [answer] from now on.
  void on(
    String method,
    FutureOr<http.Response> Function(Map<String, Object?> body) answer,
  ) => overrides[method] = answer;

  /// The decoded JSON bodies of the requests to [method].
  List<Map<String, Object?>> bodiesOf(String method) => <Map<String, Object?>>[
    for (final http.Request r in requests)
      if (r.url.pathSegments.last == method)
        jsonDecode(r.body) as Map<String, Object?>,
  ];

  /// The methods of the requests, in order (`accounts:signUp`, `accounts:lookup`, `token`, ...).
  List<String> get methods => <String>[
    for (final http.Request r in requests) r.url.pathSegments.last,
  ];

  FirebaseUserAuth create({
    String? emulatorHost,
    AuthStorage? storage,
    String? appId,
    Duration requestTimeout = const Duration(seconds: 30),
  }) => FirebaseUserAuth(
    apiKey: apiKey,
    requestTimeout: requestTimeout,
    appId: appId,
    storage: storage ?? this.storage,
    emulatorHost: emulatorHost,
    httpClient: MockClient((http.Request request) {
      requests.add(request);
      return handler(request);
    }),
    clock: clock.call,
    createTimer: timers.create,
  );

  /// The tokens of a sign-in answer for [uid].
  Map<String, Object?> tokensFor(
    String uid, {
    String provider = 'password',
    String? email,
  }) => <String, Object?>{
    'localId': uid,
    'idToken': idToken(
      uid,
      expires: clock.now.add(const Duration(hours: 1)),
      provider: provider,
      email: email,
      tag: '${_counter++}',
    ),
    'refreshToken': 'refresh:$uid',
    'expiresIn': '3600',
  };

  Future<http.Response> answer(http.Request request) async {
    final String method = request.url.pathSegments.last;
    final Map<String, Object?> body = request.method == 'GET'
        ? request.url.queryParameters
        : request.url.pathSegments.last == 'token'
        ? request.bodyFields
        : jsonDecode(request.body) as Map<String, Object?>;
    final FutureOr<http.Response> Function(Map<String, Object?> body)?
    override = overrides[method];
    if (override != null) {
      return override(body);
    }
    switch (method) {
      case 'token':
        final String refreshToken = body['refresh_token']! as String;
        final String uid = refreshToken.split(':')[1];
        return jsonResponse(<String, Object?>{
          'id_token': idToken(
            uid,
            expires: clock.now.add(const Duration(hours: 1)),
            tag: 'refresh${_counter++}',
          ),
          'refresh_token': refreshToken,
          'expires_in': '3600',
        });
      case 'accounts:lookup':
        final GetTokenResult token = GetTokenResult(body['idToken']! as String);
        final String uid = token.claims['sub'] as String;
        return jsonResponse(<String, Object?>{
          'users': <Object?>[
            <String, Object?>{'localId': uid, ...?accounts[uid]},
          ],
        });
      case 'accounts:signUp':
        final String? email = body['email'] as String?;
        final String uid = body['idToken'] is String
            ? GetTokenResult(body['idToken']! as String).claims['sub'] as String
            : email == null
            ? 'anon-user'
            : 'uid-of-$email';
        if (email != null) {
          accounts[uid] = <String, Object?>{
            ...?accounts[uid],
            'email': email,
            'passwordHash': 'hash',
            'providerUserInfo': <Object?>[
              <String, Object?>{
                'providerId': 'password',
                'rawId': email,
                'email': email,
              },
            ],
          };
        }
        return jsonResponse(<String, Object?>{
          'kind': 'identitytoolkit#SignupNewUserResponse',
          ...tokensFor(
            uid,
            provider: email == null ? 'anonymous' : 'password',
            email: email,
          ),
        });
      case 'accounts:signInWithPassword':
        final String email = body['email']! as String;
        final String uid = 'uid-of-$email';
        accounts[uid] ??= <String, Object?>{
          'email': email,
          'passwordHash': 'hash',
          'providerUserInfo': <Object?>[
            <String, Object?>{
              'providerId': 'password',
              'rawId': email,
              'email': email,
            },
          ],
        };
        return jsonResponse(<String, Object?>{
          'kind': 'identitytoolkit#VerifyPasswordResponse',
          'email': email,
          'registered': true,
          ...tokensFor(uid, email: email),
        });
      case 'accounts:signInWithCustomToken':
        return jsonResponse(<String, Object?>{
          'kind': 'identitytoolkit#VerifyCustomTokenResponse',
          'isNewUser': false,
          ...tokensFor('custom-user', provider: 'custom'),
        });
      default:
        return jsonResponse(<String, Object?>{});
    }
  }
}
