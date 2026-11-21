## Unreleased

- `PhoneAuthCredential.toJson` and `PhoneAuthCredential.fromJson`, in the JSON format of the JS SDK's `toJSON` and
  `fromJSON`: a verification id with its code, or a temporary proof with its phone number (the `credential` of
  `credential-already-in-use`). As in the JS SDK, empty values are left out and read back as missing, and
  `fromJson` returns null when all four values are missing; it also returns null for JSON that is not a map or a
  value that is not a string. `toString` still shows none of the values.
- `MultiFactorResolver.session`: a `MultiFactorSession` of type `MultiFactorSessionType.signIn` that wraps the
  pending credential of the sign-in (`resolver.session` of the JS SDK). It is opaque: no member, `toString` or JSON
  form shows the credential.
- Cross-tab sync on the web, as in the JS SDK. `ObservableAuthStorage` is an `AuthStorage` with
  `changes(key)`, a stream that emits when someone else (another tab) changed the key; `WebAuthStorage`
  (the browser's `storage` event), `IndexedDbAuthStorage` (a `readonly` read every `pollInterval`, 800 ms by
  default, while the stream is listened to) and `BestWebAuthStorage` (whichever storage it chose) implement it.
  The writes of the object itself never emit. The polls stop when nobody listens and at `close()`, also
  `BestWebAuthStorage.close()`, and pause while the page is in the back/forward cache.
- `FirebaseUserAuth` follows an `ObservableAuthStorage` while it uses it: a sign-out in another tab signs it out,
  another user signed in there becomes its user, and new tokens or data of the same user are taken over (the ID
  token stays until the next refresh, which uses the stored refresh token). `authStateChanges`, `idTokenChanges`,
  `userChanges` and `onTokenChanged` emit as for a sign-in or sign-out here; the `beforeAuthStateChanged`
  callbacks do not run. It never writes back what it read. Before it stores an update of the user's session (a
  rotated refresh token, new user data), it reads the storage and takes over a sign-out or another user stored
  there instead of writing over it, so a sign-out in one tab is no longer undone by another tab's next write.
  The JS SDK writes the adopted user back to the persistence; this client does not. Other storages behave as
  before.
- `BestWebAuthStorage`: the read of a key marked by a write made without IndexedDB copies the state from
  `localStorage` to IndexedDB and now keeps the `localStorage` copy (only the marker goes), so that a tab that
  chose `localStorage` is not signed out when a tab on IndexedDB follows its write. A copy, once there, follows
  the writes made with IndexedDB (a sign-out deletes it), and an unmarked copy is deleted at a read only when it
  differs from IndexedDB. When `localStorage` cannot be read for a marked key, the read throws an
  `IndexedDbAuthStorageException` (`migrate`) instead of returning null, which read as a sign-out.

## 0.3.2

- `FirebaseUserAuth.refreshToken`: the refresh token of the signed-in user's session, null when signed out; it
  follows the server's rotation. It is not a field of `AuthUser` (JS has `User.refreshToken`), so a user that is
  printed or serialized never carries it.
- Phone sign-in, with the names of the iOS SDK: `FirebaseUserAuth.verifyPhoneNumber(phoneNumber, appVerification:)`
  sends the SMS code (`v1/accounts:sendVerificationCode`, with the reCAPTCHA v2 or Enterprise token of the
  `AppVerification`, or none for the emulator) and returns the verification id; `PhoneAuthProvider.credential(
  verificationId:, verificationCode:)` makes a `PhoneAuthCredential` that `signInWithCredential`,
  `linkWithCredential`, `reauthenticateWithCredential` and the new `updatePhoneNumber` take
  (`v1/accounts:signInWithPhoneNumber`). The app asks for the code with its own field. A number that another
  account has is `credential-already-in-use` (also from `PHONE_NUMBER_EXISTS`), whose `credential` is a
  `PhoneAuthCredential` of the backend's temporary proof that signs in to that account, as in the iOS SDK; a
  reauthentication with a number of no account or another account is
  `user-mismatch`. `verifyPhoneNumberInteractively` does both steps for a program without a code field: the
  reCAPTCHA page and a `CodeEntryFlow` of `secure_flow` (VM only). Tested with unit tests against a fake backend;
  not run against the emulator or a real project.
