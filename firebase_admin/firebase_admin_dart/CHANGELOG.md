## 0.1.0

First version.

- Licensed under Apache-2.0 (see `LICENSE` and `NOTICE`), like the other packages of the repository.
- `firebase_admin_dart.dart`: `FirebaseAdminApp` (a project, its credential, the emulators, the HTTP client),
  `AdminCredential.serviceAccount` (a key file you loaded) and `AdminCredential.iam` (any access token source,
  signing by the IAM Credentials API), `FirebaseAdminException`. `adc.dart` (needs `dart:io`):
  `applicationDefaultCredential()`.
- `auth.dart`: `FirebaseAuthAdmin` (`app.auth()`) with `createCustomToken` (RS256 with a key, IAM `signBlob`
  without one, unsigned in emulator mode), `createUser`, `getUser`, `findUserByEmail`, `updateUser`,
  `deleteUser`, `deleteUsers` (batches of 1000), `setCustomUserClaims`, `revokeRefreshTokens` and
  `verifyIdToken` (Google's x509 keys cached for their `max-age`, RS256 checked in pure Dart, `checkRevoked`).
  `AdminUser`, `DeleteUsersResult`, `VerifiedIdToken`, and `FirebaseAuthAdminException` with the codes of the
  Node Admin SDK.
- Pure Dart: compiles for the VM, Flutter and the web (dart2js and dart2wasm). No `dart:ffi`, no `googleapis`,
  no `pointycastle`.
- Requires Dart 3.8.0 or later.

Verified with unit tests and against the Firebase Auth emulator only. Nothing was run against the real
Firebase Auth service, Google's token endpoint, the IAM Credentials API or Google's public key endpoint.
`example/production_check.dart` is the check to run by hand against a test project.
