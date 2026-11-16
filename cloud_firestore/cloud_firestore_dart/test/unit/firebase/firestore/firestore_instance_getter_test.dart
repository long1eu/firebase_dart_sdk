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

  test(
    'before instanceFor it creates the instance, like FlutterFire',
    () async {
      final FirebaseApp app = _defaultApp();
      addTearDown(app.delete);
      final FirebaseFirestore created = FirebaseFirestore.instance;
      addTearDown(created.terminate);
      expect(created.app, same(app));
      expect(created.databaseId, '(default)');
      expect(FirebaseFirestore.instanceFor(app: app), same(created));
      expect(FirebaseFirestore.instance, same(created));
    },
  );

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

  test('after terminate a new default instance is created', () async {
    final FirebaseApp app = _defaultApp();
    addTearDown(app.delete);
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    await firestore.terminate();
    final FirebaseFirestore next = FirebaseFirestore.instance;
    addTearDown(next.terminate);
    expect(next, isNot(same(firestore)));
  });
}
