// A helper for Flutter integration tests (integration_test/) that run on a device: each test gets a fresh user,
// signs the app in as that user with a custom token, runs under the real security rules, and deletes the user.
// Plain Dart, so it compiles here; copy it into the integration_test/ folder of your app. The README shows the
// test that uses it.
//
// Where the credentials come from, at build time of the TEST app only:
//
//     # Emulator (no key at all):
//     flutter test integration_test --dart-define=FIREBASE_AUTH_EMULATOR_HOST=10.0.2.2:9099
//     # A real test project: the key file, base64, from a CI secret. Never in a release build.
//     flutter test integration_test --dart-define=ADMIN_SERVICE_ACCOUNT_B64="$(base64 < key.json | tr -d '\n')"
//
// A --dart-define value is compiled into the test binary. That is acceptable for a throwaway test build on a CI
// device; it is why the key must never be passed to `flutter build` of an app you ship, nor kept in assets/.
// Use a separate test project and a service account that has only roles/firebaseauth.admin there.

// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:firebase_admin_dart/auth.dart';

/// The users a test run created, so that they can be deleted in `tearDownAll`.
class TestUsers {
  TestUsers._(this.app);

  /// The admin app built from the `--dart-define` values, or null when none is given (skip the tests then).
  static TestUsers? fromEnvironment({required String projectId}) {
    const String emulator = String.fromEnvironment(
      'FIREBASE_AUTH_EMULATOR_HOST',
    );
    const String key = String.fromEnvironment('ADMIN_SERVICE_ACCOUNT_B64');
    if (emulator.isNotEmpty) {
      return TestUsers._(
        FirebaseAdminApp.emulator(
          projectId: projectId,
          authEmulatorHost: emulator,
        ),
      );
    }
    if (key.isNotEmpty) {
      return TestUsers._(
        FirebaseAdminApp(
          projectId: projectId,
          credential: AdminCredential.serviceAccount(
            utf8.decode(base64.decode(key)),
          ),
        ),
      );
    }
    return null;
  }

  /// The admin app.
  final FirebaseAdminApp app;

  final List<String> _created = <String>[];

  /// Creates a user with [claims] and returns a custom token for it: pass it to `signInWithCustomToken` of
  /// the client the app uses (FlutterFire's `FirebaseAuth` or `FirebaseUserAuth`).
  Future<({String uid, String customToken})> create({
    Map<String, Object?> claims = const <String, Object?>{},
  }) async {
    final AdminUser user = await app.auth().createUser(customClaims: claims);
    _created.add(user.uid);
    return (
      uid: user.uid,
      customToken: await app.auth().createCustomToken(user.uid),
    );
  }

  /// Deletes every user [create] made, and closes the app.
  Future<void> deleteAll() async {
    final DeleteUsersResult result = await app.auth().deleteUsers(_created);
    if (result.failureCount > 0) {
      print(
        'Could not delete ${result.failureCount} test users: ${result.errors}',
      );
    }
    _created.clear();
    await app.close();
  }
}

Future<void> main() async {
  final TestUsers? users = TestUsers.fromEnvironment(projectId: 'demo-test');
  print(
    users == null
        ? 'no credentials given (see the top of this file)'
        : 'ready: ${users.app}',
  );
}
