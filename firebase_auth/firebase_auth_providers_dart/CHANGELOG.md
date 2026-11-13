## 0.1.0

First version. Not published yet.

- Licensed under Apache-2.0 (see `LICENSE` and `NOTICE`), like `cloud_firestore_dart` and
  `firebase_app_dart`; the `_vm` packages they replace were licensed under BSD-3-Clause.

- `FirebaseUserAuth`: Firebase Auth user sign-in over the Identity Toolkit and Secure Token REST
  APIs (anonymous, email and password, custom token), ID token refresh on demand and ahead of
  expiry, sign-out, `AuthStorage` for the session (in memory by default), Auth emulator support.
  It implements the token provider interface of `firebase_app_dart`, so `cloud_firestore_dart`
  sends the ID token and follows user switches. Every request carries the headers of the JS SDK:
  `X-Client-Version` (`FirebaseUserAuth.clientVersion`), `X-Firebase-gmpid` (the `appId`
  parameter) and `X-Firebase-AppCheck` (the `appCheck` parameter); `forApp` takes both from the
  app.
- `FirebaseUserAuth` account management, ported from the REST-backed operations of the JS SDK:
  `sendPasswordResetEmail`, `confirmPasswordReset`, `verifyPasswordResetCode`, `checkActionCode`,
  `applyActionCode`, `sendEmailVerification`, `verifyBeforeUpdateEmail`, `updateEmail`,
  `updatePassword`, `updateProfile`, `reauthenticateWithEmailAndPassword`, `reload`,
  `deleteCurrentUser` and `fetchSignInMethodsForEmail`, with `ActionCodeSettings`,
  `ActionCodeInfo` and `ActionCodeOperation`. `AuthUser` has `emailVerified`, `displayName` and
  `photoUrl`, stored with the session; `userChanges` also emits after a change of the user's
  data. Error codes follow the JS SDK's map of server codes (an unknown code is its kebab case
  form).
- The Auth emulator host is checked like the Firestore host: user info, a path, a query, a bad
  port and Google hosts throw an `ArgumentError`; `http://` and `https://` URLs are accepted as
  `connectAuthEmulator` takes them, and an emulator off the loopback interface logs a warning.
  The stored refresh token is a credential; the `AuthStorage` docs say how to protect it.
- `OAuthTokenProvider.serviceAccount` and, in `adc.dart`, `applicationDefaultCredentials()`:
  OAuth 2.0 access tokens for servers and command line tools. These bypass security rules.
  The RS256 signer of the service account assertion blinds the message and verifies each
  signature before using it.
- Web-compatible main library (no `dart:io`); `FirebaseUserAuth` was run in Chrome (dart2js and
  dart2wasm) against the Auth emulator.
- Requires Dart 3.8.0 or later.

Verified with unit tests and against the Firebase Auth and Firestore emulators only. Nothing was
run against the real Firebase Auth service or Google's token endpoint.
