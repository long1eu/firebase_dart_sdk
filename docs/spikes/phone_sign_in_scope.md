# Spike: what phone sign-in would take in the pure-Dart Auth client

> **Status.** Scoping only, written on 2026-11-21. No code was written. Nothing was sent to Google or Firebase
> (no request to `identitytoolkit.googleapis.com` or to any real project); every statement about what the server
> does is taken from Google's public documentation or from the source of the SDKs and the emulator, and the
> statements that only a real request could settle are listed under "Not checked". The effort figures are estimates.

**The answer.** The REST side of phone sign-in is small: two calls (`accounts:sendVerificationCode`,
`accounts:signInWithPhoneNumber`) plus the SMS second-factor calls, and the client already has the same shape for
TOTP. What a pure-Dart client cannot produce by itself is the proof that the request comes from a real app:
a reCAPTCHA token (v2 or Enterprise), a Play Integrity token, or an APNs silent-push receipt. The Auth emulator
ignores that proof, so against the emulator everything can be built and tested with no browser. Against a real
project, the documented way to skip the proof is a console test number together with the SDKs' "app verification
disabled" setting, and what the SDKs send in that case differs by platform and is not documented as a REST
contract. The honest offer for a desktop or command-line client is: (a) the emulator and test numbers, plus (b) a
typed hook through which the app hands in a token it got elsewhere. Real numbers on a real project without a token
are out of reach. Build (a) with the hook in the API from the start, about 7 agent days for sign-in, link,
reauthenticate, `updatePhoneNumber` and the shim, and about 10 with SMS second factor. Do not build the
localhost reCAPTCHA page (3 to 5 more days) unless a user needs real numbers on desktop.

## What the endpoints need

All paths are under `https://identitytoolkit.googleapis.com`. Field names are from Google's REST reference
(`https://cloud.google.com/identity-platform/docs/reference/rest/v1/accounts/sendVerificationCode`, last updated
2026-03-10, and `.../signInWithPhoneNumber`) and from the JS SDK at `a086865`
(`packages/auth/src/api/authentication/sms.ts`).

| Call | Body | Answer | Notes |
|---|---|---|---|
| `POST /v1/accounts:sendVerificationCode` | `phoneNumber` (E.164); app proof, one of: `recaptchaToken` (reCAPTCHA v2), `iosReceipt` plus `iosSecret` (and header `x-ios-bundle-identifier`), `playIntegrityToken` (nonce is the SHA-256 of `phoneNumber`), `safetyNetToken` (deprecated); or, when reCAPTCHA Enterprise is on, `captchaResponse` plus `clientType` plus `recaptchaVersion`; also `tenantId`, `autoRetrievalInfo.appSignatureHash` (Android SMS retriever) | `sessionInfo` | The reference says one of the three proofs "must be specified to verify the verification code is being sent on behalf of a real app and not an emulator", unless `captchaResponse` is used. It names no exception for test numbers. Header `X-Firebase-Locale` localises the SMS. |
| `POST /v1/accounts:signInWithPhoneNumber` | `sessionInfo` plus `code`, or `temporaryProof` plus `phoneNumber`; for linking `idToken`; for reauthentication `idToken` plus `operation: "REAUTH"`; `tenantId` | ID token, refresh token, `isNewUser`, `phoneNumber`; or `temporaryProof` when the number belongs to another account | JS: `sms.ts:66` (request), `:101` (link; a `temporaryProof` in the answer becomes `need-confirmation`), `:121-136` (reauth, `USER_NOT_FOUND` becomes `user-deleted`). |
| `updatePhoneNumber` | no endpoint of its own: a phone credential is linked with `_link`, the same `signInWithPhoneNumber` call with `idToken` | | JS `platform_browser/strategies/phone.ts` (`updatePhoneNumber`, after `_verifyPhoneNumber`). |
| `POST /v2/accounts/mfaEnrollment:start` | `idToken`, `phoneEnrollmentInfo` { `phoneNumber`, `recaptchaToken` or `captchaResponse`/`clientType`/`recaptchaVersion` }, `tenantId` | `phoneSessionInfo.sessionInfo` | `api/account_management/mfa.ts:55-70`. Finalise: `mfaEnrollment:finalize` with `phoneVerificationInfo` { `sessionInfo`, `code` }. |
| `POST /v2/accounts/mfaSignIn:start` | `mfaPendingCredential`, `mfaEnrollmentId`, `phoneSignInInfo` { same proof fields }, `tenantId` | `phoneResponseInfo.sessionInfo` | `api/authentication/mfa.ts:47-66`. Finalise: `mfaSignIn:finalize` with `phoneVerificationInfo`. |
| `GET /v1/recaptchaParams` | none | `recaptchaSiteKey` | The key the v2 widget renders with (`api/authentication/recaptcha.ts:32`). |
| `GET /v2/recaptchaConfig` | `clientType`, `version=RECAPTCHA_ENTERPRISE` | site key and per-provider enforcement state (`OFF`, `AUDIT`, `ENFORCE`) | How the JS SDK learns whether phone is under Enterprise (`_initializeRecaptchaConfig`). |

