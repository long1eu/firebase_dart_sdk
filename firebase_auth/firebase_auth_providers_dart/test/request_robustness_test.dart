// Requests that hang, proactive refreshes that fail with errors that are not from the backend, and a storage that
// cannot be read at startup.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';

/// An [InMemoryAuthStorage] whose reads and writes can be made to throw.
class FlakyStorage extends InMemoryAuthStorage {
  bool failReads = false;
  bool failWrites = false;

  @override
  String? read(String key) {
    if (failReads) {
      throw StateError('storage locked');
    }
    return super.read(key);
  }

  @override
  void write(String key, String? value) {
    if (failWrites) {
      throw StateError('storage locked');
    }
    super.write(key, value);
  }
}

void main() {
  late FakeBackend backend;
  late FlakyStorage storage;
  late FirebaseUserAuth auth;

  setUp(() {
    backend = FakeBackend();
    storage = FlakyStorage();
    auth = backend.create(
      storage: storage,
      requestTimeout: const Duration(milliseconds: 20),
    );
  });

  tearDown(() => auth.dispose());

  int countOf(String method) =>
      backend.methods.where((String m) => m == method).length;

  group('request timeout', () {
    test('a hung response fails with network-request-failed', () async {
      await auth.signInAnonymously();
      backend.on('token', (_) => Completer<http.Response>().future);
      await expectLater(
        auth.getAccessToken(forceRefresh: true),
        throwsA(
          isA<FirebaseAuthException>()
              .having(
                (FirebaseAuthException e) => e.code,
                'code',
                'network-request-failed',
              )
              .having(
                (FirebaseAuthException e) => e.message,
                'message',
                contains('timed out'),
              ),
        ),
      );
      expect(auth.uid, 'anon-user');
    });

    test(
      'a later token request after a timeout retries and succeeds',
      () async {
        await auth.signInAnonymously();
        backend.on('token', (_) => Completer<http.Response>().future);
        await expectLater(
          auth.getAccessToken(forceRefresh: true),
          throwsAuth('network-request-failed'),
        );
        backend.overrides.remove('token');
        final GetTokenResult token = await auth.getAccessToken(
          forceRefresh: true,
        );
        expect(token.token, isNotEmpty);
        expect(countOf('token'), 2);
        expect(auth.uid, 'anon-user');
      },
    );
  });

  group('proactive refresh', () {
    test('reschedules after an error that is not from the backend', () async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      addTearDown(sub.cancel);
      await auth.signInAnonymously();
      // A new refresh token is stored, and the storage throws a StateError.
      backend.on(
        'token',
        (_) => jsonResponse(<String, Object?>{
          'id_token': 'not-a-jwt',
          'refresh_token': 'refresh:anon-user:rotated',
          'expires_in': '3600',
        }),
      );
      storage.failWrites = true;
      backend.clock.advance(const Duration(minutes: 55));
      backend.timers.active.single.fire();
      await pump();
      expect(auth.uid, 'anon-user');
      expect(backend.timers.active, hasLength(1));
    });

    test('backs off after a timed-out refresh', () async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      addTearDown(sub.cancel);
      await auth.signInAnonymously();
      backend.on('token', (_) => Completer<http.Response>().future);
      backend.clock.advance(const Duration(minutes: 55));
      backend.timers.active.single.fire();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(auth.uid, 'anon-user');
      expect(backend.timers.active.single.delay, const Duration(seconds: 30));
    });

    test('does not reschedule after the session ended', () async {
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((_) {});
      addTearDown(sub.cancel);
      await auth.signInAnonymously();
      backend.on('token', (_) => errorResponse('TOKEN_EXPIRED'));
      backend.clock.advance(const Duration(minutes: 55));
      backend.timers.active.single.fire();
      await pump();
      expect(auth.uid, isNull);
      expect(backend.timers.active, isEmpty);
    });
  });

  group('storage write', () {
    const String key = 'firebase_auth_providers_dart:$apiKey';

    /// A secure token service that rejects a refresh token once it has been used, and replaces it with a new one
    /// while [rotate] says so.
    late bool rotate;
    setUp(() {
      rotate = true;
      final Set<String> revoked = <String>{};
      int rotation = 0;
      backend.on('token', (Map<String, Object?> body) {
        final String refreshToken = body['refresh_token']! as String;
        if (revoked.contains(refreshToken)) {
          return errorResponse('INVALID_REFRESH_TOKEN');
        }
        final String uid = refreshToken.split(':')[1];
        String next = refreshToken;
        if (rotate) {
          revoked.add(refreshToken);
          next = 'refresh:$uid:${++rotation}';
        }
        return jsonResponse(<String, Object?>{
          'id_token': idToken(
            uid,
            expires: backend.clock.now.add(const Duration(hours: 1)),
            tag: 'rotation$rotation',
          ),
          'refresh_token': next,
          'expires_in': '3600',
        });
      });
    });

    test(
      'a failed write keeps the new session in memory and stores it at the next refresh',
      () async {
        await auth.signInAnonymously();
        final String? before = storage.read(key);
        expect(before, contains('refresh:anon-user'));

        storage.failWrites = true;
        await expectLater(
          auth.getAccessToken(forceRefresh: true),
          throwsStateError,
        );
        // Still signed in, with the new tokens; the storage has the old session.
        expect(auth.uid, 'anon-user');
        expect(storage.read(key), before);
        final GetTokenResult token = await auth.getAccessToken(
          forceRefresh: false,
        );
        expect(token.claims['tag'], 'rotation1');
        expect(countOf('token'), 1);

        // The next refresh keeps the same refresh token, and stores the session all the same.
        storage.failWrites = false;
        rotate = false;
        await auth.getAccessToken(forceRefresh: true);
        expect(storage.read(key), contains('refresh:anon-user:1'));
        await auth.dispose();

        auth = backend.create(storage: storage);
        await auth.restore();
        expect(auth.uid, 'anon-user');
        expect(
          (await auth.getAccessToken(forceRefresh: false)).token,
          isNotEmpty,
        );
        expect(auth.uid, 'anon-user');
      },
    );
  });

  group('forApp', () {
    test(
      'registers the provider when the storage throws on read, and restore() retries',
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
          backend.requests.add(request);
          return backend.handler(request);
        });
        final FirebaseUserAuth first = await FirebaseUserAuth.forApp(
          app,
          storage: storage,
          httpClient: client,
        );
        await first.signInAnonymously();
        await first.dispose();

        storage.failReads = true;
        await expectLater(
          FirebaseUserAuth.forApp(app, storage: storage, httpClient: client),
          throwsStateError,
        );
        final AuthTokenProvider provider = app.authProvider;
        expect(provider, isA<FirebaseUserAuth>());
        expect(provider, isNot(same(first)));
        final FirebaseUserAuth second = provider as FirebaseUserAuth;
        addTearDown(second.dispose);
        expect(second.uid, isNull);

        storage.failReads = false;
        await second.restore();
        expect(second.uid, 'anon-user');
      },
    );
  });

  group('restore', () {
    test('a storage that throws on read keeps the stored session', () async {
      await auth.signInAnonymously();
      await auth.dispose();
      final String? stored = storage.read(
        'firebase_auth_providers_dart:$apiKey',
      );
      expect(stored, isNotNull);

      storage.failReads = true;
      auth = backend.create(storage: storage);
      await expectLater(auth.restore(), throwsStateError);
      expect(auth.uid, isNull);
      storage.failReads = false;
      expect(storage.read('firebase_auth_providers_dart:$apiKey'), stored);

      // Once the storage can be read, the session comes back.
      await auth.restore();
      expect(auth.uid, 'anon-user');
    });

    test('a storage that throws on read keeps the signed-in user', () async {
      await auth.signInAnonymously();
      storage.failReads = true;
      await expectLater(auth.restore(), throwsStateError);
      expect(auth.uid, 'anon-user');
      storage.failReads = false;
      expect(storage.read('firebase_auth_providers_dart:$apiKey'), isNotNull);
    });
  });
}
