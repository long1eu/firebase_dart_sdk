# firebase_auth_providers_dart

Unofficial, pure-Dart token providers for
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) and
[`firebase_app_dart`](https://pub.dev/packages/firebase_app_dart): what Firestore sends with its requests so
that they run as someone. You need it when your users sign in with Firebase Auth (email and password,
email link, anonymous, custom token, or a Google, Apple, Microsoft, OIDC, ... token your app already has) and
their requests must pass your security rules, or when a server or tool uses a service account or Application
Default Credentials. Without it, requests carry no user, which is enough for
the emulator and open rules. It is not affiliated with or supported by Google or Firebase.

> **Status: 0.3.1.** Verified with unit tests and against the Firebase emulators. One flow was also run
> against a real Firebase project: Google sign-in in the system browser with a "Desktop app" client (see
> [Browser sign-in on desktop and command line](#browser-sign-in-on-desktop-and-command-line)).

## Install

```shell
dart pub add firebase_auth_providers_dart
```

Dart 3.8 or later. You also need `firebase_app_dart`, and `cloud_firestore_dart` for the
requests the tokens are for.

## Quick start

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    appId: '1:1234567890:dart:example',
    projectId: 'my-project',
  ),
);
// Before the Firestore instance is created: it becomes the token provider of the app.
final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);