What the JS SDK does with the proof, in order (`platform_browser/strategies/phone.ts:227-440`,
`platform_browser/recaptcha/recaptcha_enterprise_verifier.ts:~300-375`):

1. It fetches the Enterprise config. If that fails it goes on with v2.
2. Phone provider enabled in the config: it sends the Enterprise token as `captchaResponse` with
   `clientType: CLIENT_TYPE_WEB` and `recaptchaVersion: RECAPTCHA_ENTERPRISE`. In `AUDIT` mode, an error
   `missing-recaptcha-token` or `invalid-app-credential` makes it retry with the v2 flow. In `ENFORCE` mode the error is
   returned to the caller.
3. Phone provider not enabled: it sends `captchaResponse: "NO_RECAPTCHA"` as a marker, then replaces it with a v2
   `recaptchaToken` from the `RecaptchaVerifier`.

What the client has today. `firebase_auth_providers_dart` has no phone code (`rg -i phone` in `firebase_user_auth.dart`
finds only session-field handling). It has the pieces phone would sit next to: `MultiFactorTransport.postJson` for v2
JSON calls (`multi_factor_api.dart:13-24`), `signInWithCredential`, `linkWithCredential`,
`reauthenticateWithCredential` (`firebase_user_auth.dart:1238,1332,1375`), `AuthCredential` subclasses
(`auth_credential.dart:17,35,196`), and `FirebaseAuthMultiFactorException` with a resolver for TOTP. The shim throws
`unimplemented` with the `noPhone` text in `signInWithPhoneNumber` (`firebase_auth.dart:520-524`),
`verifyPhoneNumber` (`:526-538`), `initializeRecaptchaConfig` (`:540-542`), `linkWithPhoneNumber`
(`user.dart:170-174`), `updatePhoneNumber` (`user.dart:176-178`), `PhoneMultiFactorGenerator.getAssertion`
(`multi_factor.dart:158-162`) and phone credential conversion (`convert.dart:278`). `setSettings` accepts
`appVerificationDisabledForTesting`, `phoneNumber`, `smsCode` and `forceRecaptchaFlow` and ignores them
(`firebase_auth.dart:283-291`). The parity rows are `docs/auth_parity.md` lines 47-50, 75-76, 168, 211, 241-242, 275, 290;
gaps 18 (phone with a caller-supplied token), 19 (reCAPTCHA Enterprise) and 20 (phone second factor) are open.

## Does a console test number skip app verification on REST?

Three kinds of statement are separated here.

**What Google's documentation says.**

- A test number ("Phone numbers for testing" in the console, up to 10) sends no SMS, does not use quota, is not
  throttled, works "from an iOS simulator or Android emulator without Google Play Services", and lets you "write
  integration tests without being blocked by security checks normally applied on real phone numbers"
  (`https://firebase.google.com/docs/auth/web/phone-auth`, "Test with fictional phone numbers";
  `https://docs.cloud.google.com/identity-platform/docs/test-phone-numbers.md.txt`).
