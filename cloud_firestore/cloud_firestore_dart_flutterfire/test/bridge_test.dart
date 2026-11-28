import 'dart:async';

import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_core/firebase_core.dart' as flutterfire;
import 'package:flutter_test/flutter_test.dart';

/// A user whose token fetches the test controls.
class FakeUser implements IdTokenUser {
  FakeUser(this.uid);

  @override
  final String uid;

  final List<bool> requests = <bool>[];
  Completer<String?>? pending;
  Object? error;
  int refreshes = 0;

  @override
  Future<String?> getIdToken({required bool forceRefresh}) {
    requests.add(forceRefresh);
    if (error != null) {
      return Future<String?>.error(error!);
    }
    if (pending != null) {
      return pending!.future;
    }
    if (forceRefresh) {
      refreshes++;
    }
    return Future<String?>.value('$uid-token-$refreshes');
  }
}

/// The plugin side: the current user and the idTokenChanges() stream.
class FakeAuth {
  FakeAuth([this.current]);

  FakeUser? current;
  final StreamController<IdTokenUser?> changes =
      StreamController<IdTokenUser?>.broadcast(sync: true);

  /// Like firebase_auth: currentUser changes first, the event follows.
  void switchTo(FakeUser? user, {bool emit = true}) {
    current = user;
    if (emit) {
      changes.add(user);
    }
  }

  FlutterFireAuthTokenProvider provider() =>
      FlutterFireAuthTokenProvider.fromSource(
        currentUser: () => current,
        idTokenChanges: changes.stream,
        userChangeTimeout: const Duration(milliseconds: 200),
      );
}

