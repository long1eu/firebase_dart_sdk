import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'key',
  appId: '1:1234567890:dart:test',
  projectId: 'project',
);

void main() {
  tearDown(() async {
    for (final FirebaseApp app in Firebase.apps) {
      await app.delete();
    }
  });

  group('Firebase.initializeApp', () {
    test('creates the default app, which Firebase.app returns', () async {
      final FirebaseApp app = await Firebase.initializeApp(options: _options);
      expect(app.name, defaultFirebaseAppName);
      expect(Firebase.app(), same(app));
      expect(FirebaseApp.instance, same(app));
      expect(Firebase.apps, <FirebaseApp>[app]);
    });

    test('returns the existing app for the same options or none', () async {
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'named',
        options: _options,
      );
      expect(
        await Firebase.initializeApp(name: 'named', options: _options),
        same(app),
      );
      expect(await Firebase.initializeApp(name: 'named'), same(app));
    });

    test('rejects other options for an existing name', () async {
      await Firebase.initializeApp(options: _options);
      await expectLater(
        Firebase.initializeApp(options: _options.copyWith(projectId: 'other')),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException e) => e.code,
            'code',
            'duplicate-app',
          ),
        ),
      );
    });

    test('needs options for a new app', () async {
      await expectLater(
        Firebase.initializeApp(name: 'new'),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException e) => e.code,
            'code',
            'no-options',
          ),
        ),
      );
    });
  });

  group('FirebaseOptions', () {
    test('a JSON round trip keeps every value', () {
      const FirebaseOptions options = FirebaseOptions(
        apiKey: 'key',
        appId: '1:1234567890:dart:test',
        messagingSenderId: '1234567890',
        projectId: 'project',
        authDomain: 'project.firebaseapp.com',
        databaseURL: 'https://project.firebaseio.com',
        storageBucket: 'project.appspot.com',
        measurementId: 'G-1',
        trackingId: 'UA-1',
        deepLinkURLScheme: 'scheme',
        androidClientId: 'android',
        iosClientId: 'ios',
        iosBundleId: 'bundle',
        appGroupId: 'group',
        dataCollectionEnabled: false,
      );
      expect(FirebaseOptions.fromJson(options.toJson()), options);
    });

    test('copyWith replaces only the given values', () {
      final FirebaseOptions copy = _options.copyWith(projectId: 'other');
      expect(copy.projectId, 'other');
      expect(copy.appId, _options.appId);
      expect(copy.apiKey, _options.apiKey);
    });
  });

  test('FirebaseException is an Exception with the FlutterFire format', () {
    const FirebaseException e = FirebaseException(
      plugin: 'core',
      code: 'no-app',
      message: 'No app.',
    );
    expect(e, isA<Exception>());
    expect(e.toString(), '[core/no-app] No app.');
    expect(const FirebaseException(plugin: 'core').code, 'unknown');
  });
}