- The SDKs have a switch that "disables app verification", and with it "using a non-fictional phone number will
  still fail to complete sign in. Only fictional phone numbers can be used with this API" (same pages; the iOS and
  Android pages repeat it).
- The documentation never says that a REST caller may leave out the proof for a test number, and never says it may not.
  The REST reference requires one proof field (see above) and names no test-number exception.

**What the SDK sources send when the switch is on.**

| SDK | Switch | What goes to `sendVerificationCode` | Source |
|---|---|---|---|
| JS | `auth.settings.appVerificationDisabledForTesting = true` | A mock `RecaptchaVerifier` resolves with a random 50-character alphanumeric string, sent as `recaptchaToken`. If the project has phone under Enterprise, the mock Enterprise client resolves with the string `token` as `captchaResponse` (`clientType` web, `recaptchaVersion` Enterprise). | `recaptcha_mock.ts:171`; `recaptcha_verifier.ts:114`; `recaptcha_enterprise_verifier.ts:148-151`; `strategies/phone.ts` |
| iOS | `settings.isAppVerificationDisabledForTesting` | No proof field at all: `CodeIdentity.empty`, so the body holds `phoneNumber`, `clientType: "CLIENT_TYPE_IOS"` and `tenantId` if any. The Enterprise config is not fetched in this mode; a source comment says the config call "is not implemented in emulator". Same for the MFA start calls. | firebase-ios-sdk `cef246f`: `PhoneAuthProvider.swift:199-211, 339-350`, `SendVerificationTokenRequest.swift:26-34, 80-100`, `IdentityToolkitRequest.swift:62` |
| Android | `setAppVerificationDisabledForTesting()` (and `forceRecaptchaFlowForTesting()` for the opposite) | Not known: the Android Auth SDK is not open source (it is not in the firebase-android-sdk repository's public source). The documentation says it disables Play Integrity and reCAPTCHA. | Android phone-auth page only |

So the iOS SDK sends a request with no app proof, and the JS SDK sends a proof that cannot be real. Both only work for
test numbers. That makes it likely, but it is an inference and not a documented REST contract, that the server skips
or relaxes the app check for registered test numbers. Which of the two shapes (no field, or a junk token) the server
accepts for a test number is not known; a REST client should be able to send either, and the typed hook below allows
both.

**What is unverified.** Whether a bare REST request (no proof) for a test number succeeds on a real project; whether it
still succeeds when the phone provider is in reCAPTCHA Enterprise `ENFORCE` mode or SMS defense is on; whether the
Android shape differs. Settling these takes one request against a project with a test number, which was not made.

## What the Auth emulator accepts

Source: firebase-tools `a134d3f`, `src/emulator/auth/operations.ts`.

- `sendVerificationCode` reads only `phoneNumber` (valid E.164) and ignores `iosReceipt`, `iosSecret` and
  `recaptchaToken` by design (`:990-1003`, comment at `:996`). It rejects a number that already has SMS second factors
  (`UNSUPPORTED_FIRST_FACTOR`, `:1005-1009`). It returns a `sessionInfo`, and prints
  `To verify the phone number +…, use the code NNNNNN.` to the emulator log (`:1011-1018`).
- The codes are also readable over REST: `GET /emulator/v1/projects/{projectId}/verificationCodes`, and the same under
  `/tenants/{tenantId}/` (`operations.ts:136`, `:2032-2037`; `apiSpec.ts:4223,4251`). The emulator's own tests use it
  (`testing/helpers.ts:309-313`). An automated test can therefore read the code with no log scraping.
- `signInWithPhoneNumber` checks `sessionInfo` and `code` (`INVALID_SESSION_INFO`, `INVALID_CODE`, `:2659-2665`), supports
  `temporaryProof` and the link and reauth paths (`:1854-1900`).
- SMS second factor: `mfaEnrollment:start` ignores `recaptchaToken`, `safetyNetToken`, `iosReceipt`, `iosSecret` and
  `autoRetrievalInfo` ("the emulator doesn't implement anti-abuse features", `:2063-2067`); `mfaSignIn:start` does not
  require `phoneSignInInfo` (`:2190-2200`). Both print codes the same way.
- `GET /v1/recaptchaParams` answers with a fake site key and a note that "clients MUST disable Recaptcha" when talking
  to the emulator (`:752-766`). There is no handler for `/v2/recaptchaConfig` in `operations.ts` (`rg` finds none),
  so a client must not depend on that call when pointed at the emulator.
- Google's emulator page confirms the design: the emulator "does not support reCAPTCHA and APN flows", client SDKs
  disable them once connected, and codes are printed to the terminal
  (`https://firebase.google.com/docs/emulator-suite/connect_auth`, "Emulated phone/SMS authentication").

Google's emulator page does not say whether the console's test numbers exist in the emulator; the emulator
does not need them, because every number gets a code. Not checked.

## What can block a client without app verification

- **Enterprise enforcement.** Per provider the state is `OFF`, `AUDIT` or `ENFORCE`. For email and password, `ENFORCE`
  rejects requests without a token. For phone, the documented switch is `phoneEnforcementState: ENFORCE` with
  `useSmsBotScore` (bot protection) and, separately, `useSmsTollFraudProtection` with `tollFraudManagedRules`
  (`BLOCK` above a configured score). Both are Preview features and say "no fallback verification is required": the
  token is the verification (`https://docs.cloud.google.com/identity-platform/docs/recaptcha-enterprise.md.txt`,
  `https://docs.cloud.google.com/identity-platform/docs/recaptcha-sms.md.txt`). The `captchaResponse`, `clientType`
  and `recaptchaVersion` fields are documented as "required when reCAPTCHA Enterprise is enabled". A project in
  `ENFORCE` will reject a REST caller with no token, with the possible exception of test numbers (unverified).
- **Score-based, not challenge-based.** SMS defense returns a risk score for the phone number; a token from a browser
  that Google scores as a bot, or a number in a high-risk range, is blocked. A desktop WebView or localhost page may
  score differently from a real site. Not checked.
- **Limits that apply regardless of app verification** (`https://firebase.google.com/docs/auth/limits`): 150
  verification requests per IP per hour; 50 SMS per minute and 500 per hour per IP; 900 SMS per minute and 3,000 per
  day for Firebase Authentication without Identity Platform; a per-number rate limit (test numbers are exempt, per the
  test-number page).
- **SMS region policy.** "For new projects, the default policy allows no regions"
  (`https://firebase.google.com/docs/auth/android/phone-auth`). A real number in a region the policy does not allow
  is refused whatever the client sends.
- **Key restrictions.** The Android and iOS pages say the reCAPTCHA fallback needs an API key that is unrestricted or
  allowlisted for `PROJECT_ID.firebaseapp.com`. A key restricted to app identifiers (bundle id, package and
  certificate) would reject a desktop request outright; this is a deployment concern for the owner, not a client one.
- **App Check.** Whether App Check enforcement applies to the phone calls was not checked.

## What a pure-Dart desktop or command-line client can honestly offer

| Option | Works for | Needs | Fragility |
|---|---|---|---|
| (a) Emulator and test numbers | Local development and CI; test numbers on a real project if the server accepts a request without a proof (unverified) | Nothing from the platform | Low; relies on Google keeping test numbers exempt |
| (b) Caller-supplied proof | Real numbers, where the app can get a token itself: a Flutter WebView, a page the app serves, a web build, or a backend that does the reCAPTCHA step | An `AppVerification` value (v2 token, Enterprise token with version and client type, or none) given to the send call | Low for the client; the app owns the token source |
| (b2) Loopback reCAPTCHA page, shipped by this package | Real numbers on desktop with a system browser | A `localhost` HTTP server and a page that loads Google's JS SDK and a `RecaptchaVerifier` (the legacy `firebase_auth_vm/lib/src/util/http_server.dart:20-185` does this with firebasejs 7.10.0 and an invisible widget that redirects the token back to the server) | High: the page depends on Google's hosted script, on `localhost` being an authorised domain and a valid origin for the key (not checked), on the project's enforcement state, and on a score Google gives a localhost page (not checked). It has the ToS question below. |
| (c) Nothing | Real numbers on a real project without a token | | Not applicable |

Terms of service. Using Google's reCAPTCHA from a page that this package serves on localhost, or from a WebView, is
a use of Google's widget and of the Firebase hosted JS; whether that is allowed for a library that other apps embed was
not checked and is the owner's call. The official JS SDK itself does not offer phone in Node
(`platform_node/index.ts:87-91`: every phone export is `fail`), which is the same position as option (a) plus (b).

**Shim API shape.** FlutterFire's platform interface has two entry points and both can carry a proof.

- `signInWithPhoneNumber(phoneNumber, RecaptchaVerifierFactoryPlatform)` returns a `ConfirmationResultPlatform`
  (`verificationId`, `confirm(code)`). The verifier has `Future<String> verify()` (flutterfire
  `platform_interface_recaptcha_verifier_factory.dart:118`). The shim can call `verify()` and send the string as
  `recaptchaToken`, so an app on desktop passes its own verifier subclass that returns a token; with
  `appVerificationDisabledForTesting` set, it can skip the call.
- `verifyPhoneNumber(...)` takes `codeSent(verificationId, resendToken)`, `verificationFailed`,
  `verificationCompleted` and `codeAutoRetrievalTimeout`. With REST, `codeSent` is the only success path:
  `verificationCompleted` (instant verification and auto-retrieval) exists only through Google Play services on Android, so it
  never fires, and `codeAutoRetrievalTimeout` can fire when the timeout elapses. `forceResendingToken` has no REST
  meaning; a resend is another `sendVerificationCode` call. The `autoRetrievedSmsCodeForTesting` parameter and
  `setSettings(phoneNumber, smsCode)` are Android test helpers and can stay ignored.
- `setSettings(appVerificationDisabledForTesting: true)` is the natural switch for "send no proof" or a fixed marker.
  The shim currently accepts and drops it (`firebase_auth.dart:283-291`).
- `PhoneAuthProvider.credential(verificationId, smsCode)` and `PhoneAuthCredential` need the conversion in
  `convert.dart:278` to produce the client's phone credential, and the JS JSON form (`toJSON`/`fromJSON`,
  `core/credentials/phone.ts:100,121`) for parity with the OAuth and email credentials already done.

