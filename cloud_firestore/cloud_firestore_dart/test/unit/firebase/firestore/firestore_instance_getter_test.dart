import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import 'clear_persistence_test.dart' show offlineSettings;

FirebaseApp _defaultApp() => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'key',
    applicationId: 'appId',
    projectId: 'projectId',
  ),
);

void main() {
  test('without a default app it fails like FirebaseApp.instance', () {
    expect(() => Firestore.instance, throwsStateError);
  });

  test('before instanceFor it names the call to make', () {
    final FirebaseApp app = _defaultApp();
    addTearDown(app.delete);
    expect(
      () => Firestore.instance,
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
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(firestore.terminate);

    expect(Firestore.instance, same(firestore));

    // An instance of another database is not the default one.
    final Firestore other = Firestore.instanceFor(
      app: app,
      database: 'other',
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(other.terminate);
    expect(Firestore.instance, same(firestore));
  });

  test('a terminated default instance is no longer returned', () async {
    final FirebaseApp app = _defaultApp();
    addTearDown(app.delete);
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    await firestore.terminate();
    expect(() => Firestore.instance, throwsStateError);
  });
}
