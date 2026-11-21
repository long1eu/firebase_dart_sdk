// What the test files share: the fake backend, the registration and new apps.

import 'dart:async';

import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart'
    show FlutterFireAppCheckProvider;
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

/// The App Check of each app name, as `firebase_app_check` would have it; an
/// app without one has no App Check.
final Map<String, FakeAppCheck> appChecks = <String, FakeAppCheck>{};

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
      // Chunks of 256 KiB: the task tests follow progress and pauses between chunks.
      maxUploadChunkSize: 256 * 1024,
      useDartCore: true,
      tokenProviderFor: (FirebaseApp app) {
        final String? token = tokens[app.name];
        return token == null ? null : FixedToken(token);
      },
      // Wired as the README shows for firebase_app_check.
      appCheckProviderFor: (FirebaseApp app) {
        final FakeAppCheck? appCheck = appChecks[app.name];
        if (appCheck == null) {
          return null;
        }
        return FlutterFireAppCheckProvider(
          getToken: appCheck.getToken,
          onTokenChange: appCheck.onTokenChange,
        );
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

/// The two members of `FirebaseAppCheck` that `FlutterFireAppCheckProvider`
/// takes: `getToken([bool? forceRefresh])` and `onTokenChange`.
class FakeAppCheck {
  /// The token `getToken` returns; null when there is none.
  String? token;

  /// What `getToken` throws instead, like a failed attestation.
  Exception? error;

  /// The `forceRefresh` of each `getToken` call.
  final List<bool> calls = <bool>[];

  final StreamController<String?> _changes =
      StreamController<String?>.broadcast();

  Future<String?> getToken([bool? forceRefresh]) async {
    calls.add(forceRefresh ?? false);
    final Exception? failure = error;
    if (failure != null) {
      throw failure;
    }
    return token;
  }

  Stream<String?> get onTokenChange => _changes.stream;

  /// A new token, as App Check refreshes it.
  void change(String? next) {
    token = next;
    _changes.add(next);
  }
}