## Sizes

The unit is the one in `docs/auth_client_assessment.md`: what one implementer agent did in a day on the Auth client.
Tests run against the Auth emulator, reading codes from `verificationCodes`.

| Piece | What | Agent days |
|---|---|---|
| A1. Client REST and credential | `sendVerificationCode`, `signInWithPhoneNumber`, `PhoneAuthCredential` with JSON, `signInWithCredential` / `link` / `reauthenticate` with phone (including `temporaryProof` and `need-confirmation`), `updatePhoneNumber`, error codes (`missing-phone-number`, `missing-verification-code`, `invalid-phone-number`, `quota-exceeded`, `missing-app-credential`, `invalid-app-credential`, `captcha-check-failed`), `AppVerification` type with v2, Enterprise and none | 3 to 4 |
| A2. Shim | `signInWithPhoneNumber` and `ConfirmationResult`, `verifyPhoneNumber` callbacks, `linkWithPhoneNumber`, `updatePhoneNumber`, phone credential conversion, `setSettings` mapping | 2 to 3 |
| A3. SMS second factor | `mfaEnrollment:start/finalize` and `mfaSignIn:start/finalize` with `phoneEnrollmentInfo` and `phoneVerificationInfo`; resolver for a phone hint; shim `PhoneMultiFactorGenerator` and the resolver's phone assertion | 2.5 to 3.5 |
| B1. Enterprise handling | `GET /v2/recaptchaConfig`, enforcement state, the `NO_RECAPTCHA` marker, the `AUDIT` retry; useful only when a token source exists | 1.5 |
| B2. Loopback reCAPTCHA page | Server, page, timeout, state check, a test with a fake page; the legacy code is a guide, not a base | 3 to 5 |
| CI | One emulator job step, no new job | 0.5 |