await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: password);
await firestore.doc('users/${auth.uid}/notes/first').set({'text': 'hello'});
await auth.signOut();
```

A server uses `app.authProvider = OAuthTokenProvider.serviceAccount(keyJson)` or
`app.authProvider = applicationDefaultCredentials()` (from `adc.dart`) instead, also before the
Firestore instance is created.

## What it offers

| Provider | For | Security rules | Status |
| --- | --- | --- | --- |
| `FirebaseUserAuth`: anonymous, email and password, email link, custom-token and federated (token exchange) sign-in over REST; linking; token refresh; sign-out; account management; FlutterFire's streams; a session kept in an `AuthStorage` (memory, an owner-only file, or browser storage) | apps with end users (VM, Flutter, web) | apply (`request.auth` is the user) | stable, emulator only |
| `OAuthTokenProvider.serviceAccount`: a service account key | servers | **bypassed** | stable, unit tests only |
| `applicationDefaultCredentials()` (`adc.dart`, VM only) | servers, command line tools | **bypassed** | stable, not exercised by tests |

Pick the provider by who makes the requests; of the providers here, only `FirebaseUserAuth` keeps
security rules in force:

![Who makes the requests? A person signed in to your app: FirebaseUserAuth.forApp(app), security rules apply. A server or tool on Google Cloud or with gcloud credentials: applicationDefaultCredentials(), VM only, rules bypassed. A server or tool with a service account key file: OAuthTokenProvider.serviceAccount(key), rules bypassed. Access tokens from a source of your own: OAuthTokenProvider(fetch), rules bypassed.](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/images/readme/auth_providers.svg)

One example per task, each runnable on its own (the header of each file says how):

| Task | Example | Needs |
| --- | --- | --- |
| Anonymous sign-in, the token, `userChanges` | [`main.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/main.dart) | Auth emulator |
| Email and password: sign up, sign in, the errors of a sign-in form | [`email_password.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/email_password.dart) | Auth emulator |
| Email verification, profile, password reset, reauthentication, deletion | [`account_flows.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/account_flows.dart) | Auth emulator |
| Custom token sign-in and its claims | [`custom_token.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/custom_token.dart) | Auth emulator |
| Keeping the user signed in across restarts: `FileAuthStorage` | [`persistent_session.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/persistent_session.dart) | Auth emulator |
| `authStateChanges()`, linking a Google credential to an anonymous user, email link sign-in, `unlink` | [`linking_and_email_link.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/linking_and_email_link.dart) | Auth emulator |
| Wiring a provider into Firestore; the rules see the user | [`firestore_wiring.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/firestore_wiring.dart) | Auth and Firestore emulators |
| Google sign-in through the system browser, for desktop apps and command line tools | [`google_desktop_sign_in.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/google_desktop_sign_in.dart) | a Google OAuth client and a real project (or the Auth emulator) |
| A service account key, its path in an environment variable | [`service_account.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/service_account.dart) | a real project |
| Application Default Credentials on a server | [`adc_server.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/adc_server.dart) | a real project |

[`example/README.md`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/README.md) explains how to start the emulators.

This is **not** a port of the whole Firebase Auth SDK: it has the REST-backed operations of the JS SDK
(see [What is supported](#what-is-supported)), with FlutterFire's names. Federated providers work by
**token exchange**: the app gets the provider's ID token or access token itself (a platform sign-in package, a
browser flow of its own) and `signInWithCredential` exchanges it, as the JS SDK does for a credential. There are
no popup or redirect flows (nothing opens a sign-in page) and no phone sign-in; second factors work with
authenticator apps (TOTP) only.

```dart
final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
auth.authStateChanges().listen((AuthUser? user) => print(user?.uid ?? 'signed out'));

// From Google Sign-In, or any other way your app signs the user in with Google.
const String googleIdToken = '<a Google ID token>';
final UserCredential result = await auth.signInWithCredential(
  GoogleAuthProvider.credential(idToken: googleIdToken),
);
print(result.additionalUserInfo?.isNewUser);
```

**Platforms.** The Dart VM (servers, command line tools, Flutter) and the web; `adc.dart` is VM
only. `FirebaseUserAuth` was run in Chrome against the Auth emulator.

## What is supported

`FirebaseUserAuth` compared with the modular JS SDK (`firebase/auth`). "Emulator" means tested
against the Firebase Auth emulator; nothing was run against the real service.

| JS SDK | `FirebaseUserAuth` | Tested |
| --- | --- | --- |
| `signInAnonymously` | `signInAnonymously()` | emulator, Chrome |
| `signInWithEmailAndPassword` | `signInWithEmailAndPassword(email:, password:)` | emulator |
| `createUserWithEmailAndPassword` | `createUserWithEmailAndPassword(email:, password:)` | emulator, Chrome |
| `signInWithCustomToken` | `signInWithCustomToken(token)` | emulator |
| `signInWithCredential` with `EmailAuthProvider` | `signInWithCredential(EmailAuthProvider.credential(...))` / `credentialWithLink(...)` | emulator |
| `signInWithCredential` with `GoogleAuthProvider`, `OAuthProvider('apple.com')` (with raw nonce), `OAuthProvider('microsoft.com')`, `OAuthProvider('oidc.*')` (ID token) | `signInWithCredential(GoogleAuthProvider.credential(idToken:))`, `AppleAuthProvider.credentialWithIDToken(...)`, `MicrosoftAuthProvider.credential(...)`, `OAuthProvider('oidc.x').credential(idToken:)` | emulator (fake tokens) |
| `signInWithCredential` with `FacebookAuthProvider`, `GithubAuthProvider`, `TwitterAuthProvider`, `OAuthProvider('yahoo.com')` (access token) | `FacebookAuthProvider.credential(token)`, `GithubAuthProvider.credential(token)`, `TwitterAuthProvider.credential(accessToken:, secret:)`, `YahooAuthProvider.credential(token)` | emulator (fake tokens) |
| `linkWithCredential`, `reauthenticateWithCredential`, `unlink` | `linkWithCredential(credential)`, `reauthenticateWithCredential(credential)` (and `reauthenticateWithEmailAndPassword`), `unlink(providerId)` | emulator |
| `credentialFromResult` / `credentialFromError` | `UserCredential.credential` / `FirebaseAuthException.credential` (with `account-exists-with-different-credential`, `credential-already-in-use`) | emulator |
| `sendSignInLinkToEmail`, `isSignInWithEmailLink`, `signInWithEmailLink`, `parseActionCodeURL` | the same names; `ActionCodeURL.parseLink(link)` | emulator |
| `AuthCredential.toJSON`, `EmailAuthCredential.fromJSON`, `OAuthCredential.fromJSON`, `OAuthProvider.credentialFromJSON` | `toJson()`, `EmailAuthCredential.fromJson(json)`, `OAuthCredential.fromJson(json)`, `OAuthProvider.credentialFromJson(json)` (same JSON; an email link keeps only its code and tenant) | unit (fixtures from the JS sources) |
| `signOut` | `signOut()` | emulator |
| `onAuthStateChanged` / `onIdTokenChanged` | `authStateChanges()` / `idTokenChanges()` (start with the current user); `userChanges()` also after profile changes; `onTokenChanged` for Firestore | unit, emulator |
| `beforeAuthStateChanged`, `authStateReady`, `updateCurrentUser` | the same names | unit, emulator |
| `languageCode`, `useDeviceLanguage` | `languageCode`, `setLanguageCode`, `useDeviceLanguage()` (`X-Firebase-Locale`) | unit (the emulator ignores it), Chrome |
| `tenantId` | `tenantId` (sent with the requests the JS SDK sends it with; `tenant-id-mismatch`) | emulator |
| `validatePassword` | `validatePassword(password)` (`PasswordPolicy`, `PasswordValidationStatus`) | unit only (the emulator does not implement `v2/passwordPolicy`) |
| `getAdditionalUserInfo` | `UserCredential.additionalUserInfo` (`isNewUser`, `providerId`, `profile`, `username`) | emulator |
| `user.getIdToken(forceRefresh)` / `getIdTokenResult` | `getAccessToken(forceRefresh:)` (a `GetTokenResult` with the claims) | emulator |
| `sendPasswordResetEmail(auth, email, settings)` | `sendPasswordResetEmail(email:, actionCodeSettings:)` | emulator, Chrome |
| `confirmPasswordReset(auth, code, password)` | `confirmPasswordReset(code:, newPassword:)` | emulator |
| `verifyPasswordResetCode(auth, code)` | `verifyPasswordResetCode(code)` | emulator |
| `checkActionCode(auth, code)` | `checkActionCode(code)` (`ActionCodeInfo`; an unknown operation is `ActionCodeOperation.unknown`) | emulator |
| `applyActionCode(auth, code)` | `applyActionCode(code)` (does not reload the user, like JS) | emulator |
| `sendEmailVerification(user, settings)` | `sendEmailVerification(actionCodeSettings:)` | emulator, Chrome |
| `verifyBeforeUpdateEmail(user, email, settings)` | `verifyBeforeUpdateEmail(newEmail, actionCodeSettings:)` | emulator |
| `updateEmail(user, email)` | `updateEmail(newEmail)` | emulator |
| `updatePassword(user, password)` | `updatePassword(newPassword)` | emulator, Chrome |
| `updateProfile(user, {displayName, photoURL})` | `updateProfile(displayName:, photoUrl:)`; `''` removes a value (JS: `null`) | emulator, Chrome |
| `user.reload()` | `reload()` | emulator, Chrome |
| `user.delete()` / `deleteUser(user)` | `deleteCurrentUser()` | emulator, Chrome |
| `revokeToken(withAuthorizationCode:)` of the iOS SDK (Sign in with Apple; no JS equivalent) | `revokeToken(authorizationCode)` (`v2/accounts:revokeToken`; the user stays signed in; sends `tenantId` when set) | unit only |
| `revokeAccessToken(auth, token)` (Sign in with Apple) | `revokeAccessToken(token)` (`v2/accounts:revokeToken`, token type `ACCESS_TOKEN`; the user stays signed in; throws `null-user` where JS does nothing) | unit only |
| `fetchSignInMethodsForEmail(auth, email)` (deprecated upstream: empty with email enumeration protection) | `fetchSignInMethodsForEmail(email)` | emulator, Chrome |
| `connectAuthEmulator(auth, url)` | the `emulatorHost` argument | emulator, Chrome |
| `user.uid`, `email`, `emailVerified`, `isAnonymous`, `displayName`, `photoURL`, `phoneNumber`, `tenantId`, `metadata`, `providerData` | `currentUser` (`AuthUser`, read with `accounts:lookup` after every sign-in) | emulator |
| `setPersistence` (`inMemory`, `browserSession`, `browserLocal`) | an `AuthStorage`: `InMemoryAuthStorage` (default), `WebAuthStorage.session()`, `WebAuthStorage.local()`, and `FileAuthStorage(path)` on the VM, given to the constructor or switched later with `setStorage`, which moves the session | unit, Chrome |
| `ActionCodeSettings` (`url`, `handleCodeInApp`, `iOS`, `android`, `linkDomain`) | `ActionCodeSettings` (flattened; no `dynamicLinkDomain`) | unit |
| Popup and redirect flows on desktop and command line (no JS SDK equivalent) | `signInWithOAuthLoopback(OAuthLoopbackProvider.google(...))` / `.github(...)` / `.oidc(...)` / `.discover(...)`, `linkWithOAuthLoopback`, `reauthenticateWithOAuthLoopback`, or `authorizeWithOAuthLoopback(...)` for the credential (VM only; see below) | unit (fake identity provider); Google with a Desktop client against a real project |
| Popup and redirect flows in a browser, `signInWithProvider`, SAML | – (use a token from elsewhere with `signInWithCredential`) | |
| `multiFactor(user).getSession()` + `TotpMultiFactorGenerator.generateSecret`, `TotpSecret.generateQrCodeUrl` | `startTotpEnrollment()`, `TotpSecret.otpauthUri(issuer:)` and its parameters (see below) | unit (fake backend) |
| `multiFactor(user).enroll(TotpMultiFactorGenerator.assertionForEnrollment(...))`, `unenroll`, `enrolledFactors` | `finalizeTotpEnrollment(secret, code:, displayName:)`, `unenrollMultiFactor(uid)`, `AuthUser.enrolledFactors` | unit; real project, 2026-11-20 |
| `getMultiFactorResolver(auth, error).resolveSignIn(TotpMultiFactorGenerator.assertionForSignIn(...))` | `FirebaseAuthMultiFactorException.resolver.resolveSignInWithTotp(code)` | unit; real project, 2026-11-20 |
| `RecaptchaVerifier` (a reCAPTCHA v2 token) on desktop and command line; `getRecaptchaParams` | `AppVerification.recaptchaV2Loopback()` (VM only; the `RecaptchaFlow` of `secure_flow`), `getRecaptchaSiteKey()`, and the `AppVerification` value the phone calls will take (see below) | unit (simulated browser, fake backend); not run against Google |
| Phone sign-in, SMS second factors (enrolment and sign-in), reCAPTCHA Enterprise configuration, passkeys | – (SMS factors are listed and can be unenrolled) | |

Of the federated providers, only the request and the flows were exercised, against the emulator with fake
tokens (the emulator checks no signature, audience or nonce). The checks of the real backend (the audience of an
ID token must be a client id configured for the provider in the project, which matters for Google, Microsoft,
Yahoo and OIDC providers; Apple's nonce) were not run, except for Google: a Google ID token from
`signInWithOAuthLoopback` with a Desktop client signed in to a real project.

Error codes are those of the JS SDK: its complete map of server codes (`SERVER_ERROR_MAP` of
`packages/auth/src/api/errors.ts`: `EXPIRED_OOB_CODE` is `expired-action-code`, `USER_NOT_FOUND` is
`user-token-expired`, ...), and any other code of the backend in kebab case (`QUOTA_EXCEEDED` is
`quota-exceeded`). An answer with HTTP 200 and an `errorMessage` is an error, as in the JS SDK. Operations of
the signed-in user throw `null-user` when nobody is signed in, and sign the user out when the
backend answers `user-disabled` or `user-token-expired` (`_logoutIfInvalidated` of the JS SDK).

### Authenticator app second factors (TOTP)

Needs Identity Platform with TOTP enabled for the project (the Auth emulator has no TOTP), and a verified email
address on the account.

```dart
final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);

