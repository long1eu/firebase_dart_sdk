## 0.1.0

- First version: an implementation of `FirebaseAuthPlatform` (the platform interface of the official `firebase_auth`
  plugin) on top of `FirebaseUserAuth` of `firebase_auth_providers_dart`, so that an app keeps the official API.
- Registers itself on Linux; `FirebaseAuthDart.use()` selects it on any other platform.
- A small pure-Dart `firebase_core` implementation, installed on Linux only while `firebase_core` has no other one,
  so that it can be in one app with `cloud_firestore_dart_platform`.
- Sign-in anonymously, with email and password, a custom token, an email link and the credentials of federated
  providers; account management, action codes, `tenantId`, `languageCode`, the three streams, `useAuthEmulator`,
  and the session kept in a file per program (`setPersistence` moves it to memory and back).
- `FirebaseAuthDart.userAuthFor(app)`: the client behind an app, also a token provider for `cloud_firestore_dart`.
- Not implemented (`FirebaseAuthException` with the code `unimplemented`): provider, popup and redirect flows, phone
  sign-in, multi-factor authentication, token revocation, Play Games and Game Center credentials.
