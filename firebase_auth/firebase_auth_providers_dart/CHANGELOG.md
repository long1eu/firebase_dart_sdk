## 0.1.0

First version. Not published yet.

- `FirebaseUserAuth`: Firebase Auth user sign-in over the Identity Toolkit and Secure Token REST
  APIs (anonymous, email and password, custom token), ID token refresh on demand and ahead of
  expiry, sign-out, `AuthStorage` for the session (in memory by default), Auth emulator support.
  It implements the token provider interface of `firebase_app_dart`, so `cloud_firestore_dart`
  sends the ID token and follows user switches.
- `OAuthTokenProvider.serviceAccount` and, in `adc.dart`, `applicationDefaultCredentials()`:
  OAuth 2.0 access tokens for servers and command line tools. These bypass security rules.
- Web-compatible main library (no `dart:io`); `FirebaseUserAuth` was run in Chrome (dart2js and
  dart2wasm) against the Auth emulator.
- Requires Dart 3.8.0 or later.

Verified with unit tests and against the Firebase Auth and Firestore emulators only. Nothing was
run against the real Firebase Auth service or Google's token endpoint.
