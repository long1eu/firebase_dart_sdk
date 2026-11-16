import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

FirebaseApp newApp(String name) => FirebaseApp.withOptions(
      const FirebaseOptions(
          apiKey: 'key', appId: 'appId', projectId: 'projectId'),
      dependencies: null,
      name: name,
    );

void main() {
  checkTestsLeaveNothingBehind();

  test('instanceFor returns the cached instance per app and database',
      () async {
    final FirebaseApp app = newApp('cacheTestApp');
    final FirebaseApp other = newApp('cacheTestOtherApp');
    addTearDown(() async {
      await app.delete();
      await other.delete();
    });

    final FirebaseFirestore first = FirebaseFirestore.instanceFor(app: app);
    expect(identical(FirebaseFirestore.instanceFor(app: app), first), isTrue);
    expect(first.app, same(app));

    // Repeated calls return the same instance.
    final List<FirebaseFirestore> both = <FirebaseFirestore>[
      FirebaseFirestore.instanceFor(app: other),
      FirebaseFirestore.instanceFor(app: other),
    ];
    expect(identical(both[0], both[1]), isTrue);
    expect(identical(both[0], first), isFalse);

    final FirebaseFirestore named = FirebaseFirestore.instanceFor(app: app, databaseId: 'db2');
    expect(identical(named, first), isFalse);
    expect(identical(FirebaseFirestore.instanceFor(app: app, databaseId: 'db2'), named),
        isTrue);
  });

  test('shutdown releases the instance', () async {
    final FirebaseApp app = newApp('cacheTestShutdownApp');
    addTearDown(app.delete);

    final FirebaseFirestore first = FirebaseFirestore.instanceFor(app: app);
    await first.terminate();
    final FirebaseFirestore second = FirebaseFirestore.instanceFor(app: app);
    expect(identical(second, first), isFalse);
    await second.terminate();
  });

  test('deleting the app shuts its instances down', () async {
    final FirebaseApp app = newApp('cacheTestDeleteApp');
    final FirebaseFirestore first = FirebaseFirestore.instanceFor(app: app);
    await app.delete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(() => first.collection('a').get(), throwsA(anything));
  });
}
