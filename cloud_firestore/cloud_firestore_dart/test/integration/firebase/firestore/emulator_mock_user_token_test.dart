import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/emulator_credentials_provider.dart'
    show createMockUserToken;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/integration_test_util.dart';

import '../../../util/test_hygiene.dart';

/// The mockUserToken of the emulator settings against the emulator. The rules
/// of the test project allow everything, so these check that requests carrying
/// a valid token succeed and that a malformed token reaches the emulator (the
/// header itself is checked by
/// test/unit/firebase/firestore/auth/emulator_mock_user_token_test.dart).
void main() {
  checkTestsLeaveNothingBehind();

  Future<Firestore> instanceWith(Object mockUserToken) async {
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
          apiKey: 'key',
          applicationId: 'appId',
          projectId: IntegrationTestUtil.provider.projectId),
      dependencies: null,
      name: 'mockUserToken-${const Uuid().v4()}',
    );
    addTearDown(app.delete);
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: base
          .withEmulator(base.host, base.port, mockUserToken: mockUserToken)
          .copyWith(cacheSettings: const MemoryCacheSettings()),
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  Future<void> writeAndRead(Firestore firestore) async {
    final DocumentReference<Map<String, Object?>> doc =
        firestore.collection('mock-user-token').doc(const Uuid().v4());
    await doc.set(<String, Object?>{'a': 1});
    final DocumentSnapshot<Map<String, Object?>> snapshot =
        await doc.get(Source.server);
    expect(snapshot.data, <String, Object?>{'a': 1});
  }

  test('requests with a mock user token from claims succeed', () async {
    await writeAndRead(await instanceWith(<String, Object?>{
      'sub': 'alice',
      'email': 'alice@example.com',
    }));
  });

  test('requests with a mock user token string succeed', () async {
    // A string is sent as is: here an unsigned JWT like the JS SDK builds.
    await writeAndRead(await instanceWith(
        createMockUserToken(<String, Object?>{'sub': 'bob'})));
  });

  test('the emulator receives the token: a malformed one is rejected',
      () async {
    // The rules allow everything, so the only way to see that the emulator got the token is to send one it can't
    // parse. A transaction surfaces the error of the request (a listen or a write would retry).
    final Firestore firestore = await instanceWith('not-a-jwt');
    await expectLater(
        firestore.runTransaction((Transaction transaction) =>
            transaction.get(firestore.doc('mock-user-token/doc'))),
        throwsA(isA<FirestoreError>()
            .having((FirestoreError e) => e.code, 'code',
                FirestoreErrorCode.invalidArgument)
            .having((FirestoreError e) => e.message.toLowerCase(), 'message',
                contains('jwt'))));
  });
}
