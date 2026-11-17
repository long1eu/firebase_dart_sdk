// A check against a REAL Firebase project, for the owner to run by hand. Nothing in the test suite runs it.
//
// Keyless (no key file anywhere): admin calls use the Application Default Credentials of the person signed in
// with `gcloud auth application-default login`, and custom tokens are signed by the IAM Credentials API
// (signBlob) as a service account that person may impersonate:
//
//     ADMIN_CHECK_PROJECT_ID=my-project \
//     ADMIN_CHECK_SERVICE_ACCOUNT=admin-check@my-project.iam.gserviceaccount.com \
//     FIREBASE_WEB_API_KEY=<the Web API key of the same project> \
//     dart run example/production_check.dart
//
// That needs the IAM Service Account Credentials API enabled in the project, the role Firebase Authentication
// Admin (roles/firebaseauth.admin) for the service account, and the role Service Account Token Creator
// (roles/iam.serviceAccountTokenCreator) on that account for the signed-in person. ADMIN_CHECK_PROJECT_ID is
// also sent as the quota project. GOOGLE_APPLICATION_CREDENTIALS must be unset.
//
// With a key file: admin calls use the key, and custom tokens are signed locally with its private key:
//
//     GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json \
//     FIREBASE_WEB_API_KEY=<the Web API key of the same project> \
//     dart run example/production_check.dart
//
// The key's service account needs Firebase Authentication Admin. Optional: ADMIN_CHECK_SIGN_BLOB=1 also mints a
// token through signBlob with Application Default Credentials, signing as the key's service account; that needs
// the IAM Service Account Credentials API and Service Account Token Creator for that account on itself.
//
// What it does: creates one user with a random uid, mints a custom token with claims whose JSON forces `+` and
// `/` in standard base64 (so a wrong alphabet would fail), signs in with firebase_auth_providers_dart, verifies
// the ID token (signature, claims, and checkRevoked), sets and reads custom claims, revokes the sessions and
// checks that the verifier sees it, and deletes the user in `finally`. It prints PASS or FAIL, and never a
// token or a key.
//
// A role granted seconds before the run may not be in effect yet (signBlob answers 403 with
// `iam.serviceAccounts.signBlob denied`): wait a minute and run it again.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_admin_dart/adc.dart';
import 'package:firebase_admin_dart/auth.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

const String _usage = '''
Usage: set either

  keyless:   ADMIN_CHECK_PROJECT_ID, ADMIN_CHECK_SERVICE_ACCOUNT and FIREBASE_WEB_API_KEY
             (after `gcloud auth application-default login`; GOOGLE_APPLICATION_CREDENTIALS unset)

  key file:  GOOGLE_APPLICATION_CREDENTIALS and FIREBASE_WEB_API_KEY
             (optional ADMIN_CHECK_SIGN_BLOB=1 also tries IAM signBlob)

then run: dart run example/production_check.dart
The top of example/production_check.dart lists the roles each mode needs.''';

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final String? keyPath = env['GOOGLE_APPLICATION_CREDENTIALS'];
  final String? keylessProjectId = env['ADMIN_CHECK_PROJECT_ID'];
  final String? keylessAccount = env['ADMIN_CHECK_SERVICE_ACCOUNT'];
  final String? apiKey = env['FIREBASE_WEB_API_KEY'];
  final bool keyless =
      keyPath == null && keylessProjectId != null && keylessAccount != null;

  if (apiKey == null || (keyPath == null && !keyless)) {
    print(_usage);
    exitCode = 2;
    return;
  }
  if (keyPath != null && keylessAccount != null) {
    print(
      'Both GOOGLE_APPLICATION_CREDENTIALS and ADMIN_CHECK_SERVICE_ACCOUNT are set; pick one mode.\n\n$_usage',
    );
    exitCode = 2;
    return;
  }
  if (env['FIREBASE_AUTH_EMULATOR_HOST'] != null) {
    print(
      'FIREBASE_AUTH_EMULATOR_HOST is set; this check is for a real project. Unset it.',
    );
    exitCode = 2;
    return;
  }

  final String projectId;
  final AdminCredential credential;
  final String signing;
  // The service account to sign as through signBlob in the key-file mode, when ADMIN_CHECK_SIGN_BLOB=1.
  String? signBlobAccount;
  if (keyless) {
    projectId = keylessProjectId;
    credential = applicationDefaultCredential(
      serviceAccountEmail: keylessAccount,
      quotaProjectId: keylessProjectId,
    );
    signing = 'IAM signBlob, no key';
  } else {
    final Map<String, Object?> key =
        jsonDecode(File(keyPath!).readAsStringSync()) as Map<String, Object?>;
    projectId = key['project_id']! as String;
    credential = AdminCredential.serviceAccount(key);
    signing = 'local RS256';
    if (env['ADMIN_CHECK_SIGN_BLOB'] == '1') {
      signBlobAccount = key['client_email']! as String;
    }
  }
  print('mode: ${keyless ? 'keyless' : 'key file'}');

  final FirebaseAdminApp app = FirebaseAdminApp(
    projectId: projectId,
    credential: credential,
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
    step('createCustomToken ($signing) + signInWithCustomToken');

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

    if (signBlobAccount != null) {
      final FirebaseAdminApp adcApp = FirebaseAdminApp(
        projectId: projectId,
        credential: applicationDefaultCredential(
          serviceAccountEmail: signBlobAccount,
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
