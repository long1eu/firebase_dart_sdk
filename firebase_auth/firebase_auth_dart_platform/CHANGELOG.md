## 0.1.0

- First version: an implementation of `FirebaseAuthPlatform` (the platform interface of the official `firebase_auth`
  plugin) on top of `FirebaseUserAuth` of `firebase_auth_providers_dart`, so that an app keeps the official API.
- Registers itself on Linux; `FirebaseAuthDart.use()` selects it on any other platform. Under `flutter test` the
  registration keeps the sessions in memory and leaves `firebase_core` alone.
- A small pure-Dart `firebase_core` implementation, installed on Linux only while `firebase_core` has no other one,
  so that it can be in one app with `cloud_firestore_dart_platform`.
- Sign-in anonymously, with email and password, a custom token, an email link and the credentials of federated
  providers; account management, action codes, `tenantId`, `languageCode`, the three streams, `useAuthEmulator`,
  and the session kept in a file per program, one storage object for all apps (`setPersistence` moves it to memory
  and back; when the file cannot be written, the session stays in memory for the run).
- `FirebaseAuthDart.userAuthFor(app)`: the client behind an app, also a token provider for `cloud_firestore_dart`.
- Not implemented (`FirebaseAuthException` with the code `unimplemented`): provider, popup and redirect flows, phone
  sign-in, multi-factor authentication, token revocation, Play Games and Game Center credentials.
- Multi-factor with an authenticator app (TOTP): `User.multiFactor.getSession`, `enroll`, `unenroll` and
  `getEnrolledFactors`, `TotpMultiFactorGenerator.generateSecret`, `getAssertionForEnrollment` and
  `getAssertionForSignIn`, and `TotpSecret.generateQrCodeUrl`. `MultiFactorResolver.resolveSignIn` finishes a
  sign-in or a reauthentication with a TOTP assertion. `enroll` with a TOTP assertion and no `displayName` throws
  `argument-error`; `TotpSecret.openInOtpApp` and `PhoneMultiFactorGenerator.getAssertion` throw `unimplemented`.
- `signInWithProvider`, `User.linkWithProvider` and `User.reauthenticateWithProvider` run the loopback OAuth flow
  with the providers passed to `FirebaseAuthDart.use(oauthProviders:)`; the scopes and custom parameters of the
  FlutterFire provider are added to the request. `presentUrl` on `use()` opens the authorization URL and is needed
  on Android and iOS. A provider id that was not passed, and the web, throw `unimplemented`. The library exports
  `OAuthLoopbackProvider`, `OAuthAuthorizationCode`, `OAuthCodeExchange` and `UrlPresenter`.
- `revokeAccessToken` and `revokeTokenWithAuthorizationCode`.
- An error from the backend is a `DartFirebaseAuthException`, a `FirebaseAuthException` that also has `serverCode`
  and `httpStatus`. Multi-factor errors do not keep them, because `firebase_auth` builds its own class for those.
- `FirebaseAuthDart.validatePassword(app, password)` checks a password against the policy of the project or the
  tenant, also on the emulator. `FirebaseAuth.validatePassword` of `firebase_auth` does not go through the platform
  interface: it asks the production backend itself.
- An `UnsupportedError` of the client is a `FirebaseAuthException` with the code `unimplemented`, and a call after
  the instance was disposed one with `app-deleted`.
- `setPersistence` moves the session with the client's `setStorage`. The session is still kept in memory when the
  storage of the app cannot be written.
- `FirebaseAuthDart.use(oauthProvidersFor:)`: the loopback providers of one app, added to `oauthProviders`; a
  provider with the same id replaces the shared one for that app. Exports `OAuthProvidersFactory`.
