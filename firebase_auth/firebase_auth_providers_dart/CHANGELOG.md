## Unreleased

- Browser sign-in for desktop apps and command line tools (VM only): `FirebaseUserAuth.signInWithOAuthLoopback`
  and `authorizeWithOAuthLoopback`, with `OAuthLoopbackProvider.google`, `.oidc` and `.discover`. The system
  browser (`openInSystemBrowser`, or a `presenter` of your own) runs the authorization code flow with PKCE (S256),
  a random `state` (compared in constant time) and a nonce; the redirect comes back to a one-shot server on
  127.0.0.1 that answers 404 to any other path and is always closed (success, error or `timeout`). The code is
  exchanged at the token endpoint, or through an `exchangeEndpoint` with the request and answer of
  `google_sign_in_dart`'s code exchange endpoint. The result (`OAuthLoopbackResult`) has the provider's tokens and
  a ready `OAuthCredential`. On the web these throw an `UnsupportedError`. New error codes: `timeout`,
  `user-cancelled`, `oauth-state-mismatch`, `invalid-oauth-response`, `invalid-oauth-provider`. Tested against an
  in-process fake identity provider only.
- A backend error ends the session only when it comes with HTTP 400: `invalidatesSession` is false for a 5xx that
  names `TOKEN_EXPIRED`, `USER_DISABLED`, ..., and the user stays signed in.
- When a request with the ID token is rejected with `TOKEN_EXPIRED` or `INVALID_ID_TOKEN`, the token is refreshed
  once to check the session (as in the iOS SDK): the user is signed out only when the refresh says that the session
  ended, and otherwise the request is sent once more with the new token.
- Token lifetimes from the backend are bounded as in the iOS SDK: an `expiresIn` outside of (0, 24 h], missing or
  not a number counts as one hour, an `exp` claim more than 24 h ahead is not trusted, and a proactive refresh
  delay beyond 24 h refreshes right away.

- `FirebaseUserAuth.revokeToken(authorizationCode)` revokes the Sign in with Apple token of the signed-in user
  with Apple's authorization code (`v2/accounts:revokeToken`, like `revokeToken(withAuthorizationCode:)` of the
  iOS SDK). The user stays signed in. Throws `null-user` when nobody is signed in. Tested with a fake HTTP client
  only.

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
