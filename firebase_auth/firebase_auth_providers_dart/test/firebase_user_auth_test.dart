// Unit tests of FirebaseUserAuth with a fake HTTP client, a fake clock and fake timers.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const String apiKey = 'test-api-key';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

http.Response error(String message, [int status = 400]) =>
    json(<String, Object?>{
      'error': <String, Object?>{'code': status, 'message': message},
    }, status);

void main() {
  late FakeClock clock;
  late FakeTimers timers;
  late InMemoryAuthStorage storage;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request request) handler;
  late FirebaseUserAuth auth;
  int refreshes = 0;

  FirebaseUserAuth create({String? emulatorHost, AuthStorage? withStorage}) {
    return FirebaseUserAuth(
      apiKey: apiKey,
      storage: withStorage ?? storage,
      emulatorHost: emulatorHost,
      httpClient: MockClient((http.Request request) {
        requests.add(request);
        return handler(request);
      }),
      clock: clock.call,
      createTimer: timers.create,
    );
  }

  /// The accounts that `accounts:lookup` of [backend] knows beyond what the ID token says, by uid.
  late Map<String, Map<String, Object?>> accounts;

  /// The answer of `accounts:lookup` for the ID token in [body]: the uid and email of the token, the fields of
  /// [accounts], and a password provider for an account with an email address.
  http.Response lookupAnswer(Map<String, Object?> body) {
    final GetTokenResult token = GetTokenResult(body['idToken']! as String);
    final String uid = token.claims['sub'] as String;
    final String? email = token.claims['email'] as String?;
    return json(<String, Object?>{
      'users': <Object?>[
        <String, Object?>{
          'localId': uid,
          'email': ?email,
          if (email != null) 'passwordHash': 'hash',
          if (email != null)
            'providerUserInfo': <Object?>[
              <String, Object?>{
                'providerId': 'password',
                'rawId': email,
                'email': email,
              },
            ],
          ...?accounts[uid],
        },
      ],
    });
  }

  /// The backend: sign-in answers for the user in the request, the token endpoint answers with a new ID token.
  Future<http.Response> backend(http.Request request) async {
    if (request.url.path.endsWith('/token')) {
      refreshes++;
      final String refreshToken = request.bodyFields['refresh_token']!;
      final String uid = refreshToken.split(':')[1];
      return json(<String, Object?>{
        'id_token': idToken(
          uid,
          expires: clock.now.add(const Duration(hours: 1)),
          tag: 'refresh$refreshes',
        ),
        'refresh_token': refreshToken,
        'expires_in': '3600',
        'user_id': uid,
      });
    }
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    if (request.url.path.endsWith('accounts:lookup')) {
      return lookupAnswer(body);
    }
    final String? email = body['email'] as String?;
    final bool custom = request.url.path.endsWith(':signInWithCustomToken');
    final String uid = custom
        ? 'custom-user'
        : email == null
        ? 'anon-user'
        : 'uid-of-$email';
    return json(<String, Object?>{
      // The custom token answer has no localId: the uid comes from the ID token.
      if (!custom) 'localId': uid,
      'email': ?email,
      'idToken': idToken(
        uid,
        expires: clock.now.add(const Duration(hours: 1)),
        provider: custom
            ? 'custom'
            : email == null
            ? 'anonymous'
            : 'password',
        email: email,
      ),
      'refreshToken': 'refresh:$uid',
      'expiresIn': '3600',
    });
  }

  setUp(() {
    accounts = <String, Map<String, Object?>>{};
    clock = FakeClock();
    timers = FakeTimers();
    storage = InMemoryAuthStorage();
    requests = <http.Request>[];
    handler = backend;
    refreshes = 0;
    auth = create();
  });

  tearDown(() => auth.dispose());

  group('requests', () {
    test('anonymous sign-in', () async {
      final AuthUser user = await auth.signInAnonymously();
      expect(user, const AuthUser(uid: 'anon-user', isAnonymous: true));
      // Like the JS SDK, the account is read right after the sign-in.
      expect(requests, hasLength(2));
      expect(
        requests.last.url.toString(),
        'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey',
      );
      expect(jsonDecode(requests.last.body), <String, Object?>{
        'idToken': (await auth.getAccessToken(forceRefresh: false)).token,
      });
      final http.Request request = requests.first;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
      );
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), <String, Object?>{
        'returnSecureToken': true,
      });
    });

    test('email and password sign-in and sign-up', () async {
      final AuthUser user = await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      expect(
        user,
        const AuthUser(
          uid: 'uid-of-a@example.com',
          email: 'a@example.com',
          providerData: <UserInfo>[
            UserInfo(
              providerId: 'password',
              uid: 'a@example.com',
              email: 'a@example.com',
            ),
          ],
        ),
      );
      expect(
        requests.first.url.toString(),
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
      );
      expect(jsonDecode(requests.first.body), <String, Object?>{
        'email': 'a@example.com',
        'password': 'secret',
        'returnSecureToken': true,
      });

      requests.clear();
      await auth.createUserWithEmailAndPassword(
        email: 'b@example.com',
        password: 'secret2',
      );
      expect(requests.first.url.path, '/v1/accounts:signUp');
      expect(jsonDecode(requests.first.body), <String, Object?>{
        'email': 'b@example.com',
        'password': 'secret2',
        'returnSecureToken': true,
      });
      expect(auth.uid, 'uid-of-b@example.com');
    });

    test('custom token sign-in takes the uid from the ID token', () async {
      final AuthUser user = await auth.signInWithCustomToken(
        'minted.by.server',
      );
      expect(user.uid, 'custom-user');
      expect(user.isAnonymous, isFalse);
      expect(requests.first.url.path, '/v1/accounts:signInWithCustomToken');
      expect(jsonDecode(requests.first.body), <String, Object?>{
        'token': 'minted.by.server',
        'returnSecureToken': true,
      });
    });

    test('token refresh is a form post of the refresh token', () async {
      await auth.signInAnonymously();
      requests.clear();
      await auth.getAccessToken(forceRefresh: true);
      final http.Request request = requests.single;
      expect(
        request.url.toString(),
        'https://securetoken.googleapis.com/v1/token?key=$apiKey',
      );
      expect(
        request.headers['content-type'],
        contains('application/x-www-form-urlencoded'),
      );
      expect(request.bodyFields, <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': 'refresh:anon-user',
      });
    });

    test('the emulator host replaces both services', () async {
      await auth.dispose();
      auth = create(emulatorHost: '127.0.0.1:9099');
      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      expect(requests.map((http.Request r) => r.url.toString()), <String>[
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey',
        'http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=$apiKey',
      ]);
    });

    test(
      'the emulator host may name its scheme, like connectAuthEmulator',
      () async {
        for (final (String given, String origin) in <(String, String)>[
          ('localhost:9099', 'http://localhost:9099'),
          ('http://127.0.0.1:9099/', 'http://127.0.0.1:9099'),
          ('HTTPS://auth.internal:8443', 'https://auth.internal:8443'),
          ('[::1]:9099', 'http://[::1]:9099'),
          ('auth-emulator', 'http://auth-emulator'),
        ]) {
          requests.clear();
          await auth.dispose();
          auth = create(emulatorHost: given);
          await auth.signInAnonymously();
          expect(
            requests.first.url.toString(),
            '$origin/identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
            reason: given,
          );
        }
      },
    );

    test('an emulator host that is not host:port is refused', () {
      for (final String host in <String>[
        '',
        'user@127.0.0.1:9099',
        '127.0.0.1:9099/path',
        '127.0.0.1:9099?x=1',
        '127.0.0.1:9099#x',
        'ftp://127.0.0.1:9099',
        '127.0.0.1 :9099',
        r'127.0.0.1\x',
        '127.0.0.1:0',
        '127.0.0.1:65536',
        '127.0.0.1:port',
        '::1:9099',
        '[::1',
        '[::1]9099',
      ]) {
        expect(
          () => create(emulatorHost: host),
          throwsA(isA<ArgumentError>()),
          reason: host,
        );
      }
    });

    test('a Google host is never taken for an emulator', () {
      for (final String host in <String>[
        'identitytoolkit.googleapis.com',
        'securetoken.googleapis.com:443',
        'https://identitytoolkit.googleapis.com',
        'IdentityToolkit.GoogleApis.com.',
        'googleapis.com',
        'www.google.com',
      ]) {
        expect(
          () => create(emulatorHost: host),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('not an emulator'),
            ),
          ),
          reason: host,
        );
      }
    });

    test('an emulator off the loopback interface is logged as a warning', () {
      final List<String> printed = <String>[];
      runZoned(
        () {
          create(emulatorHost: '127.0.0.1:9099');
          create(emulatorHost: 'localhost:9099');
          create(emulatorHost: '[::1]:9099');
          expect(printed, isEmpty);
          create(emulatorHost: '10.0.0.5:9099');
        },
        zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
              printed.add(line),
        ),
      );
      expect(printed, hasLength(1));
      expect(
        printed.single,
        allOf(
          contains('http://10.0.0.5:9099'),
          contains('Do not use with production credentials'),
        ),
      );
    });
  });

  group('tokens', () {
    test('nobody signed in: no uid, FirebaseNoSignedInUserError', () async {
      expect(auth.uid, isNull);
      expect(auth.currentUser, isNull);
      await expectLater(
        auth.getAccessToken(forceRefresh: false),
        throwsA(isA<FirebaseNoSignedInUserException>()),
      );
      expect(requests, isEmpty);
    });

    test(
      'the ID token is reused until five minutes before it expires',
      () async {
        await auth.signInAnonymously();
        final String first = (await auth.getAccessToken(
          forceRefresh: false,
        )).token;
        clock.advance(const Duration(minutes: 54, seconds: 59));
        expect((await auth.getAccessToken(forceRefresh: false)).token, first);
        expect(refreshes, 0);

        // Within five minutes of the expiry: refreshed.
        clock.advance(const Duration(seconds: 2));
        final GetTokenResult second = await auth.getAccessToken(
          forceRefresh: false,
        );
        expect(second.token, isNot(first));
        expect(second.claims['tag'], 'refresh1');
        expect(refreshes, 1);
        // The new token is good for another hour.
        clock.advance(const Duration(minutes: 54));
        expect(
          (await auth.getAccessToken(forceRefresh: false)).token,
          second.token,
        );
        expect(refreshes, 1);
      },
    );

    test('forceRefresh always asks for a new token', () async {
      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      await auth.getAccessToken(forceRefresh: true);
      expect(refreshes, 2);
    });

    test('concurrent requests share one refresh', () async {
      await auth.signInAnonymously();
      final List<GetTokenResult> results =
          await Future.wait(<Future<GetTokenResult>>[
            auth.getAccessToken(forceRefresh: true),
            auth.getAccessToken(forceRefresh: true),
            auth.getAccessToken(forceRefresh: true),
          ]);
      expect(refreshes, 1);
      expect(results.map((GetTokenResult r) => r.token).toSet(), hasLength(1));
    });

    test('token and user changes are announced', () async {
      final List<String> tokens = <String>[];
      final List<AuthUser?> users = <AuthUser?>[];
      final StreamSubscription<AuthTokenChange> tokenSub = auth.onTokenChanged
          .listen((AuthTokenChange r) => tokens.add(r.token));
      final StreamSubscription<AuthUser?> userSub = auth.userChanges().listen(
        users.add,
      );

      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      await auth.signOut();
      await pump();

      expect(users.map((AuthUser? u) => u?.uid), <String?>[
        'anon-user',
        'uid-of-a@example.com',
        null,
      ]);
      expect(tokens, hasLength(4));
      expect(GetTokenResult(tokens[0]).claims['user_id'], 'anon-user');
      expect(GetTokenResult(tokens[1]).claims['tag'], 'refresh1');
      expect(
        GetTokenResult(tokens[2]).claims['user_id'],
        'uid-of-a@example.com',
      );
      expect(tokens[3], isEmpty);
      await tokenSub.cancel();
      await userSub.cancel();
    });

    test('a refresh that is overtaken by a user switch is dropped', () async {
      await auth.signInAnonymously();
      final Completer<void> release = Completer<void>();
      handler = (http.Request request) async {
        if (request.url.path.endsWith('/token') &&
            request.bodyFields['refresh_token'] == 'refresh:anon-user') {
          await release.future;
        }
        return backend(request);
      };
      final Future<GetTokenResult> pending = auth.getAccessToken(
        forceRefresh: true,
      );
      await pump();
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      release.complete();
      // The answer is the token of the user who is signed in now, never the one of the previous user.
      final GetTokenResult result = await pending;
      expect(result.claims['user_id'], 'uid-of-a@example.com');
      expect(auth.uid, 'uid-of-a@example.com');
    });

    test(
      'a sign-in that is overtaken by a sign-out does not sign in',
      () async {
        await auth.signInAnonymously();
        final Completer<void> release = Completer<void>();
        handler = (http.Request request) async {
          await release.future;
          return backend(request);
        };
        final Future<AuthUser> pending = auth.signInWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        );
        await pump();
        await auth.signOut();
        release.complete();
        await expectLater(
          pending,
          throwsA(
            isA<FirebaseAuthException>().having(
              (FirebaseAuthException e) => e.code,
              'code',
              'cancelled',
            ),
          ),
        );
        expect(auth.uid, isNull);
      },
    );
  });

  test(
    'a sign-in or sign-out has reached the listeners when the call returns',
    () async {
      // A chain like the one of Firestore: the listener forwards the change through a few asynchronous hops before
      // it acts on it. An operation issued right after `await signIn...()` must come after that.
      final List<String> order = <String>[];
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((AuthTokenChange result) async {
            await null;
            await Future<void>.microtask(() {});
            await null;
            order.add(
              result.token.isEmpty ? 'switch to nobody' : 'switch to user',
            );
          });
      await auth.signInAnonymously();
      order.add('after signIn');
      await auth.signOut();
      order.add('after signOut');
      expect(order, <String>[
        'switch to user',
        'after signIn',
        'switch to nobody',
        'after signOut',
      ]);
      await sub.cancel();
    },
  );

  test('deleteCurrentUser deletes the account and signs out', () async {
    await auth.signInAnonymously();
    final String token = (await auth.getAccessToken(forceRefresh: false)).token;
    requests.clear();
    handler = (http.Request request) async => json(<String, Object?>{
      'kind': 'identitytoolkit#DeleteAccountResponse',
    });
    await auth.deleteCurrentUser();
    expect(requests.single.url.path, '/v1/accounts:delete');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'idToken': token,
    });
    expect(auth.uid, isNull);
    expect(storage.read('firebase_auth_providers_dart:$apiKey'), isNull);
  });

  group('errors', () {
    Future<FirebaseAuthException> failure(
      Future<Object?> Function() action,
    ) async {
      try {
        await action();
      } on FirebaseAuthException catch (e) {
        return e;
      }
      fail('No exception');
    }

    test('the codes of the backend are mapped', () async {
      const Map<String, String> expected = <String, String>{
        'EMAIL_EXISTS': 'email-already-in-use',
        'EMAIL_NOT_FOUND': 'user-not-found',
        'INVALID_PASSWORD': 'wrong-password',
        'INVALID_LOGIN_CREDENTIALS': 'invalid-credential',
        'INVALID_EMAIL': 'invalid-email',
        'WEAK_PASSWORD : Password should be at least 6 characters':
            'weak-password',
        'USER_DISABLED': 'user-disabled',
        'TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account has been temporarily disabled':
            'too-many-requests',
        'OPERATION_NOT_ALLOWED': 'operation-not-allowed',
        'ADMIN_ONLY_OPERATION': 'admin-restricted-operation',
        'INVALID_CUSTOM_TOKEN': 'invalid-custom-token',
        'CREDENTIAL_MISMATCH': 'custom-token-mismatch',
        'API key not valid. Please pass a valid API key.': 'invalid-api-key',
        // SERVER_ERROR_MAP of the JS SDK.
        'USER_NOT_FOUND': 'user-token-expired',
        'TOKEN_EXPIRED': 'user-token-expired',
        'INVALID_ID_TOKEN': 'invalid-user-token',
        'CREDENTIAL_TOO_OLD_LOGIN_AGAIN': 'requires-recent-login',
        'EXPIRED_OOB_CODE': 'expired-action-code',
        'INVALID_OOB_CODE': 'invalid-action-code',
        'MISSING_OOB_CODE': 'internal-error',
        'RESET_PASSWORD_EXCEED_LIMIT': 'too-many-requests',
        'INVALID_IDENTIFIER': 'invalid-email',
        'PASSWORD_LOGIN_DISABLED': 'operation-not-allowed',
        'MISSING_CUSTOM_TOKEN': 'internal-error',
        'PASSWORD_DOES_NOT_MEET_REQUIREMENTS : Missing password requirements: [Password must contain an upper case character]':
            'password-does-not-meet-requirements',
        // The rest of SERVER_ERROR_MAP.
        'INVALID_IDP_RESPONSE': 'invalid-credential',
        'INVALID_PENDING_TOKEN': 'invalid-credential',
        'FEDERATED_USER_ID_ALREADY_LINKED': 'credential-already-in-use',
        'MISSING_REQ_TYPE': 'internal-error',
        'MISSING_CONTINUE_URI': 'internal-error',
        'MISSING_PASSWORD': 'missing-password',
        'INVALID_CODE': 'invalid-verification-code',
        'INVALID_SESSION_INFO': 'invalid-verification-id',
        'INVALID_TEMPORARY_PROOF': 'invalid-credential',
        'MISSING_SESSION_INFO': 'missing-verification-id',
        'SESSION_EXPIRED': 'code-expired',
        'MISSING_ANDROID_PACKAGE_NAME': 'missing-android-pkg-name',
        'UNAUTHORIZED_DOMAIN': 'unauthorized-continue-uri',
        'INVALID_OAUTH_CLIENT_ID': 'invalid-oauth-client-id',
        'INVALID_MFA_PENDING_CREDENTIAL': 'invalid-multi-factor-session',
        'MFA_ENROLLMENT_NOT_FOUND': 'multi-factor-info-not-found',
        'MISSING_MFA_ENROLLMENT_ID': 'missing-multi-factor-info',
        'MISSING_MFA_PENDING_CREDENTIAL': 'missing-multi-factor-session',
        'SECOND_FACTOR_EXISTS': 'second-factor-already-in-use',
        'SECOND_FACTOR_LIMIT_EXCEEDED': 'maximum-second-factor-count-exceeded',
        'BLOCKING_FUNCTION_ERROR_RESPONSE : HTTP Cloud Function returned an error':
            'internal-error',
        'RECAPTCHA_NOT_ENABLED': 'recaptcha-not-enabled',
        'MISSING_RECAPTCHA_TOKEN': 'missing-recaptcha-token',
        'INVALID_RECAPTCHA_TOKEN': 'invalid-recaptcha-token',
        'INVALID_RECAPTCHA_ACTION': 'invalid-recaptcha-action',
        'MISSING_CLIENT_TYPE': 'missing-client-type',
        'MISSING_RECAPTCHA_VERSION': 'missing-recaptcha-version',
        'INVALID_RECAPTCHA_VERSION': 'invalid-recaptcha-version',
        'INVALID_REQ_TYPE': 'invalid-req-type',
        // Not in the map: kebab case, which is the client code of the JS SDK too.
        'TENANT_ID_MISMATCH': 'tenant-id-mismatch',
        'INVALID_TENANT_ID': 'invalid-tenant-id',
        'MISSING_OR_INVALID_NONCE': 'missing-or-invalid-nonce',
        'UNSUPPORTED_TENANT_OPERATION': 'unsupported-tenant-operation',
        'INVALID_HOSTING_LINK_DOMAIN': 'invalid-hosting-link-domain',
        // Like the JS SDK, any other code of the backend in kebab case.
        'SOMETHING_NEW': 'something-new',
        'QUOTA_EXCEEDED : Exceeded quota for email lookup.': 'quota-exceeded',
      };
      for (final MapEntry<String, String> entry in expected.entries) {
        handler = (http.Request request) async => error(entry.key);
        final FirebaseAuthException e = await failure(
          () => auth.signInWithEmailAndPassword(
            email: 'a@example.com',
            password: 'secret',
          ),
        );
        expect(e.code, entry.value, reason: entry.key);
        expect(e.httpStatus, 400);
        expect(e.serverCode, entry.key.split(' : ').first);
        expect(auth.uid, isNull);
      }
      handler = (http.Request request) async =>
          error('WEAK_PASSWORD : Password should be at least 6 characters');
      expect(
        (await failure(
          () => auth.createUserWithEmailAndPassword(
            email: 'a@example.com',
            password: '1',
          ),
        )).message,
        'Password should be at least 6 characters',
      );
    });

    test('an HTTP 200 answer with an errorMessage is an error', () async {
      handler = (http.Request request) async => json(<String, Object?>{
        'errorMessage': 'INVALID_IDP_RESPONSE : Unable to parse id_token',
        'localId': 'someone',
        'idToken': idToken(
          'someone',
          expires: clock.now.add(const Duration(hours: 1)),
        ),
        'refreshToken': 'refresh:someone',
      });
      final FirebaseAuthException e = await failure(auth.signInAnonymously);
      expect(e.code, 'invalid-credential');
      expect(e.message, 'Unable to parse id_token');
      expect(e.httpStatus, 200);
      expect(auth.uid, isNull);
    });

    test('the errors the JS SDK tags carry the account', () async {
      handler = (http.Request request) async => json(<String, Object?>{
        'errorMessage': 'FEDERATED_USER_ID_ALREADY_LINKED',
        'email': 'a@example.com',
        'tenantId': 'tenant-1',
      });
      FirebaseAuthException e = await failure(auth.signInAnonymously);
      expect(e.code, 'credential-already-in-use');
      expect(e.email, 'a@example.com');
      expect(e.tenantId, 'tenant-1');
      expect(
        e.message,
        'This credential is already associated with a different user account.',
      );
      // Other errors do not take the address.
      handler = (http.Request request) async => json(<String, Object?>{
        'errorMessage': 'INVALID_IDP_RESPONSE',
        'email': 'a@example.com',
      });
      e = await failure(auth.signInAnonymously);
      expect(e.email, isNull);
    });

    test(
      'needConfirmation is account-exists-with-different-credential',
      () async {
        handler = (http.Request request) async => json(<String, Object?>{
          'needConfirmation': true,
          'email': 'a@example.com',
          'providerId': 'google.com',
        });
        final FirebaseAuthException e = await failure(auth.signInAnonymously);
        expect(e.code, 'account-exists-with-different-credential');
        expect(e.email, 'a@example.com');
        expect(e.httpStatus, 200);
        expect(auth.uid, isNull);
      },
    );

    test('a network error does not leak the URL or the API key', () async {
      handler = (http.Request request) =>
          throw http.ClientException('Connection refused', request.url);
      final FirebaseAuthException e = await failure(auth.signInAnonymously);
      expect(e.code, 'network-request-failed');
      expect('$e', isNot(contains(apiKey)));
      expect('$e', isNot(contains('identitytoolkit')));
    });

    test('an answer that is not JSON is an internal error', () async {
      handler = (http.Request request) async =>
          http.Response('<html>Bad gateway</html>', 502);
      final FirebaseAuthException e = await failure(auth.signInAnonymously);
      expect(e.code, 'internal-error');
      expect(e.httpStatus, 502);
    });

    test(
      'a refresh that fails because the session is gone signs the user out',
      () async {
        for (final String message in <String>[
          'TOKEN_EXPIRED',
          'USER_DISABLED',
          'USER_NOT_FOUND',
          'INVALID_REFRESH_TOKEN',
        ]) {
          handler = backend;
          await auth.signInAnonymously();
          final List<String> tokens = <String>[];
          final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
              .listen((AuthTokenChange r) => tokens.add(r.token));
          handler = (http.Request request) async => error(message);
          final FirebaseAuthException e = await failure(
            () => auth.getAccessToken(forceRefresh: true),
          );
          expect(e.invalidatesSession, isTrue, reason: message);
          expect(auth.uid, isNull, reason: message);
          expect(storage.read('firebase_auth_providers_dart:$apiKey'), isNull);
          await pump();
          expect(tokens, <String>['']);
          await sub.cancel();
        }
      },
    );

    test('a refresh that fails for another reason keeps the user', () async {
      await auth.signInAnonymously();
      handler = (http.Request request) =>
          throw http.ClientException('offline', request.url);
      final FirebaseAuthException e = await failure(
        () => auth.getAccessToken(forceRefresh: true),
      );
      expect(e.code, 'network-request-failed');
      expect(auth.uid, 'anon-user');
      // The token that is still valid keeps being served.
      expect(
        (await auth.getAccessToken(forceRefresh: false)).claims['user_id'],
        'anon-user',
      );
    });
  });

  group('multi-factor', () {
    // The answer of a sign-in endpoint for an account with a second factor (HTTP 200, no tokens), with a phone
    // and a TOTP factor, as the Identity Toolkit API lists them (`MfaEnrollment`).
    final Map<String, Object?> secondFactorRequired = <String, Object?>{
      'kind': 'identitytoolkit#VerifyPasswordResponse',
      'localId': 'uid-of-a@example.com',
      'email': 'a@example.com',
      'registered': true,
      'mfaPendingCredential': 'pending-credential',
      'mfaInfo': <Object?>[
        <String, Object?>{
          'mfaEnrollmentId': 'phone-enrollment',
          'displayName': 'Work phone',
          'phoneInfo': '+*******1234',
          'enrolledAt': '2026-03-04T05:06:07.123456Z',
        },
        <String, Object?>{
          'mfaEnrollmentId': 'totp-enrollment',
          'totpInfo': <String, Object?>{},
          'enrolledAt': '2026-05-06T07:08:09Z',
        },
        // Not an enrolment: left out.
        <String, Object?>{'displayName': 'no id'},
        'garbage',
      ],
    };

    final List<MultiFactorInfo> expectedHints = <MultiFactorInfo>[
      MultiFactorInfo(
        uid: 'phone-enrollment',
        factorId: MultiFactorInfo.phoneFactorId,
        displayName: 'Work phone',
        phoneNumber: '+*******1234',
        enrollmentTime: DateTime.utc(2026, 3, 4, 5, 6, 7, 123, 456),
      ),
      MultiFactorInfo(
        uid: 'totp-enrollment',
        factorId: MultiFactorInfo.totpFactorId,
        enrollmentTime: DateTime.utc(2026, 5, 6, 7, 8, 9),
      ),
    ];

    Matcher throwsSecondFactorRequired() => throwsA(
      isA<FirebaseAuthMultiFactorException>()
          .having(
            (FirebaseAuthMultiFactorException e) => e.code,
            'code',
            'multi-factor-auth-required',
          )
          .having(
            (FirebaseAuthMultiFactorException e) => e.pendingCredential,
            'pendingCredential',
            'pending-credential',
          )
          .having(
            (FirebaseAuthMultiFactorException e) => e.hints,
            'hints',
            expectedHints,
          )
          .having(
            (FirebaseAuthMultiFactorException e) => e.message,
            'message',
            FirebaseAuthMultiFactorException.defaultMessage,
          )
          .having(
            (FirebaseAuthMultiFactorException e) => '$e',
            'toString',
            isNot(contains('pending-credential')),
          ),
    );

    Matcher throwsAuthCode(String code) => throwsA(
      isA<FirebaseAuthException>().having(
        (FirebaseAuthException e) => e.code,
        'code',
        code,
      ),
    );

    test(
      'email and password sign-in throws multi-factor-auth-required',
      () async {
        handler = (http.Request request) async => json(secondFactorRequired);
        await expectLater(
          auth.signInWithEmailAndPassword(
            email: 'a@example.com',
            password: 'secret',
          ),
          throwsSecondFactorRequired(),
        );
        expect(auth.uid, isNull);
        expect(storage.read('firebase_auth_providers_dart:$apiKey'), isNull);
      },
    );

    test('custom token sign-in throws multi-factor-auth-required', () async {
      handler = (http.Request request) async => json(secondFactorRequired);
      await expectLater(
        auth.signInWithCustomToken('a custom token'),
        throwsSecondFactorRequired(),
      );
      expect(auth.uid, isNull);
    });

    test(
      'the signed-in user stays when another sign-in needs a second factor',
      () async {
        await auth.signInAnonymously();
        handler = (http.Request request) async => json(secondFactorRequired);
        await expectLater(
          auth.signInWithEmailAndPassword(
            email: 'a@example.com',
            password: 'secret',
          ),
          throwsSecondFactorRequired(),
        );
        expect(auth.uid, 'anon-user');
      },
    );

    test(
      'reauthentication throws multi-factor-auth-required and keeps the user',
      () async {
        await auth.signInWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        );
        handler = (http.Request request) async => json(secondFactorRequired);
        await expectLater(
          auth.reauthenticateWithEmailAndPassword(
            email: 'a@example.com',
            password: 'secret',
          ),
          throwsSecondFactorRequired(),
        );
        expect(auth.uid, 'uid-of-a@example.com');
      },
    );

    test('a normal answer still signs in', () async {
      final AuthUser user = await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      expect(user.uid, 'uid-of-a@example.com');
      // Reauthentication reads the account afterwards (accounts:lookup).
      handler = (http.Request request) async =>
          request.url.path.endsWith('accounts:lookup')
          ? json(<String, Object?>{
              'users': <Object?>[
                <String, Object?>{
                  'localId': 'uid-of-a@example.com',
                  'email': 'a@example.com',
                },
              ],
            })
          : backend(request);
      expect(
        (await auth.reauthenticateWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        )).uid,
        'uid-of-a@example.com',
      );
      expect((await auth.signInWithCustomToken('t')).uid, 'custom-user');
    });

    test(
      'an answer without tokens and without a pending credential is still an internal-error',
      () async {
        for (final Map<String, Object?> body in <Map<String, Object?>>[
          <String, Object?>{'localId': 'uid-of-a@example.com'},
          // The fields of a second factor without a usable pending credential.
          <String, Object?>{
            'mfaPendingCredential': '',
            'mfaInfo': secondFactorRequired['mfaInfo'],
          },
          <String, Object?>{'mfaPendingCredential': 42},
        ]) {
          handler = (http.Request request) async => json(body);
          await expectLater(
            auth.signInWithEmailAndPassword(
              email: 'a@example.com',
              password: 'secret',
            ),
            throwsAuthCode('internal-error'),
            reason: '$body',
          );
          await expectLater(
            auth.signInWithCustomToken('t'),
            throwsAuthCode('internal-error'),
            reason: '$body',
          );
        }
        handler = backend;
        await auth.signInWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        );
        handler = (http.Request request) async =>
            json(<String, Object?>{'localId': 'uid-of-a@example.com'});
        await expectLater(
          auth.reauthenticateWithEmailAndPassword(
            email: 'a@example.com',
            password: 'secret',
          ),
          throwsAuthCode('internal-error'),
        );
      },
    );

    test('MultiFactorInfo.fromResponse', () {
      expect(MultiFactorInfo.fromResponse(null), isNull);
      expect(MultiFactorInfo.fromResponse(<String, Object?>{}), isNull);
      expect(
        MultiFactorInfo.fromResponse(<String, Object?>{
          'mfaEnrollmentId': 'e',
          'enrolledAt': 1700000000000,
        }),
        MultiFactorInfo(
          uid: 'e',
          factorId: MultiFactorInfo.unknownFactorId,
          enrollmentTime: DateTime.fromMillisecondsSinceEpoch(
            1700000000000,
            isUtc: true,
          ),
        ),
      );
      expect(
        MultiFactorInfo.fromResponse(<String, Object?>{
          'mfaEnrollmentId': 'e',
          'phoneInfo': '+*******1234',
          'enrolledAt': 'not a time',
          'displayName': '',
        }),
        const MultiFactorInfo(
          uid: 'e',
          factorId: MultiFactorInfo.phoneFactorId,
          phoneNumber: '+*******1234',
        ),
      );
      expect(
        FirebaseAuthMultiFactorException.fromResponse(<String, Object?>{
          'mfaPendingCredential': 'p',
        })?.hints,
        isEmpty,
      );
    });
  });

  group('account management', () {
    /// The backend of the group: sign-in as [backend], [answer] for the account operations.
    void answering(
      Future<http.Response> Function(String method, Map<String, Object?> body)
      answer,
    ) {
      handler = (http.Request request) async {
        final String method = request.url.pathSegments.last;
        // A sign-in reads the account right after (accounts:lookup).
        final bool afterSignIn =
            method == 'accounts:lookup' &&
            requests.length > 1 &&
            requests[requests.length - 2].url.pathSegments.last.startsWith(
              'accounts:sign',
            );
        if (method.startsWith('accounts:sign') ||
            method == 'token' ||
            afterSignIn) {
          return backend(request);
        }
        return answer(method, jsonDecode(request.body) as Map<String, Object?>);
      };
    }

    test('the requests have the shape of the JS SDK', () async {
      final List<List<Object?>> calls = <List<Object?>>[];
      answering((String method, Map<String, Object?> body) async {
        calls.add(<Object?>[method, body]);
        return switch (method) {
          'accounts:sendOobCode' => json(<String, Object?>{
            'email': 'a@example.com',
          }),
          'accounts:createAuthUri' => json(<String, Object?>{
            'signinMethods': <String>['password'],
          }),
          'accounts:lookup' => json(<String, Object?>{
            'users': <Object?>[
              <String, Object?>{
                'localId': 'uid-of-a@example.com',
                'email': 'a@example.com',
              },
            ],
          }),
          _ => json(<String, Object?>{}),
        };
      });
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      final String idToken = (await auth.getAccessToken(
        forceRefresh: false,
      )).token;

      await auth.sendPasswordResetEmail(
        email: 'a@example.com',
        actionCodeSettings: const ActionCodeSettings(
          url: 'https://example.com/done',
          handleCodeInApp: true,
          iOSBundleId: 'com.example.ios',
          androidPackageName: 'com.example.android',
          androidInstallApp: true,
          androidMinimumVersion: '12',
          linkDomain: 'example.page.link',
        ),
      );
      await auth.confirmPasswordReset(
        code: 'code-1',
        newPassword: 'new-password',
      );
      await auth.applyActionCode('code-2');
      await auth.sendEmailVerification();
      await auth.updateProfile(displayName: 'Ada', photoUrl: '');
      expect(await auth.fetchSignInMethodsForEmail('a@example.com'), <String>[
        'password',
      ]);

      expect(calls, <List<Object?>>[
        <Object?>[
          'accounts:sendOobCode',
          <String, Object?>{
            'requestType': 'PASSWORD_RESET',
            'email': 'a@example.com',
            'continueUrl': 'https://example.com/done',
            'linkDomain': 'example.page.link',
            'canHandleCodeInApp': true,
            'iOSBundleId': 'com.example.ios',
            'androidPackageName': 'com.example.android',
            'androidInstallApp': true,
            'androidMinimumVersionCode': '12',
          },
        ],
        <Object?>[
          'accounts:resetPassword',
          <String, Object?>{'oobCode': 'code-1', 'newPassword': 'new-password'},
        ],
        <Object?>[
          'accounts:update',
          <String, Object?>{'oobCode': 'code-2'},
        ],
        <Object?>[
          'accounts:sendOobCode',
          <String, Object?>{'requestType': 'VERIFY_EMAIL', 'idToken': idToken},
        ],
        <Object?>[
          'accounts:update',
          <String, Object?>{
            'idToken': idToken,
            'displayName': 'Ada',
            'deleteAttribute': <Object?>['PHOTO_URL'],
            'returnSecureToken': true,
          },
        ],
        <Object?>[
          'accounts:createAuthUri',
          <String, Object?>{
            'identifier': 'a@example.com',
            'continueUri': 'http://localhost',
          },
        ],
      ]);
    });

    test('action code settings are checked before sending', () async {
      for (final (ActionCodeSettings settings, String code)
          in <(ActionCodeSettings, String)>[
            (const ActionCodeSettings(url: ''), 'invalid-continue-uri'),
            (
              const ActionCodeSettings(url: 'https://x', iOSBundleId: ''),
              'missing-ios-bundle-id',
            ),
            (
              const ActionCodeSettings(
                url: 'https://x',
                androidPackageName: '',
              ),
              'missing-android-pkg-name',
            ),
            (
              const ActionCodeSettings(url: 'https://x', linkDomain: ''),
              'invalid-hosting-link-domain',
            ),
          ]) {
        await expectLater(
          auth.sendPasswordResetEmail(
            email: 'a@example.com',
            actionCodeSettings: settings,
          ),
          throwsA(
            isA<FirebaseAuthException>().having(
              (FirebaseAuthException e) => e.code,
              'code',
              code,
            ),
          ),
        );
      }
      expect(requests, isEmpty);
    });

    test('checkActionCode reads the operation and the addresses', () async {
      answering(
        (String method, Map<String, Object?> body) async =>
            json(<String, Object?>{
              'email': 'old@example.com',
              'newEmail': 'new@example.com',
              'requestType': body['oobCode'],
            }),
      );
      final ActionCodeInfo change = await auth.checkActionCode(
        'VERIFY_AND_CHANGE_EMAIL',
      );
      expect(change.operation, ActionCodeOperation.verifyAndChangeEmail);
      expect(change.email, 'new@example.com');
      expect(change.previousEmail, 'old@example.com');
      final ActionCodeInfo recover = await auth.checkActionCode(
        'RECOVER_EMAIL',
      );
      expect(recover.email, 'old@example.com');
      expect(recover.previousEmail, 'new@example.com');
      // An operation the package does not know is returned as given, like the JS SDK does.
      final ActionCodeInfo other = await auth.checkActionCode('SOMETHING_NEW');
      expect(other.operation, ActionCodeOperation.unknown);
      expect(other.requestType, 'SOMETHING_NEW');
      expect(other.email, 'old@example.com');
      expect('$other', 'ActionCodeInfo(SOMETHING_NEW)');
      expect(change.requestType, 'VERIFY_AND_CHANGE_EMAIL');
    });

    test('checkActionCode checks what each operation needs', () async {
      Map<String, Object?> answer = <String, Object?>{};
      answering(
        (String method, Map<String, Object?> body) async => json(answer),
      );
      Matcher internal = throwsA(
        isA<FirebaseAuthException>().having(
          (FirebaseAuthException e) => e.code,
          'code',
          'internal-error',
        ),
      );
      // No operation, and an unknown operation without an email address.
      answer = <String, Object?>{'email': 'a@example.com'};
      await expectLater(auth.checkActionCode('c'), internal);
      answer = <String, Object?>{'requestType': 'SOMETHING_NEW'};
      await expectLater(auth.checkActionCode('c'), internal);
      // An email link sign-in needs nothing.
      answer = <String, Object?>{'requestType': 'EMAIL_SIGNIN'};
      expect(
        (await auth.checkActionCode('c')).operation,
        ActionCodeOperation.emailSignIn,
      );
      // Reverting a second factor needs the factor and the address.
      answer = <String, Object?>{
        'requestType': 'REVERT_SECOND_FACTOR_ADDITION',
        'email': 'a@example.com',
      };
      await expectLater(auth.checkActionCode('c'), internal);
      answer = <String, Object?>{
        'requestType': 'REVERT_SECOND_FACTOR_ADDITION',
        'email': 'a@example.com',
        'mfaInfo': <String, Object?>{
          'mfaEnrollmentId': 'factor-1',
          'phoneInfo': '+*******1234',
        },
      };
      final ActionCodeInfo revert = await auth.checkActionCode('c');
      expect(revert.operation, ActionCodeOperation.revertSecondFactorAddition);
      expect(revert.multiFactorInfo?.uid, 'factor-1');
      expect(revert.multiFactorInfo?.factorId, MultiFactorInfo.phoneFactorId);
    });

    test(
      'a disabled account signs the user out (_logoutIfInvalidated)',
      () async {
        answering(
          (String method, Map<String, Object?> body) async =>
              error('USER_DISABLED'),
        );
        await auth.signInWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        );
        await expectLater(
          auth.updateProfile(displayName: 'x'),
          throwsA(isA<FirebaseAuthException>()),
        );
        expect(auth.uid, isNull);
      },
    );

    test('another error keeps the user', () async {
      answering(
        (String method, Map<String, Object?> body) async =>
            error('CREDENTIAL_TOO_OLD_LOGIN_AGAIN'),
      );
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      await expectLater(
        auth.updatePassword('another'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (FirebaseAuthException e) => e.code,
            'code',
            'requires-recent-login',
          ),
        ),
      );
      expect(auth.uid, 'uid-of-a@example.com');
    });

    test('reauthentication as somebody else is a user-mismatch', () async {
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      await expectLater(
        auth.reauthenticateWithEmailAndPassword(
          email: 'b@example.com',
          password: 'secret',
        ),
        throwsA(
          isA<FirebaseAuthException>().having(
            (FirebaseAuthException e) => e.code,
            'code',
            'user-mismatch',
          ),
        ),
      );
      expect(auth.uid, 'uid-of-a@example.com');
    });

    test('the profile is stored and restored', () async {
      answering(
        (String method, Map<String, Object?> body) async =>
            json(<String, Object?>{
              'displayName': 'Ada',
              'photoUrl': 'https://example.com/a.png',
            }),
      );
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      await auth.updateProfile(
        displayName: 'Ada',
        photoUrl: 'https://example.com/a.png',
      );
      await auth.dispose();
      auth = create();
      await auth.restore();
      expect(
        auth.currentUser,
        const AuthUser(
          uid: 'uid-of-a@example.com',
          email: 'a@example.com',
          displayName: 'Ada',
          photoUrl: 'https://example.com/a.png',
          providerData: <UserInfo>[
            UserInfo(
              providerId: 'password',
              uid: 'a@example.com',
              email: 'a@example.com',
            ),
          ],
        ),
      );
    });
  });

  group('storage', () {
    const String key = 'firebase_auth_providers_dart:$apiKey';

    test(
      'the session is stored without the ID token, and removed on sign-out',
      () async {
        await auth.signInWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        );
        expect(jsonDecode(storage.read(key)!), <String, Object?>{
          'version': 2,
          'uid': 'uid-of-a@example.com',
          'email': 'a@example.com',
          'isAnonymous': false,
          'emailVerified': false,
          'displayName': null,
          'photoUrl': null,
          'phoneNumber': null,
          'tenantId': null,
          'createdAt': null,
          'lastLoginAt': null,
          'providerData': <Object?>[
            <String, Object?>{
              'providerId': 'password',
              'rawId': 'a@example.com',
              'email': 'a@example.com',
              'displayName': null,
              'photoUrl': null,
              'phoneNumber': null,
            },
          ],
          'refreshToken': 'refresh:uid-of-a@example.com',
        });
        await auth.signOut();
        expect(storage.read(key), isNull);
      },
    );

    test(
      'a new instance restores the user and fetches a token when needed',
      () async {
        await auth.signInAnonymously();
        await auth.dispose();
        requests.clear();

        auth = create();
        expect(auth.uid, isNull);
        await auth.restore();
        expect(
          auth.currentUser,
          const AuthUser(uid: 'anon-user', isAnonymous: true),
        );
        expect(
          requests,
          isEmpty,
          reason: 'restoring does not need the network',
        );

        final GetTokenResult token = await auth.getAccessToken(
          forceRefresh: false,
        );
        expect(token.claims['user_id'], 'anon-user');
        expect(
          requests.single.bodyFields['refresh_token'],
          'refresh:anon-user',
        );
      },
    );

    test('a rotated refresh token is stored', () async {
      await auth.signInAnonymously();
      handler = (http.Request request) async => json(<String, Object?>{
        'id_token': idToken(
          'anon-user',
          expires: clock.now.add(const Duration(hours: 1)),
        ),
        'refresh_token': 'refresh:anon-user:rotated',
        'expires_in': '3600',
      });
      await auth.getAccessToken(forceRefresh: true);
      expect(
        (jsonDecode(storage.read(key)!)
            as Map<String, Object?>)['refreshToken'],
        'refresh:anon-user:rotated',
      );
      await auth.getAccessToken(forceRefresh: true);
      expect(
        requests.last.bodyFields['refresh_token'],
        'refresh:anon-user:rotated',
      );
    });

    test('garbage in the storage means signed out', () async {
      storage.write(key, 'not json');
      await auth.restore();
      expect(auth.uid, isNull);
      storage.write(key, '{"uid": 1}');
      await auth.restore();
      expect(auth.uid, isNull);
    });

    test('a stored email that is not a string is dropped', () async {
      storage.write(
        key,
        '{"uid": "u", "refreshToken": "r", "email": 1, "isAnonymous": false}',
      );
      await auth.restore();
      expect(auth.uid, 'u');
      expect(auth.currentUser!.email, isNull);
    });

    test('an asynchronous storage works', () async {
      final _AsyncStorage asyncStorage = _AsyncStorage();
      await auth.dispose();
      auth = create(withStorage: asyncStorage);
      await auth.signInAnonymously();
      expect(asyncStorage.values, hasLength(1));
      await auth.dispose();
      auth = create(withStorage: asyncStorage);
      await auth.restore();
      expect(auth.uid, 'anon-user');
    });
  });

  group('proactive refresh', () {
    test('without a token listener nothing is scheduled', () async {
      await auth.signInAnonymously();
      expect(timers.active, isEmpty);
    });

    test(
      'with a listener the token is refreshed five minutes before expiry',
      () async {
        final List<String> tokens = <String>[];
        final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
            .listen((AuthTokenChange r) => tokens.add(r.token));
        await auth.signInAnonymously();
        expect(timers.active.single.delay, const Duration(minutes: 55));

        clock.advance(const Duration(minutes: 55));
        timers.active.single.fire();
        await pump();
        expect(refreshes, 1);
        expect(tokens, hasLength(2));
        // And the next one is scheduled for the new token.
        expect(timers.active.single.delay, const Duration(minutes: 55));

        // The last listener leaves: the timer is cancelled.
        await sub.cancel();
        expect(timers.active, isEmpty);
      },
    );

    test(
      'a listener that arrives after the sign-in starts the schedule',
      () async {
        await auth.signInAnonymously();
        clock.advance(const Duration(minutes: 10));
        final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
            .listen((_) {});
        expect(timers.active.single.delay, const Duration(minutes: 45));
        await sub.cancel();
      },
    );

    test('a failed attempt is retried with a growing delay', () async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      await auth.signInAnonymously();
      handler = (http.Request request) =>
          throw http.ClientException('offline', request.url);

      clock.advance(const Duration(minutes: 55));
      final List<Duration> delays = <Duration>[];
      for (int i = 0; i < 8; i++) {
        final FakeTimer timer = timers.active.single;
        timer.fire();
        await pump();
        delays.add(timers.active.single.delay);
        clock.advance(timers.active.single.delay);
      }
      expect(delays, const <Duration>[
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 4),
        Duration(minutes: 8),
        Duration(minutes: 16),
        Duration(minutes: 16),
        Duration(minutes: 16),
      ]);
      expect(auth.uid, 'anon-user');

      // Back online: the refresh succeeds and the normal schedule resumes.
      handler = backend;
      timers.active.single.fire();
      await pump();
      expect(timers.active.single.delay, const Duration(minutes: 55));
      await sub.cancel();
    });

    test('sign-out and dispose cancel the schedule', () async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      await auth.signInAnonymously();
      expect(timers.active, hasLength(1));
      await auth.signOut();
      expect(timers.active, isEmpty);

      await auth.signInAnonymously();
      expect(timers.active, hasLength(1));
      await sub.cancel();
      await auth.dispose();
      expect(timers.active, isEmpty);
      expect(auth.signInAnonymously, throwsStateError);
    });
  });

  group('forApp', () {
    test(
      'registers the provider with the app and restores the session',
      () async {
        final FirebaseApp app = FirebaseApp.withOptions(
          const FirebaseOptions(
            apiKey: apiKey,
            appId: '1:1:web:1',
            projectId: 'demo',
          ),
          name: 'forApp-${DateTime.now().microsecondsSinceEpoch}',
        );
        addTearDown(app.delete);
        final MockClient client = MockClient((http.Request request) {
          requests.add(request);
          return backend(request);
        });
        final FirebaseUserAuth first = await FirebaseUserAuth.forApp(
          app,
          storage: storage,
          httpClient: client,
        );
        expect(app.authProvider, same(first));
        await first.signInAnonymously();
        expect(
          storage.read('firebase_auth_providers_dart:$apiKey:${app.name}'),
          isNotNull,
        );
        await first.dispose();

        final FirebaseUserAuth second = await FirebaseUserAuth.forApp(
          app,
          storage: storage,
          httpClient: client,
        );
        expect(second.uid, 'anon-user');
        expect(app.authProvider, same(second));
        await second.dispose();
      },
    );

    test('sends the app id and the App Check token of the app', () async {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: apiKey,
          appId: '1:1:web:1',
          projectId: 'demo',
        ),
        name: 'forApp-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(app.delete);
      app.appCheckProvider = _AppCheck(
        () async => const AppCheckTokenResult('app-check-token'),
      );
      final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
        app,
        storage: storage,
        httpClient: MockClient((http.Request request) {
          requests.add(request);
          return backend(request);
        }),
      );
      addTearDown(auth.dispose);
      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      expect(requests, hasLength(3));
      for (final http.Request request in requests) {
        expect(request.headers['X-Firebase-gmpid'], '1:1:web:1');
        expect(request.headers['X-Firebase-AppCheck'], 'app-check-token');
        expect(
          request.headers['X-Client-Version'],
          FirebaseUserAuth.clientVersion,
        );
      }
    });
  });

  group('the headers of the JS SDK', () {
    FirebaseUserAuth withAppCheck(AppCheckTokenProvider? appCheck) {
      final FirebaseUserAuth created = FirebaseUserAuth(
        apiKey: apiKey,
        appId: '1:2:web:3',
        appCheck: appCheck,
        storage: storage,
        httpClient: MockClient((http.Request request) {
          requests.add(request);
          return backend(request);
        }),
        clock: clock.call,
        createTimer: timers.create,
      );
      addTearDown(created.dispose);
      return created;
    }

    test('every request: client version and app id; content types', () async {
      final FirebaseUserAuth auth = withAppCheck(null);
      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      expect(requests, hasLength(3));
      for (final http.Request request in requests) {
        expect(
          request.headers['X-Client-Version'],
          'Dart/DartCore/0.3.0/FirebaseCore-dart',
        );
        expect(request.headers['X-Firebase-gmpid'], '1:2:web:3');
        expect(request.headers.containsKey('X-Firebase-AppCheck'), isFalse);
      }
      expect(
        requests[0].headers['content-type'],
        startsWith('application/json'),
      );
      expect(
        requests[1].headers['content-type'],
        startsWith('application/json'),
      );
      expect(
        requests[2].headers['content-type'],
        startsWith('application/x-www-form-urlencoded'),
      );
    });

    test('no app id: no X-Firebase-gmpid', () async {
      await auth.signInAnonymously();
      expect(requests.first.headers.containsKey('X-Firebase-gmpid'), isFalse);
      expect(
        requests.first.headers['X-Client-Version'],
        FirebaseUserAuth.clientVersion,
      );
    });

    test(
      'a failed App Check request: the placeholder is sent and logged',
      () async {
        final List<String> printed = <String>[];
        await runZoned(
          () async {
            await withAppCheck(
              _AppCheck(
                () async => AppCheckTokenResult(
                  'placeholder',
                  error: StateError('attestation failed'),
                ),
              ),
            ).signInAnonymously();
            await withAppCheck(
              _AppCheck(() async => throw StateError('no provider')),
            ).signInAnonymously();
          },
          zoneSpecification: ZoneSpecification(
            print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
                printed.add(line),
          ),
        );
        // Two requests each: the sign-in and the account lookup.
        expect(requests, hasLength(4));
        expect(requests[0].headers['X-Firebase-AppCheck'], 'placeholder');
        expect(requests[1].headers['X-Firebase-AppCheck'], 'placeholder');
        expect(requests[2].headers.containsKey('X-Firebase-AppCheck'), isFalse);
        expect(printed, <Matcher>[
          contains('attestation failed'),
          contains('attestation failed'),
          contains('no provider'),
          contains('no provider'),
        ]);
      },
    );
  });

  test('nothing prints a token', () async {
    await auth.signInWithEmailAndPassword(
      email: 'a@example.com',
      password: 'secret',
    );
    final GetTokenResult token = await auth.getAccessToken(forceRefresh: false);
    // The string form of the user has the uid, not the email address.
    expect(
      '${auth.currentUser}',
      'AuthUser(uid: uid-of-a@example.com, isAnonymous: false)',
    );
    expect('$token', isNot(contains(token.token)));
  });
}

class _AsyncStorage implements AuthStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(Duration.zero);
    return values[key];
  }

  @override
  Future<void> write(String key, String? value) async {
    await Future<void>.delayed(Duration.zero);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class _AppCheck implements AppCheckTokenProvider {
  _AppCheck(this._getToken);

  final Future<AppCheckTokenResult> Function() _getToken;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) =>
      _getToken();

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}
