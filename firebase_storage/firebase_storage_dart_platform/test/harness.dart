// What the test files share: the fake backend, the registration and new apps.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_dart_platform/firebase_storage_dart_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

const String bucket = 'demo-unit.appspot.com';

const FirebaseOptions options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
  storageBucket: bucket,
);

final FakeBackend backend = FakeBackend();

/// The tokens handed out per app name; an app without one sends no user.
final Map<String, String> tokens = <String, String>{};

int _apps = 0;

/// A new app, so that every test starts with fresh instances and settings.
Future<FirebaseApp> newApp({FirebaseOptions appOptions = options}) =>
    Firebase.initializeApp(name: 'app${_apps++}', options: appOptions);

/// Registers the package as an app on Linux would, against [backend].
void registerForTests() {
  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FirebaseStorageDart.use(
      httpClient: backend.client,
      useDartCore: true,
      tokenProviderFor: (FirebaseApp app) {
        final String? token = tokens[app.name];
        return token == null ? null : FixedToken(token);
      },
    );
  });
  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });
  setUp(backend.reset);
}

/// Throws a [FirebaseException] of `firebase_core` (not the client's) with
/// the plugin `firebase_storage` and [code].
Matcher throwsStorageCode(String code) => throwsA(isStorageCode(code));

Matcher isStorageCode(String code) => isA<FirebaseException>()
    .having((FirebaseException e) => e.plugin, 'plugin', 'firebase_storage')
    .having((FirebaseException e) => e.code, 'code', code)
    .having(
      (FirebaseException e) => e,
      'not the client exception',
      isNot(isA<dart_app.FirebaseException>()),
    );

/// A provider with one token.
class FixedToken extends dart_app.AuthTokenProvider {
  FixedToken(this.token);

  final String token;

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) async => dart_app.GetTokenResult(token);

  @override
  String? get uid => 'user';

  @override
  Stream<dart_app.AuthTokenChange> get onTokenChanged =>
      const Stream<dart_app.AuthTokenChange>.empty();
}
