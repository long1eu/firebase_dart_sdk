// authStateChanges(), idTokenChanges(), authStateReady(), beforeAuthStateChanged() and updateCurrentUser(), and
// that the token stream Firestore follows (onTokenChanged) keeps its contract.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
  });

  tearDown(() => auth.dispose());

  List<String?> uids(List<AuthUser?> users) => <String?>[
    for (final AuthUser? user in users) user?.uid,
  ];

  group('authStateChanges', () {
    test(
      'starts with the current user, then follows sign-in and sign-out',
      () async {
        final List<AuthUser?> events = <AuthUser?>[];
        auth.authStateChanges().listen(events.add);
        await pump();
        expect(events, <AuthUser?>[null]);

        await auth.signInAnonymously();
        await pump();
        expect(uids(events), <String?>[null, 'anon-user']);

        // The same user again, a refresh, a profile change: nothing.
        await auth.signInAnonymously();
        await auth.getAccessToken(forceRefresh: true);
        await auth.updateProfile(displayName: 'x');
        await pump();
        expect(events, hasLength(2));

        await auth.signInWithEmailAndPassword(
          email: 'a@example.com',
          password: 'secret',
        );
        await auth.signOut();
        await pump();
        expect(uids(events), <String?>[
          null,
          'anon-user',
          'uid-of-a@example.com',
          null,
        ]);
      },
    );

    test('a late listener gets the signed-in user first', () async {
      await auth.signInAnonymously();
      expect(uids(await auth.authStateChanges().take(1).toList()), <String?>[
        'anon-user',
      ]);
    });

    test('waits for a restore in progress, and emits once', () async {
      final FirebaseUserAuth first = backend.create();
      await first.signInAnonymously();
      await first.dispose();

      final List<AuthUser?> events = <AuthUser?>[];
      final Future<void> restoring = auth.restore();
      auth.authStateChanges().listen(events.add);
      await restoring;
      await pump();
      expect(uids(events), <String?>['anon-user']);
    });

    test('a restore after the first event is a change', () async {
      final FirebaseUserAuth first = backend.create();
      await first.signInAnonymously();
      await first.dispose();

      final List<AuthUser?> events = <AuthUser?>[];
      auth.authStateChanges().listen(events.add);
      await pump();
      await auth.restore();
      await pump();
      expect(uids(events), <String?>[null, 'anon-user']);
    });

    test('closes when the instance is disposed', () async {
      final Completer<void> done = Completer<void>();
      auth.authStateChanges().listen(null, onDone: done.complete);
      await auth.dispose();
      await done.future;
    });
  });

  group('idTokenChanges', () {
    test('also emits for every new token', () async {
      final List<AuthUser?> events = <AuthUser?>[];
      auth.idTokenChanges().listen(events.add);
      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      await auth.signOut();
      await pump();
      expect(uids(events), <String?>[null, 'anon-user', 'anon-user', null]);
    });

    test('the token stream Firestore follows is unchanged', () async {
      // FirebaseAuthCredentialsProvider of cloud_firestore_dart reads uid synchronously on each event.
      final List<(String, String?)> events = <(String, String?)>[];
      auth.onTokenChanged.listen(
        (AuthTokenChange change) => events.add((change.token, auth.uid)),
      );
      await auth.signInAnonymously();
      await auth.getAccessToken(forceRefresh: true);
      await auth.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      await auth.signOut();
      expect(
        <String?>[for (final (_, String? uid) in events) uid],
        <String?>['anon-user', 'anon-user', 'uid-of-a@example.com', null],
      );
      expect(events.last.$1, '');
      expect(events.first.$1, isNotEmpty);
    });
  });

  group('authStateReady', () {
    test('completes at once without a restore', () async {
      await auth.authStateReady();
    });

    test('completes after the restore', () async {
      final Completer<String?> read = Completer<String?>();
      auth = backend.create(storage: _ControlledStorage(read.future));
      final Future<void> restoring = auth.restore();
      bool ready = false;
      final Future<void> waiting = auth.authStateReady().then(
        (_) => ready = true,
      );
      await pump();
      expect(ready, isFalse);
      read.complete(null);
      await restoring;
      await waiting;
      expect(ready, isTrue);
    });

    test('fails like the restore', () async {
      auth = backend.create(
        storage: _ControlledStorage(Future<String?>.error(StateError('disk'))),
      );
      final Future<void> restoring = auth.restore();
      final Future<void> ready = auth.authStateReady();
      await expectLater(restoring, throwsStateError);
      await expectLater(ready, throwsStateError);
      // The stream still starts, signed out.
      expect(await auth.authStateChanges().first, isNull);
    });
  });

  group('beforeAuthStateChanged', () {
    test('runs before the user changes, and is awaited', () async {
      final List<String> log = <String>[];
      auth.beforeAuthStateChanged((AuthUser? next) async {
        await pump();
        log.add('before ${next?.uid} (current ${auth.uid})');
      });
      auth.authStateChanges().listen(
        (AuthUser? u) => log.add('state ${u?.uid}'),
      );
      await pump();
      await auth.signInAnonymously();
      await auth.signOut();
      await pump();
      expect(log, <String>[
        'state null',
        'before anon-user (current null)',
        'state anon-user',
        'before null (current anon-user)',
        'state null',
      ]);
    });

    test('a callback that throws blocks the change: login-blocked', () async {
      final List<String> log = <String>[];
      auth.beforeAuthStateChanged(
        (AuthUser? next) => log.add('first'),
        onAbort: () => log.add('abort first'),
      );
      auth.beforeAuthStateChanged(
        (AuthUser? next) => log.add('second'),
        onAbort: () {
          log.add('abort second');
          throw StateError('ignored');
        },
      );
      final void Function() remove = auth.beforeAuthStateChanged(
        (AuthUser? next) => throw StateError('not allowed'),
        onAbort: () => log.add('abort third'),
      );
      await expectLater(
        auth.signInAnonymously(),
        throwsA(
          isA<FirebaseAuthException>()
              .having(
                (FirebaseAuthException e) => e.code,
                'code',
                'login-blocked',
              )
              .having(
                (FirebaseAuthException e) => e.message,
                'message',
                contains('not allowed'),
              ),
        ),
      );
      expect(auth.currentUser, isNull);
      expect(log, <String>['first', 'second', 'abort second', 'abort first']);
      expect(
        backend.storage.read('firebase_auth_providers_dart:$apiKey'),
        isNull,
      );

      remove();
      await auth.signInAnonymously();
      final void Function() block = auth.beforeAuthStateChanged(
        (AuthUser? next) => throw StateError('stay'),
      );
      await expectLater(auth.signOut(), throwsAuth('login-blocked'));
      expect(auth.uid, 'anon-user');
      block();
      await auth.signOut();
      expect(auth.uid, isNull);
    });

    test(
      'a session the backend ended signs out without the callbacks',
      () async {
        await auth.signInAnonymously();
        auth.beforeAuthStateChanged((AuthUser? next) => throw StateError('no'));
        backend.on('token', (_) => errorResponse('TOKEN_EXPIRED'));
        await expectLater(
          auth.getAccessToken(forceRefresh: true),
          throwsAuth('user-token-expired'),
        );
        expect(auth.uid, isNull);
      },
    );
  });

  group('updateCurrentUser', () {
    test('takes over the session of another instance', () async {
      final FirebaseUserAuth other = backend.create(
        storage: InMemoryAuthStorage(),
      );
      addTearDown(other.dispose);
      final UserCredential result = await other.signInWithEmailAndPassword(
        email: 'a@example.com',
        password: 'secret',
      );
      final List<String> tokens = <String>[];
      auth.onTokenChanged.listen((AuthTokenChange c) => tokens.add(c.token));
      final List<AuthUser?> states = <AuthUser?>[];
      auth.authStateChanges().listen(states.add);
      await pump();
      backend.requests.clear();

      await auth.updateCurrentUser(other.currentUser);
      expect(auth.currentUser, other.currentUser);
      expect(
        (await auth.getAccessToken(forceRefresh: false)).token,
        (await other.getAccessToken(forceRefresh: false)).token,
      );
      expect(backend.requests, isEmpty);
      expect(tokens, hasLength(1));
      expect(
        backend.storage.read('firebase_auth_providers_dart:$apiKey'),
        isNotNull,
      );
      await pump();
      expect(uids(states), <String?>[null, 'uid-of-a@example.com']);

      // The result of a sign-in works too; the two sessions are independent.
      await auth.signOut();
      await auth.updateCurrentUser(result);
      expect(auth.uid, 'uid-of-a@example.com');
      await other.signOut();
      expect(auth.uid, 'uid-of-a@example.com');

      await auth.updateCurrentUser(null);
      expect(auth.uid, isNull);
    });

    test('refuses a user of another API key or of nobody', () async {
      final FirebaseUserAuth other = FirebaseUserAuth(
        apiKey: 'another-key',
        httpClient: MockClient((http.Request request) {
          backend.requests.add(request);
          return backend.handler(request);
        }),
      );
      addTearDown(other.dispose);
      await other.signInAnonymously();
      await expectLater(
        auth.updateCurrentUser(other.currentUser),
        throwsAuth('invalid-user-token'),
      );
      await expectLater(
        auth.updateCurrentUser(const AuthUser(uid: 'made-up')),
        throwsAuth('invalid-user-token'),
      );
      expect(auth.uid, isNull);
    });

    test('runs the beforeAuthStateChanged callbacks', () async {
      final FirebaseUserAuth other = backend.create(
        storage: InMemoryAuthStorage(),
      );
      addTearDown(other.dispose);
      await other.signInAnonymously();
      auth.beforeAuthStateChanged((AuthUser? next) => throw StateError('no'));
      await expectLater(
        auth.updateCurrentUser(other.currentUser),
        throwsAuth('login-blocked'),
      );
      expect(auth.uid, isNull);
    });
  });
}

class _ControlledStorage implements AuthStorage {
  _ControlledStorage(this._read);

  final Future<String?> _read;

  @override
  Future<String?> read(String key) => _read;

  @override
  void write(String key, String? value) {}
}
