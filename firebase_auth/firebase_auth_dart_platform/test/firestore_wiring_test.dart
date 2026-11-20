// FlutterFireAuthTokenProvider of cloud_firestore_dart_flutterfire, the
// documented token provider of the Firestore platform package, driven by the
// official firebase_auth on top of this package (against a fake backend).

import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show InMemoryAuthStorage;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
);

void main() {
  final FakeBackend backend = FakeBackend();

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseAuthDart.use(
      httpClient: backend.client,
      storageFor: (FirebaseApp app) => InMemoryAuthStorage(),
    );
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'FlutterFireAuthTokenProvider follows the user of this package',
    () async {
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'wiring',
        options: _options,
      );
      final FirebaseAuth auth = FirebaseAuth.instanceFor(app: app);
      final FlutterFireAuthTokenProvider provider =
          FlutterFireAuthTokenProvider(auth);
      await provider.ready;
      expect(provider.uid, isNull);
      await expectLater(
        provider.getAccessToken(forceRefresh: false),
        throwsA(isA<dart_app.FirebaseNoSignedInUserException>()),
      );

      final List<String> changes = <String>[];
      provider.onTokenChanged.listen(
        (dart_app.AuthTokenChange change) => changes.add(change.token),
      );

      await auth.signInAnonymously();
      await provider.waitForCurrentUser();
      expect(provider.uid, 'anon-user');
      final dart_app.GetTokenResult token = await provider.getAccessToken(
        forceRefresh: false,
      );
      expect(token.token, await auth.currentUser!.getIdToken());
      expect(changes, isNotEmpty);

      await auth.signOut();
      await provider.waitForCurrentUser();
      expect(provider.uid, isNull);
      expect(changes.last, isEmpty);
      await provider.dispose();
    },
  );

  test('userAuthFor is a token provider for the same user', () async {
    final FirebaseApp app = await Firebase.initializeApp(
      name: 'direct',
      options: _options,
    );
    final FirebaseAuth auth = FirebaseAuth.instanceFor(app: app);
    await auth.signInAnonymously();
    final dart_app.AuthTokenProvider provider = FirebaseAuthDart.userAuthFor(
      app,
    );
    expect(provider.uid, auth.currentUser!.uid);
    expect(
      (await provider.getAccessToken(forceRefresh: false)).token,
      await auth.currentUser!.getIdToken(),
    );
  });
}
