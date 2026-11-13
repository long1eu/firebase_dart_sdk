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
      if (email != null) 'email': email,
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
      final http.Request request = requests.single;
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
        'a@example.com',
        'secret',
      );
      expect(
        user,
        const AuthUser(uid: 'uid-of-a@example.com', email: 'a@example.com'),
      );
      expect(
        requests.single.url.toString(),
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
      );
      expect(jsonDecode(requests.single.body), <String, Object?>{
        'email': 'a@example.com',
        'password': 'secret',
        'returnSecureToken': true,
      });

      requests.clear();
      await auth.createUserWithEmailAndPassword('b@example.com', 'secret2');
      expect(requests.single.url.path, '/v1/accounts:signUp');
      expect(jsonDecode(requests.single.body), <String, Object?>{
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
      expect(requests.single.url.path, '/v1/accounts:signInWithCustomToken');
      expect(jsonDecode(requests.single.body), <String, Object?>{
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
            requests.single.url.toString(),
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
        throwsA(isA<FirebaseNoSignedInUserError>()),
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
      final StreamSubscription<InternalTokenResult> tokenSub = auth
          .onTokenChanged
          .listen((InternalTokenResult r) => tokens.add(r.token));
      final StreamSubscription<AuthUser?> userSub = auth.userChanges.listen(
        users.add,
      );

      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      await auth.signInWithEmailAndPassword('a@example.com', 'secret');
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
      await auth.signInWithEmailAndPassword('a@example.com', 'secret');
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
          'a@example.com',
          'secret',
        );
        await pump();
        await auth.signOut();
        release.complete();
        await expectLater(
          pending,
          throwsA(
            isA<FirebaseAuthProviderException>().having(
              (FirebaseAuthProviderException e) => e.code,
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
      final StreamSubscription<InternalTokenResult> sub = auth.onTokenChanged
          .listen((InternalTokenResult result) async {
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
    Future<FirebaseAuthProviderException> failure(
      Future<Object?> Function() action,
    ) async {
      try {
        await action();
      } on FirebaseAuthProviderException catch (e) {
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
        'SOMETHING_NEW': 'internal-error',
      };
      for (final MapEntry<String, String> entry in expected.entries) {
        handler = (http.Request request) async => error(entry.key);
        final FirebaseAuthProviderException e = await failure(
          () => auth.signInWithEmailAndPassword('a@example.com', 'secret'),
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
          () => auth.createUserWithEmailAndPassword('a@example.com', '1'),
        )).message,
        'Password should be at least 6 characters',
      );
    });

    test('a network error does not leak the URL or the API key', () async {
      handler = (http.Request request) =>
          throw http.ClientException('Connection refused', request.url);
      final FirebaseAuthProviderException e = await failure(
        auth.signInAnonymously,
      );
      expect(e.code, 'network-request-failed');
      expect('$e', isNot(contains(apiKey)));
      expect('$e', isNot(contains('identitytoolkit')));
    });

    test('an answer that is not JSON is an internal error', () async {
      handler = (http.Request request) async =>
          http.Response('<html>Bad gateway</html>', 502);
      final FirebaseAuthProviderException e = await failure(
        auth.signInAnonymously,
      );
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
          final StreamSubscription<InternalTokenResult> sub = auth
              .onTokenChanged
              .listen((InternalTokenResult r) => tokens.add(r.token));
          handler = (http.Request request) async => error(message);
          final FirebaseAuthProviderException e = await failure(
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
      final FirebaseAuthProviderException e = await failure(
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

  group('storage', () {
    const String key = 'firebase_auth_providers_dart:$apiKey';

    test(
      'the session is stored without the ID token, and removed on sign-out',
      () async {
        await auth.signInWithEmailAndPassword('a@example.com', 'secret');
        expect(jsonDecode(storage.read(key)!), <String, Object?>{
          'uid': 'uid-of-a@example.com',
          'email': 'a@example.com',
          'isAnonymous': false,
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
        final StreamSubscription<InternalTokenResult> sub = auth.onTokenChanged
            .listen((InternalTokenResult r) => tokens.add(r.token));
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
        final StreamSubscription<InternalTokenResult> sub = auth.onTokenChanged
            .listen((_) {});
        expect(timers.active.single.delay, const Duration(minutes: 45));
        await sub.cancel();
      },
    );

    test('a failed attempt is retried with a growing delay', () async {
      final StreamSubscription<InternalTokenResult> sub = auth.onTokenChanged
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
      final StreamSubscription<InternalTokenResult> sub = auth.onTokenChanged
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
            applicationId: '1:1:web:1',
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
          applicationId: '1:1:web:1',
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
      expect(requests, hasLength(2));
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
    FirebaseUserAuth withAppCheck(InternalAppCheckTokenProvider? appCheck) {
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
      expect(requests, hasLength(2));
      for (final http.Request request in requests) {
        expect(
          request.headers['X-Client-Version'],
          'Dart/DartCore/0.1.0/FirebaseCore-dart',
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
        startsWith('application/x-www-form-urlencoded'),
      );
    });

    test('no app id: no X-Firebase-gmpid', () async {
      await auth.signInAnonymously();
      expect(requests.single.headers.containsKey('X-Firebase-gmpid'), isFalse);
      expect(
        requests.single.headers['X-Client-Version'],
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
        expect(requests, hasLength(2));
        expect(requests[0].headers['X-Firebase-AppCheck'], 'placeholder');
        expect(requests[1].headers.containsKey('X-Firebase-AppCheck'), isFalse);
        expect(printed, <Matcher>[
          contains('attestation failed'),
          contains('no provider'),
        ]);
      },
    );
  });

  test('nothing prints a token', () async {
    await auth.signInWithEmailAndPassword('a@example.com', 'secret');
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

class _AppCheck implements InternalAppCheckTokenProvider {
  _AppCheck(this._getToken);

  final Future<AppCheckTokenResult> Function() _getToken;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) =>
      _getToken();

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}