// Enrol: show the URI as a QR code (or the secret for typing in), then ask for a code of the app.
final TotpSecret secret = await auth.startTotpEnrollment();
print(secret.otpauthUri(issuer: 'My App')); // otpauth://totp/My%20App:ada@example.com?secret=...
await auth.finalizeTotpEnrollment(secret, code: '123456', displayName: 'Phone');
print(auth.currentUser!.enrolledFactors); // [MultiFactorInfo(totp, ...)]

// Sign in: the first factor throws, the resolver finishes with a code.
try {
  await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: '<the password>');
} on FirebaseAuthMultiFactorException catch (e) {
  // The code the user reads from the authenticator app.
  final UserCredential result = await e.resolver!.resolveSignInWithTotp('654321');
  print(result.user?.uid);
}

// Remove a factor (TOTP or SMS).
await auth.unenrollMultiFactor(auth.currentUser!.enrolledFactors.first.uid);
```

Enrolment, unenrolment and the resolver update the session like any sign-in or token change: the streams emit,
the new tokens are stored, and the account is read again. A reauthentication of an account with a second factor
goes through the same resolver. An account whose only second factors are SMS cannot finish a sign-in here: the
exception's message says so and `resolveSignInWithTotp` throws `multi-factor-info-not-found`.

The calls use the Identity Toolkit API v2. The published Identity Toolkit v2 protos have no TOTP fields, so all
multi-factor calls use JSON.

On 2026-11-20 one run against a real Identity Platform project went through enrolment, sign-in with the second factor and removal, with the errors for an unverified email, a wrong code and a missing display name. Tenants and SMS factors were not part of it.

### Browser sign-in on desktop and command line

`signInWithOAuthLoopback` (VM only; it throws an `UnsupportedError` on the web) signs the user in to Google or an
OpenID Connect provider in the system browser, the way RFC 8252 describes for native apps: an authorization code
request with PKCE (S256), a random `state` and a nonce, whose redirect comes back to a one-shot HTTP server bound to
127.0.0.1 on a free port. The code is exchanged for the provider's tokens and the ID token signs in to Firebase
with `signInWithCredential`.

```dart
final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
final UserCredential result = await auth.signInWithOAuthLoopback(
  OAuthLoopbackProvider.google(
    clientId: '<the client id of a "Desktop app" OAuth client>',
    clientSecret: '<its client secret>', // not confidential for a desktop client, says Google
  ),
);
print(result.user?.email);
```

- The request runs as an `OAuthFlow` of [`secure_flow`](https://pub.dev/packages/secure_flow) (its presenters are
  re-exported here). Without `presenter:`, the flow takes the best presenter of `environment:` (the real one by
  default): a `ProviderAppPresenter` registered for the provider (an SDK that returns the provider's tokens; none is
  part of these packages), then the system browser (`open`, `xdg-open` or `rundll32`), an in-app browser, the
  console (only the URL, on stderr, over SSH or without a display). Pass `presenter:` to choose:
  `SystemBrowserPresenter()`, `ConsolePresenter()`, or `CallbackPresenter((Uri url) => launchUrl(url))` with
  `url_launcher` in a Flutter app. A presenter the flow does not accept (a web view,
  `CallbackPresenter(..., kind: SecurePresenterKind.embeddedWebView)`) is refused with `SecureFlowRefused`, never replaced.
  The package depends on no Flutter plugin.
- Tokens from a provider app skip the code exchange: the ID token must carry the nonce claim, and it must be the
  hash that was sent (`missing-or-invalid-nonce` otherwise), and the raw nonce goes to Firebase with the credential
  (for OpenID Connect providers), as after a redirect. An access token without an ID token fails with
  `invalid-oauth-response` unless the provider is made with `acceptAccessTokenOnly: true`: such a token has no
  binding to this request (no nonce, no state), so turn it on only for a provider whose app returns no ID token.
- The code is exchanged at the provider's token endpoint with the client id and the secret. Google with a
  "Desktop app" client needs nothing more: Google says the secret of such a client is not confidential.
- `exchangeCode:` is optional. It is for a provider that wants a confidential client, whose secret must stay on a
  server of yours. It is the counterpart of `serverAuthCode` in `google_sign_in`: the function gets the code, the
  PKCE verifier, the redirect URL and the client id, sends them to your server, and returns the JSON of the token
  endpoint. How you call your server is up to you. See the example below.
- `OAuthLoopbackProvider.oidc(providerId: 'oidc.<name>', authorizationEndpoint:, tokenEndpoint:, clientId:)` or
  `OAuthLoopbackProvider.discover(issuer:, ...)` for an OpenID Connect provider of Identity Platform; the client id
  must be the one configured for the provider in the project.
- `OAuthLoopbackProvider.github(clientId:, clientSecret:)` for GitHub, with a GitHub OAuth App whose authorization
  callback URL is `http://127.0.0.1`, exactly so, without a `/` at the end (GitHub accepts any port on a loopback
  redirect, but with `http://127.0.0.1/` it answers "The redirect_uri is not associated with this application").
  GitHub's code exchange needs the client secret even with PKCE, so it ships with the app. The default scopes are
  `read:user user:email`; no nonce is sent, and Firebase gets the access token only. The OAuth App must be the one
  whose client id and secret are set for GitHub in the Firebase project: the backend checks the access token
  against that app and answers `INVALID_IDP_RESPONSE` (`invalid-credential`) for a token of another app.
