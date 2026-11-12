import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../util/test_hygiene.dart';

void main() {
  final FirestoreSettings settings = FirestoreSettings()
      .withEmulator('127.0.0.1', 1)
      .copyWith(cacheSettings: const MemoryCacheSettings());

  FirebaseApp newApp(String name) => FirebaseApp.withOptions(
        const FirebaseOptions(
            apiKey: 'key', applicationId: 'appId', projectId: 'projectId'),
        dependencies: null,
        name: name,
      );

  test('a running instance is reported until it is terminated', () async {
    final FirebaseApp app = newApp('hygieneRunning');
    addTearDown(app.delete);
    final Firestore firestore =
        await Firestore.instanceFor(app: app, settings: settings);

    expect(runningFirestoreInstances(), <String>['hygieneRunning/(default)']);
    await expectLater(expectTestLeftNothingBehind(),
        throwsA(isA<TestFailure>()));
    // An instance created outside the registry is checked when it is passed.
    await expectLater(
        expectTestLeftNothingBehind(instances: <Firestore>[firestore]),
        throwsA(isA<TestFailure>()));

    await firestore.terminate();
    expect(runningFirestoreInstances(), isEmpty);
    await expectTestLeftNothingBehind(instances: <Firestore>[firestore]);
  });
}
