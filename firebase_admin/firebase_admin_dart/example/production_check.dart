// A check against a REAL Firebase project, for the owner to run by hand. Nothing in the test suite runs it.
//
//     GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json \
//     FIREBASE_WEB_API_KEY=<the Web API key of the same project> \
//     dart run example/production_check.dart
//
// Optional: ADMIN_CHECK_SIGN_BLOB=1 also mints a token through the IAM Credentials API (signBlob) with
// Application Default Credentials, signing as the key's service account. That needs the IAM Service Account
// Credentials API enabled and the role Service Account Token Creator for that account on itself.
//
// What it does: creates one user with a random uid, mints a custom token with claims whose JSON forces `+` and
// `/` in standard base64 (so a wrong alphabet would fail), signs in with firebase_auth_providers_dart, verifies
// the ID token (signature, claims, and checkRevoked), sets and reads custom claims, revokes the sessions and
// checks that the verifier sees it, and deletes the user in `finally`. It prints PASS or FAIL, and never a
// token or a key.
//
// The service account needs the role Firebase Authentication Admin (roles/firebaseauth.admin).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_admin_dart/adc.dart';
import 'package:firebase_admin_dart/auth.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final String? keyPath =
      Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
  final String? apiKey = Platform.environment['FIREBASE_WEB_API_KEY'];
  if (keyPath == null || apiKey == null) {
    print(
      'Set GOOGLE_APPLICATION_CREDENTIALS and FIREBASE_WEB_API_KEY (see the top of this file).',
    );
    exitCode = 2;
    return;
  }
  if (Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] != null) {
    print(
      'FIREBASE_AUTH_EMULATOR_HOST is set; this check is for a real project. Unset it.',
    );
    exitCode = 2;
    return;
  }

  final Map<String, Object?> key =
      jsonDecode(File(keyPath).readAsStringSync()) as Map<String, Object?>;
  final String projectId = key['project_id']! as String;
  final FirebaseAdminApp app = FirebaseAdminApp(
    projectId: projectId,
    credential: AdminCredential.serviceAccount(key),
  );
  final FirebaseAuthAdmin admin = app.auth();
  final FirebaseUserAuth client = FirebaseUserAuth(apiKey: apiKey);

  final Random random = Random.secure();
  final String uid =
      'admin-check-${List<String>.generate(12, (_) => random.nextInt(36).toRadixString(36)).join()}';
  // '???' encodes to 'Pz8/' and '~~~' to 'fn5+' in standard base64: the token holds both.
  final Map<String, Object?> claims = <String, Object?>{
    'check': '???~~~>>>',
    'role': 'tester',
  };
  if (!base64
      .encode(utf8.encode(jsonEncode(<String, Object?>{'claims': claims})))
      .contains(RegExp('[+/]'))) {
    print('FAIL: the claims do not force + or / (a bug of this check)');
    exitCode = 1;
    return;
  }

  final List<String> passed = <String>[];
  void step(String name) {
    passed.add(name);
    print('ok   $name');
  }

  bool created = false;
  try {
    final AdminUser user = await admin.createUser(
      uid: uid,
      displayName: 'admin check',
    );
    created = true;
    if (user.uid != uid) {
      throw StateError('createUser returned another uid');
    }
    step('createUser');

    final String token = await admin.createCustomToken(uid, claims: claims);
    if (token.split('.').any((String part) => part.contains(RegExp('[+/=]')))) {
      throw StateError('the custom token is not base64url');
    }
    await client.signInWithCustomToken(token);
    step('createCustomToken (local RS256) + signInWithCustomToken');

    final GetTokenResult idToken = await client.getAccessToken(
      forceRefresh: false,
    );
    if (idToken.claims['check'] != claims['check'] ||
        idToken.claims['role'] != 'tester') {
      throw StateError(
        'the ID token does not carry the claims of the custom token',
      );
    }
    step('claims of the custom token in the ID token');

    final VerifiedIdToken verified = await admin.verifyIdToken(
      idToken.token,
      checkRevoked: true,
    );
    if (verified.uid != uid || verified.signInProvider != 'custom') {
      throw StateError('verifyIdToken returned other claims');
    }
    step('verifyIdToken (Google keys, RS256) with checkRevoked');

    await admin.setCustomUserClaims(uid, <String, Object?>{'plan': 'pro'});
    if ((await admin.getUser(uid)).customClaims['plan'] != 'pro') {
      throw StateError('getUser does not show the custom claims');
    }
    final GetTokenResult refreshed = await client.getAccessToken(
      forceRefresh: true,
    );
    if (refreshed.claims['plan'] != 'pro') {
      throw StateError('a refreshed ID token does not carry the user claims');
    }
    step('setCustomUserClaims + getUser + refreshed ID token');

    if (Platform.environment['ADMIN_CHECK_SIGN_BLOB'] == '1') {
      final FirebaseAdminApp adcApp = FirebaseAdminApp(
        projectId: projectId,
        credential: applicationDefaultCredential(
          serviceAccountEmail: key['client_email']! as String,
        ),
      );
      try {
        final String iamToken = await adcApp.auth().createCustomToken(
          uid,
          claims: claims,
        );
        await client.signInWithCustomToken(iamToken);
        step('createCustomToken (IAM signBlob) + signInWithCustomToken');
      } finally {
        await adcApp.close();
      }
    }

    // The cut-off has second precision: wait so that the current sign-in is strictly older.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await admin.revokeRefreshTokens(uid);
    try {
      await admin.verifyIdToken(refreshed.token, checkRevoked: true);
      throw StateError('a revoked token passed checkRevoked');
    } on FirebaseAuthAdminException catch (e) {
      if (e.code != 'id-token-revoked') {
        rethrow;
      }
    }
    step('revokeRefreshTokens + checkRevoked');

    await admin.deleteUser(uid);
    created = false;
    try {
      await admin.getUser(uid);
      throw StateError('the user still exists after deleteUser');
    } on FirebaseAuthAdminException catch (e) {
      if (e.code != 'user-not-found') {
        rethrow;
      }
    }
    step('deleteUser');
    print('PASS (${passed.length} steps)');
  } on FirebaseException catch (e) {
    // The message of these exceptions never holds a token or a key.
    print(
      'FAIL after ${passed.length} steps: [${e.plugin}/${e.code}] ${e.message}',
    );
    exitCode = 1;
  } on StateError catch (e) {
    print('FAIL after ${passed.length} steps: ${e.message}');
    exitCode = 1;
  } on Object catch (e) {
    print('FAIL after ${passed.length} steps: ${e.runtimeType}');
    exitCode = 1;
  } finally {
    if (created) {
      try {
        await admin.deleteUser(uid);
      } on Object catch (e) {
        print(
          'could not delete the test user $uid (${e.runtimeType}); delete it in the console',
        );
      }
    }
    await client.dispose();
    await app.close();
  }
}
