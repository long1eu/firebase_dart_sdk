// Requests that hang, proactive refreshes that fail with errors that are not from the backend, and a storage that
// cannot be read at startup.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
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
