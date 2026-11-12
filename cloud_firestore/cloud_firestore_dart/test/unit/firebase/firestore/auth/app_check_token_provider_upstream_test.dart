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

// Ported from upstream FirebaseAppCheckTokenProviderTest (main). The cases
// that need a Deferred provider are adapted to the port's nullable
// interop provider.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

class _MockAppCheck implements InternalAppCheckTokenProvider {
  final StreamController<AppCheckTokenResult> changes =
      StreamController<AppCheckTokenResult>.broadcast();
  final List<bool> getTokenCalls = <bool>[];
  Future<AppCheckTokenResult> Function() onGetToken =
      () async => const AppCheckTokenResult('TestToken');

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) {
    getTokenCalls.add(forceRefresh);
    return onGetToken();
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => changes.stream;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockAppCheck interop;

  setUp(() => interop = _MockAppCheck());
  tearDown(() => interop.changes.close());

  test('setChangeListenerShouldBeCalledWhenIdTokenChanges', () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);
    String? receivedToken;
    final StreamSubscription<String> sub =
        provider.onChange.listen((String t) => receivedToken = t);

    interop.changes.add(const AppCheckTokenResult('TestToken'));
    await _flush();
    expect(receivedToken, 'TestToken');

    interop.changes.add(const AppCheckTokenResult('NewTestToken'));
    await _flush();
    expect(receivedToken, 'NewTestToken');

    await sub.cancel();
    await provider.close();
  });

  test('removeChangeListenerShouldStopNotifyingTheListener', () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);
    final StreamSubscription<String> sub =
        provider.onChange.listen((String _) {});
    expect(interop.changes.hasListener, isTrue);

    await sub.cancel();
    await provider.close();

    expect(interop.changes.hasListener, isFalse);
  });

  test('removeChangeListenerShouldNotThrowIfProviderIsNotAvailable', () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(null);
    await provider.close();
  });

  test('removeChangeListenerShouldUnregisterTheIdTokenListener', () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);
    expect(interop.changes.hasListener, isTrue);

    await provider.close();

    expect(interop.changes.hasListener, isFalse);
  });

  test('getTokenShouldReturnAFailedTaskIfProviderIsNotAvailable', () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(null);

    await expectLater(
        provider.token, throwsA(isA<FirebaseApiNotAvailableError>()));
  });

  test('getTokenShouldReturnAFailedTaskIfAppCheckGetTokenFails', () async {
    final Exception getTokenException = Exception();
    interop.onGetToken = () => Future<AppCheckTokenResult>.error(getTokenException);
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);

    await expectLater(provider.token, throwsA(same(getTokenException)));
    await provider.close();
  });

  test('getTokenShouldReturnASuccessfulTaskIfAppCheckGetTokenSucceeds',
      () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);

    expect(await provider.token, 'TestToken');
    await provider.close();
  });

  test('getTokenShouldNotForceRefreshTheTokenIfInvalidateTokenIsNotCalled',
      () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);

    await provider.token;

    expect(interop.getTokenCalls, <bool>[false]);
    await provider.close();
  });

  test('invalidateTokenShouldCauseGetTokenToForceRefresh', () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);

    provider.invalidateToken();
    await provider.token;

    expect(interop.getTokenCalls, <bool>[true]);
    await provider.close();
  });

  test(
      'invalidateTokenShouldOnlyForceRefreshOnTheImmediatelyFollowingGetTokenInvocation',
      () async {
    final AppCheckTokenProvider provider = AppCheckTokenProvider(interop);

    provider.invalidateToken();
    await provider.token;
    await provider.token;

    expect(interop.getTokenCalls, <bool>[true, false]);
    await provider.close();
  });
}