| Option | Contents | Agent days |
|---|---|---|
| 1. Emulator and test numbers, with the proof hook | A1, A2, CI | 6 to 8 |
| 2. Option 1 and SMS second factor | A1, A2, A3, CI | 9 to 11 |
| 3. Option 2 and Enterprise handling | plus B1 | 10.5 to 12.5 |
| 4. Option 3 and the loopback page | plus B2 | 13.5 to 17.5 |
| 5. Do nothing | keep `noPhone`; point to `firebase_dart` and the official plugins | 0 (about 0.5 to reword the docs) |

## Recommendation

Option 1, with the `AppVerification` hook in the public API from the first commit, then option 2 when someone needs SMS
second factor. This gives phone sign-in on the emulator and with test numbers, in the same shape as the JS API, and
lets an app that already has a token (a web build, a WebView, a backend step) use real numbers. It does not claim
real-number support on desktop. It closes gap 18 and half of gap 20, and leaves gap 19 for a user with an enforced project.

The reasons for stopping short of the loopback page: it is the fragile part (Google's hosted script, a key origin and a
score that nobody here has measured), it needs a decision on terms of service, and the value is for desktop users
with real numbers, which nobody has asked for. `firebase_dart` already offers a loopback reCAPTCHA page on IO
(`docs/auth_client_assessment.md`, "Another pure-Dart option exists").

