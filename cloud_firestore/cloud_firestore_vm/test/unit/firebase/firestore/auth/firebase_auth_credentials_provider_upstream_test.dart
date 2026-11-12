// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported from upstream FirebaseAuthCredentialsProviderTest (main). The
// Deferred / UnavailableDeferred / DelayedDeferred cases are skipped: the port
// takes the auth provider directly and has no deferred (lazily available)
// provider.

import 'dart:async';
import 'dart:convert';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:test/test.dart';

String _jwt(String id) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc(<String, String>{'alg': 'none'})}.${enc(<String, String>{
        'id': id
      })}.sig';
}

class _MockAuthProvider implements InternalTokenProvider {
  final StreamController<InternalTokenResult> tokenChanges =
      StreamController<InternalTokenResult>.broadcast();
  final List<bool> getAccessTokenCalls = <bool>[];

  /// Called for every getAccessToken; defaults to a completed result.
  Future<GetTokenResult> Function() onGetAccessToken =
      () async => GetTokenResult(_jwt('TestToken'));

  @override
  String? uid;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) {
    getAccessTokenCalls.add(forceRefresh);
    return onGetAccessToken();
  }

  @override
  Stream<InternalTokenResult> get onTokenChanged => tokenChanges.stream;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockAuthProvider auth;

  setUp(() => auth = _MockAuthProvider());
  tearDown(() => auth.tokenChanges.close());

  test('setChangeListenerShouldBeCalledWithUnauthenticatedIfProviderIsNotAvailable',
      skip: 'The port has no deferred auth provider (UnavailableDeferred)',
      () {});

  test('setChangeListenerShouldBeCalledWithUnauthenticatedIfUidIsNull',
      () async {
    auth.uid = null;
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    final List<User> users = <User>[];
    final StreamSubscription<User> sub = provider.onChange.listen(users.add);
    await _flush();
    await sub.cancel();

    expect(users, <User>[User.unauthenticated]);
  });

  test('setChangeListenerShouldBeCalledWithAuthenticatedUserIfUidIsNotNull',
      () async {
    auth.uid = 'TestUID';
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    final List<User> users = <User>[];
    final StreamSubscription<User> sub = provider.onChange.listen(users.add);
    await _flush();
    await sub.cancel();

    expect(users, <User>[const User('TestUID')]);
  });

  test(
      'setChangeListenerShouldBeCalledWithUnauthenticatedUserWhenProviderWithNullUidBecomesAvailable',
      skip: 'The port has no deferred auth provider (DelayedDeferred)', () {});

  test(
      'setChangeListenerShouldBeCalledWithAuthenticatedUserWhenProviderWithAuthenticatedUserBecomesAvailable',
      skip: 'The port has no deferred auth provider (DelayedDeferred)', () {});

  test('setChangeListenerShouldBeCalledWhenIdTokenChanges', () async {
    auth.uid = 'TestUID1';
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);
    // The provider registered its token listener at construction time.
    expect(auth.tokenChanges.hasListener, isTrue);

    final List<User> users = <User>[];
    final StreamSubscription<User> sub = provider.onChange.listen(users.add);
    await _flush();
    expect(users, <User>[const User('TestUID1')]);

    auth.uid = 'TestUID2';
    auth.tokenChanges.add(InternalTokenResult(_jwt('changed')));
    await _flush();
    await sub.cancel();

    expect(users, <User>[const User('TestUID1'), const User('TestUID2')]);
  });

  test('removeChangeListenerShouldStopNotifyingTheListener', () async {
    auth.uid = null;
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    final List<User> users = <User>[];
    final StreamSubscription<User> sub = provider.onChange.listen(users.add);
    await _flush();
    expect(users, <User>[User.unauthenticated]);

    await sub.cancel();
    auth.uid = 'TestUID';
    auth.tokenChanges.add(InternalTokenResult(_jwt('changed')));
    await _flush();

    expect(users, <User>[User.unauthenticated]);
  });

  test('removeChangeListenerShouldNotThrowIfProviderIsNotAvailable',
      skip: 'The port has no deferred auth provider (UnavailableDeferred)',
      () {});

  test('removeChangeListenerShouldUnregisterTheIdTokenListener', () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);
    expect(auth.tokenChanges.hasListener, isTrue);

    final StreamSubscription<User> sub = provider.onChange.listen((_) {});
    await sub.cancel();

    expect(auth.tokenChanges.hasListener, isFalse);
  });

  test('getTokenShouldReturnAFailedTaskIfProviderIsNotAvailable',
      skip: 'The port has no deferred auth provider (UnavailableDeferred)',
      () {});

  test('getTokenShouldReturnAFailedTaskIfGetAccessTokenFails', () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);
    final Exception getAccessTokenException = Exception();
    auth.onGetAccessToken = () => Future<GetTokenResult>.error(getAccessTokenException);

    await expectLater(
        provider.token, throwsA(same(getAccessTokenException)));
  });

  test('getTokenShouldReturnASuccessfulTaskIfGetAccessTokenSucceeds',
      () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);
    auth.onGetAccessToken = () async => GetTokenResult(_jwt('TestToken'));

    expect(await provider.token, _jwt('TestToken'));
  });

  test('getTokenShouldNotForceRefreshTheTokenIfInvalidateTokenIsNotCalled',
      () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    await provider.token;

    expect(auth.getAccessTokenCalls, <bool>[false]);
  });

  test('getTokenShouldRecursivelyCallItselfIfTheTokenCounterChanges',
      () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);
    final Completer<GetTokenResult> first = Completer<GetTokenResult>();

    // Order of operations:
    // 1. token calls getAccessToken(), which returns an uncompleted future.
    // 2. The token listener fires, which increments the token counter.
    // 3. The uncompleted future is completed.
    // 4. The continuation detects that the counter changed and calls token again.
    // 5. The second getAccessToken() returns "TestToken2".
    auth.onGetAccessToken = () => first.future;
    final Future<String?> result = provider.token;
    expect(auth.getAccessTokenCalls.length, 1);

    auth.tokenChanges.add(InternalTokenResult(_jwt('changed')));
    await _flush();
    auth.onGetAccessToken = () async => GetTokenResult(_jwt('TestToken2'));
    first.complete(GetTokenResult(_jwt('TestToken')));

    expect(await result, _jwt('TestToken2'));
    expect(auth.getAccessTokenCalls.length, 2);
  });

  test('invalidateTokenShouldCauseGetTokenToForceRefresh', () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    provider.invalidateToken();
    await provider.token;

    expect(auth.getAccessTokenCalls, <bool>[true]);
  });

  test(
      'invalidateTokenShouldOnlyForceRefreshOnTheImmediatelyFollowingGetTokenInvocation',
      () async {
    final FirebaseAuthCredentialsProvider provider =
        FirebaseAuthCredentialsProvider(auth);

    provider.invalidateToken();
    await provider.token;
    await provider.token;

    expect(auth.getAccessTokenCalls, <bool>[true, false]);
  });
}
