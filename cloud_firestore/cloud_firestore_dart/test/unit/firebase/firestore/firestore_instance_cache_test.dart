import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

FirebaseApp newApp(String name) => FirebaseApp.withOptions(
      const FirebaseOptions(
          apiKey: 'key', applicationId: 'appId', projectId: 'projectId'),
      dependencies: null,
      name: name,
    );

void main() {
  checkTestsLeaveNothingBehind();

  test('getInstance returns the cached instance per app and database',
      () async {
    final FirebaseApp app = newApp('cacheTestApp');
    final FirebaseApp other = newApp('cacheTestOtherApp');
    addTearDown(() {
      app.delete();
      other.delete();
    });

    // ignore: deprecated_member_use_from_same_package
    final Firestore first = Firestore.getInstance(app);
    expect(identical(Firestore.getInstance(app), first), isTrue);
    expect(first.app, same(app));
    expect(first.app, same(first.firebaseApp));

    // Repeated calls return the same instance.
    final List<Firestore> both = <Firestore>[
      Firestore.getInstance(other),
      Firestore.getInstance(other),
    ];
    expect(identical(both[0], both[1]), isTrue);
    expect(identical(both[0], first), isFalse);

    final Firestore named = Firestore.getInstance(app, database: 'db2');
    expect(identical(named, first), isFalse);
    expect(identical(Firestore.getInstance(app, database: 'db2'), named),
        isTrue);
  });

  test('shutdown releases the instance', () async {
    final FirebaseApp app = newApp('cacheTestShutdownApp');
    addTearDown(app.delete);

    final Firestore first = Firestore.getInstance(app);
    await first.shutdown();
    final Firestore second = Firestore.getInstance(app);
    expect(identical(second, first), isFalse);
    await second.shutdown();
  });

  test('deleting the app shuts its instances down', () async {
    final FirebaseApp app = newApp('cacheTestDeleteApp');
    final Firestore first = Firestore.getInstance(app);
    app.delete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(() => first.collection('a').get(), throwsA(anything));
  });
}
