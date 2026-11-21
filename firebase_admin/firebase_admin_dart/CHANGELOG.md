## 0.1.2

No code change. The constraint on `firebase_auth_providers_dart` is `>=0.2.0 <0.5.0` instead of
`>=0.2.0 <0.4.0`, so that the package can be used with `firebase_auth_providers_dart` 0.4.0.

## 0.1.1

No code change. The constraint on `firebase_auth_providers_dart` is `>=0.2.0 <0.4.0` instead of `^0.2.0`, so that
the package can be used with `firebase_auth_providers_dart` 0.3.0. It compiles against 0.2.x and 0.3.0.

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

Verified with unit tests and against the Firebase Auth emulator. On 2026-11-18 the main path also passed against
one real Firebase project (`example/production_check.dart`, `firebase_auth_providers_dart` 0.2.1 as the client),
keyless: admin calls with the Application Default Credentials of a person
(`applicationDefaultCredential(serviceAccountEmail: ..., quotaProjectId: ...)`), custom tokens signed by the IAM
Credentials API `signBlob` as a service account that person may impersonate. All seven steps passed: `createUser`;
`createCustomToken` and `signInWithCustomToken` with claims whose standard base64 would hold `+` and `/`; the
claims in the ID token; `verifyIdToken` against Google's keys with `checkRevoked`; `setCustomUserClaims`, `getUser`
and a refreshed ID token with the claims; `revokeRefreshTokens`, after which `checkRevoked` rejects the old token
with `id-token-revoked`; `deleteUser`, after which `getUser` gives `user-not-found`.

Not run against a real project: local signing with a key (`AdminCredential.serviceAccount`), `findUserByEmail`,
`updateUser`, `deleteUsers` batches, tenants, the email lookup on the metadata server of Google Cloud, and user
credentials without a quota project.
