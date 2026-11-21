## 0.1.1

- `User.refreshToken`: the client's refresh token while that user is signed in, null for a `User` kept after a
  sign-out or a switch of user. FlutterFire's own `User.toString()` prints it, as on the native platforms.
- Phone sign-in through the client: `verifyPhoneNumber` (`codeSent` with the verification id,
  `verificationFailed`, `codeAutoRetrievalTimeout` after `timeout`; never `verificationCompleted`, since there is
  no instant verification or SMS auto-retrieval outside Android), `signInWithPhoneNumber` and
  `User.linkWithPhoneNumber` (a `ConfirmationResult` whose `confirm` takes the code), `User.updatePhoneNumber`, and
  phone credentials in `signInWithCredential`, `linkWithCredential` and `reauthenticateWithCredential`. Every error
  of `verifyPhoneNumber` reaches `verificationFailed` (`internal-error` for one that is not a
  `FirebaseAuthException`). `linkWithPhoneNumber` throws `provider-already-linked` before any SMS when the user has
  a phone number. The `credential` of `credential-already-in-use` signs in to the account that has the number.
- `FirebaseAuthDart.use(appVerification:)`: the proof of the phone requests, by default the reCAPTCHA v2 page of
  the client, shown by the `presenter` of `use` (the system browser on a desktop without one). With the Auth emulator, or after
  `setSettings(appVerificationDisabledForTesting: true)` (no longer ignored), no proof is sent. `use` also
  registers a `RecaptchaVerifier` factory, so that `signInWithPhoneNumber` without a verifier works; it renders
  nothing, and `RecaptchaVerifier.verify` throws `unimplemented`.
- SMS second factors: `verifyPhoneNumber` with the session of `User.multiFactor.getSession()` (enrolment) or of a
  `MultiFactorResolver` (sign-in), `PhoneMultiFactorGenerator.getAssertion`, and `MultiFactor.enroll` and
  `MultiFactorResolver.resolveSignIn` with the assertion.
- The real-project harness has `phone` and `sms` steps for a test phone number of the console
  (`AUTH_HARNESS_PHONE_NUMBER`, `AUTH_HARNESS_PHONE_CODE`; skipped without them).
- Tested with unit tests against a fake backend; the emulator tests and the harness steps are written but were not
  run.
- On the web the default storage of the sessions is `BestWebAuthStorage` of `firebase_auth_providers_dart`
  (IndexedDB, else `localStorage`, else memory) instead of memory, so the user stays signed in after a reload. A
  session an app kept in `localStorage` under the same key moves to IndexedDB at the first read.
- `setPersistence` on the web: `LOCAL` and `INDEXED_DB` keep the session in the storage of the app (that default, or
  `storageFor`). `SESSION` keeps it in the tab's `sessionStorage` (`WebAuthStorage.session`) when the app passed no
  `storageFor`, and a reloaded tab restores it from there (a `setPersistence(SESSION)` at start keeps it); with
  `storageFor`, `SESSION` is memory as before. `NONE` is memory. Elsewhere nothing changes (`SESSION` is memory).
  `FirebaseAuthDart.use(storageFor: ...)` still replaces the default. The web wiring is unit-tested on the VM with
  fakes; the shim has not been run in a browser.

## 0.1.0

- First version: an implementation of `FirebaseAuthPlatform` (the platform interface of the official `firebase_auth`
  plugin) on top of `FirebaseUserAuth` of `firebase_auth_providers_dart`, so that an app keeps the official API.
- Registers itself on Linux; `FirebaseAuthDart.use()` selects it on any other platform. Under `flutter test` the
  registration keeps the sessions in memory and leaves `firebase_core` alone.
- A small pure-Dart `firebase_core` implementation, installed on Linux only while `firebase_core` has no other one,
  so that it can be in one app with `cloud_firestore_dart_platform`.
- Sign-in anonymously, with email and password, a custom token, an email link and the credentials of federated
  providers; account management, action codes, `tenantId`, `languageCode`, the three streams, `useAuthEmulator`,
  and the session kept by one storage object for all apps (`setPersistence` moves it to memory and back; when the
  storage cannot be written, the session stays in memory for the run).
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
  FlutterFire provider are added to the request. `presenter` on `use()` (a `SecurePresenter` of `secure_flow`)
  runs the browser part; it is needed on Android and iOS (without it the calls throw
  `operation-not-supported-in-this-environment`, where they threw `unimplemented` before), and defaults to the
  system browser elsewhere (the URL on stderr over SSH or without a display). A presenter the flow refuses (a web
  view) is `argument-error`. A provider id that was not passed, and the web, throw `unimplemented`. The
  library exports `OAuthLoopbackProvider`, `OAuthAuthorizationCode`, `OAuthCodeExchange`, `SecurePresenter`,
  `SystemBrowserPresenter`, `ConsolePresenter` and `CallbackPresenter`.
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
- The default storage of the sessions is the secure store of the platform, `SecureAuthStorage` of
  `firebase_auth_secure_storage_flutter` (new dependency), on every platform but the web, which keeps memory. Linux
  builds now need `libsecret-1-dev`, Windows builds the ATL libraries, and the macOS keychain the
  `keychain-access-groups` entitlement.
- A session in the session file (`defaultSessionFile()`) moves to the secure store at its first read (read back and
  compared before the file loses it); when both hold one, the secure store's wins and the file is left alone.
- Before the first operation of a run, a probe writes, reads back and deletes `<namespace>/.probe` in the secure store
  (concurrent callers wait for it). When a step fails with `SecureAuthStorageException.isUnavailable` (no plugin, no
  Secret Service, a locked keyring, a missing macOS entitlement, Windows without an interactive logon), or there is no
  services binding, the run keeps the
  sessions in the session file instead (memory on Android and iOS), and one line per process says so. Other probe
  errors are thrown and the next operation probes again; other errors of the store are thrown and never answered from
  the file; a failed write still ends in memory through `FallbackStorage`.
- The marker of the secure store, `<session file>.secure` (session key to `secure` or `sign-out`, never a token),
  records the apps whose session lives in the store. A marked session is never read from or written to the session
  file: in a run where the store cannot be used (any reason, a locked keyring and Windows DPAPI refusing access
  included) it is kept in memory only, and a sign-in or sign-out there, or a write the store refuses later in a run,
  marks it `sign-out`; the next run that can use the store deletes it there before anything reads it. A copy left in
  the file by a crash during the move is deleted, never restored.
- `storageFor` replaces the default entirely; returning a `FileAuthStorage(defaultSessionFile()!)` keeps the file.
