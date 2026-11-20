# firebase_auth_providers_dart

Unofficial, pure-Dart token providers for
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) and
[`firebase_app_dart`](https://pub.dev/packages/firebase_app_dart): what Firestore sends with its requests so
that they run as someone. You need it when your users sign in with Firebase Auth (email and password,
email link, anonymous, custom token, or a Google, Apple, Microsoft, OIDC, ... token your app already has) and
their requests must pass your security rules, or when a server or tool uses a service account or Application
Default Credentials. Without it, requests carry no user, which is enough for
the emulator and open rules. It is not affiliated with or supported by Google or Firebase.

> **Status: 0.3.0.** Verified with unit tests and against the Firebase emulators. One flow was also run
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
no popup or redirect flows (nothing opens a sign-in page), no phone sign-in and no sign-in with a second factor.

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
| Popup and redirect flows on desktop and command line (no JS SDK equivalent) | `signInWithOAuthLoopback(OAuthLoopbackProvider.google(...))` / `.oidc(...)` / `.discover(...)`, `linkWithOAuthLoopback`, `reauthenticateWithOAuthLoopback`, or `authorizeWithOAuthLoopback(...)` for the credential (VM only; see below) | unit (fake identity provider); Google with a Desktop client against a real project |
| Popup and redirect flows in a browser, `signInWithProvider`, SAML | – (use a token from elsewhere with `signInWithCredential`) | |
| Phone sign-in, reCAPTCHA, multi-factor sign-in and enrolment, TOTP, `revokeAccessToken`, passkeys | – | |

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
- The code is exchanged at the provider's token endpoint with the client id and the secret. Google with a
  "Desktop app" client needs nothing more: Google says the secret of such a client is not confidential.
- `exchangeCode:` is optional. It is for a provider that wants a confidential client, whose secret must stay on a
  server of yours. It is the counterpart of `serverAuthCode` in `google_sign_in`: the function gets the code, the
  PKCE verifier, the redirect URL and the client id, sends them to your server, and returns the JSON of the token
  endpoint. How you call your server is up to you. See the example below.
- `OAuthLoopbackProvider.oidc(providerId: 'oidc.<name>', authorizationEndpoint:, tokenEndpoint:, clientId:)` or
  `OAuthLoopbackProvider.discover(issuer:, ...)` for an OpenID Connect provider of Identity Platform; the client id
  must be the one configured for the provider in the project.
- `linkWithOAuthLoopback` links the provider to the signed-in user, and `reauthenticateWithOAuthLoopback` signs
  the same user in again. Both take the same arguments as `signInWithOAuthLoopback`, and throw `null-user` before
  the browser opens when nobody is signed in.
- `authorizeWithOAuthLoopback` returns the tokens and the credential without signing in.
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
`exchangeCode` and generic OpenID Connect providers were run only against the fake identity provider of the tests.

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
  Phone sign-in, multi-factor sign-in and enrolment, and reCAPTCHA are not there (the table above lists the
  rest). A project that enforces reCAPTCHA Enterprise for email and password refuses these sign-ins
  (`missing-recaptcha-token`).
- An account with a second factor cannot sign in: the sign-in and the reauthentication throw a
  `FirebaseAuthMultiFactorException` (`multi-factor-auth-required`, like the JS SDK) whose `hints`
  list the enrolled factors and whose `pendingCredential` lets your own code finish the sign-in
  over REST (`v2/accounts/mfaSignIn:start` and `:finalize`).
- The session is kept in memory unless you supply an `AuthStorage` (`FileAuthStorage`, `WebAuthStorage` or your
  own). The stored value is a credential, the refresh token: keep it where the platform keeps secrets.
- `signOut()` forgets the session locally; it does not revoke the refresh token on the backend.
- The token providers are read once, when the Firestore instance is created: set them first.
- Service account and Application Default Credentials tokens bypass security rules: use them on
  trusted machines only.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
