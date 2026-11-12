import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:test/test.dart';

String _jwt(String id) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc(<String, String>{'alg': 'none'})}.${enc(<String, String>{
        'id': id
      })}.sig';
}

class _FakeAuth extends InternalTokenProvider {
  final List<bool> forceRefreshArgs = <bool>[];
  int calls = 0;

  /// Called while the first request is outstanding.
  void Function()? duringFirstCall;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    forceRefreshArgs.add(forceRefresh);
    final int call = ++calls;
    await Future<void>.delayed(Duration.zero);
    if (call == 1) {
      duringFirstCall?.call();
    }
    return GetTokenResult(_jwt('token$call'));
  }

  @override
  String? get uid => 'uid';

  @override
  Stream<InternalTokenResult> get onTokenChanged =>
      const Stream<InternalTokenResult>.empty();
}

void main() {
  test('getToken is retried when the token changes while it is outstanding',
      () async {
    final _FakeAuth auth = _FakeAuth();
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);
    auth.duringFirstCall =
        () => provider.tokenObserver(InternalTokenResult(_jwt('changed')));

    final String? token = await provider.token;

    expect(auth.calls, 2);
    expect(token, _jwt('token2'));
  });

  test('getToken returns the token when nothing changed', () async {
    final _FakeAuth auth = _FakeAuth();
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    expect(await provider.token, _jwt('token1'));
    expect(auth.calls, 1);
  });

  test('invalidateToken forces a refresh on the next request only', () async {
    final _FakeAuth auth = _FakeAuth();
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    provider.invalidateToken();
    await provider.token;
    await provider.token;

    expect(auth.forceRefreshArgs, <bool>[true, false]);
  });

  group('auth state changes after the provider was created', () {
    late _SignInAuth auth;
    late FirebaseAuthCredentialsProvider provider;

    setUp(() {
      auth = _SignInAuth();
      provider = FirebaseAuthCredentialsProvider(auth);
    });

    tearDown(() => auth.tokenChanges.close());

    test('the initial user is replayed to the first listener', () async {
      expect(await provider.onChange.first, User.unauthenticated);
    });

    test('sign-in and sign-out reach the listener', () async {
      final List<User> users = <User>[];
      final StreamSubscription<User> sub = provider.onChange.listen(users.add);

      auth.uid = 'u1';
      auth.tokenChanges.add(InternalTokenResult(_jwt('t1')));
      await Future<void>.delayed(Duration.zero);
      auth.uid = null;
      auth.tokenChanges.add(InternalTokenResult(_jwt('t2')));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(users,
          <User>[User.unauthenticated, const User('u1'), User.unauthenticated]);
    });

    test('a change before the first listener is not lost', () async {
      auth.uid = 'u1';
      auth.tokenChanges.add(InternalTokenResult(_jwt('t1')));
      await Future<void>.delayed(Duration.zero);

      expect(await provider.onChange.first, const User('u1'));
    });

    test('token() returns a freshly fetched token after a change', () async {
      expect(await provider.token, _jwt('uid-none'));

      auth.uid = 'u1';
      auth.tokenChanges.add(InternalTokenResult(_jwt('t1')));
      await Future<void>.delayed(Duration.zero);

      expect(await provider.token, _jwt('uid-u1'));
    });

    test('cancelling the listener unsubscribes from the auth provider',
        () async {
      expect(auth.tokenChanges.hasListener, isTrue);

      final StreamSubscription<User> sub = provider.onChange.listen((_) {});
      expect(auth.tokenChanges.hasListener, isTrue);
      await sub.cancel();

      expect(auth.tokenChanges.hasListener, isFalse);
    });

    test('a later listener gets updates again after the first one left',
        () async {
      await provider.onChange.first;
      expect(auth.tokenChanges.hasListener, isFalse);

      final List<User> users = <User>[];
      final StreamSubscription<User> sub = provider.onChange.listen(users.add);
      expect(auth.tokenChanges.hasListener, isTrue);

      auth.uid = 'u2';
      auth.tokenChanges.add(InternalTokenResult(_jwt('t2')));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(users.last, const User('u2'));
    });

    test('a token stream error does not escape as an unhandled error',
        () async {
      final StreamSubscription<User> sub = provider.onChange.listen((_) {});
      auth.tokenChanges.addError(StateError('boom'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
    });
  });
}

/// An auth provider whose user can change after the credentials provider was
/// created.
class _SignInAuth extends InternalTokenProvider {
  final StreamController<InternalTokenResult> tokenChanges =
      StreamController<InternalTokenResult>.broadcast();

  @override
  String? uid;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async =>
      GetTokenResult(_jwt('uid-${uid ?? 'none'}'));

  @override
  Stream<InternalTokenResult> get onTokenChanged => tokenChanges.stream;
}
