# Auth parity with the JS SDK

This document compares the public API of the JS SDK's `firebase/auth` with two Dart packages:

- **The Dart client**: `firebase_auth/firebase_auth_providers_dart`, as of this branch. It has TOTP, the loopback exchange, link, reauthentication and GitHub flows, the request timeout and the session rules.
- **The FlutterFire shim**: `firebase_auth/firebase_auth_dart_platform`, as on main.

The client was audited on 2026-11-20 against firebase-js-sdk `main` at a086865 (`packages/auth`: `index.ts` and what it re-exports). The shim is described as on main. Both Dart packages were checked against their code, not their READMEs. Line numbers are from the audit and will drift.

The Status column describes the Dart client, and the Shim column holds the shim's own result. Status is one of:
- **same**
- **different**: the notes say how
- **missing**
- **n/a outside a browser**: the notes say why

Path shorthand:
- `FUA` and `F` mean `lib/src/firebase_user_auth.dart`.
- `CRED` means `lib/src/auth_credential.dart`.
- `D:` means `firebase_auth_providers_dart/lib/src`.
- `S:` means the shim's `lib/src`.
- `J:` means `packages/auth/src` in the JS SDK.
- A bare file name such as `auth_user.dart` is in the client's `lib/src`, except where the shim column names a shim file.

## Sign-in methods

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| signInAnonymously | `signInAnonymously()` FUA:570 | `signInAnonymously` firebase_auth.dart:285 | same | |
| createUserWithEmailAndPassword | `createUserWithEmailAndPassword({email,password})` FUA:596 | positional args, firebase_auth.dart:289 | same | Named vs positional is only a FlutterFire convention. |
| signInWithEmailAndPassword | `signInWithEmailAndPassword({email,password})` FUA:579 | firebase_auth.dart:302 | same | |
| sendSignInLinkToEmail | `sendSignInLinkToEmail({email, actionCodeSettings})` FUA:973 | firebase_auth.dart:355 | same | |
| isSignInWithEmailLink | `isSignInWithEmailLink` FUA:998 (via `ActionCodeURL.parseLink`) | firebase_auth.dart:335 | same | |
| signInWithEmailLink | `signInWithEmailLink({email,emailLink})` FUA:1019 | firebase_auth.dart:325 | same | Tenant mismatch check matches JS. JS also allows omitting email (read from storage); Dart requires it, as FlutterFire does. |
| signInWithCustomToken | `signInWithCustomToken` FUA:614 | firebase_auth.dart:312 | same | |
| signInWithCredential | `signInWithCredential` FUA:1061 | firebase_auth.dart:316 | different | Client handles OAuth/email credentials only. Shim throws for Phone, Play Games and Game Center credentials (convert.dart `clientCredentialOf`). |
| linkWithCredential | FUA:1108 | user.dart:47 | same | Re-checks provider-already-linked after a reload, like JS `_assertLinkedStatus`. |
| reauthenticateWithCredential | FUA:1151 | user.dart:56 | same | Maps user-not-found and uid mismatch to `user-mismatch`, like JS. |
| unlink | `unlink(providerId)` FUA:1216 | user.dart:78 | same | |
| signInWithPopup | none; native alternative `signInWithOAuthLoopback(OAuthLoopbackProvider)` FUA:1086 (PKCE, loopback redirect, system browser) | throws `unimplemented` firebase_auth.dart:394 | n/a outside a browser | Needs `window.open`. The loopback flow is the native equivalent, but it is a different API (`OAuthLoopbackProvider`, not `AuthProvider`). The shim runs it from `signInWithProvider` (see Shim coverage). |
| linkWithPopup | `linkWithOAuthLoopback` FUA:1239 | throws user.dart:126 | n/a outside a browser | |
| reauthenticateWithPopup | `reauthenticateWithOAuthLoopback` FUA:1263 | throws user.dart:134 | n/a outside a browser | |
| signInWithRedirect | none | throws firebase_auth.dart:398 | n/a outside a browser | Page navigation. |
| linkWithRedirect | none | throws user.dart:130 | n/a outside a browser | |
| reauthenticateWithRedirect | none | throws user.dart:139 | n/a outside a browser | |
| getRedirectResult | none | throws firebase_auth.dart:402 | n/a outside a browser | |
| browserPopupRedirectResolver | none | none | n/a outside a browser | Resolver for DOM operations. |
| signInWithPhoneNumber | none | throws `noPhone` firebase_auth.dart:406 | missing | Needs reCAPTCHA or an app verifier, which is a browser or native SDK on real projects. The emulator and test numbers need no verifier, so the REST `sendVerificationCode` and `signInWithPhoneNumber` calls could be done. |
| linkWithPhoneNumber | none | throws user.dart:143 | missing | Same as above. |
| reauthenticateWithPhoneNumber | none | none (FlutterFire has no such method) | missing | |
| updatePhoneNumber | none | throws user.dart:149 | missing | |
| RecaptchaVerifier | none | `RecaptchaVerifierFactoryPlatform` is only a parameter type | n/a outside a browser | DOM widget. |
| initializeRecaptchaConfig | none | throws firebase_auth.dart:426 | n/a outside a browser | reCAPTCHA Enterprise. |
| signOut | FUA:625 | firebase_auth.dart:339 | same | |
| deleteUser | `deleteCurrentUser()` FUA:646 | user.dart:31 | different | Named differently, and it is on the auth instance, not the user. |
| fetchSignInMethodsForEmail | FUA:746 | firebase_auth.dart:383 | same | Deprecated in JS. |
| getAdditionalUserInfo | `UserCredential.additionalUserInfo` (auth_user.dart:269) | convert.dart `additionalUserInfoOf` | different | A field, not a function. `isNewUser`, `providerId`, `profile`, `username` are all present. |
| updateCurrentUser | FUA:480 (runs beforeAuthStateChanged callbacks; rejects users of another API key) | none (the setter is a no-op, firebase_auth.dart:148) | different | Shim drops it. FlutterFire has no public equivalent either. |
| onAuthStateChanged | `authStateChanges()` FUA:437 | firebase_auth.dart:203 | different | Stream instead of observer and unsubscribe. Emits the current user on listen, as JS does. |
| authStateReady | `authStateReady()` FUA:448 | none (FlutterFire has none) | same | |
| setPersistence | `setStorage(AuthStorage)`: moves the session to the new storage and deletes it from the old one | `setPersistence` firebase_auth.dart:180 maps NONE and SESSION to in-memory and LOCAL to file | different | Takes a storage object rather than a `Persistence` name. |
| inMemoryPersistence | `InMemoryAuthStorage` auth_storage.dart:66 (default) | via setPersistence | same | |
| browserLocalPersistence / browserSessionPersistence / indexedDBLocalPersistence / browserCookiePersistence | `WebAuthStorage` (`storage/web_auth_storage_web.dart`) and `FileAuthStorage` (`storage/file_auth_storage_io.dart`) | `defaultStorage()` storage.dart | different | Equivalent in purpose. The web storage is not selectable by name, and there is no cookie variant. |
| revokeAccessToken | `revokeAccessToken(token)` FUA:774 (`tokenType: 'ACCESS_TOKEN'`, `tenantId` sent); also `revokeToken(authorizationCode)` FUA:754 (`tokenType: '3'`, as the iOS SDK, `tenantId` sent) | `revokeAccessToken` and `revokeTokenWithAuthorizationCode` call the client | different | Same `v2/accounts:revokeToken` endpoint and body as JS. With no signed-in user the client throws `null-user`; JS returns silently. |
| sendPasswordResetEmail, confirmPasswordReset, verifyPasswordResetCode, checkActionCode, applyActionCode, sendEmailVerification, verifyBeforeUpdateEmail, updateProfile, updateEmail, updatePassword, reload | all present (FUA:665 to 828, 1471) | all wired (firebase_auth.dart:344 to 380, user.dart) | same | Listed for completeness; account management is probably another auditor's area. |

