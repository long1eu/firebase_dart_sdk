import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import 'clear_persistence_test.dart' show offlineSettings;

FirebaseApp _defaultApp() => FirebaseApp.withOptions(
  const FirebaseOptions(apiKey: 'key', appId: 'appId', projectId: 'projectId'),
);

void main() {
  test('without a default app it fails like FirebaseApp.instance', () {
    expect(() => FirebaseFirestore.instance, throwsStateError);
  });

  test('before instanceFor it names the call to make', () {
    final FirebaseApp app = _defaultApp();
    addTearDown(app.delete);
    expect(
      () => FirebaseFirestore.instance,
      throwsA(
        isA<StateError>()
            .having(
              (StateError e) => e.message,
              'message',
              contains('Firestore.instanceFor'),
            )
            .having(
              (StateError e) => e.message,
              'message',
              isNot(contains('getInstance')),
            ),
      ),
    );
  });

  test('returns the default database instance of the default app', () async {
    final FirebaseApp app = _defaultApp();
    addTearDown(app.delete);
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(firestore.terminate);

    expect(FirebaseFirestore.instance, same(firestore));

    // An instance of another database is not the default one.
    final FirebaseFirestore other = FirebaseFirestore.instanceFor(
      app: app,
      databaseId: 'other',
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(other.terminate);
    expect(FirebaseFirestore.instance, same(firestore));
  });

  test('a terminated default instance is no longer returned', () async {
    final FirebaseApp app = _defaultApp();
    addTearDown(app.delete);
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    await firestore.terminate();
    expect(() => FirebaseFirestore.instance, throwsStateError);
  });
}