**Questions only the owner can answer.**

1. Is there a user or an app of yours that needs real phone numbers on desktop or command line? If not, option 1 is
   enough and option 4 stays off the list.
2. May one request be sent to a throwaway project with a registered test number and no app proof, to settle whether the
   server accepts it, and with the phone provider in `OFF`, `AUDIT` and `ENFORCE`? Which project, and who runs it?
3. Is serving Google's reCAPTCHA from a localhost page or a WebView acceptable under the terms you accept for this
   library? (Only matters for option 4.)
4. Should the library name `firebase_dart` in the README as the route for real numbers on desktop, as it does today?
5. Should SMS second factor wait for a user, or ship with phone sign-in?
6. Does the shim's `setSettings(appVerificationDisabledForTesting: true)` mean "send no proof" (iOS shape) or "send a
   fixed marker" (JS shape)? The answer from question 2 decides; until then the hook lets the app choose.

## Not checked

- No request was sent to any Google or Firebase service, so the following are open: whether the server accepts
  `sendVerificationCode` for a test number with no proof, with a junk `recaptchaToken`, or with a junk Enterprise token;
  how `ENFORCE` and SMS defense treat test numbers; what the Android SDK sends in test mode (closed source).
- The Enterprise and SMS defense pages are marked Preview; their behavior may change. Google's page for
  `v2/projects/updateConfig` was not read beyond the field names quoted from the SMS defense page.
- Whether `localhost` is accepted as an origin for the key that `recaptchaParams` returns, and what score a localhost
  page or a WebView gets.
- Whether App Check enforcement covers Auth's phone calls.
- The flutterfire platform interface was read for `RecaptchaVerifierFactoryPlatform` and `ConfirmationResultPlatform`
  only, from the `main` branch on GitHub, not from the version pinned by the shim.
- The emulator's handling of console test numbers; the emulator's own behavior was read from source, not run.
- Sizes are estimates scaled from the TOTP work and the phone code of the JS SDK (534 lines in
  `strategies/phone.ts`, 220 in `providers/phone.ts`, 144 in `core/credentials/phone.ts`, 102 in
  `mfa/assertions/phone.ts`); nothing was measured.

Sources read: firebase-js-sdk `a086865` (2026-11-20, `packages/auth/src`), firebase-ios-sdk `cef246f` (2026-11-20,
`FirebaseAuth/Sources`), firebase-tools `a134d3f` (2026-11-21, `src/emulator/auth`), this repository at `8addaf0`, and the
public pages cited inline, fetched on 2026-11-21.