## Providers

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| AuthCredential (providerId, signInMethod, toJSON, fromJSON) | abstract `AuthCredential` CRED:15 (providerId, signInMethod) | FlutterFire `AuthCredential` | different | `EmailAuthCredential` and `OAuthCredential` have `toJson`/`fromJson` (rows below); the abstract class has none. |
| OAuthCredential | `OAuthCredential` CRED:110 (idToken, accessToken, secret, rawNonce, pendingToken, appleFullPersonName) | `DartOAuthCredential` wraps it (convert.dart) | different | Has `pendingToken` and Apple name, which JS lacks. `toJson` is in the JS shape and leaves the Apple name out. |
| OAuthCredential.fromJSON | `OAuthCredential.fromJson` CRED:249 | none | different | Returns null for JSON that is not a credential, as JS does. Text that is not JSON throws `FormatException`. A field that is present and not a string also gives null. |
| EmailAuthCredential | CRED:33 (email, password, emailLink) | converted both ways in convert.dart | same | |
| EmailAuthProvider | `abstract final class` CRED:64; `credential`, `credentialWithLink`, `PROVIDER_ID='password'`, `EMAIL_PASSWORD_SIGN_IN_METHOD`, `EMAIL_LINK_SIGN_IN_METHOD` | FlutterFire's own | same | Named args, not positional. |
| PhoneAuthCredential | none | throws on conversion (convert.dart `clientCredentialOf`) | missing | |
| PhoneAuthProvider (credential, verifyPhoneNumber, PROVIDER_ID) | none | `verifyPhoneNumber` throws firebase_auth.dart:412 | missing | JS's is browser-only (reCAPTCHA). The REST calls themselves work without a browser on the emulator. |
| GoogleAuthProvider | `abstract final class` CRED:256; `credential({idToken,accessToken})`, `PROVIDER_ID`, `GOOGLE_SIGN_IN_METHOD` | FlutterFire's own | different | JS is instantiable (`new GoogleAuthProvider()`, `addScope`, `setCustomParameters`) and has `credentialFromResult`, `credentialFromError`, `credentialFromJSON`. Dart has none of these, because there is no popup flow. |
| GithubAuthProvider | CRED:310; `credential(accessToken)` | same | same | Instance methods missing, as above. |
| FacebookAuthProvider | CRED:297; `credential(accessToken)` | same | same | |
| TwitterAuthProvider | CRED:323; `credential({required accessToken, required secret})` | same | different | JS takes `(token, secret)` positionally. |
| OAuthProvider | `class OAuthProvider(providerId)` CRED:218; `credential({accessToken,secret,idToken,rawNonce,signInMethod})` | FlutterFire's own | different | JS also has `addScope`, `setScopes`, `getScopes`, `setCustomParameters`, `credentialFromResult`, `credentialFromError`. `credentialFromJson` exists (see below). Dart has `secret` and `signInMethod` instead of JS `OAuthCredentialOptions {idToken, accessToken, rawNonce}`. `pendingToken` is not accepted by `credential`. |
| OAuthCredentialOptions (type) | none (named args instead) | none | different | |
| SAMLAuthProvider | none | none | missing | `new OAuthProvider('saml.x')` does build a credential shape, but SAML is a redirect/popup flow. It has no `credential` factory in JS either, so it is practically n/a outside a browser. |
| CustomParameters (type) | `OAuthLoopbackProvider.customParameters` (`oauth_loopback.dart:275`) | `setCustomParameters` and `addScope` of the FlutterFire provider are added to the registered loopback provider's request (`S:oauth_provider.dart` `oauthRequestOf`, `S:firebase_auth.dart` `loopbackProviderFor`) | different | The client has them only on the loopback provider. |
| AppleAuthProvider, MicrosoftAuthProvider, YahooAuthProvider | CRED:270, :338, :353 | FlutterFire's own | same | Not exported by JS `index.ts` (JS uses `OAuthProvider('apple.com')`). Dart extras, in line with FlutterFire. |
| ProviderId, SignInMethod, OperationType enum maps | `PROVIDER_ID` and `*_SIGN_IN_METHOD` constants per provider; `ActionCodeOperation` enum (action_code.dart:116); `OperationType` enum (auth_user.dart:274) | none | different | `OperationType` (signIn, link, reauthenticate) is there. There is no aggregate `ProviderId` or `SignInMethod` map. |
| ActionCodeURL, parseActionCodeURL | `ActionCodeURL.parseLink` action_code.dart:270 | none | different | Static factory, returns null on failure. |
| OAuthLoopbackProvider (no JS peer) | `OAuthLoopbackProvider.google/.github/.oidc/.discover` oauth_loopback.dart:32, 95, 122, 155; `copyWith(scopes:, customParameters:)` | exported; passed to `FirebaseAuthDart.use(oauthProviders:)` for `signInWithProvider` and the user's link and reauthenticate variants | n/a | A Dart-only native OAuth flow; the closest thing to popup. |

## User and profile

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| User uid, email, emailVerified, displayName, photoURL, phoneNumber, isAnonymous | `AuthUser` fields | `userDetailsOf` (convert.dart) | same | auth_user.dart:37-62; `photoUrl` plus a `photoURL` getter (:56) |
| User.tenantId | `AuthUser.tenantId` | convert.dart:328 | same | auth_user.dart:62 |
| User.metadata | `UserMetadata` with `DateTime` | converted to millis (convert.dart:329) | different | JS `creationTime`/`lastSignInTime` are strings; auth_user.dart:181 |
| User.providerData / UserInfo | `List<UserInfo>` | passed through | same | auth_user.dart:69, :127 |
| User.refreshToken | none public; `getAccessToken` only | — | missing | firebase_user_auth.dart:1482 |
| User.providerId (`'firebase'`) | `AuthUser.providerId` auth_user.dart:80 | — | same | A getter that returns `'firebase'`. |
| updateProfile({displayName, photoURL}) | `updateProfile({displayName, photoUrl})` on the client | user.dart:93 | different | `''` removes, null keeps; firebase_user_auth.dart:828 |
| updateEmail | `updateEmail` on the client | user.dart:82 | same | firebase_user_auth.dart:812 |
| updatePassword | `updatePassword` on the client | user.dart:86 | same | firebase_user_auth.dart:819 |
| verifyBeforeUpdateEmail | `verifyBeforeUpdateEmail(newEmail, actionCodeSettings)` | user.dart:103 | same | firebase_user_auth.dart:789 |
| reload | `reload` | user.dart:67 | same | firebase_user_auth.dart:1471 |
| delete | `deleteCurrentUser` | user.dart:31 | same | firebase_user_auth.dart:646 |
| User.toJSON | `AuthUser.toJson()` auth_user.dart:88 | — | different | Same keys as JS, but no `stsTokenManager`, `apiKey` or `appName`, so it cannot restore a session. |
| getAdditionalUserInfo(cred) | `UserCredential.additionalUserInfo` (isNewUser, providerId, profile, username) | passed through (convert.dart:306) | different | a field, not a function; auth_user.dart:207-227 |
| UserCredential {user, providerId} | `UserCredential extends AuthUser` + `user`, `credential` | `DartUserCredential` (user.dart:154) | different | No `providerId`, by design: `UserCredential` extends `AuthUser`, whose `providerId` is `'firebase'` as on a JS `User`. The sign-in provider is in `credential.providerId` and `additionalUserInfo.providerId`. auth_user.dart:245-274 |
| UserCredential.operationType | `UserCredential.operationType` (`OperationType`: signIn, link, reauthenticate) auth_user.dart:337 | none | same | |