- The phone errors map to the codes of the JS SDK and FlutterFire: `INVALID_CODE`, `INVALID_SESSION_INFO`,
  `SESSION_EXPIRED` and `CODE_EXPIRED`, `MISSING_CODE` (`missing-verification-code`), `MISSING_SESSION_INFO`,
  `INVALID_PHONE_NUMBER`, `MISSING_PHONE_NUMBER`, `QUOTA_EXCEEDED`, `TOO_MANY_ATTEMPTS_TRY_LATER`,
  `MISSING_APP_CREDENTIAL`, `INVALID_APP_CREDENTIAL` and `CAPTCHA_CHECK_FAILED`. An empty number, verification id
  or code fails before anything is sent. No error of a phone request holds the phone number, the verification id,
  the SMS code or the reCAPTCHA token: they are cut from the message, and `phoneNumber` and `serverResponse` are
  left empty.
- SMS second factors: `FirebaseUserAuth.startPhoneEnrollment(phoneNumber, appVerification:)` sends the code and
  returns the verification id, `finalizePhoneEnrollment(credential, displayName:)` enrols the factor
  (`v2/accounts/mfaEnrollment:start` and `:finalize` with the phone fields), and `MultiFactorResolver` gets
  `startPhoneSignIn(enrollmentId:, appVerification:)` and `resolveSignInWithPhone(credential)`
  (`v2/accounts/mfaSignIn:start` and `:finalize`). `unenrollMultiFactor` removes SMS factors as before. An account
  with SMS factors only now gets the default message of `FirebaseAuthMultiFactorException`;
  `unsupportedFactorsMessage` is for factors of an unknown kind. Tested with unit tests against a fake backend;
  not run against the emulator or a real project.
