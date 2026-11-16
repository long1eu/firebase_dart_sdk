# firebase_admin_dart

Unofficial, light, pure-Dart Firebase admin calls for servers, command line tools, CI jobs and
integration tests. The first library is Firebase Auth: mint custom tokens, create, read, update and
delete users, set custom claims, revoke sessions and verify ID tokens. It is not affiliated with or
supported by Google or Firebase.

> **Status: 0.1.0.** Verified with unit tests and against the Firebase Auth emulator only: nothing
> was run against the real Firebase Auth service or Google's endpoints. Run
> [`example/production_check.dart`](#checking-a-real-project) once against a test project before
> you rely on it.

> **Admin credentials bypass security rules and can act as any user.** Use this package only in
> code you control. Never put a service account key in an app you ship, a web page, a Flutter asset
> or a repository. See [Security](#security).

## Install

```shell
dart pub add firebase_admin_dart
```

Dart 3.8 or later. It depends on `firebase_auth_providers_dart` (access tokens, the RS256 signer),
`firebase_app_dart`, `http`, `crypto` and `meta`; nothing else.

## Quick start

```dart
import 'package:firebase_admin_dart/auth.dart';

Future<void> main() async {
  // The Auth emulator. With a real project:
  // FirebaseAdminApp(projectId: ..., credential: AdminCredential.serviceAccount(keyJson)).
  final FirebaseAdminApp app = FirebaseAdminApp.emulator(
    projectId: 'demo-test',
    authEmulatorHost: '127.0.0.1:9099',
  );

  final AdminUser user = await app.auth().createUser(
    customClaims: <String, Object?>{'role': 'tester'},
  );
  final String token = await app.auth().createCustomToken(
    user.uid,
    claims: <String, Object?>{'tier': 'pro'},
  );
  // Hand the token to the client: FirebaseUserAuth.signInWithCustomToken(token), or
  // FirebaseAuth.instance.signInWithCustomToken(token) of FlutterFire.

  await app.auth().deleteUser(user.uid);
  await app.close();
}
```

`example/main.dart` runs the whole loop against the emulator: create a user, mint a token with
claims, sign in with `firebase_auth_providers_dart`, read the claims of the ID token, verify it,
delete the user.

## Layout

| Library | What it has |
| --- | --- |
| `package:firebase_admin_dart/firebase_admin_dart.dart` | What every admin area shares: `FirebaseAdminApp`, `AdminCredential`, `FirebaseAdminException` |
| `package:firebase_admin_dart/auth.dart` | Firebase Auth: `FirebaseAuthAdmin` (`app.auth()`), `AdminUser`, `VerifiedIdToken`, `FirebaseAuthAdminException`. Exports the library above |
| `package:firebase_admin_dart/adc.dart` | `applicationDefaultCredential()`: Application Default Credentials. Needs `dart:io` |

The names do not collide with `firebase_app_dart` (`FirebaseApp`, `FirebaseException`) or with
FlutterFire (`FirebaseAuth`, `User`): you can import them side by side without prefixes.

## The three environments

| Where | App | Custom tokens are signed |
| --- | --- | --- |
| A machine you control with a key file (CI, a CLI, a test runner) | `FirebaseAdminApp(projectId: ..., credential: AdminCredential.serviceAccount(keyJson))` | locally, RS256 |
| Google Cloud (Cloud Run, Functions, GKE, Compute Engine) | `FirebaseAdminApp(projectId: ..., credential: applicationDefaultCredential())` | by the IAM Credentials API (`signBlob`) as the default service account |
| The Auth emulator | `FirebaseAdminApp.emulator(projectId: 'demo-test', authEmulatorHost: '127.0.0.1:9099')` | not at all (`alg: none`) |

You load the key file yourself and pass its content (a `Map` or the JSON string): the package never
reads a file or an environment variable on its own. The only exception is `adc.dart`, which uses
the Application Default Credentials lookup of `firebase_auth_providers_dart`.

The emulator is never picked from `FIREBASE_AUTH_EMULATOR_HOST` behind your back: only
`FirebaseAdminApp.emulator` turns emulator mode on, and only in emulator mode does `verifyIdToken`
accept unsigned tokens. Pass `FirebaseUserAuth.emulatorHostFromEnvironment` yourself if you want
the variable.

With `AdminCredential.iam`, signing needs the IAM Service Account Credentials API enabled, and the
role Service Account Token Creator for the caller on the signing account. Off Google Cloud, pass
`serviceAccountEmail`, or load the key and use `AdminCredential.serviceAccount`. With the
credentials of a person (`gcloud auth application-default login`) Google APIs may ask for a quota
project: pass `quotaProjectId`.

The service account needs the role Firebase Authentication Admin (`roles/firebaseauth.admin`).

## What it offers

| Call | Endpoint | Emulator |
| --- | --- | --- |
| `createCustomToken(uid, {claims, tenantId})` | none with a key; `iamcredentials ...:signBlob` without | yes (unsigned) |
| `createUser({uid, email, password, emailVerified, displayName, photoUrl, phoneNumber, disabled, customClaims})` | `POST v1/projects/{p}/accounts` (+ `accounts:update` for claims) | yes |
| `getUser(uid)`, `findUserByEmail(email)` | `accounts:lookup` | yes |
| `updateUser(uid, {...})` | `accounts:update` | yes |
| `deleteUser(uid)`, `deleteUsers(uids)` (batches of 1000) | `accounts:delete`, `accounts:batchDelete` | yes |
| `setCustomUserClaims(uid, claims)`, `revokeRefreshTokens(uid)` | `accounts:update` | yes |
| `verifyIdToken(idToken, {checkRevoked, clockSkew})` | Google's x509 keys; `accounts:lookup` with `checkRevoked` | yes (unsigned tokens) |

Custom tokens follow the rules of the Firebase documentation: RS256, base64url without padding, the
Identity Toolkit audience, one hour of life, `uid` of 1 to 128 characters, no reserved claim names
(`FirebaseAuthAdmin.reservedClaims`).

`verifyIdToken` checks the signature with the key named by `kid`, then `aud`, `iss`, `sub`, `exp`,
`iat` and `auth_time`, with a clock skew of 10 seconds by default (at most 5 minutes). The keys are
fetched from
`https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com`, the
source the Firebase documentation names, and kept for the `max-age` of the answer.

## Errors

Every call throws a `FirebaseAuthAdminException` (a `FirebaseException` of `firebase_app_dart`).
Its `code` is the code of the Node.js Admin SDK without the `auth/` prefix: `user-not-found`,
`uid-already-exists`, `email-already-exists`, `id-token-expired`, `id-token-revoked`,
`argument-error`, `invalid-credential`, `insufficient-permission`, ... It prints as
`[auth/user-not-found] ...`. `serverCode` keeps the code of the REST API. No message holds a token,
a password or a key.

```dart
try {
  await app.auth().getUser(uid);
} on FirebaseAuthAdminException catch (e) {
  if (e.code != 'user-not-found') rethrow;
}
```

## In Flutter integration tests

The package has no Flutter dependency, so it runs inside `integration_test` on a device: the test
creates a user, mints a token, the app signs in with it and runs under the real security rules, and
the test deletes the user.

Where the credential comes from:

- **The emulator** needs none: pass the host with
  `--dart-define=FIREBASE_AUTH_EMULATOR_HOST=10.0.2.2:9099` (the host machine as the Android
  emulator sees it; `127.0.0.1` on iOS simulators and desktop).
- **A real test project**: a CI secret holds the key file, passed to the test build only, for
  example `--dart-define=ADMIN_SERVICE_ACCOUNT_B64="$(base64 < key.json | tr -d '\n')"`. A
  `--dart-define` value is compiled into that test binary, so never pass it to `flutter build` of an
  app you ship, and never keep the key in `assets/`. Use a separate test project and a service
  account with only `roles/firebaseauth.admin` there.

[`example/integration_test_helper.dart`](example/integration_test_helper.dart) is a small helper
(`TestUsers`) that builds the app from those values, creates users and deletes them. A test with
it:

```dart
// integration_test/signed_in_test.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'integration_test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final TestUsers? users = TestUsers.fromEnvironment(projectId: 'demo-test');

  tearDownAll(() => users?.deleteAll());

  testWidgets('a tester sees the tester screen', (WidgetTester tester) async {
    final (:String uid, :String customToken) = await users!.create(
      claims: <String, Object?>{'role': 'tester'},
    );
    await FirebaseAuth.instance.signInWithCustomToken(customToken);
    // ... pump the app and check what a user with the role "tester" sees.
    expect(FirebaseAuth.instance.currentUser?.uid, uid);
  }, skip: users == null);
}
```

## Security

- Never ship a service account key in an app, a web page, a Flutter asset or a repository. Prefer
  Application Default Credentials and `signBlob` on Google Cloud; a key file is for machines you
  control. Whoever holds the key can mint a token for any uid and so act as any user.
- Admin calls and service account tokens bypass security rules. The rules apply again only to a
  client that signs in as a user, for example with a custom token.
- A custom token lives at most one hour and is only for `signInWithCustomToken`; the ID token it
  yields lives one hour and the client refreshes it. Do not log either.
- `revokeRefreshTokens` does not end ID tokens already issued: they stay valid until they expire
  unless the verifier passes `checkRevoked: true` (one more request per call) or the rules compare
  `auth_time`. The cut-off has second precision.
- Custom claims are at most 1000 bytes and appear in every ID token: no secrets, no large data.
- `signBlob` counts against 60,000 signing requests per project per minute and adds a request per
  token: reuse a token within its hour where you can.
- Clock skew: custom tokens are issued at the current time, and `verifyIdToken` allows 10 seconds of
  skew by default. Keep the clocks of your machines in sync.
- The package compiles for the web, but a browser is not a place for admin credentials, and
  Google's endpoints may refuse cross-origin calls anyway.

## Checking a real project

[`example/production_check.dart`](example/production_check.dart) runs the main path against a
real project, for you to run by hand (no test runs it):

```shell
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json \
FIREBASE_WEB_API_KEY=<the Web API key of the same project> \
dart run example/production_check.dart
```

It creates one user with a random uid, mints a token with claims whose JSON forces `+` and `/` in
standard base64, signs in, verifies the ID token with Google's keys, sets and reads custom claims,
revokes and checks the revocation, and deletes the user in `finally`. It prints `PASS` or `FAIL`
and never a token or a key. Add `ADMIN_CHECK_SIGN_BLOB=1` to also sign through the IAM Credentials
API with Application Default Credentials.

## What it does not do

This is a small subset of the Firebase Admin SDKs. For anything else use the official
[`firebase_admin_sdk`](https://pub.dev/packages/firebase_admin_sdk) (Dart, VM only) or a Firebase
Admin SDK in another language: session cookies, `listUsers`, `getUsers`, lookups by phone or
provider, user import with password hashes, email action links, OIDC and SAML provider configs,
tenant management, project config, multi-factor fields, and every other Firebase service.
`docs/guides/admin.md` in the repository compares the options.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
