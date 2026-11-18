// What a call of the previous user may do when it finishes after another user signed in: nothing. Its tokens and
// its data never reach the new session or the storage.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';

const String storageKey = 'firebase_auth_providers_dart:$apiKey';
const String uidB = 'uid-of-b@example.com';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  /// Requests that wait until their completer is completed, by a test of the request.
  late Map<bool Function(http.Request), Completer<void>> held;

  setUp(() async {
    backend = FakeBackend();
    held = <bool Function(http.Request), Completer<void>>{};
    backend.handler = (http.Request request) async {
      for (final MapEntry<bool Function(http.Request), Completer<void>> e
          in held.entries) {
        if (e.key(request)) {
          await e.value.future;
        }
      }
      return backend.answer(request);
    };
    auth = backend.create();
    addTearDown(auth.dispose);
    // User A.
    await auth.signInAnonymously();
    expect(auth.uid, 'anon-user');
  });

  Completer<void> hold(bool Function(http.Request) match) =>
      held[match] = Completer<void>();

  bool method(http.Request request, String name) =>
      request.url.pathSegments.last == name;

  Future<void> expectSessionOfB() async {
    expect(auth.uid, uidB);
    final Map<String, Object?> stored =
        jsonDecode(backend.storage.read(storageKey)!) as Map<String, Object?>;
    final String text = jsonEncode(stored);
    expect(text, contains('refresh:$uidB'));
    expect(text, isNot(contains('anon-user')));
    final GetTokenResult token = await auth.getAccessToken(forceRefresh: false);
    expect(token.claims['user_id'], uidB);
    // And the refresh token in use is B's.
    backend.requests.clear();
    await auth.getAccessToken(forceRefresh: true);
    expect(
      backend.requests.single.bodyFields['refresh_token'],
      'refresh:$uidB',
    );
  }

  test(
    'a refresh of A that starts during the sign-in of B and ends after it',
    () async {
      final Completer<void> signIn = hold(
        (http.Request r) => method(r, 'accounts:signInWithPassword'),
      );
      final Completer<void> refresh = hold(
        (http.Request r) =>
            method(r, 'token') &&
            r.bodyFields['refresh_token'] == 'refresh:anon-user',
      );
      final List<String> tokenUids = <String>[];
      final StreamSubscription<AuthTokenChange> sub = auth.onTokenChanged
          .listen((AuthTokenChange change) {
            final String token = change.token;
            if (token.isNotEmpty) {
              tokenUids.add(GetTokenResult(token).claims['user_id']! as String);
            }
          });
      addTearDown(sub.cancel);

      final Future<UserCredential> signingIn = auth.signInWithEmailAndPassword(
        email: 'b@example.com',
        password: 'secret',
      );
      await pump();
      // A is still the user: the refresh is A's.
      final Future<GetTokenResult> refreshing = auth.getAccessToken(
        forceRefresh: true,
      );
      // Not awaited yet: it may fail or give B's token, but never install A's.
      unawaited(refreshing.then((_) {}, onError: (Object _) {}));
      await pump();
      expect(
        backend.requests.where((http.Request r) => method(r, 'token')),
        hasLength(1),
      );

      signIn.complete();
      expect((await signingIn).uid, uidB);
      tokenUids.clear();

      refresh.complete();
      await refreshing.then((_) {}, onError: (Object _) {});
      await pump();

      expect(tokenUids, everyElement(uidB));
      await expectSessionOfB();
    },
  );

  test(
    'an updateProfile of A that starts during the sign-in of B and ends after it',
    () async {
      final Completer<void> signIn = hold(
        (http.Request r) => method(r, 'accounts:signInWithPassword'),
      );
      final Completer<void> update = hold(
        (http.Request r) => method(r, 'accounts:update'),
      );
      backend.on(
        'accounts:update',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'localId': 'anon-user',
          'displayName': 'name of A',
          ...backend.tokensFor('anon-user', provider: 'anonymous'),
        }),
      );

      final Future<UserCredential> signingIn = auth.signInWithEmailAndPassword(
        email: 'b@example.com',
        password: 'secret',
      );
      await pump();
      final Future<void> updating = auth.updateProfile(
        displayName: 'name of A',
      );
      unawaited(updating.then((_) {}, onError: (Object _) {}));
      await pump();
      expect(backend.methods, contains('accounts:update'));

      signIn.complete();
      expect((await signingIn).uid, uidB);

      update.complete();
      await updating.then((_) {}, onError: (Object _) {});
      await pump();

      expect(auth.currentUser?.displayName, isNot('name of A'));
      await expectSessionOfB();
    },
  );

  test(
    'a sign-in that fails does not cancel a call of the signed-in user',
    () async {
      final Completer<void> update = hold(
        (http.Request r) => method(r, 'accounts:update'),
      );
      backend.on(
        'accounts:update',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'localId': 'anon-user',
          'displayName': 'name of A',
          ...backend.tokensFor('anon-user', provider: 'anonymous'),
        }),
      );
      backend.on(
        'accounts:signInWithPassword',
        (Map<String, Object?> body) => errorResponse('INVALID_PASSWORD'),
      );
      final Future<void> updating = auth.updateProfile(
        displayName: 'name of A',
      );
      await pump();
      expect(backend.methods, contains('accounts:update'));

      await expectLater(
        auth.signInWithEmailAndPassword(
          email: 'b@example.com',
          password: 'wrong',
        ),
        throwsAuth('wrong-password'),
      );
      update.complete();
      await updating;
      expect(auth.uid, 'anon-user');
      expect(auth.currentUser?.displayName, 'name of A');
    },
  );
}