- `linkWithOAuthLoopback` links the provider to the signed-in user, and `reauthenticateWithOAuthLoopback` signs
  the same user in again. Both take the same arguments as `signInWithOAuthLoopback`, and throw `null-user` before
  the browser opens when nobody is signed in.
- `authorizeWithOAuthLoopback` returns the tokens and the credential without signing in.
- `provider.copyWith(scopes:, customParameters:)` makes a provider for one request that asks for more, such as one
  more scope: `google.copyWith(scopes: <String>[...google.scopes, 'https://www.googleapis.com/auth/drive.file'])`.
- Only the code is exchanged: once signed in, the Firebase session refreshes itself; the provider's refresh token is
  returned but not used.
- Errors are `FirebaseAuthException`s: `timeout` (five minutes by default), `user-cancelled`,
  `invalid-oauth-response`, `missing-or-invalid-nonce`, `invalid-credential` (the code was refused) and
  `network-request-failed` (also when the exchange takes more than 30 seconds).
- The loopback server ends the wait only for the redirect of this sign-in: the `Host` header must be
  `127.0.0.1:<port>` and the `state` must be the one sent. Any other request gets an error page, and the server keeps
  waiting until the timeout.
- The ID token is not verified locally. Firebase checks it at sign-in, so do not trust its claims before that.
- On a machine shared with other users, another local user can read the authorization URL from the process list.
  This is inherent to loopback flows (RFC 8252); PKCE keeps the code useless to them.

