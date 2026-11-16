import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../util/test_hygiene.dart';

void main() {
  final Settings settings = Settings()
      .withEmulator('127.0.0.1', 1)
      .copyWith(cacheSettings: const MemoryCacheSettings());

  FirebaseApp newApp(String name) => FirebaseApp.withOptions(
        const FirebaseOptions(
            apiKey: 'key', appId: 'appId', projectId: 'projectId'),
        dependencies: null,
        name: name,
      );

  test('a running instance is reported until it is terminated', () async {
    final FirebaseApp app = newApp('hygieneRunning');
    addTearDown(app.delete);
    final FirebaseFirestore firestore =
        FirebaseFirestore.instanceFor(app: app, settings: settings);

    expect(runningFirestoreInstances(), <String>['hygieneRunning/(default)']);
    await expectLater(expectTestLeftNothingBehind(),
        throwsA(isA<TestFailure>()));
    // An instance created outside the registry is checked when it is passed.
    await expectLater(
        expectTestLeftNothingBehind(instances: <FirebaseFirestore>[firestore]),
        throwsA(isA<TestFailure>()));

    await firestore.terminate();
    expect(runningFirestoreInstances(), isEmpty);
    await expectTestLeftNothingBehind(instances: <FirebaseFirestore>[firestore]);
  });
}