void main() {
  group('FlutterFireAuthTokenProvider', () {
    test(
      'notifies sign-in, user switch and sign-out, with uid updated first',
      () async {
        final FakeAuth auth = FakeAuth();
        final FlutterFireAuthTokenProvider provider = auth.provider();
        final List<String?> seen = <String?>[];
        final List<String> tokens = <String>[];
        provider.onTokenChanged.listen((AuthTokenChange result) {
          seen.add(provider.uid);
          tokens.add(result.token);
        });

        auth.changes.add(
          null,
        ); // the replay of the current state: not passed on
        auth.switchTo(FakeUser('alice'));
        auth.switchTo(FakeUser('bob'));
        auth.switchTo(null);
        auth.switchTo(null); // signed out already: not passed on

        expect(seen, <String?>['alice', 'bob', null]);
        expect(tokens, <String>[
          FlutterFireAuthTokenProvider.changedTokenMarker,
          FlutterFireAuthTokenProvider.changedTokenMarker,
          '',
        ]);
        await provider.dispose();
      },
    );

    test(
      'passes on a token refresh of the same user, but not the initial replay',
      () async {
        final FakeUser alice = FakeUser('alice');
        final FakeAuth auth = FakeAuth(alice);
        final FlutterFireAuthTokenProvider provider = auth.provider();
        final List<AuthTokenChange> events = <AuthTokenChange>[];
        provider.onTokenChanged.listen(events.add);

        auth.changes.add(alice); // replay
        expect(events, isEmpty);
        await provider.ready;
        auth.changes.add(alice); // refresh
        expect(events, hasLength(1));
        expect(provider.uid, 'alice');
        await provider.dispose();
      },
    );

    test('forwards forceRefresh and returns the ID token', () async {
      final FakeUser alice = FakeUser('alice');
      final FlutterFireAuthTokenProvider provider = FakeAuth(alice).provider();

      expect(
        (await provider.getAccessToken(forceRefresh: false)).token,
        'alice-token-0',
      );
      expect(
        (await provider.getAccessToken(forceRefresh: true)).token,
        'alice-token-1',
      );
      expect(alice.requests, <bool>[false, true]);
      await provider.dispose();
    });

    test('throws FirebaseNoSignedInUserException when signed out', () async {
      final FakeAuth auth = FakeAuth(FakeUser('alice'));
      final FlutterFireAuthTokenProvider provider = auth.provider();
      auth.switchTo(null);

      expect(provider.uid, isNull);
      await expectLater(
        provider.getAccessToken(forceRefresh: false),
        throwsA(isA<FirebaseNoSignedInUserException>()),
      );
      await provider.dispose();
    });

    test('passes on an error of the plugin', () async {
      final FakeUser alice = FakeUser('alice')
        ..error = StateError('network-request-failed');
      final FlutterFireAuthTokenProvider provider = FakeAuth(alice).provider();

      await expectLater(
        provider.getAccessToken(forceRefresh: true),
        throwsA(isA<StateError>()),
      );
      await provider.dispose();
    });

    test(
      'drops a token fetched for a user that was replaced meanwhile',
      () async {
        final FakeUser alice = FakeUser('alice')
          ..pending = Completer<String?>();
        final FakeAuth auth = FakeAuth(alice);
        final FlutterFireAuthTokenProvider provider = auth.provider();

        final Future<GetTokenResult> request = provider.getAccessToken(
          forceRefresh: false,
        );
        auth.switchTo(FakeUser('bob'));
        alice.pending!.complete('alice-token');

        expect((await request).token, 'bob-token-0');
        await provider.dispose();
      },
    );

    test(
      'waits for the event of a sign-in before handing out the new token',
      () async {
        final FakeAuth auth = FakeAuth(FakeUser('alice'));
        final FlutterFireAuthTokenProvider provider = auth.provider();
        final FakeUser bob = FakeUser('bob');

        // signInWith...() completed: currentUser is bob, the event is still on its way.
        auth.switchTo(bob, emit: false);
        expect(provider.uid, 'alice');
        final Future<GetTokenResult> request = provider.getAccessToken(
          forceRefresh: false,
        );
        final Future<void> settled = provider.waitForCurrentUser();
        auth.changes.add(bob);

        expect((await request).token, 'bob-token-0');
        await settled;
        expect(provider.uid, 'bob');
        await provider.dispose();
      },
    );

    test('times out when the plugin never reports its current user', () async {
      final FakeAuth auth = FakeAuth(FakeUser('alice'));
      final FlutterFireAuthTokenProvider provider = auth.provider();
      auth.switchTo(FakeUser('bob'), emit: false);

      await expectLater(
        provider.waitForCurrentUser(),
        throwsA(isA<TimeoutException>()),
      );
      await provider.dispose();
    });
  });

  group('FlutterFireAppCheckProvider', () {
    test('reports failures in the result instead of throwing', () async {
      final FlutterFireAppCheckProvider ok = FlutterFireAppCheckProvider(
        getToken: (bool forceRefresh) async => 'check-$forceRefresh',
        onTokenChange: const Stream<String?>.empty(),
      );
      expect((await ok.getToken(forceRefresh: true)).token, 'check-true');

      final FlutterFireAppCheckProvider failing = FlutterFireAppCheckProvider(
        getToken: (bool forceRefresh) async =>
            throw StateError('attestation failed'),
        onTokenChange: Stream<String?>.fromIterable(<String?>['a', null]),
      );
      final AppCheckTokenResult result = await failing.getToken(
        forceRefresh: false,
      );
      // A failure carries the placeholder token, which the services send (shared spec 5.2, 5.6).
      expect(result.token, AppCheckTokenResult.placeholderToken);
      expect(result.error, isA<StateError>());
      // Tokenless events are not successes, so they are not emitted.
      expect(
        await failing.onTokenChanged
            .map((AppCheckTokenResult r) => r.token)
            .toList(),
        <String>['a'],
      );
    });
  });

  group('options', () {
    const flutterfire.FirebaseOptions options = flutterfire.FirebaseOptions(
      apiKey: 'test-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      messagingSenderId: '1234567890',
      projectId: 'demo-bridge',
      storageBucket: 'demo-bridge.appspot.com',
      databaseURL: 'https://demo-bridge.firebaseio.com',
      authDomain: 'demo-bridge.firebaseapp.com',
    );

    tearDown(FirebaseApp.clearInstancesForTest);

    test('maps the FlutterFire options', () {
      expect(
        firebaseOptionsFromFlutterFire(options),
        const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: '1:1234567890:web:0123456789abcdef',
          projectId: 'demo-bridge',
          messagingSenderId: '1234567890',
          storageBucket: 'demo-bridge.appspot.com',
          databaseURL: 'https://demo-bridge.firebaseio.com',
          authDomain: 'demo-bridge.firebaseapp.com',
        ),
      );
    });

    test('dartAppFor creates the app once, with the token providers', () {
      final FlutterFireAuthTokenProvider auth = FakeAuth().provider();
      final FirebaseApp app = dartAppFor(
        '[DEFAULT]',
        options,
        authProvider: auth,
      );

      expect(identical(FirebaseApp.instance, app), isTrue);
      expect(identical(app.authProvider, auth), isTrue);
      expect(identical(dartAppFor('[DEFAULT]', options), app), isTrue);
      expect(
        () => dartAppFor(
          '[DEFAULT]',
          const flutterfire.FirebaseOptions(
            apiKey: 'other',
            appId: '1:1:web:1',
            messagingSenderId: '1',
            projectId: 'demo-other',
          ),
        ),
        throwsStateError,
      );
    });
  });
}