An `exchangeCode` that posts the four values to a server of yours:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

final OAuthLoopbackProvider provider = OAuthLoopbackProvider.oidc(
  providerId: 'oidc.example',
  authorizationEndpoint: Uri.parse('https://idp.example.com/authorize'),
  tokenEndpoint: Uri.parse('https://idp.example.com/token'),
  clientId: '<the client id>',
  exchangeCode: (OAuthAuthorizationCode code) async {
    final http.Response response = await http.post(
      Uri.parse('https://api.example.com/oauth/exchange'),
      headers: <String, String>{'content-type': 'application/json'},
      body: jsonEncode(<String, String>{
        'code': code.code,
        'codeVerifier': code.codeVerifier,
        'redirectUri': code.redirectUri,
        'clientId': code.clientId,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('The exchange failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  },
);
```

An error thrown by `exchangeCode` becomes `invalid-credential`; throw a `FirebaseAuthException` to choose the code.

On 2026-11-20, Google sign-in with a Desktop client was run against a real Firebase project: the code was
exchanged directly with the client secret and PKCE, and the redirect was `http://127.0.0.1:<port>`.
The same day, a generic OpenID Connect provider (`oidc.<name>` of Identity Platform, with Google as the issuer) was
run against the real project twice: with `discover` and a direct exchange, and with explicit endpoints and an
`exchangeCode` callback, which also reauthenticated the user. GitHub was run with a real OAuth App: with another
GitHub app configured in the project the backend refused the token (see above); with the same app, the sign-in
gave `account-exists-with-different-credential` for an email that already had an account, and after a Google
sign-in `linkWithOAuthLoopback` linked `github.com` to that account and `unlink` removed it again. A GitHub
sign-in that creates a new account has not been run on a real project.

Not offered by the loopback helper:

- Facebook: its documentation does not cover `http` loopback redirects with an arbitrary port (Strict Mode wants an
  exact match), and Firebase documents a Facebook ID token only for iOS Limited Login.
- Microsoft: Firebase does not support direct sign-in with Microsoft OAuth tokens
  ([Firebase docs](https://firebase.google.com/docs/auth/web/microsoft-oauth)).
- Phone sign-in: not in the client yet. On a real project `sendVerificationCode` needs app verification
  (reCAPTCHA, Play Integrity or APNs); see the loopback reCAPTCHA page below.
- Auth-domain options (`customAuthDomain`): the loopback flow builds no hosted auth-domain page, so they do not
  apply.

### App verification and the loopback reCAPTCHA page

Phone requests (`accounts:sendVerificationCode`, the start of an SMS second factor) carry a proof that they come
from a real app. Phone sign-in is not in the client yet; these are the pieces it will use:

- `AppVerification`, a sealed value with three shapes: a reCAPTCHA v2 token
  (`AppVerification.recaptchaV2(source)`, where `source` is yours and is called with the project's site key, or
  `AppVerification.recaptchaV2Loopback()` for the page below); a reCAPTCHA Enterprise token of yours
  (`AppVerification.recaptchaEnterprise(source, clientType:)`); and no proof (`AppVerification.none()`, for the
  Auth emulator and test phone numbers, like the iOS SDK in test mode; whether a real project accepts it for a
  test number has not been checked).
- `auth.getRecaptchaSiteKey()`: the reCAPTCHA v2 site key of the project (`v1/recaptchaParams`), from the
  emulator when one is set (the emulator returns a fake key).
- `AppVerification.recaptchaV2Loopback(presenter:, timeout:)` (VM only; on the web the presenters throw an
  `UnsupportedError`): for each phone request, a `RecaptchaFlow` of `secure_flow` serves a page with the
  reCAPTCHA v2 checkbox for the project's site key on localhost, the presenter shows it (the default presenter of
  the environment when null), and the token the page posts back is the proof.

```dart
final AppVerification verification = AppVerification.recaptchaV2Loopback();
```

How the page is served (by `secure_flow`):

- The server listens on 127.0.0.1 and, on the same port, on ::1, and on no other interface. The page address is
  `http://localhost:<port>/<random path>?state=<random state>`: `localhost` is the domain that Firebase projects
  and their reCAPTCHA site keys allow by default, 127.0.0.1 is not. Listening on ::1 too means a browser that
  tries ::1 first for `localhost` still reaches this server, not another process.
- The page loads only Google's reCAPTCHA script (`https://www.google.com/recaptcha/api.js`), under a content
  security policy with a nonce. It follows the system's light or dark setting. Its referrer policy sends Google
  the origin only, not the path or the state.
- The token ends the wait only when posted to the random path with the `Host` `localhost:<port>`, the page's
  `Origin` (when sent), and the state of this check (compared in constant time). Anything else gets an error
  page and the server keeps waiting. Only one answer is ever taken.
- The server is closed on success, on timeout (the token source throws `timeout`, after five minutes by default)
  and when the presenter throws. Nothing is logged; the token and the state are never part of an exception
  message.

Not checked against Google: whether a token made on a localhost page is accepted for a real project. That depends
on the project (the allowed domains of the key, reCAPTCHA Enterprise enforcement, SMS defense). Serving Google's
widget from a page of your app is a use of reCAPTCHA under Google's terms; check that they fit your app.

## Documentation

- **Guide**: [authentication and App Check](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md):
  the token lifecycle, a switch of users, the sign-in methods (email link, federated credentials, linking),
  tenants and language, keeping the user signed in (and where to store the session safely), the Auth emulator,
  server credentials, and how the providers were tested.
  [All guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md).
- **API reference**: [pub.dev/documentation/firebase_auth_providers_dart](https://pub.dev/documentation/firebase_auth_providers_dart/latest/).

## Limits

- The providers were tested with unit tests and against the Firebase emulators. Only Google sign-in with a
  Desktop client (`signInWithOAuthLoopback`) was run against a real Firebase project, on 2026-11-20.
  `exchangeCode` and generic OpenID Connect providers were run only against a fake identity provider. Application
  Default Credentials are delegated to `package:googleapis_auth` without a test of their own.
- Federated sign-in needs a provider token the app obtained itself, or, on desktop and command line, the browser
  sign-in of `signInWithOAuthLoopback` (Google and OpenID Connect; not Apple, which does not accept loopback
  redirects). There are no popup or redirect flows in a browser.
  Phone sign-in, SMS second factors and reCAPTCHA are not there (the table above lists the
  rest). A project that enforces reCAPTCHA Enterprise for email and password refuses these sign-ins
  (`missing-recaptcha-token`).
- An account with a second factor signs in with an authenticator app code through
  `FirebaseAuthMultiFactorException.resolver`; an account with SMS second factors only cannot sign in here.
- The session is kept in memory unless you supply an `AuthStorage` (`FileAuthStorage`, `WebAuthStorage` or your
  own). The stored value is a credential, the refresh token: keep it where the platform keeps secrets.
- `signOut()` forgets the session locally; it does not revoke the refresh token on the backend.
- The token providers are read once, when the Firestore instance is created: set them first.
- Service account and Application Default Credentials tokens bypass security rules: use them on
  trusted machines only.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
