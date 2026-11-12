import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';

/// Emits two users back to back, the second one while the client is still
/// initializing.
class _TwoUsersCredentialsProvider extends CredentialsProvider {
  @override
  Future<String?> get token => Future<String?>.value(null);

  @override
  void invalidateToken() {}

  @override
  Stream<User> get onChange =>
      Stream<User>.fromIterable(
          <User>[const User('first'), const User('second')]);
}

void main() {
  test('credential change that arrives before initialization finished',
      () async {
    final List<Object> uncaught = <Object>[];
    FirestoreClient? client;
    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);

    await runZonedGuarded(() async {
      client = await FirestoreClient.initialize(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        FirestoreSettings(persistenceEnabled: false),
        _TwoUsersCredentialsProvider(),
        null,
        onNetworkConnected,
        TaskScheduler(''),
      );
      // Give the queued credential change time to run.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, (Object error, StackTrace stackTrace) => uncaught.add(error));

    expect(uncaught, isEmpty);
    await client?.shutdown();
    await onNetworkConnected.close();
  });

  test('sign-in after startup reaches the client, shutdown unsubscribes',
      () async {
    final List<Object> uncaught = <Object>[];
    final _Auth auth = _Auth();
    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);

    await runZonedGuarded(() async {
      final FirestoreClient client = await FirestoreClient.initialize(
        IntegrationTestUtil.testEnvDatabaseInfo(),
        FirestoreSettings(persistenceEnabled: false),
        FirebaseAuthCredentialsProvider(auth),
        null,
        onNetworkConnected,
        TaskScheduler(''),
      );
      expect(auth.tokenChanges.hasListener, isTrue);

      auth.uid = 'signed-in';
      auth.tokenChanges.add(const InternalTokenResult('token'));
      // Give the queued credential change time to run.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await client.shutdown();
      expect(auth.tokenChanges.hasListener, isFalse);
    }, (Object error, StackTrace stackTrace) => uncaught.add(error));

    expect(uncaught, isEmpty);
    await auth.tokenChanges.close();
    await onNetworkConnected.close();
  });
}

class _Auth extends InternalTokenProvider {
  final StreamController<InternalTokenResult> tokenChanges =
      StreamController<InternalTokenResult>.broadcast();

  @override
  String? uid;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) =>
      throw UnimplementedError();

  @override
  Stream<InternalTokenResult> get onTokenChanged => tokenChanges.stream;
}