- `IndexedDbAuthStorage`: an `AuthStorage` in IndexedDB for the web (the JS SDK's `indexedDBLocalPersistence`), in
  its own database (`firebase_auth_providers_dart`, store `sessions`; not the JS SDK's format). A write completes
  once its transaction has completed (`durability: 'strict'`); the calls of one instance run in order; each request
  has `requestTimeout` (2.5 s by default) and one that takes longer is aborted with an `IndexedDbTimeoutException`;
  an open or deletion blocked by another connection fails at once. A connection found closed, or a transaction
  aborted by the browser, is opened and tried again once. Only the default database is deleted and created again
  when it exists without the store; another name throws. Errors are `IndexedDbAuthStorageException`s (with an
  `IndexedDbOperation` and the browser's `DOMException` name and message), which carry no stored value.
  `IndexedDbAuthStorage.isAvailable()` probes IndexedDB within the same limit and never throws.
- `BestWebAuthStorage`: IndexedDB, else `localStorage`, else memory, decided once by a probe on its own connection
  (`kind`, a `WebAuthStorageKind`), like `getAuth` of the JS SDK; `close()` closes the connection. With IndexedDB, a
  session of the same key found in `localStorage` (`localStoragePrefix`) is moved at the first read: written, read
  back, then deleted from `localStorage`; a session IndexedDB already has wins and the `localStorage` copy is
  deleted. A write made while `localStorage` or memory holds the sessions leaves a marker in `localStorage` and
  tries to delete the key from IndexedDB, so the next load with IndexedDB keeps that state.
- No cross-tab sync: a sign-out in one tab can be undone by another signed-in tab's next write until it reloads. On
  the Dart VM both constructors throw an `UnsupportedError`. `test/browser/indexed_db_auth_storage_test.dart` and
  `test/browser/web_auth_storage_test.dart` pass in headless Chrome with dart2js and dart2wasm.

## 0.3.1

- The browser flows run on the new package `secure_flow` (a new dependency, `^0.1.0`), whose presenters,
  environment and errors this library re-exports. `authorizeWithOAuthLoopback`, `signInWithOAuthLoopback`,
  `linkWithOAuthLoopback` and `reauthenticateWithOAuthLoopback` take a `presenter` (a `SecurePresenter`) and an
  `environment` (a `SecureEnvironment`); without a presenter, the `OAuthFlow` takes the best one the environment
  offers: a `ProviderAppPresenter` registered for the provider, the system browser on a desktop, an in-app
  browser, the console (only the URL on stderr over SSH or on Linux without a display; a timeout then names the
  `ssh -L` forward that would help). A presenter the flow does not accept (a web view, a provider app for another
  provider) fails with a `FirebaseAuthException` `argument-error`, and no presenter for the environment (Android
  and iOS without one passed) with `operation-not-supported-in-this-environment`; both carry the `SecureFlowRefused`
  or `SecureFlowNoPresenter` of `secure_flow` in the new `FirebaseAuthException.cause`. Before, the flow threw an
  `UnsupportedError` on Android and iOS, where it had no browser launcher. An error of the presenter itself is
  rethrown as it is. `AppVerification.recaptchaV2Loopback` maps them the same way.
- A `ProviderAppPresenter` (the provider's app or SDK; none is part of this package) returns the provider's tokens
  directly: they go to `signInWithIdp` without a code exchange, with the raw nonce in the credential for OpenID
  Connect providers. When a nonce was sent, the ID token must carry it: an ID token without the nonce claim fails
  with `missing-or-invalid-nonce`, like one with another nonce. An access token without an ID token fails with
  `invalid-oauth-response` unless the provider sets the new `OAuthLoopbackProvider.acceptAccessTokenOnly` (off by
  default; such a token has no binding to the request). Tested with a fake presenter only. The redirect URI (`http://127.0.0.1:<port>`), PKCE, the state and
  the nonce are unchanged.
- `AppVerification.recaptchaV2Loopback(presenter:, environment:, timeout:)` serves the reCAPTCHA v2 page with the
  `RecaptchaFlow` of `secure_flow`; a timeout is `timeout`. Its site key comes from `getRecaptchaSiteKey()`.
  Not run against Google.
- `FirebaseUserAuth.useEmulator(emulatorHost)`: sends the later requests to the Auth emulator, for an instance that
  is created before the emulator is known (FlutterFire's `useAuthEmulator`). `emulatorHost` is now a getter.
- Authenticator app (TOTP) multi-factor authentication, for projects on Identity Platform:
  `FirebaseUserAuth.startTotpEnrollment` returns a `TotpSecret` (`secretKey`, `hashingAlgorithm`, `codeLength`,
  `codeIntervalSeconds`, `enrollmentCompletionDeadline`, and `otpauthUri(issuer:, accountName:)` for a QR code),
  `finalizeTotpEnrollment(secret, code:, displayName:)` finishes the enrolment, `unenrollMultiFactor(uid)` removes
  any factor, and the new `AuthUser.enrolledFactors` lists them (read with `accounts:lookup` and stored with the
  session; storage format still version 2). `FirebaseAuthMultiFactorException` has a `resolver`
  (`MultiFactorResolver.resolveSignInWithTotp(code, enrollmentId:)`) that finishes a sign-in or a
  reauthentication; its message now says when the account's only factors are SMS, which this package cannot use
  (the resolver then throws `multi-factor-info-not-found`). `MultiFactorInfo` moved to its own file (same export)
  and reads `enrolledAt` strictly as RFC 3339 with a time zone. The calls go to the Identity Toolkit API v2 as
  JSON. On 2026-11-20 one run against a real Identity Platform project went through enrolment, sign-in with the second factor and removal, with the errors for an unverified email, a wrong code and a missing display name. Tenants and SMS factors were not part of it.

- Browser sign-in for desktop apps and command line tools (VM only): `FirebaseUserAuth.signInWithOAuthLoopback`
  and `authorizeWithOAuthLoopback`, with `OAuthLoopbackProvider.google`, `.oidc` and `.discover`. The system
  browser (through a `presenter`, see the `secure_flow` entry below) runs the authorization code flow with PKCE (S256),
  a random `state` (compared in constant time) and a nonce; the redirect comes back to a one-shot server on
  127.0.0.1 that answers 404 to any other path and is always closed (success, error or `timeout`). The code is
  exchanged at the token endpoint with the client id and secret. Google with a "Desktop app" client needs nothing
  more. The optional `exchangeCode` callback is for a provider that wants a confidential client: it gets the code,
  the PKCE verifier, the redirect URL and the client id (`OAuthAuthorizationCode`), sends them to a server of yours,
  and returns the token endpoint's JSON. It is the counterpart of `serverAuthCode` in `google_sign_in`. The result
  (`OAuthLoopbackResult`) has the provider's tokens and a ready `OAuthCredential`. On the web these throw an
  `UnsupportedError`. New error codes: `timeout`, `user-cancelled`,
  `invalid-oauth-response`, `invalid-oauth-provider`. Only the redirect of this sign-in (its `Host` header and its
  `state`) ends the wait; any other request gets a 400. The code exchange and the discovery request fail with
  `network-request-failed` after 30 seconds. Plain `http` endpoints are accepted only on `127.0.0.1` and `::1`.
- `FirebaseUserAuth.linkWithOAuthLoopback` and `reauthenticateWithOAuthLoopback`: the same browser sign-in, then
  `linkWithCredential` or `reauthenticateWithCredential`. Same arguments as `signInWithOAuthLoopback`; `null-user`
  before the browser opens when nobody is signed in.
- On 2026-11-20, Google sign-in with a Desktop client was run against a real Firebase project: the code was
  exchanged directly with the client secret and PKCE, and the redirect was `http://127.0.0.1:<port>`.
  `exchangeCode` and generic OpenID Connect providers were run only against the fake identity provider of the
  tests.
- `OAuthLoopbackProvider.github`: GitHub sign-in through the loopback helper (PKCE S256, client secret, default
  scopes `read:user user:email`, no nonce; Firebase gets the access token only). Run only against the fake
  identity provider of the tests.
- A backend error ends the session only when it comes with HTTP 400: `invalidatesSession` is false for a 5xx that
  names `TOKEN_EXPIRED`, `USER_DISABLED`, ..., and the user stays signed in.
- When a request with the ID token is rejected with `TOKEN_EXPIRED` or `INVALID_ID_TOKEN`, the token is refreshed
  once to check the session (as in the iOS SDK): the user is signed out only when the refresh says that the session
  ended, and otherwise the request is sent once more with the new token.
- Token lifetimes from the backend are bounded as in the iOS SDK: an `expiresIn` outside of (0, 24 h], missing or
  not a number counts as one hour, an `exp` claim more than 24 h ahead is not trusted, and a proactive refresh
  delay beyond 24 h refreshes right away.
- Every request is bounded by `requestTimeout` (a new named parameter of `FirebaseUserAuth`, 30 s by default): a
  request that takes longer fails with `network-request-failed`, and the next token request tries again. The
  proactive token refresh retries with backoff after any error that does not end the session (a failing storage,
  for example), not only after a `FirebaseAuthException`. A storage that throws on read in `restore` keeps the
  stored session (tested; the behavior was already so).

- `FirebaseUserAuth.revokeToken(authorizationCode)` revokes the Sign in with Apple token of the signed-in user
  with Apple's authorization code (`v2/accounts:revokeToken`, like `revokeToken(withAuthorizationCode:)` of the
  iOS SDK). The user stays signed in. Throws `null-user` when nobody is signed in. Sends the `tenantId` when one is
  set, like the JS SDK's `revokeToken` request. Tested with a fake HTTP client only.
- `FirebaseUserAuth.revokeAccessToken(token)` revokes a Sign in with Apple access token of the signed-in user
  (`revokeAccessToken` of the JS SDK: `v2/accounts:revokeToken` with the token type `ACCESS_TOKEN` and the
  `tenantId` when set). The user stays signed in. Throws `null-user` when nobody is signed in, where the JS SDK
  does nothing. Tested with a fake HTTP client only.
- A storage that fails to write a new session no longer leaves the stored session behind for good: the session in
  memory is the new one (the backend may have replaced the refresh token), the operation throws the error of the
  storage, and the next session change (a token refresh, a reload, a sign-in) writes it again, even when the refresh
  token did not change. The user is not signed out.
- `FirebaseUserAuth.forApp` sets `app.authProvider` even when the `read` of the storage throws, then rethrows: the
  app works signed out, and `restore()` on that instance tries again.
- `signOut` with a storage that fails to delete the session signs the user out in memory (the streams emit null)
  and throws the error of the storage; `restore()` on that instance deletes the stored session again instead of
  signing the user back in. A new instance still restores it until a write succeeds.
- JSON for credentials in the format of the JS SDK: `EmailAuthCredential.toJson`/`fromJson`,
  `OAuthCredential.toJson`/`fromJson` and `OAuthProvider.credentialFromJson` (`toJSON`, `fromJSON` and
  `credentialFromJSON` of the JS SDK). `fromJson` returns null for JSON that is not a credential, as in the JS SDK;
  `credentialFromJson` throws an `ArgumentError`. An email link is written as its code and tenant, as in the JS SDK.
  The JSON holds the credential's password or tokens. Tested with fixtures derived from the JS sources only.
- `FirebaseUserAuth.emulatorConfig` (`AuthEmulatorConfig`: protocol, host, port, options), like the JS SDK's
  `emulatorConfig`; null without an emulator. `emulatorOptions: AuthEmulatorOptions(disableWarnings: true)` on the
  constructor and `forApp`, and `options:` on `useEmulator`, leave out the warning for an emulator off the loopback
  interface. An invalid emulator host stays an `ArgumentError` (the JS SDK's `invalid-emulator-scheme` is a
  `FirebaseAuthException`); a scheme other than `http` or `https` now says so in the message.
- `AuthUser.providerId` (always `firebase`), `UserCredential.operationType` (the new `OperationType` enum:
  `signIn`, `link`, `reauthenticate`, with the JS SDK's strings in `value`) and `AuthUser.toJson()` with the keys of
  the JS SDK's `User.toJSON`, except `stsTokenManager`, `apiKey` and `appName`, which belong to the session.
- On 2026-11-20, a generic OpenID Connect provider was run against a real Firebase project with `discover` and with
  an `exchangeCode` callback, and GitHub with a real OAuth App (`account-exists-with-different-credential`, then
  link and unlink on an existing account). The backend accepts only a token of the GitHub app configured in the
  project, and the callback URL of the app must be `http://127.0.0.1` without a `/` at the end. All of it is in the
  README.
- `FirebaseUserAuth.setStorage(storage)` keeps the session in another `AuthStorage` from now on and moves the
  current one there (`setPersistence` of the JS SDK). The session is written to the new storage first and deleted
  from the old one after; when the write fails, nothing changes.
- `OAuthLoopbackProvider.copyWith(scopes:, customParameters:)`.
- A call after `dispose` throws `FirebaseUserAuthDisposedError`, a `StateError`.
- `FirebaseUserAuth.app`: the app of an instance made by `forApp`; null for one made with the constructor.
- Constants `ProviderId`, `SignInMethod`, `FactorId` and `AuthErrorCode` (the codes of the JS SDK and the five only
  this client has). `MultiFactorInfo.phoneFactorId` and `totpFactorId` are the `FactorId` values.
- `FirebaseAuthException.serverResponse`: the answer of the backend on the errors the JS SDK tags with it
  (`account-exists-with-different-credential`, `credential-already-in-use`, `email-already-in-use`,
  `user-disabled`). It is unmodifiable, and neither it nor the exception prints its values.
- A change of the account (email verification, `verifyBeforeUpdateEmail`, linking, TOTP enrolment and unenrolment,
  email and password updates) is no longer sent a second time when the backend rejects the ID token of the account
  read that follows it.

## 0.3.0

- The complete server error map of the JS SDK (`SERVER_ERROR_MAP` of `@firebase/auth` 1.13.10): the phone,
  multi-factor, reCAPTCHA, `signInWithIdp` and action code settings codes are mapped like the JS SDK maps them
  (`INVALID_CODE` is `invalid-verification-code`, `UNAUTHORIZED_DOMAIN` is `unauthorized-continue-uri`, ...), with
  the JS SDK's messages. Codes that were already mapped are unchanged.
- Fix: an answer with HTTP 200 whose body has an `errorMessage` was taken for a success; it is an error now, like in
  the JS SDK. An answer with `needConfirmation` throws `account-exists-with-different-credential`.
- `FirebaseAuthException` has FlutterFire's `email`, `phoneNumber` and `tenantId`, set for the errors the JS SDK
  tags with the answer (`credential-already-in-use`, `email-already-in-use`, `user-disabled`,
  `account-exists-with-different-credential`).
- Fix: `checkActionCode` threw `internal-error` for an operation the package does not know; it returns it, like the
  JS SDK, as the new `ActionCodeOperation.unknown` with the backend's name in the new `ActionCodeInfo.requestType`.
  **Breaking** for a `switch` over `ActionCodeOperation` without a default: add a case for `unknown` (FlutterFire's
  `ActionCodeInfoOperation` has the same value). `ActionCodeInfo.multiFactorInfo` is the factor of
  `revertSecondFactorAddition`, which now requires it, like the JS SDK.
- The full user record, like FlutterFire's `User`: `AuthUser.providerData` (a list of the new `UserInfo`),
  `metadata` (the new `UserMetadata`: creation and last sign-in time), `phoneNumber`, `tenantId`, and `photoURL`
  (the FlutterFire name of `photoUrl`). Like the JS SDK, every sign-in now reads the account (`accounts:lookup`)
  before it completes, so a sign-in makes two requests; a sign-in whose account cannot be read fails and signs
  nobody in. `reload` reads the same fields.
- The sign-in methods and `reauthenticateWithEmailAndPassword` return a `UserCredential` (FlutterFire's name), which
  is also the `AuthUser` they returned before: `user` and the new `additionalUserInfo` (`AdditionalUserInfo`:
  `isNewUser`, `providerId`, `profile`, `username`). Code that reads the result as an `AuthUser` is unchanged;
  **breaking** only for classes that implement or mock `FirebaseUserAuth` and return an `AuthUser` from these methods.
- The stored session has a version (2) and the whole record. Sessions stored by 0.1 and 0.2 are still restored;
  their user lacks the new fields until `reload`.
- `authStateChanges()` and `idTokenChanges()` (FlutterFire's streams): they start with the current user (after a
  `restore` in progress) and then follow sign-ins of another user and sign-outs, and, for `idTokenChanges()`, every
  new ID token. `userChanges()` is unchanged (it still does not emit the current user when listened to).
- `authStateReady()`, `beforeAuthStateChanged(callback, onAbort:)` (a throwing callback blocks the sign-in, sign-out
  or switch with `login-blocked`) and `updateCurrentUser(user)` (continue the session of a user of another
  instance with the same API key), from the JS SDK. The token stream Firestore follows (`onTokenChanged`) emits as
  before; `updateCurrentUser` is a user switch for it.
- `languageCode`, `setLanguageCode` (FlutterFire) and `useDeviceLanguage()` (JS SDK): the language of the emails
  the backend sends, in `X-Firebase-Locale` of every Identity Toolkit request. The device language is
  `Platform.localeName` on the VM and `navigator.languages` in a browser. New dependency: `web` (already in the
  dependency graph through `http`).
- `tenantId` (Identity Platform multi-tenancy), sent with the requests the JS SDK sends it with (sign-ins, action
  code requests, `createAuthUri`); a sign-in or `updateCurrentUser` of a user of another tenant throws
  `tenant-id-mismatch`, like the JS SDK.
- Email link sign-in: `sendSignInLinkToEmail(email:, actionCodeSettings:)`, `isSignInWithEmailLink(link)`,
  `signInWithEmailLink(email:, emailLink:)`, and `ActionCodeURL.parseLink(link)` (the JS SDK's
  `parseActionCodeURL`, with its Dynamic Link and iOS deep link unwrapping).
- Credentials: `AuthCredential`, `EmailAuthCredential` and `EmailAuthProvider.credential` /
  `credentialWithLink` (FlutterFire names), with `signInWithCredential`, `linkWithCredential` (an email and password
  or an email link to an anonymous user, for example) and `reauthenticateWithCredential`.
  `reauthenticateWithEmailAndPassword` stays, as a shortcut for the latter. New error codes from the JS SDK:
  `provider-already-linked`, `argument-error`, `login-blocked`, `tenant-id-mismatch`.
- Federated sign-in by token exchange: `OAuthCredential` and the providers `GoogleAuthProvider`,
  `AppleAuthProvider` (with `credentialWithIDToken` and its raw nonce), `FacebookAuthProvider`, `GithubAuthProvider`,
  `TwitterAuthProvider`, `MicrosoftAuthProvider`, `YahooAuthProvider` and `OAuthProvider(providerId)` (`oidc.*` and
  any other id), with FlutterFire's names. The app gets the provider's ID or access token itself;
  `signInWithCredential`, `linkWithCredential` and `reauthenticateWithCredential` exchange it through
  `accounts:signInWithIdp` with the request of the JS SDK. `unlink(providerId)` removes a sign-in method.
- `UserCredential.credential` and `FirebaseAuthException.credential`: the provider's credential the backend
  returned, so that `account-exists-with-different-credential` and `credential-already-in-use` can be recovered
  (sign in with the existing method, then link). New error codes: `no-such-provider`.
- `validatePassword(password)` with the new `PasswordPolicy` and `PasswordValidationStatus` (FlutterFire's names):
  the project's (or tenant's) policy is fetched once from `v2/passwordPolicy`, cached, and fetched again after
  `password-does-not-meet-requirements`, like the JS SDK. The Auth emulator does not implement the endpoint.
- Ready-made storages: `FileAuthStorage(path)` on the Dart VM (a JSON file written atomically and owner-only: on
  Linux and macOS it is written in a new staging directory with mode 0700, checked before anything is written, and
  renamed into place with mode 0600; on Windows it inherits the access list of its directory) and `WebAuthStorage.session()` / `WebAuthStorage.local()` in a browser
  (`sessionStorage` / `localStorage`), exported through conditional imports so that the library still compiles
  everywhere (each throws `UnsupportedError` on the other platform). Their documentation says what a stored refresh
  token exposes. `example/persistent_session.dart` uses `FileAuthStorage`. `FileAuthStorage` is exported from the
  main library: **breaking** for an app that declared its own `FileAuthStorage` (as the 0.2 docs and example
  suggested) in another library and imports both, which is now an `ambiguous_import`; rename the class or import
  the package with `hide FileAuthStorage`.
- Fix: a token refresh or an operation of the signed-in user (a profile update, a link, an unlink) that completed
  after another user signed in could write the tokens or data of the previous user into the new session and its
  storage. Each operation now belongs to the session it started in, and its result is dropped once another session
  is installed or the session is cleared. A sign-in that fails or is blocked no longer cancels the operations of the
  signed-in user, and `signOut()` after `dispose()` throws a `StateError` instead of deleting the stored session.
- Documentation: the README, the authentication guide and the API docs cover the new sign-in methods, streams,
  tenants, language, password policy and storages; a new example, `example/linking_and_email_link.dart`.

## 0.2.1

- Fix: signing in (`signInWithEmailAndPassword`, `signInWithCustomToken`) or reauthenticating
  (`reauthenticateWithEmailAndPassword`) with an account that has a second factor threw
  `internal-error` ("did not return tokens"). It now throws a `FirebaseAuthMultiFactorException`
  with the code `multi-factor-auth-required`, like the JS SDK, carrying the `pendingCredential` and
  the enrolled factors (`hints`, a list of the new `MultiFactorInfo`). Signing in with a second
  factor is still not supported. Additive; nothing changes for accounts without a second factor.

## 0.2.0

Breaking: the calls that FlutterFire's `firebase_auth` also has take its arguments. Every change
is in [docs/api_migration_0_2.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/api_migration_0_2.md).

- `FirebaseAuthException` (was `FirebaseAuthProviderException`) extends `FirebaseException`.
- `signInWithEmailAndPassword`, `createUserWithEmailAndPassword`,
  `reauthenticateWithEmailAndPassword`, `sendPasswordResetEmail` and `confirmPasswordReset`
  take named arguments; `userChanges()` is a method.
- Token providers implement `AuthTokenProvider` (was `InternalTokenProvider`) of
  `firebase_app_dart` 0.2.
- New, additive: `ServiceAccountKey` (parses a key file and signs with RS256, the signer of
  `OAuthTokenProvider.serviceAccount`) and `FirebaseUserAuth.emulatorOrigin` (the emulator host
  check of the constructor), for `firebase_admin_dart`. Nothing else changes.

## 0.1.1

Documentation and examples only. The library behaves exactly as in 0.1.0; the only code
change is the version in `FirebaseUserAuth.clientVersion`.

- Doc comments with compiling samples across the public API.
- A rewritten README, and one example per task in `example/`: email and password, account
  flows, custom tokens, a persistent session, a service account, Application Default
  Credentials and wiring into `cloud_firestore_dart`.

## 0.1.0

First version.

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
