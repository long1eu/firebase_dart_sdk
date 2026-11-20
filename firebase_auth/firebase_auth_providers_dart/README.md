# firebase_auth_providers_dart

Unofficial, pure-Dart token providers for
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) and
[`firebase_app_dart`](https://pub.dev/packages/firebase_app_dart): what Firestore sends with its requests so
that they run as someone. You need it when your users sign in with Firebase Auth (email and password,
email link, anonymous, custom token, or a Google, Apple, Microsoft, OIDC, ... token your app already has) and
their requests must pass your security rules, or when a server or tool uses a service account or Application
Default Credentials. Without it, requests carry no user, which is enough for
the emulator and open rules. It is not affiliated with or supported by Google or Firebase.

> **Status: 0.3.0.** Verified with unit tests and against the Firebase
> emulators only: nothing was run against the real Firebase Auth service or Google's token
> endpoint.

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
| `fetchSignInMethodsForEmail(auth, email)` (deprecated upstream: empty with email enumeration protection) | `fetchSignInMethodsForEmail(email)` | emulator, Chrome |
| `connectAuthEmulator(auth, url)` | the `emulatorHost` argument | emulator, Chrome |
| `user.uid`, `email`, `emailVerified`, `isAnonymous`, `displayName`, `photoURL`, `phoneNumber`, `tenantId`, `metadata`, `providerData` | `currentUser` (`AuthUser`, read with `accounts:lookup` after every sign-in) | emulator |
| `setPersistence` (`inMemory`, `browserSession`, `browserLocal`) | an `AuthStorage`: `InMemoryAuthStorage` (default), `WebAuthStorage.session()`, `WebAuthStorage.local()`, and `FileAuthStorage(path)` on the VM | unit, Chrome |
| `ActionCodeSettings` (`url`, `handleCodeInApp`, `iOS`, `android`, `linkDomain`) | `ActionCodeSettings` (flattened; no `dynamicLinkDomain`) | unit |
| Popup and redirect flows on desktop and command line (no JS SDK equivalent) | `signInWithOAuthLoopback(OAuthLoopbackProvider.google(...))` / `.oidc(...)` / `.discover(...)`, or `authorizeWithOAuthLoopback(...)` for the credential (VM only; see below) | unit (fake identity provider) |
| Popup and redirect flows in a browser, `signInWithProvider`, SAML | – (use a token from elsewhere with `signInWithCredential`) | |
| `multiFactor(user).getSession()` + `TotpMultiFactorGenerator.generateSecret`, `TotpSecret.generateQrCodeUrl` | `startTotpEnrollment()`, `TotpSecret.otpauthUri(issuer:)` and its parameters (see below) | unit (fake backend) |
| `multiFactor(user).enroll(TotpMultiFactorGenerator.assertionForEnrollment(...))`, `unenroll`, `enrolledFactors` | `finalizeTotpEnrollment(secret, code:, displayName:)`, `unenrollMultiFactor(uid)`, `AuthUser.enrolledFactors` | unit; real project, 2026-11-20 |
| `getMultiFactorResolver(auth, error).resolveSignIn(TotpMultiFactorGenerator.assertionForSignIn(...))` | `FirebaseAuthMultiFactorException.resolver.resolveSignInWithTotp(code)` | unit; real project, 2026-11-20 |
| Phone sign-in, SMS second factors (enrolment and sign-in), reCAPTCHA, `revokeAccessToken`, passkeys | – (SMS factors are listed and can be unenrolled) | |

Of the federated providers, only the request and the flows were exercised, against the emulator with fake
tokens (the emulator checks no signature, audience or nonce). The checks of the real backend (the audience of an
ID token must be a client id configured for the provider in the project, which matters for Google, Microsoft,
Yahoo and OIDC providers; Apple's nonce) were not run.

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
// Enrol: show the URI as a QR code (or the secret for typing in), then ask for a code of the app.
final TotpSecret secret = await auth.startTotpEnrollment();
print(secret.otpauthUri(issuer: 'My App')); // otpauth://totp/My%20App:ada@example.com?secret=...
await auth.finalizeTotpEnrollment(secret, code: '123456', displayName: 'Phone');
print(auth.currentUser!.enrolledFactors); // [MultiFactorInfo(totp, ...)]

// Sign in: the first factor throws, the resolver finishes with a code.
try {
  await auth.signInWithEmailAndPassword(email: email, password: password);
} on FirebaseAuthMultiFactorException catch (e) {
  final UserCredential result = await e.resolver!.resolveSignInWithTotp(await askForCode());
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

- The browser is opened with `open`, `xdg-open` or `rundll32` (`openInSystemBrowser`); pass `presenter:` to open it
  another way (`url_launcher` in a Flutter app, or a printed link). The package depends on no Flutter plugin.
- The code is exchanged at the provider's token endpoint with the client id and secret, or, with
  `exchangeEndpoint:`, on a server of yours that keeps the secret. That endpoint gets the request of
  `google_sign_in_dart`'s code exchange endpoint (a JSON text with `code`, `codeVerifier`, `clientId` and
  `redirectUrl`), so an existing Cloud Function for it keeps working.
- `OAuthLoopbackProvider.oidc(providerId: 'oidc.<name>', authorizationEndpoint:, tokenEndpoint:, clientId:)` or
  `OAuthLoopbackProvider.discover(issuer:, ...)` for an OpenID Connect provider of Identity Platform; the client id
  must be the one configured for the provider in the project.
- `authorizeWithOAuthLoopback` returns the tokens and the credential without signing in, for
  `linkWithCredential` and `reauthenticateWithCredential`.
- Only the code is exchanged: once signed in, the Firebase session refreshes itself; the provider's refresh token is
  returned but not used.
- Errors are `FirebaseAuthException`s: `timeout` (five minutes by default), `user-cancelled`,
  `oauth-state-mismatch`, `invalid-oauth-response`, `missing-or-invalid-nonce`, `invalid-credential` (the code was
  refused) and `network-request-failed`.

Tested against an in-process fake identity provider only: no real Google client or Firebase project was used.

## Documentation

- **Guide**: [authentication and App Check](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md):
  the token lifecycle, a switch of users, the sign-in methods (email link, federated credentials, linking),
  tenants and language, keeping the user signed in (and where to store the session safely), the Auth emulator,
  server credentials, and how the providers were tested.
  [All guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md).
- **API reference**: [pub.dev/documentation/firebase_auth_providers_dart](https://pub.dev/documentation/firebase_auth_providers_dart/latest/).

## Limits

- Nothing was run against the real Firebase Auth service or Google's token endpoint: the
  providers were tested with unit tests and against the Firebase emulators. Application Default
  Credentials are delegated to `package:googleapis_auth` without a test of their own.
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