## Tokens

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| getIdToken(user, forceRefresh) | `getAccessToken({forceRefresh})` FUA:1482 returns `GetTokenResult`; `.token` is the string | `DartUser.getIdToken` user.dart:34 | different | Different name (it is the `AuthTokenProvider` interface). Throws `FirebaseNoSignedInUserException` rather than `null-user`. |
| getIdTokenResult(user, forceRefresh) | `getAccessToken` returns `GetTokenResult` (firebase_core `internal/auth.dart`) | `idTokenResultOf` convert.dart:349 | different | See field rows below. |
| IdTokenResult.token | `GetTokenResult.token` | `token` | same | |
| IdTokenResult.claims | `claims` map | `claims` | same | |
| IdTokenResult.issuedAtTime | `issuedAtTimestamp` (DateTime; 1970 if absent) | `issuedAtTimestamp` ms | different | JS returns a UTC string; Dart returns a DateTime and never null. |
| IdTokenResult.authTime | `authTimestamp` (1970 if absent) | `authTimestamp` | different | Same. |
| IdTokenResult.expirationTime | `expirationTimestamp` | `expirationTimestamp` | different | Same. |
| IdTokenResult.signInProvider | `signInProvider` (also falls back to a top-level claim) | `signInProvider` | same | |
| IdTokenResult.signInSecondFactor | none on `GetTokenResult` | read from `firebase.sign_in_second_factor` claim, convert.dart:365 | different | Missing in the client (can be read through `claims['firebase']`), present in the shim. |
| (no JS peer) `extraClaims` | `GetTokenResult.extraClaims` | none | n/a | Dart extra. |
| onIdTokenChanged | `idTokenChanges()` FUA:442 (current user on listen, then every new token) and `onTokenChanged` FUA:425 (raw token stream) | firebase_auth.dart:207 | different | Streams, not observers. Two APIs in the client (see Ideas). |
| onAuthStateChanged | `authStateChanges()` FUA:437 | firebase_auth.dart:203 | same | |
| (FlutterFire `userChanges`) | `userChanges()` FUA:419 | firebase_auth.dart:220 (merges two streams, deduplicated per turn) | same | JS has no such stream; Dart extra. |
| beforeAuthStateChanged | `beforeAuthStateChanged(cb, {onAbort})` FUA:464; throws `login-blocked`, reverse-order onAbort, skipped on backend session end | none (FlutterFire has no such API) | different | In the client, not in the shim. Needs a shim extension type to reach it. |
| Token refresh (proactive) | `refreshBefore` 5 min, back-off 30 s to 16 min, only while a listener exists (FUA:2180) | uses client | same | JS refreshes while any listener is attached too. |
| Token refresh (reactive, session invalidation) | `user-disabled` and `user-token-expired` sign the user out (FUA:1548); also `_refreshAfterRejection` and a 1 h and 24 h lifetime clamp (`_standardTokenLifetime`) | uses client | different | The lifetime clamp and the refresh after a rejection have no direct JS counterpart. |
| reload | FUA:1471 | user.dart:67 | same | |
| requestTimeout (JS `networkTimeout`, 30 s) | `requestTimeout` ctor arg, default 30 s, FUA:141 and :2022 | not passed | different | Fails with `network-request-failed`, like JS. The shim constructs without it. |
| Auth.tenantId, languageCode, useDeviceLanguage | `tenantId` FUA:243, `languageCode`, `setLanguageCode` FUA:223, `useDeviceLanguage` FUA:234 | firebase_auth.dart:155 to 165 | same | The shim has no `useDeviceLanguage` (FlutterFire's `setLanguageCode(null)` does it). |
| MFA token fields (sign_in_second_factor) | see row above | see row above | different | MFA belongs to another area. |

## Email actions

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| sendPasswordResetEmail | yes | firebase_auth.dart:344 | same | firebase_user_auth.dart:665 |
| confirmPasswordReset | named params | :374 | same | firebase_user_auth.dart:684 |
| verifyPasswordResetCode | yes | :379 | same | firebase_user_auth.dart:716 |
| sendEmailVerification | on the client | user.dart:70 | same | firebase_user_auth.dart:767 |
| applyActionCode | yes | :366 | same | firebase_user_auth.dart:733 |
| checkActionCode / ActionCodeInfo `data` | `ActionCodeInfo` (email, previousEmail, multiFactorInfo) | convert.dart:281 | same | firebase_user_auth.dart:702; action_code.dart:151-236 |
| ActionCodeSettings | flat fields: url, handleCodeInApp, iOSBundleId, androidPackageName, androidInstallApp, androidMinimumVersion, linkDomain | `actionCodeSettingsOf` | different | no deprecated `dynamicLinkDomain`; action_code.dart:23-56 |
| ActionCodeURL / parseActionCodeURL | `ActionCodeURL.parseLink` | — | same | unwraps Dynamic Links; action_code.dart:253-312 |
| ActionCodeOperation | enum (+ `unknown`) | mapped | same | action_code.dart:116 |
| isSignInWithEmailLink | yes | :335 | same | firebase_user_auth.dart:998 |
| sendSignInLinkToEmail | yes | :355 | same | firebase_user_auth.dart:973 |
| signInWithEmailLink | yes | :325 | same | firebase_user_auth.dart:1019 |
| fetchSignInMethodsForEmail | yes | :383 | same | firebase_user_auth.dart:746 |
| validatePassword | returns `PasswordValidationStatus`; cached policy, re-fetched on failure | `FirebaseAuthDart.validatePassword(app, password)` | same | `FirebaseAuth.validatePassword` never reaches the platform (it fetches the policy from production itself), so the shim offers a static that goes through the client; firebase_user_auth.dart:901, :935 |
| PasswordPolicy / PasswordValidationStatus | flat fields; `meets*Requirement` | none | different | JS `contains*`, `customStrengthOptions`; password_policy.dart:6, :142 |

## Multi-factor

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| multiFactor(user).enrolledFactors | `AuthUser.enrolledFactors` | `DartMultiFactor.getEnrolledFactors` reads the client's current user (Phone/Totp subtypes) | different | auth_user.dart:76; shim multi_factor.dart:82 |
| MultiFactorUser.getSession | none | `DartMultiFactorSession`: keeps the user, id = uid; nothing is sent (the backend session starts in `generateSecret`) | different | shim multi_factor.dart:29, :100 |
| MultiFactorUser.enroll (TOTP) | `startTotpEnrollment` → `finalizeTotpEnrollment(secret, code, displayName)` | `finalizeTotpEnrollment`; `argument-error` without a displayName | different | firebase_user_auth.dart:1280, :1310; shim multi_factor.dart:38 |
| MultiFactorUser.unenroll | `unenrollMultiFactor(uid)` (SMS factors too) | `factorUid` or `multiFactorInfo.uid` → `unenrollMultiFactor` | different | uid only in the client; firebase_user_auth.dart:1343; shim multi_factor.dart:65 |
| getMultiFactorResolver | `FirebaseAuthMultiFactorException.resolver` (also on reauth) | `exceptionOf` wraps the client's resolver in `DartMultiFactorResolver` (convert.dart:87) | different | auth_exception.dart:436; firebase_user_auth.dart:1930 |
| MultiFactorResolver.hints | `hints` | `DartMultiFactorResolver` | same | multi_factor.dart:229 |
| MultiFactorResolver.session | none (`pendingCredential` on the exception) | pending credential used as session id | missing | |
| MultiFactorResolver.resolveSignIn(assertion) | `resolveSignInWithTotp(code, enrollmentId)`; SMS throws `multi-factor-info-not-found` | TOTP assertion → `resolveSignInWithTotp`, for sign-in and reauthentication; other assertions `argument-error` | different | multi_factor.dart:247; shim multi_factor.dart:129 |
| PhoneMultiFactorGenerator | none | throws (noPhone) | missing | needs SMS + reCAPTCHA; shim multi_factor.dart:49 |
| TotpMultiFactorGenerator | folded into the enroll/resolve methods | `generateSecret` → `startTotpEnrollment`; the assertions carry the secret or enrollment id and the code | different | shim multi_factor.dart:167 |
| TotpSecret | `TotpSecret` (secretKey, hashingAlgorithm, codeLength, codeIntervalSeconds, enrollmentCompletionDeadline, otpauthUri) | `DartTotpSecret`: `generateQrCodeUrl` → `otpauthUri` (issuer defaults to the app name, as in JS); `openInOtpApp` throws `unimplemented` (needs a URL launcher) | different | JS `generateQrCodeUrl`; multi_factor.dart:113-200; shim multi_factor.dart:210 |
| MultiFactorInfo / PhoneMultiFactorInfo / TotpMultiFactorInfo | one `MultiFactorInfo`; `enrollmentTime` is a `DateTime` | shim builds Phone/Totp subtypes (convert.dart:114) | different | multi_factor.dart:12-98 |
| FactorId | `phoneFactorId`, `totpFactorId`, `unknownFactorId` | — | same | multi_factor.dart:25-32 |
| MFA error codes | all 8 JS codes | — | same | auth_exception.dart:259-263, :383, :390 |
| MultiFactorError | `FirebaseAuthMultiFactorException` (hints, pendingCredential, resolver) | — | different | |

## Persistence

| JS export | Dart client | Shim | Status | Notes |
| --- | --- | --- | --- | --- |
| inMemoryPersistence (`J:core/persistence/in_memory.ts:65`) | `InMemoryAuthStorage`, default storage (`D:auth_storage.dart:66`) | `Persistence.NONE` moves the session to an in-memory store through the client's `setStorage` | same | JS is a `NONE` class; Dart is a KV map shared by instance, so one instance can be reused to restore a session. |
| browserLocalPersistence (`J:platform_browser/persistence/local_storage.ts:232`) | `WebAuthStorage.local` (`D:storage/web_auth_storage_web.dart:30`) | Not available on web (storage_path_stub gives memory); `Persistence.LOCAL` means the session file on VM | different | Dart is plain `window.localStorage` get/set. JS also polls (`_POLLING_INTERVAL_MS = 1000`, local_storage.ts:30) and handles `storage` events for cross-tab sync; Dart does neither. |
| browserSessionPersistence (`J:.../session_storage.ts:54`) | `WebAuthStorage.session` (web_auth_storage_web.dart) | `Persistence.SESSION` is mapped to memory, not to a per-tab store (`S:firebase_auth.dart:180`) | same | Client is equivalent. Shim: SESSION behaves like NONE (lost at process end) which is the nearest thing outside a browser. |
| indexedDBLocalPersistence (`J:.../indexed_db.ts:622`) | none | none | missing | JS `getAuth` tries IndexedDB first, then localStorage, then sessionStorage (`J:platform_browser/index.ts` `getAuth`). Dart web has local/session only. `AuthStorage.read/write` is `FutureOr`, so an async backend fits the interface. |
| browserCookiePersistence (`J:.../cookie_storage.ts:166`) | none | none | n/a outside a browser | Exported by `index.ts`; type `'COOKIE'`. Needs `document.cookie`. |
| setPersistence(auth, persistence) (`J:core/auth/auth_impl.ts:477`) | `setStorage(AuthStorage)` (`D:firebase_user_auth.dart`) | Implemented on the client's `setStorage`: memory for NONE and SESSION, the app's storage for LOCAL (`S:firebase_auth.dart` `setPersistence`) | different | Takes a storage, not a `Persistence`. JS removes the user from the old persistence before writing the new one; the client writes the new storage first, so a failed write changes nothing. It waits for a restore in progress and rewrites a session that changed during the move. |
| Persistence type (`'SESSION','LOCAL','NONE','COOKIE'`, `J:model/public_types.ts:346`) | none | FlutterFire `Persistence` enum (NONE/SESSION/LOCAL) is accepted | missing | No client-level type; only `AuthStorage` instances. |
| initializeAuth({persistence: [..]}) fallback order and migration (`J:core/persistence/persistence_user_manager.ts:205-217`) | none | Partial: a failed write to the file falls back to memory for the rest of the process (`S:storage.dart` `_persistentFailed`) | missing | JS picks the first available persistence in the array and migrates the user from the others. Dart has no list and no migration. |
| Cross-tab sync (`PersistenceInternal._addListener/_removeListener`, `J:core/persistence/index.ts:46`) | none | none | n/a outside a browser | Multi-tab `storage` events; a process has no equivalent. |
| Stored key and blob (`firebase:authUser:<apiKey>:<appName>` of a user JSON) | key `firebase_auth_providers_dart:<apiKey>`, JSON with `version: 2` (`D:firebase_user_auth.dart:129`, `auth_storage.dart` doc) | key `firebase_auth_providers_dart:<apiKey>:<appName>` (`S:firebase_auth.dart storageKeyOf`) | different | Not readable by the JS SDK or by FlutterFire web; no cross-SDK session sharing. |
| Public Persistence is an opaque marker, custom persistence is internal | `AuthStorage` abstract class is public: `read/write` of a string, any backend (`D:auth_storage.dart:39`) | `DartAuthConfig.storageFor` per app (`S:firebase_auth.dart`) | different | Dart is more open than JS (JS has `PersistenceInternal`, only React Native's `getReactNativePersistence` is public). |
| FileAuthStorage (no JS equivalent) | owner-only file, atomic rename, mode checks (`D:storage/file_auth_storage_io.dart:41`) | default on VM: `FileAuthStorage` in `defaultSessionFile()` (`S:storage_path_io.dart:19,52`) | different | Dart-only; JS has no file storage. |
| Secure storage (Keychain, Keystore, libsecret) | none in package; doc recommends `flutter_secure_storage` (`D:auth_storage.dart` doc) | none; default is a plain file, memory on Android/iOS/web (`S:storage_path_io.dart:24`) | missing | Refresh token sits in a 0600 file. No secure-storage adapter ships. |

## Emulator

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| connectAuthEmulator(auth, url) | `emulatorHost` ctor arg, `forApp(emulatorHost:)` and `useEmulator(host, options:)` FUA:248; accepts `host:port` or `http(s)://host:port`; rejects userinfo, path, query, bad port and Google hosts (FUA:322) | `useAuthEmulator(host, port)` firebase_auth.dart:168, calling `FirebaseUserAuth.useEmulator` | different | `useEmulator` may be called at any time and later requests follow it. JS requires `http://` or `https://` in the URL; Dart accepts bare `host:port`. |
| connectAuthEmulator options `{disableWarnings}` | `AuthEmulatorOptions(disableWarnings:)` on the constructor (`emulatorOptions`), `forApp` and `useEmulator`; warns (log) only for a non-loopback host, FUA:392 | none | different | JS warns for every emulator and adds a banner; Dart does neither for a loopback host. |
| `emulator-config-failed` guard (cannot connect after a request was made) | none, by design: `useEmulator` may be called at any time | same | different | JS throws `emulator-config-failed`. Dart lets later requests follow the new config; a request in flight keeps the old origin. |
| Auth.emulatorConfig (`{protocol,host,port,options}`) | `emulatorConfig` (`AuthEmulatorConfig`, auth_emulator_config.dart) FUA:261 | none | same | Null for the real service. |
| (no JS peer) `FIREBASE_AUTH_EMULATOR_HOST` | `emulatorHostFromEnvironment` FUA:186; `emulatorOrigin()` FUA:199 | not read | n/a | Dart extra. The shim does not read the variable. |

## Tenants, languages and the Auth object

| JS export | Dart client | Shim | Status | Notes |
|---|---|---|---|---|
| Auth.tenantId | mutable `tenantId` | firebase_auth.dart:155 | same | sent on requests; firebase_user_auth.dart:243 |
| Auth.languageCode | `languageCode` / `setLanguageCode` | :161 | same | firebase_user_auth.dart:219 |
| useDeviceLanguage | yes | `setLanguageCode(null)` | same | firebase_user_auth.dart:234 |
| Auth.settings.appVerificationDisabledForTesting | none | accepted and ignored (:191) | n/a outside a browser | phone/reCAPTCHA only |
| initializeAuth | `FirebaseUserAuth(...)` (storage, requestTimeout, appCheck) | `DartFirebaseAuth` | different | firebase_user_auth.dart:100-134 |
| getAuth | `FirebaseUserAuth.forApp(app)` | `delegateFor` | different | firebase_user_auth.dart:163 |
| Auth.app | none (`apiKey`, `appId` only) | — | missing | firebase_user_auth.dart:206-213 |
| Auth.name | none | — | missing | |
| Auth.config | none (`apiKey`, `appId`, `emulatorHost`) | — | different | firebase_user_auth.dart:206-213 |
| Auth.currentUser | `currentUser` | :143 | same | firebase_user_auth.dart:410 |
| Auth.emulatorConfig | `emulatorConfig` (`AuthEmulatorConfig`) | `useAuthEmulator` (:168) | same | firebase_user_auth.dart:261 |
| onAuthStateChanged / onIdTokenChanged | `authStateChanges()`, `idTokenChanges()`, `userChanges()` streams | :203-220 | different | streams, not callbacks; firebase_user_auth.dart:419-442 |
| beforeAuthStateChanged | yes, with `onAbort` | none | same | firebase_user_auth.dart:465 |
| updateCurrentUser | yes | none | same | firebase_user_auth.dart:480 |
| signOut | yes | :339 | same | firebase_user_auth.dart:625 |
| authStateReady | yes | none | same | firebase_user_auth.dart:448 |

## Errors

| JS export | Dart client | Shim | Status | Notes |
| --- | --- | --- | --- | --- |
| SERVER_ERROR_MAP, 48 server codes to client codes (`J:api/errors.ts:134`) | `_codes`, same 48 keys and same values, no differences (`D:auth_exception.dart:212`) | uses client mapping via `exceptionOf` (`S:convert.dart:98`) | same (48 of 48) | Includes the single-code oddities: `USER_NOT_FOUND` to `user-token-expired`, `INVALID_PENDING_TOKEN` and `INVALID_TEMPORARY_PROOF` to `invalid-credential`, `BLOCKING_FUNCTION_ERROR_RESPONSE` and 4 `MISSING_*` to `internal-error`. |
| Unmapped server code: lowercase, `_`/space to `-` (`J:api/index.ts:238`) | same rule (`D:auth_exception.dart:113-117`) | same | same | e.g. `QUOTA_EXCEEDED` to `quota-exceeded`. |
| `API key not valid` text | mapped to `invalid-api-key` (`D:auth_exception.dart:115`) | same | different | JS has no such special case in `api/index.ts` (`INVALID_API_KEY` is asserted client-side only, `J:core/util/handler.ts:73`); JS would yield a kebab-cased message code. Dart is nicer, but is a divergence. |
| Tagged errors: `FEDERATED_USER_ID_ALREADY_LINKED`, `EMAIL_EXISTS`, `USER_DISABLED`, `needConfirmation` (`J:api/index.ts:215-233`) | same four (`D:auth_exception.dart:120-135,147`) | email, phone, tenant, credential copied | same | |
| AuthErrorCodes, client codes (105 distinct, `J:core/errors.ts:503`; enum has 108) that Dart emits or maps (76) plus the 3 enum-only codes `login-blocked`, `password-does-not-meet-requirements`, `unsupported-password-policy-schema-version` | emitted at `D:firebase_user_auth.dart:2094` (`login-blocked`), `:949` (`password-does-not-meet-requirements`), `:917` (`unsupported-password-policy-schema-version`), rest via `_codes` and literals | passes through | same (79 of 108) | Verified by searching for each code as a string literal in the client. |
| `already-initialized` | not emitted | n/a | missing | JS throws on a second `initializeAuth` with other options. |
| `app-deleted` | not emitted | `dispose()` has no such error | missing | JS: any call after the app is deleted. |
| `dependent-sdk-initialized-before-auth` | not emitted | n/a | missing | Init-order guard between Firebase SDKs; low relevance. |
| `emulator-config-failed` | not emitted, by design (`useEmulator` may be called at any time) | `useAuthEmulator` has no check | missing | JS throws if the emulator is configured after a request was made. |
| `invalid-emulator-scheme` | not emitted, by design; `ArgumentError` for a bad `emulatorHost`, also for a scheme other than http or https (`D:firebase_user_auth.dart:333`) | becomes `argument-error` via `guard` (`S:convert.dart:57`) | missing | Different code for the same condition. |
| `user-signed-out` | not emitted | `no-current-user` instead (`S:convert.dart:84`) | missing | Dart uses `null-user` (`D:firebase_user_auth.dart:1432`) and the shim `no-current-user`; JS `user-signed-out` is thrown by internal user operations after sign-out. |
| `missing-continue-uri` | not emitted (server value maps to `internal-error`) | n/a | missing | JS validates `ActionCodeSettings.url` client-side. |
| `missing-phone-number` | not emitted | n/a | missing | Phone auth is not in the client. |
| `missing-verification-code` | not emitted | n/a | missing | Phone auth is not in the client. |
| Browser/env-only client codes (20): `popup-blocked`, `popup-closed-by-user`, `cancelled-popup-request`, `redirect-cancelled-by-user`, `redirect-operation-pending`, `missing-iframe-start`, `cordova-not-ready`, `invalid-cordova-configuration`, `invalid-auth-event`, `no-auth-event`, `unauthorized-domain`, `auth-domain-config-required`, `web-storage-unsupported`, `cors-unsupported`, `operation-not-supported-in-this-environment`, `unsupported-persistence-type`, `invalid-persistence-type`, `app-not-authorized`, `app-not-installed`, `missing-app-credential` | none | none | n/a outside a browser | Popup, redirect, iframe, cordova, auth domain, web storage, reCAPTCHA/app verification. The last three are Android/web app-verification for phone auth. |
| AuthErrorCodes constants object (`J:core/errors.ts:503`) | none; codes are string literals | none | missing | A Dart app compares `e.code == 'wrong-password'`; no constants class to avoid typos. |
| Dart-only codes | `cancelled`, `invalid-oauth-response`, `oauth-state-mismatch` (loopback, `D:oauth_loopback/oauth_loopback_io.dart:220`), `timeout` (`oauth_loopback_io.dart:124`, JS enum has `timeout`) | `no-current-user`, `no-options`, `unimplemented` (`S:convert.dart:17`) | different | Native FlutterFire has `no-current-user`; the others are not in the JS enum. |
| Code format and class | `code` has no `auth/` prefix; `FirebaseAuthException extends FirebaseException(plugin: 'firebase_auth')` (`D:auth_exception.dart:65-73`) | FlutterFire `FirebaseAuthException` | different | JS: `FirebaseError` with `code: 'auth/...'`, `name: 'FirebaseError'`. Dart matches FlutterFire, by design. |
| Message text (`_debugErrorMap`, 108 messages, `J:core/errors.ts:141`; format `Firebase: <msg> (auth/<code>).`) | `_messages` 70 codes, shortened, no prefix/suffix (`D:auth_exception.dart:280`) | same text | different | Codes without a message fall back to the server message or the code. |
| customData.appName | none | none | missing | Not needed with one client per app, but absent. |
| customData.email, phoneNumber, tenantId | top-level fields `email`, `phoneNumber`, `tenantId` (`D:auth_exception.dart:184-190`), set only for the 3 tagged codes and `needConfirmation` | copied to FlutterFire exception (`S:convert.dart:114-123`) | different | JS sets them in more places (e.g. MFA errors and user-bound operations). FlutterFire exposes them top-level, so Dart is consistent with the shim target. |
| customData._tokenResponse (raw server body on tagged errors, `J:api/index.ts:369`) | not kept raw; parsed into `credential` (`D:auth_exception.dart:196`, `credentialFromResponse`) | `credential` converted | different | Raw fields such as `rawUserInfo`, `oauthIdToken` are only available through the parsed credential. |
| customData._serverResponse / MultiFactorError (`J:mfa/mfa_error.ts:28-50`) | `FirebaseAuthMultiFactorException` with `pendingCredential` and `hints` (`D:auth_exception.dart:435-486`); resolver and TOTP (`D:multi_factor.dart:225`) | converted to `FirebaseAuthMultiFactorExceptionPlatform` whose resolver finishes TOTP through the client's (`S:multi_factor.dart:111`) | different | |
| credentialFromError (`GoogleAuthProvider.credentialFromError` etc.) | `FirebaseAuthException.credential` (`D:auth_exception.dart:196`) | `credential` | different | A property instead of per-provider static helpers; same data. |
| Dart-only fields `serverCode`, `httpStatus`, `invalidatesSession` (`D:auth_exception.dart:177,180,203`) | present | `serverCode` and `httpStatus` kept on `DartFirebaseAuthException` (`S:convert.dart`) | different | Not on a multi-factor error, which `firebase_auth` rebuilds as its own class. `invalidatesSession` is not passed on. |

Counts for the AuthErrorCodes comparison: 105 distinct client codes in JS map (106 entries, `INVALID_IDP_RESPONSE` and `INVALID_LOGIN_CREDENTIALS` both `invalid-credential`), 108 in the enum. Dart covers 79; 9 missing individually (listed above); 20 browser-only.

## Other top-level exports

| JS export | Dart client | Shim | Status | Notes |
| --- | --- | --- | --- | --- |
| debugErrorMap (`J:core/errors.ts:421`) | private `_messages` of 70 codes (`D:auth_exception.dart:280`) | same | different | Not exposed and not selectable as an `AuthErrorMap`; the JS `Auth.settings`/`initializeAuth({errorMap})` hook has no Dart counterpart. |
| prodErrorMap (`J:core/errors.ts:430`) | none | none | n/a outside a browser | One-message map, a bundle-size device for web; Dart messages are always present. |
| browserPopupRedirectResolver | none; the desktop substitute is `signInWithOAuthLoopback` (`D:oauth_loopback/oauth_loopback_io.dart`) | `signInWithPopup/Redirect/getRedirectResult` throw `unimplemented` (`S:firebase_auth.dart:395-403`) | n/a outside a browser | Needs iframe/popup handler. |
| RecaptchaVerifier, ApplicationVerifier, RecaptchaParameters | none | `RecaptchaVerifierFactoryPlatform` parameters unused; phone methods throw (`S:firebase_auth.dart:409,423`) | n/a outside a browser | Needs a DOM or WebView. |
| initializeRecaptchaConfig (`J:core/index.ts:97`) | none (only the 7 reCAPTCHA server codes are mapped, `D:auth_exception.dart:268-275`) | throws `unimplemented` (`S:firebase_auth.dart:427`) | n/a outside a browser | Impact: a project with reCAPTCHA Enterprise in enforce mode rejects REST sign-ins that carry no token (`missing-recaptcha-token`); Dart has no way to send one. |
| parseActionCodeURL / ActionCodeURL (`J:core/action_code_url.ts:89,162`) | `ActionCodeURL.parseLink` (`D:action_code.dart:252,263`), handles `link`, `deep_link_id`, iOS double deep link, 6 operations | not in the platform interface (client only through `userAuthFor`) | same | Static factory instead of a top-level function. |
| ActionCodeOperation | `enum ActionCodeOperation` (`D:action_code.dart:115`) | converted (`S:convert.dart actionCodeInfoOf`) | same | |
| OperationType (`J:model/enum_maps.ts:76`) | `enum OperationType` (`D:auth_user.dart:274`); `UserCredential.operationType` | none | same | The shim does not copy it; FlutterFire has no `operationType`. |
| ProviderId (`J:model/enum_maps.ts:34`) | per-provider constants: `EmailAuthProvider.PROVIDER_ID`, `GoogleAuthProvider.PROVIDER_ID`, apple, facebook, github (`D:auth_credential.dart:66,258,272,299,312`); no aggregate map | n/a | different | |
| SignInMethod (`J:model/enum_maps.ts:54`) | per-provider `*_SIGN_IN_METHOD` constants (`D:auth_credential.dart:69,72,261,275,302`) | n/a | different | |
| FactorId (`J:model/enum_maps.ts:23`) | `MultiFactorInfo.phoneFactorId`, `totpFactorId`, `unknownFactorId` (`D:auth_exception.dart:502-509`) | `multiFactorInfoOf` switches on them (`S:convert.dart:130`) | different | Adds `unknown`. |
| EmailAuthCredential toJSON / fromJSON (`J:core/credentials/email.ts:92,109`) | `toJson` and `fromJson` (`D:auth_credential.dart:63,87`), JS format | none | same | `fromJson` returns null for JSON that is not an email credential. For an email link, `toJson` keeps only the code and the tenant. |
| OAuthCredential toJSON / fromJSON, `OAuthProvider.credentialFromJSON` (`J:core/credentials/oauth.ts:116,137`) | `OAuthCredential.toJson`/`fromJson` (`D:auth_credential.dart:239,255`), `OAuthProvider.credentialFromJson` (`:411`) | none | different | `credentialFromJson` keeps `secret` (JS drops it), so a Twitter credential still signs in. `fromJson` returns null for a non-credential; `credentialFromJson` throws `ArgumentError`, as JS throws. Used to persist a pending credential across an `account-exists-with-different-credential` flow. |
| SAMLAuthCredential and `SAMLAuthProvider` toJSON / fromJSON (`J:core/credentials/saml.ts:70,87`) | no SAML class | none | missing | |
| PhoneAuthCredential toJSON / fromJSON (`J:core/credentials/phone.ts:100,121`) | no phone credential | `convert.dart:208` throws `unimplemented` | missing | Phone auth needs SMS verification and app verification (reCAPTCHA or APNs/Play Integrity). |
| getReactNativePersistence (`J:platform_react_native/persistence`) | analogue: custom `AuthStorage` | `storageFor` | n/a outside a browser | React Native only; the Dart analogue exists in spirit (`AuthStorage`). |
| Cordova helpers (`J:platform_cordova`: `cordovaPopupRedirectResolver` etc.) | none | none | n/a outside a browser | Cordova WebView plugins. |
| revokeAccessToken(auth, token) (`J:core/index.ts:264`, `auth_impl.ts:609`: `providerId apple.com`, `tokenType ACCESS_TOKEN`, optional `tenantId`) | `revokeAccessToken(token)` (`D:firebase_user_auth.dart:774`) and `revokeToken(authorizationCode)` (`:754`, `tokenType '3'`); both send `tenantId` | both call the client (`S:firebase_auth.dart`) | different | With no user, the client throws `null-user`; JS returns silently. |

## Shim coverage of the FlutterFire platform interface

The shim never throws Dart's `UnimplementedError`: every missing member throws a `FirebaseAuthException` with code `unimplemented` (`S:convert.dart:17`, text constants `noPhone` and `noBrowserFlow`; `noProviderFlowFor` and `noLoopbackOnWeb` in `S:oauth_provider.dart`).

| JS export | Dart client | Shim | Status | Notes |
| --- | --- | --- | --- | --- |
| FirebaseAuthPlatform members implemented (32): delegateFor, setInitialValues, dispose, currentUser get/set, sendAuthChangesEvent, tenantId get/set, languageCode, setLanguageCode, useAuthEmulator, setPersistence, setSettings, authStateChanges, idTokenChanges, userChanges, signInAnonymously, createUserWithEmailAndPassword, signInWithEmailAndPassword, signInWithCustomToken, signInWithCredential, signInWithEmailLink, isSignInWithEmailLink, signOut, sendPasswordResetEmail, sendSignInLinkToEmail, applyActionCode, checkActionCode, confirmPasswordReset, verifyPasswordResetCode, fetchSignInMethodsForEmail, signInWithProvider | present | implemented (`S:firebase_auth.dart`) | same | `setSettings` is a silent no-op (:191), `currentUser` setter, `sendAuthChangesEvent` and `setInitialValues` are no-ops by design. `userChanges` merges the token and user streams (:200+). |
| UserPlatform members implemented (14): delete, getIdToken, getIdTokenResult, linkWithCredential, reauthenticateWithCredential, reload, sendEmailVerification, unlink, updateEmail, updatePassword, updateProfile, verifyBeforeUpdateEmail, linkWithProvider, reauthenticateWithProvider | present | implemented (`S:user.dart`) | same | |
| signInWithProvider (`S:firebase_auth.dart` `signInWithProvider`) | `signInWithOAuthLoopback` (VM) | the loopback flow of the `OAuthLoopbackProvider` passed to `use` for the provider id; `presentUrl` opens the URL (the system browser by default) | different | Each provider id needs an `OAuthLoopbackProvider` at `use`; another id throws `unimplemented` (`noProviderFlowFor`). The FlutterFire provider's scopes and custom parameters are added. On the web, and on Android and iOS without `presentUrl`, it throws `unimplemented`. |
| signInWithPopup, signInWithRedirect, getRedirectResult (`:395,399,403`) | none | unimplemented, `noBrowserFlow` | n/a outside a browser | |
| signInWithPhoneNumber, verifyPhoneNumber (`:409,423`) | none | unimplemented, `noPhone` | missing | |
| initializeRecaptchaConfig (`:427`) | none | unimplemented, `noPhone` | n/a outside a browser | |
| revokeAccessToken, revokeTokenWithAuthorizationCode (~430-440) | `revokeAccessToken` and `revokeToken` (authorization code) in client | calls the client | same | |
| User.linkWithProvider, reauthenticateWithProvider (`S:user.dart`) | `linkWithOAuthLoopback`, `reauthenticateWithOAuthLoopback` | as `signInWithProvider` | different | `no-current-user` before the browser opens for a user that is no longer signed in. |
| User.linkWithPopup, linkWithRedirect, reauthenticateWithPopup, reauthenticateWithRedirect (`:127,131,136,140`) | none | unimplemented, `noBrowserFlow` | n/a outside a browser | |
| User.linkWithPhoneNumber, updatePhoneNumber (`:146,150`) | none | unimplemented, `noPhone` | missing | |
| MultiFactor getSession, enroll, unenroll, getEnrolledFactors (`S:multi_factor.dart:29,38,65,82`) | present in the client (`D:multi_factor.dart`, `multi_factor_api.dart`) | implemented (TOTP; SMS factors listed and unenrolled only) | same | |
| MultiFactorResolver.resolveSignIn (`:129`) | resolver in the client | implemented for TOTP assertions | same | |
| PhoneMultiFactorGenerator.getAssertion (`:161`) | phone MFA none | unimplemented, `noPhone` | missing | |
| TotpMultiFactorGenerator generateSecret, getAssertionForEnrollment, getAssertionForSignIn (`:173,186,202`) | in the client (`D:multi_factor.dart:113` `TotpSecret`) | implemented | same | |
| TotpSecret generateQrCodeUrl, openInOtpApp (`:229,241`) | `TotpSecret.otpauthUri` | `generateQrCodeUrl` implemented; `openInOtpApp` unimplemented (needs a URL launcher) | different | |
| Credentials: PhoneAuthCredential, Play Games, Game Center (`S:convert.dart:208-212`) | none | unimplemented | missing | Play Games and Game Center need native SDKs. |

Unimplemented in the shim: 14 members (6 on `FirebaseAuthPlatform`, 6 on `UserPlatform`, 2 in the multi-factor classes) plus 3 credential kinds. Breakdown of the 14: 8 browser-only (3 sign-in popup/redirect, 4 user popup/redirect, `initializeRecaptchaConfig`), 5 phone (including `PhoneMultiFactorGenerator.getAssertion`), and `TotpSecret.openInOtpApp` (needs a URL launcher).

## Gaps worth closing, ranked

Also fixed on this branch: a failed storage write no longer loses the new session (`_setSession`), and `forApp` sets the auth provider even when the storage read fails.

Run against a real Firebase project on 2026-11-20: Google sign-in with a Desktop client, TOTP enrolment, sign-in and unenrolment, and a generic OIDC provider with `discover` and with `exchangeCode`. GitHub was run with a real OAuth App: `account-exists-with-different-credential` for an existing email, then link and unlink on that account. Not run on a real project: tenants, SMS factors, `revokeToken` and `revokeAccessToken`.

Effort: S takes hours, M a few days, L more than a week or needs outside pieces. Each entry also says whether it needs a browser or a new dependency.

| # | State | Gap | Effort | Browser | New dependency | Value | Why |
|---|---|---|---|---|---|---|---|
| 1 | closed | Bring TOTP, the loopback exchange, the request timeout and the session rules together on one branch | M | no | no | high | MFA, `requestTimeout`, `revokeToken` and the loopback link and reauthenticate methods each lived on one branch, and all of them change `firebase_user_auth.dart`. |
| 2 | closed | Signing out while the storage write fails leaves the old session on disk, and the next `restore` signs the user back in (`_clearSession`) | S | no | no | high | This is a bug, not a parity item. It is the counterpart of the `_setSession` write-failure fix. |
| 3 | closed | Connect the shim's multi-factor classes to the client's TOTP API (9 members) | M | no | no | high | The shim enrols, unenrols, lists and resolves TOTP through the client (S:multi_factor.dart); phone assertions and `openInOtpApp` still throw `unimplemented`. |
| 4 | closed | Back the shim's `signInWithProvider`, `linkWithProvider` and `reauthenticateWithProvider` with the loopback OAuth flow | M | system browser | no | high | This is the usual desktop sign-in. The providers are passed to `FirebaseAuthDart.use(oauthProviders:)`, with an optional `presentUrl`; tested with a simulated browser, not yet against a real project through the shim. |
| 5 | closed | `toJson`/`fromJson` for `EmailAuthCredential` and `OAuthCredential`, plus `OAuthProvider.credentialFromJson` | S | no | no | med | Keeps a pending credential across the `account-exists-with-different-credential` flow. Uses the JS JSON format. |
| 6 | closed | `revokeAccessToken(token)` (ACCESS_TOKEN, `tenantId`) in the client, and both revoke methods in the shim | S | no | no | med | The endpoint call already exists. Apple's account-deletion rule makes it matter on iOS and macOS. |
| 7 | partly closed: `emulatorConfig` and `disableWarnings` done; no `emulator-config-failed` or `invalid-emulator-scheme` code, by design | Emulator parity: an `emulator-config-failed` guard, an `invalid-emulator-scheme` code, a parsed `emulatorConfig`, and `disableWarnings` | S | no | no | med | Today a late emulator setting silently mixes origins, and a bad host throws `ArgumentError`. |
| 8 | partly closed: `refreshToken` left; `UserCredential.providerId` not added, by design (see the user table) | `User.providerId`, `User.refreshToken` and `User.toJson`; `UserCredential.operationType` and `providerId` | S | no | no | med | Plain fields that JS exposes. |
| 9 | closed (as `setStorage(AuthStorage)`) | `setPersistence` and a `Persistence` enum in the client, using the shim's `SwitchableStorage` | S | no | no | med | The shim already has this logic. Without it, apps that don't use the shim pick storage only at construction. |
| 10 | closed (`validatePassword` as `FirebaseAuthDart.validatePassword`) | Shim passthroughs: `validatePassword`, and keeping `serverCode` and `httpStatus` in `exceptionOf` | S | no | no | med | The client has them; the shim drops them. |
| 11 | open | Keep the raw server response on tagged errors (JS `_tokenResponse`) | S | no | no | low-med | Helps handle linking and debugging. |
| 12 | open | An optional secure-storage adapter (Keychain, Keystore, libsecret), as a separate package | M | no | yes | med | The refresh token sits in a file with mode 0600. |
| 13 | open | Client-side validation codes: `missing-continue-uri`, and `app-deleted` or `user-signed-out` after `dispose` | S | no | no | low | Today these show up as server errors, `StateError` or `null-user`. |
| 14 | partly closed: `OperationType` done | An error-code constants class; aggregate `ProviderId`, `SignInMethod` and `FactorId`; `OperationType` | S | no | no | low | Typo safety only. |
| 15 | open | `IdTokenResult` parity: nullable times and `signInSecondFactor` | S | no | no | low | `GetTokenResult` lives in `firebase_app_dart` and returns epoch 0 for a missing time. |
| 16 | open | `Auth.name`, `Auth.app`, `Auth.config` | S | no | no | low | Introspection only. |
| 17 | open | IndexedDB storage on the web | M | yes | no | low-med | The JS default on the web, but the stored data can't be shared with the JS SDK anyway because the key format differs. |
| 18 | open | Phone sign-in with a verification token supplied by the caller (works with the emulator and test numbers) | L | for production | no | med | Real projects require app verification: reCAPTCHA, Play Integrity or APNs. |
| 19 | open | reCAPTCHA Enterprise (`initializeRecaptchaConfig`, token on sign-in) | L | yes, or a WebView | yes | high where enforcement is on | A project in enforce mode rejects REST sign-ins that carry no token. |
| 20 | open | Phone second factor (`PhoneMultiFactorGenerator`, `getSession`) | L | yes | yes | med | Needs the same app verification as 18. |
| 21 | open | Popup, redirect and `RecaptchaVerifier` | L | yes | yes | low | The loopback flow already covers native apps. |

Not counted as gaps, by design:
- `FirebaseAuthException` codes have no `auth/` prefix and the class is FlutterFire's.
- Streams replace the JS observer callbacks.
- Credentials are created through static factories rather than provider instances.
- `UserCredential` has no `providerId` of its own: it extends `AuthUser`, whose `providerId` is `'firebase'`.
