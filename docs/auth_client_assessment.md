# Client auth: what we have, what the JS SDK has, and what is worth adding

Scope: what a signed-in end user can do through `firebase_auth_providers_dart` (`FirebaseUserAuth`). The server
side (custom tokens, admin user management) is covered elsewhere. Checked on 2026-11-16 against the local
branch `release/0.2.0` and `@firebase/auth` 1.13.10 (npm, published 2026-11-11; `firebase` 13.3.0).

## Status, 2026-11-18: tier 1 is done

Tier 1 below is implemented on the branch `wave/auth-tier1` (unreleased; the CHANGELOG has it under 0.3.0), one
commit per item, with unit tests against a fake backend for every request shape and error, and Auth emulator
tests for every flow the emulator implements. The rest of this document is the assessment as written on
2026-11-16; the tables mark what changed.

| # | Item | Done | Tested against the emulator |
| --- | --- | --- | --- |
| 1 | `multi-factor-auth-required` | yes (0.2.1) | no (needs SMS MFA set up in the emulator) |
| 2 | Full error map, HTTP 200 with `errorMessage`, `needConfirmation`, unknown `checkActionCode` operation | yes | `needConfirmation` yes; the rest unit only |
| 3 | User record (`providerData`, `metadata`, `phoneNumber`, `tenantId`), `UserCredential` with `additionalUserInfo` and `credential`, storage format v2 (reads 0.2) | yes | yes |
| 4 | `authStateChanges()`, `idTokenChanges()`, `authStateReady`, `beforeAuthStateChanged`, `updateCurrentUser` | yes | yes (Firestore's end-to-end auth tests pass too) |
| 5 | `languageCode`, `setLanguageCode`, `useDeviceLanguage` | yes | no: the emulator ignores `X-Firebase-Locale`; unit and Chrome |
| 6 | `tenantId` on requests, `tenant-id-mismatch` | yes | yes: **the emulator implements tenants** (created with its admin API) |
| 7 | Email link: send, check, sign in, link, reauthenticate, `ActionCodeURL.parseLink` | yes | yes |
| 8 | Credentials for email/password, email link, Google, Apple, Facebook, GitHub, Twitter, Microsoft, Yahoo, OIDC; `signInWithCredential`, `linkWithCredential`, `reauthenticateWithCredential`, `unlink`; recoverable credential on errors | yes | yes, all eight providers with fake tokens (see below) |
| 9 | Password policy, `validatePassword` | yes | no: the emulator answers 501 for `v2/passwordPolicy` |
| 10 | `FileAuthStorage` (VM, 0600) and `WebAuthStorage` (session, local) | yes | unit on the VM, Chrome (dart2js and dart2wasm) |

What the emulator showed, which settles three open points of the risks section:

- It **implements tenants** (`v2/projects/{p}/tenants` with `Authorization: Bearer owner`; tenant users, tokens with
  `firebase.tenant`, tenant action codes at `emulator/v1/projects/{p}/tenants/{t}/oobCodes`).
- It does **not** implement `v2/passwordPolicy` or `v2/accounts:revokeToken` (HTTP 501), and its multi-factor
  endpoints accept SMS enrolment only (no TOTP).
- Its `signInWithIdp` takes the provider's ID token, or its access token, as an unsigned JWT or a JSON object with a
  `sub` claim, for any provider id, and checks no signature, audience or nonce. So the requests and the flows of all
  eight providers ran against it, including `account-exists-with-different-credential` and its recovery, and
  `credential-already-in-use`; what the real backend verifies did not.

`signInWithIdp` for OIDC, Microsoft and Yahoo, from the JS SDK's source (`OAuthCredential.buildRequest`): the
request is the same for every provider, `requestUri: http://localhost`, `returnSecureToken: true`, and a form
encoded `postBody` of `id_token`, `access_token`, `oauth_token_secret`, `providerId` and `nonce` (the raw nonce) in
that order, or a `pendingToken` instead; `idToken` is added for a link and `autoCreate: false` for a
reauthentication. There is no `code` flow in `signInWithCredential` (the code flow exists only in the popup and
redirect handler, which sends the handler's URL as `requestUri`). The JS SDK does no client-id matching: the
backend checks the ID token's audience against the client id configured for the provider in the project. That,
Google's audience check, Apple's nonce check and real Facebook, GitHub, Twitter and Yahoo tokens can only be
confirmed against a real project.

API decisions, made additively:

- The sign-in methods return `UserCredential`, which **extends `AuthUser`**: 0.2 code that reads the result as an
  `AuthUser` compiles unchanged, and FlutterFire code that reads `result.user!.uid` and
  `result.additionalUserInfo` compiles too. Breaking only for code that implements or mocks `FirebaseUserAuth`.
- `ActionCodeOperation.unknown` (FlutterFire's `ActionCodeInfoOperation.unknown`) is breaking for a `switch` over
  the enum without a default; it is what returning an unknown operation "as given" needs.
- `userChanges()` keeps 0.2's behaviour (no initial event); the two new streams start with the current user, as
  FlutterFire's three do. Aligning `userChanges()` is a breaking change proposed for a later major version.
- The provider classes are static (`GoogleAuthProvider.credential(...)`), with FlutterFire's names and constants
  (`PROVIDER_ID`); they cannot be instantiated for `signInWithProvider`, which does not exist here.

FlutterFire coverage, recounted on `firebase_auth_platform_interface` 9.2.0 (the members that throw
`UnimplementedError`: 36 on `FirebaseAuthPlatform`, 20 on `UserPlatform`, 11 multi-factor, 1
`ConfirmationResultPlatform`; 68 as before): **38 of 68 (56 %)** can now be backed by this package, against the 39
expected. `FirebaseAuthPlatform`: 26 (5 plumbing, the three streams, `languageCode`, `setLanguageCode`,
`setPersistence` through the storages, `useAuthEmulator`, the four action code calls, `sendPasswordResetEmail`,
`sendSignInLinkToEmail`, `fetchSignInMethodsForEmail`, `createUserWithEmailAndPassword`, `signInAnonymously`,
`signInWithCredential`, `signInWithCustomToken`, `signInWithEmailAndPassword`, `signInWithEmailLink`, `signOut`);
missing: `setSettings`, `signInWithProvider`, `signInWithPopup`, `signInWithRedirect`, `getRedirectResult`,
`signInWithPhoneNumber`, `verifyPhoneNumber`, `revokeAccessToken`, `revokeTokenWithAuthorizationCode`,
`initializeRecaptchaConfig`. `UserPlatform`: 12 (`delete`, `getIdToken`, `getIdTokenResult`, `reload`,
`sendEmailVerification`, `verifyBeforeUpdateEmail`, `updateEmail`, `updatePassword`, `updateProfile`,
`linkWithCredential`, `reauthenticateWithCredential`, `unlink`); missing: the six provider, popup and redirect
variants, `linkWithPhoneNumber`, `updatePhoneNumber`. Multi-factor and `ConfirmationResult`: 0. The user fields the
interface expects (`providerData`, `metadata`, `tenantId`, `phoneNumber`) are there.

Still not run against the real service: everything. One smoke test against a throwaway project would confirm the
token exchange of each provider, the password policy endpoint, `X-Firebase-Locale`, and how a project that
enforces reCAPTCHA Enterprise treats these sign-ins.

## The answer

- We have a clean, well-tested REST client for anonymous, email/password and custom-token sign-in, token
  refresh, and the account operations around email and password. That is about a third of the JS SDK's surface
  and most of what a desktop, CLI or server user needs.
- Do not try to reach parity. About half of the remaining JS surface is REST and cheap; the other half needs a
  browser or native SDK (popup/redirect, phone, reCAPTCHA, SMS MFA) and does not belong in a pure-Dart package.
- Do now (about 7 to 9 agent days): surface `multi-factor-auth-required` instead of `internal-error`, the full
  user record, the three auth streams, language code, tenant id, email link sign-in, credentials with linking
  and unlinking (bring your own Google/Apple/OIDC ID token), password policy, and the full error map.
- Do on request: TOTP multi-factor, a loopback OAuth helper for desktop and CLI, Apple token revocation. Leave
  web popup/redirect, phone, SMS MFA and reCAPTCHA Enterprise to the official plugins.
- Worth it, but only tier 1, because it is what makes a Linux `firebase_auth` drop-in honest (37 thumbs-up on
  flutterfire#17338, no official Linux implementation) and the JS API barely moves (5 new exports since 2023).

## 1. What we have

### `firebase_auth_providers_dart` 0.2.0 (maintained)

Files: `lib/src/firebase_user_auth.dart` (1,242 lines), `auth_exception.dart`, `action_code.dart`,
`auth_storage.dart`, `auth_user.dart`, plus `oauth_token_provider.dart`, `rs256.dart` and `adc.dart` for service
accounts and ADC (server side, not in scope). About 2,250 lines of library code, 2,960 lines of tests in 9 files
(unit with a fake HTTP client and clock, VM against the Auth emulator, Chrome dart2js and dart2wasm against the
emulator), 9 runnable examples. Dart `^3.8.0`; deps `http`, `crypto`, `googleapis_auth`, `meta`,
`firebase_app_dart`. The main library has no `dart:io` and runs on the web; `adc.dart` is VM only.

`FirebaseUserAuth` (implements `AuthTokenProvider` of `firebase_app_dart`, so Firestore follows the user):

| Method | Endpoint |
| --- | --- |
| `signInAnonymously()` | `identitytoolkit v1 accounts:signUp` |
| `createUserWithEmailAndPassword(email:, password:)` | `accounts:signUp` |
| `signInWithEmailAndPassword(email:, password:)` | `accounts:signInWithPassword` |
| `signInWithCustomToken(token)` | `accounts:signInWithCustomToken` |
| `signOut()` | none (local only, like the JS SDK) |
| `deleteCurrentUser()` | `accounts:delete` |
| `sendPasswordResetEmail(email:, actionCodeSettings:)` | `accounts:sendOobCode` (PASSWORD_RESET) |
| `confirmPasswordReset(code:, newPassword:)` | `accounts:resetPassword` |
| `checkActionCode(code)`, `verifyPasswordResetCode(code)` | `accounts:resetPassword` (oobCode only) |
| `applyActionCode(code)` | `accounts:update` (oobCode) |
| `fetchSignInMethodsForEmail(email)` | `accounts:createAuthUri` |
| `sendEmailVerification(actionCodeSettings:)` | `accounts:sendOobCode` (VERIFY_EMAIL) |
| `verifyBeforeUpdateEmail(newEmail, ...)` | `accounts:sendOobCode` (VERIFY_AND_CHANGE_EMAIL) |
| `updateEmail`, `updatePassword`, `updateProfile(displayName:, photoUrl:)` | `accounts:update` |
| `reauthenticateWithEmailAndPassword(email:, password:)` | `accounts:signInWithPassword` + uid check |
| `reload()` | `accounts:lookup` |
| `getAccessToken(forceRefresh:)` | `securetoken v1 token` (refresh_token grant) |
| `restore()`, `forApp(app)`, `dispose()`, `currentUser`, `uid` | local |
| `userChanges()` (user stream), `onTokenChanged` (token stream) | local |

Behaviour worth keeping: token refreshed 5 minutes before expiry, on demand and proactively while someone
listens, with 30 s to 16 min backoff; session-ending errors sign the user out (`_logoutIfInvalidated`
equivalent); overlapping sign-ins are resolved by a generation counter (the later wins, the earlier throws
`cancelled`); sign-in completes only after listeners had a turn, so a Firestore write right after belongs to
the new user. `AuthStorage` (read/write of one JSON string holding the refresh token and the profile) with an
in-memory default; docs explain where to keep it safely. Emulator via `emulatorHost` or
`FIREBASE_AUTH_EMULATOR_HOST`, with host validation and the JS SDK's warning. Headers: `X-Client-Version`
(`Dart/DartCore/0.2.0/FirebaseCore-dart`), `X-Firebase-gmpid`, `X-Firebase-AppCheck` (token from the app's
provider; the package does not attest devices). Errors: `FirebaseAuthException extends FirebaseException`, about
35 server codes mapped like the JS `SERVER_ERROR_MAP`, the rest in kebab case.

Gaps inside what exists:

- **MFA users get `internal-error`.** When a user has a second factor, `signInWithPassword` returns 200 with
  `mfaPendingCredential` and no `idToken`. The JS SDK throws `multi-factor-auth-required`
  (`_performSignInRequest`); ours throws "did not return tokens". Cheap to fix, and needed before any MFA work.
- `AuthUser` has six fields. Missing: `providerData`, `metadata` (creation and last sign-in time),
  `phoneNumber`, `tenantId`, `refreshToken`, and `getAdditionalUserInfo` (`isNewUser`, profile).
- One user stream (`userChanges`). No separate `authStateChanges` (sign-in/out only), no `idTokenChanges` as a
  user stream, no `beforeAuthStateChanged`, no `authStateReady`.
- No `X-Firebase-Locale`, no `tenantId` in requests, no `X-Firebase-Client` heartbeat header.
- Only about a third of the JS SDK's 107 `AuthErrorCodes` are named; the kebab-case fallback covers most others.
- Nothing was run against the real service (stated honestly in the README).

### Legacy folders (not maintained, `sdk <3.0.0`, do not resolve on Dart 3)

| Folder | What | State |
| --- | --- | --- |
| `firebase_auth/firebase_auth_vm` 0.0.2 | port of the Android/iOS SDK: email/password, anonymous, custom token, email link, credentials for Google/Facebook/GitHub/Twitter/OAuth/SAML/Game Center, phone with a loopback reCAPTCHA page, link/unlink, reauth | 8,194 lines (3,648 generated `built_value`), no tests, pre-null-safety, `googleapis` 0.54 `identitytoolkit/v3/relyingparty` (the legacy API), `rxdart` 0.23, `http` 0.12, last code change 2021 |
| `firebase_auth/firebase_auth_dart` 0.0.1 | old `firebase_auth_platform_interface` 1.x bridge for Flutter desktop | 451 lines, Flutter, platform interface 1.x (current is 9.1.2) |
| `google_sign_in_dart` 0.0.8 | Google Sign-In for desktop: loopback HTTP server on 127.0.0.1, PKCE S256, token and code-exchange flows | 988 lines, pre-null-safety, `google_sign_in` 4.x; a newer copy is published from `long1eu/google_sign_in_dart` |

Salvage: no code, three ideas. (1) The loopback-plus-PKCE desktop flow of `google_sign_in_dart` is the right
shape for a desktop OAuth helper. (2) The legacy reCAPTCHA trick (`firebase_auth_vm/lib/src/util/http_server.dart`:
serve a page on localhost that loads the JS SDK, solve reCAPTCHA in the system browser, post the token back) is
the only pure-Dart route to phone auth on desktop; it pins firebasejs 7.10.0 and is brittle. (3) The provider
credential list in `auth_providers.dart` is a checklist. Everything else is cheaper to rewrite on v1 REST in the
style of the current package than to migrate (null safety, `built_value`, v3 API, no tests).

Files that look like credentials, listed by path only and not opened:
`firebase_auth/firebase_auth_vm/example/flutter/android/upload.key`,
`firebase_auth/firebase_auth_vm/example/flutter/android/app/google-services.json`,
`firebase_auth/firebase_auth_vm/example/flutter/ios/Runner/GoogleService-Info.plist`,
`google_sign_in_dart/example/android/upload.key`, `google_sign_in_dart/example/android/app/google-services.json`,
`google_sign_in_dart/example/ios/Runner/GoogleService-Info.plist`, and the `dev/tools` folder. Also
`firebase_auth/firebase_auth_dart/README.md` has a Web API key and an OAuth client id inline. Web API keys are
not secrets, but the owner may want to check what these files are and whether they should stay in history.

### Another pure-Dart option exists

`firebase_dart` 1.6.2 (appsup-dart, BSD-3, published 2026-03-27, 18,650 downloads in 30 days per
`docs/why_this_library.md`) has a fuller pure-Dart Auth: email link, `signInWithCredential`, phone with a
reCAPTCHA page on IO, multi-factor, tenants, language code (its README table). It lacks popup/redirect,
`linkWithCredential`, `verifyBeforeUpdateEmail` and `setPersistence`. It has no Firestore. It shows the tier 1
and part of tier 2 below are feasible; it is also a competitor for anyone who needs phone sign-in in pure Dart.

## 2. The reference: `firebase/auth` 1.13.10

Read from `dist/auth-public.d.ts` of the npm tarball: 128 exports. Compared with 1.0.0 (2023-07) only five are
new: `browserCookiePersistence` (beta), `PasswordPolicy`, `PasswordValidationStatus`, `revokeAccessToken`,
`validatePassword`. No passkey or WebAuthn API exists in the SDK (no match in the package), and Firebase Auth
has no native passkeys. Play Games and Game Center are not in the JS SDK (native only). REST endpoints the
bundle calls: `accounts:{signUp, signInWithPassword, signInWithCustomToken, signInWithEmailLink, signInWithIdp,
signInWithPhoneNumber, sendVerificationCode, sendOobCode, resetPassword, update, lookup, delete,
createAuthUri}`, `v2/accounts/mfaEnrollment:{start, finalize, withdraw}`, `v2/accounts/mfaSignIn:{start,
finalize}`, `v2/accounts:revokeToken`, `v2/passwordPolicy`, `v2/recaptchaConfig`, `v1/recaptchaParams`,
`v1/projects` (authorized domains), `securetoken v1/token`.

Public surface by area: email/password (create, sign in, `EmailAuthProvider`); email link
(`sendSignInLinkToEmail`, `isSignInWithEmailLink`, `signInWithEmailLink`, `EmailAuthProvider.credentialWithLink`,
`ActionCodeURL`, `parseActionCodeURL`); anonymous; custom token; phone (`signInWithPhoneNumber`,
`linkWithPhoneNumber`, `reauthenticateWithPhoneNumber`, `updatePhoneNumber`, `PhoneAuthProvider`,
`RecaptchaVerifier`, `ConfirmationResult`); federated (`GoogleAuthProvider`, `FacebookAuthProvider`,
`GithubAuthProvider`, `TwitterAuthProvider`, `OAuthProvider` for Apple, Microsoft, Yahoo and `oidc.*`,
`SAMLAuthProvider`); flows (`signInWithPopup`, `signInWithRedirect`, `getRedirectResult`, `link*`/`reauth*`
variants, `signInWithCredential`, `browserPopupRedirectResolver`); linking (`linkWithCredential`, `unlink`);
reauthentication (`reauthenticateWithCredential`); multi-factor (`multiFactor`, `getMultiFactorResolver`,
`PhoneMultiFactorGenerator`, `TotpMultiFactorGenerator`, `TotpSecret`); profile and email/password updates;
action codes (`applyActionCode`, `checkActionCode`, `confirmPasswordReset`, `verifyPasswordResetCode`,
`sendPasswordResetEmail`, `sendEmailVerification`, `verifyBeforeUpdateEmail`, `ActionCodeSettings`); tokens
(`getIdToken`, `getIdTokenResult` with claims, auth time, sign-in provider, second factor); persistence
(`inMemory`, `browserLocal`, `browserSession`, `indexedDBLocal`, `browserCookie` beta, `setPersistence`);
observers (`onAuthStateChanged`, `onIdTokenChanged`, `beforeAuthStateChanged`, `authStateReady`); `tenantId`;
`languageCode`, `useDeviceLanguage`; `initializeRecaptchaConfig` (reCAPTCHA Enterprise for email/password and
phone); `validatePassword`; `revokeAccessToken` (Apple); `connectAuthEmulator`; `initializeAuth` with
`Dependencies` (persistence, popup resolver, error map); `updateCurrentUser`; `getAdditionalUserInfo`;
`AuthErrorCodes` (107 codes).

## 3. Gap table

Have: yes / partly / no. Route: REST means plain HTTP in pure Dart on VM, Flutter and web. "Browser" means it
needs a browser page, a webview or a native SDK. Emulator column: what the Auth emulator documents
(https://firebase.google.com/docs/emulator-suite/connect_auth, read 2026-11-16).

| Capability | Have | Where / what it would take | Emulator |
| --- | --- | --- | --- |
| Email/password create and sign in | yes | `FirebaseUserAuth` | yes |
| Anonymous | yes | | yes |
| Custom token | yes | | yes (signature not checked) |
| Sign out, delete user | yes | | yes |
| Password reset, action codes, `ActionCodeSettings` | yes | no `dynamicLinkDomain` (deprecated upstream) | yes |
| Email verification, `verifyBeforeUpdateEmail` | yes | | yes |
| `updateEmail`, `updatePassword`, `updateProfile` | yes | | yes |
| `reload`, `getIdToken`, claims | yes | `getAccessToken` returns claims | yes |
| `fetchSignInMethodsForEmail` | yes | deprecated upstream | yes |
| Emulator | yes | `emulatorHost` | n/a |
| App Check header | yes | provider supplied by the app; no attestation | not testable |
| Reauthenticate | **yes (tier 1)** | `reauthenticateWithCredential` for every credential | yes |
| Persistence | **yes (tier 1)** | `FileAuthStorage` (0600) and `WebAuthStorage` (session, local) | n/a |
| `onAuthStateChanged` / `onIdTokenChanged` | **yes (tier 1)** | `authStateChanges()`, `idTokenChanges()` | n/a |
| `beforeAuthStateChanged`, `authStateReady`, `updateCurrentUser` | **yes (tier 1)** | local only | n/a |
| User record: `providerData`, `metadata`, `phoneNumber`, `tenantId` | **yes (tier 1)** | `accounts:lookup` after every sign-in, stored (format v2) | yes |
| `getAdditionalUserInfo` (`isNewUser`, profile) | **yes (tier 1)** | `UserCredential.additionalUserInfo` | yes |
| Error codes | **yes (tier 1)** | the full `SERVER_ERROR_MAP` and the JS messages | n/a |
| `multi-factor-auth-required` | **yes (0.2.1)** | `FirebaseAuthMultiFactorException` with the pending credential | yes (SMS MFA) |
| Language: `languageCode`, `useDeviceLanguage` | **yes (tier 1)** | `X-Firebase-Locale` header; `Platform.localeName` on VM, `navigator.languages` on web | ignored |
| Multi-tenancy `tenantId` | **yes (tier 1)** | `tenantId` in the bodies the JS SDK adds it to, `tenant-id-mismatch` | **yes** |
| Password policy, `validatePassword` | **yes (tier 1)** | `GET v2/passwordPolicy`, the JS checker | **no (501)** |
| Email link sign-in | **yes (tier 1)** | `sendSignInLinkToEmail`, `signInWithEmailLink`, `ActionCodeURL.parseLink`; the app handles the link | yes |
| `signInWithCredential` with an ID token you hold (Google, Apple, OIDC, Microsoft) | **yes (tier 1)** | `accounts:signInWithIdp` with `postBody` `id_token=...&providerId=...` (+ nonce) | yes (fake tokens) |
| Same with access tokens (Facebook, GitHub, Twitter OAuth 1, Yahoo) | **yes (tier 1)** | `signInWithIdp` with `access_token` (+ `oauth_token_secret`) | yes (a JSON access token with `sub` is accepted) |
| `linkWithCredential`, `unlink` | **yes (tier 1)** | `signInWithIdp` with `idToken`; `accounts:signUp` with an ID token for a password; `accounts:update` with `deleteProvider` | yes |
| `account-exists-with-different-credential`, `credential-already-in-use` with recoverable credential | **yes (tier 1)** | `FirebaseAuthException.email` and `.credential` | yes |
| TOTP multi-factor | **yes (unreleased)** | `startTotpEnrollment`, `finalizeTotpEnrollment`, `unenrollMultiFactor`, `AuthUser.enrolledFactors`, `FirebaseAuthMultiFactorException.resolver`; v2 `mfaEnrollment:start/finalize/withdraw` and `mfaSignIn:finalize` as JSON (the published protos lack the TOTP fields); needs Identity Platform; unit tests against a fake backend, not run against the real service | **no (SMS only)** |
| `revokeAccessToken` (Apple) | no | `v2/accounts:revokeToken` | **no (501)** |
| OAuth popup/redirect on the web | no | port the popup/redirect resolver with `package:web`: open `/__/auth/handler`, iframe messaging, event ids, authorized-domain check; 1,000+ lines of JS logic | yes (local handler) |
| Google sign-in on desktop/CLI | no | browser via loopback redirect + PKCE with the app's own "Desktop" OAuth client (`googleapis_auth` already does this on VM), then `signInWithIdp` with the ID token | exchange part yes |
| Microsoft, Yahoo, GitHub, generic OIDC on desktop/CLI | no | same loopback flow with the app's own registration at the provider; client id must match the Firebase provider config | exchange part yes |
| Sign in with Apple on desktop/CLI | no | Apple does not accept loopback redirect URLs; needs an HTTPS return page the app hosts, or a token from another package | no |
| SAML | no | only via the Firebase-hosted handler in a browser; out of reach without the web resolver | partly |
| Phone sign-in, `updatePhoneNumber`, `linkWithPhoneNumber` | no | needs a reCAPTCHA token (web: `package:web`; desktop: a localhost page in the system browser, legacy trick) or Play Integrity / APNs silent push (native only) | yes (codes printed, reCAPTCHA off) |
| SMS multi-factor | no | same reCAPTCHA problem as phone | yes |
| reCAPTCHA Enterprise for email/password (when the project sets ENFORCE) | no | web: load `enterprise.js` with `package:web`; VM: impossible without a browser. Projects that enforce it will reject our sign-ins with `missing-recaptcha-token` | no |
| `browserCookiePersistence` (beta, for SSR) | no | not relevant outside JS SSR | n/a |
| Passkeys | n/a | not in Firebase Auth | n/a |
| Play Games, Game Center | n/a | not in the JS SDK; native only | n/a |

Route for the hard ones, in one place: accept tokens obtained elsewhere and exchange them through
`signInWithIdp` (this works everywhere and is tier 1); on desktop and CLI, an optional VM-only helper that opens
the system browser and catches the redirect on 127.0.0.1 with PKCE (tier 2); on the web, `package:web` popup
(tier 2 at best, since Flutter web has the official plugin). Out of reach in pure Dart: phone and SMS MFA on
mobile (Play Integrity, APNs), reCAPTCHA Enterprise on the VM, Apple without a hosted page, Game Center and
Play Games.

## 4. Effort and order

Sizes assume an agent writes the code and a reviewer checks it, in the style of the current package (doc
comments, fakes, emulator tests). Lines include tests.

### Tier 1: do now, cheap and widely needed (about 7 to 9 agent days, about 3,000 lines)

| # | Item | Size | Tests |
| --- | --- | --- | --- |
| 1 | Throw `multi-factor-auth-required` with the pending credential and factor list instead of `internal-error` | 2 h, 80 lines | unit; emulator with SMS MFA enabled |
| 2 | Full error map: all `SERVER_ERROR_MAP` entries and their messages | 3 h, 200 lines | unit |
| 3 | Full user record: `providerData`, `metadata`, `phoneNumber`, `tenantId`; `UserCredential`-like result with `additionalUserInfo` and `operationType`; stored with the session (storage format v2, reads v1) | 1 day, 500 lines | unit, emulator |
| 4 | `authStateChanges()`, `idTokenChanges()` (user streams), `beforeAuthStateChanged`, `authStateReady`, `updateCurrentUser` | 0.5 day, 250 lines | unit |
| 5 | `languageCode`, `useDeviceLanguage()` (`X-Firebase-Locale`) | 2 h, 80 lines | unit (headers) |
| 6 | `tenantId` on requests and the token check (`tenant-id-mismatch`) | 0.5 day, 150 lines | unit; emulator tenants unverified |
| 7 | Email link: `sendSignInLinkToEmail`, `isSignInWithEmailLink`, `signInWithEmailLink`, link and reauth with an email-link credential, `parseActionCodeURL` | 1 day, 400 lines | unit, emulator |
| 8 | Credentials: `EmailAuthProvider`, `GoogleAuthProvider`, `FacebookAuthProvider`, `GithubAuthProvider`, `TwitterAuthProvider`, `OAuthProvider` (Apple with raw nonce, Microsoft, Yahoo, `oidc.*`); `signInWithCredential`, `linkWithCredential`, `reauthenticateWithCredential`, `unlink`; errors carrying the recoverable credential | 2.5 days, 1,000 lines | unit; emulator for JWT ID tokens (fake unsigned tokens), unit only for Facebook/GitHub/Twitter |
| 9 | Password policy: `validatePassword` with cached `v2/passwordPolicy`, refresh on `password-does-not-meet-requirements` | 0.5 day, 300 lines | unit; emulator support unverified |
| 10 | Ready-made storages: owner-only file storage (VM) and `sessionStorage` (web) | 0.5 day, 200 lines | unit, Chrome |

Then update the README table, the authentication guide and the examples (0.5 day). One live smoke test
against a throwaway real project (owner action: it needs a project and its Web API key) would remove the
"emulator only" caveat for the whole package.

### Tier 2: do when a user asks (about 8 to 14 agent days)

| Item | Size | Tests |
| --- | --- | --- |
| TOTP multi-factor: enrol, sign in with the resolver, unenrol, list factors, QR URL (`openInOtpApp` stays in a Flutter adapter) | 2 days, 600 lines | unit; real project with Identity Platform (emulator TOTP not documented) |
| Desktop/CLI OAuth helper (`lib/src/oauth_loopback/`, VM only): browser open, 127.0.0.1 redirect, PKCE, state, timeout; presets for Google and generic OIDC; then tier 1 credentials. **Done (unreleased)**: `signInWithOAuthLoopback`, `authorizeWithOAuthLoopback`, `OAuthLoopbackProvider.google` / `.oidc` / `.discover`; direct code exchange or through `google_sign_in_dart`'s exchange endpoint contract | about 870 lines, plus 550 of tests | unit with an in-process fake IdP (19 tests); not run with a real Google client or project |
| `revokeAccessToken` (Apple) | 2 h, 60 lines | unit |
| reCAPTCHA Enterprise token on the web for projects that enforce it | 2 days, 400 lines | Chrome with a real site key (owner) |
| Web popup/redirect resolver with `package:web` | 5 to 8 days, 1,500 lines | Chrome against the emulator's handler; real project for authorized domains |

### Tier 3: do not do in pure Dart

Phone sign-in and SMS multi-factor (reCAPTCHA in a browser, or Play Integrity and APNs, which are native SDK
features); reCAPTCHA Enterprise on the VM; Sign in with Apple without a hosted HTTPS page; SAML outside the web;
Play Games and Game Center; passkeys (not a Firebase feature). Point users to the official plugins on Android,
iOS, macOS and web, or to `firebase_dart` for phone auth in pure Dart. The legacy localhost reCAPTCHA page could
be revived for desktop phone auth if a paying user insists; budget 3 to 5 days and expect breakage when Google
changes reCAPTCHA.

## 5. FlutterFire drop-in

I counted the members of `firebase_auth_platform_interface` 9.1.2 (current, pub.dev, 2026-11-16) that throw
`UnimplementedError` by default: 36 on `FirebaseAuthPlatform` (including plumbing such as `delegateFor`,
`setInitialValues`, `sendAuthChangesEvent`), 20 on `UserPlatform`, 11 on the multi-factor classes (5 user and
resolver, 1 phone assertion, 5 TOTP), 1 on `ConfirmationResultPlatform`: 68. The web-only
`RecaptchaVerifierFactoryPlatform` adds 6, left out. The earlier estimate (about 25 of 56 covered, about 30
missing) used a different count but the same proportion; it holds.

| Stage | Covered of 68 | What it adds |
| --- | --- | --- |
| Today | about 32 (45 %) | 12 plumbing and stream members, 10 auth calls, 9 user calls, email-only reauth |
| After tier 1 (recounted 2026-11-18, see the status above) | 38 (56 %) | `languageCode`, `setLanguageCode`, `sendSignInLinkToEmail`, `signInWithEmailLink`, `signInWithCredential`, `linkWithCredential`, `unlink`, full `reauthenticateWithCredential`; and the user fields the interface expects (`providerData`, `metadata`, `tenantId`) |
| After tier 2 on Linux | about 54 (79 %) | 10 TOTP/MFA members, `signInWithProvider`, `linkWithProvider`, `reauthenticateWithProvider` through the loopback helper, 2 revoke calls |
| After tier 2 on web | about 61 | plus the 7 popup/redirect members (but the official web plugin exists) |
| Never | 7 | phone: `verifyPhoneNumber`, `signInWithPhoneNumber`, `linkWithPhoneNumber`, `updatePhoneNumber`, `confirm`, phone MFA assertion, `initializeRecaptchaConfig` |

What it means on Linux: `firebase_auth` 7.0.1 has no Linux implementation, so today every call there fails. A
Dart implementation registered for Linux (`dartPluginClass`) turns that into: after tier 1, email/password,
anonymous, custom token, email link, account management and linking of tokens the app already holds work;
`signInWithProvider` throws `unimplemented`. After tier 2, Google and OIDC sign-in work through the system
browser. Phone never works. That is roughly what Invertase's `firebase_auth_desktop` offered before it stopped
in 2022. It also needs a `firebase_core` Linux implementation, which is part of the separate drop-in work.

Status 2026-11-20: `firebase_auth/firebase_auth_dart_platform` 0.1.0 (unreleased) now exists: the official
`firebase_auth` platform interface on top of `FirebaseUserAuth`, registered for Linux and opt-in elsewhere,
with the `firebase_core` Linux piece. It throws `unimplemented` for `signInWithProvider`, `linkWithProvider`,
`reauthenticateWithProvider`, popup and redirect, phone, multi-factor (`User.multiFactor`, TOTP), token
revocation, and Play Games and Game Center credentials. Not yet run in a Linux desktop build or against a
production project. It needs `firebase_auth_providers_dart` 0.3.1, which is not released yet.

## 6. Is it worth it?

Who needs client auth from this package:

- Flutter on Linux desktop and embedded Linux: nothing official exists. flutterfire#17338 (Linux for
  `firebase_auth`) is open with 37 thumbs-up, last updated 2026-07-30; the community PR adding Linux was closed
  unmerged on 2026-07-23 (#18461), both checked with the GitHub API on 2026-11-16. Small but real demand, and the
  drop-in Firestore plan in `docs/why_this_library.md` already says it needs auth with it.
- Dart servers, CLIs and workers acting as a user under security rules (custom token or a stored refresh
  token). Covered today; tier 1 adds tenants and the user record.
- Tests: `dart test` against the emulator with real sign-in. Covered today; tier 1 adds linking and email link,
  which the emulator supports.

Smallest honest set: tier 1. Today a user with a second factor gets `internal-error`, tenant projects cannot
sign in, and an app holding a Google ID token from another package cannot use it. Tier 1 closes those with REST
only, no new platform code, and testable on the emulator. Leave popup/redirect, phone, SMS MFA and reCAPTCHA to
the official plugins, and say so in the README.

Maintenance: low. The JS public API added 5 exports in 3 years and the v1 REST endpoints are stable. Budget
half a day per quarter to diff `auth-public.d.ts` and `SERVER_ERROR_MAP` between npm versions (a small script
can do the diff). The real cost is elsewhere: no run against the real service yet, and one maintainer.

Do not do tier 2 speculatively. The loopback OAuth helper is the first tier 2 item to pick up when a Linux user
asks for Google sign-in; TOTP when someone on Identity Platform asks.

## Risks and what is unverified

- Emulator coverage of tenants, password policy, TOTP and `revokeToken` is not documented on the connect page;
  I did not run the emulator. If it lacks them, those items need a real project to test. *(Settled 2026-11-18:
  tenants yes; password policy and `revokeToken` no, HTTP 501; TOTP no.)*
- `signInWithIdp` with `code` for OIDC code flow, and the client-id matching rules for Microsoft and Yahoo
  outside the hosted handler, are from memory of the REST API, not checked against current docs. *(Settled
  2026-11-18 from the JS source: no code flow in `signInWithCredential`; no client-side matching, the backend
  checks the audience.)*
- reCAPTCHA Enterprise enforcement for email/password: I confirmed the JS SDK handles `MISSING_RECAPTCHA_TOKEN`
  and sends `captchaResponse` with `CLIENT_TYPE_WEB`; I did not confirm how a non-web client is treated when a
  project sets ENFORCE. If it is rejected, VM users of such projects cannot sign in with a password at all.
- Effort sizes are estimates from comparable work in this repo (the account-management wave), not measured.
- The 68-member count was taken with a grep for `UnimplementedError`; a member without a default body could be
  missed.
- Nothing in this package has run against the real Firebase Auth service.

Sources (all read 2026-11-16): `@firebase/auth` 1.13.10 and 1.0.0 tarballs from registry.npmjs.org;
`firebase_auth_platform_interface` 9.1.2 and `firebase_dart` 1.6.2 archives from pub.dev;
https://firebase.google.com/docs/emulator-suite/connect_auth;
https://github.com/firebase/flutterfire/issues/17338; https://github.com/firebase/flutterfire/pull/18461;
`docs/why_this_library.md` in this repository.
