# firebase_auth_providers_dart

Unofficial, pure-Dart token providers for
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) and
[`firebase_app_dart`](https://pub.dev/packages/firebase_app_dart): what Firestore sends with its requests so
that they run as someone. You need it when your users sign in with Firebase Auth (email and password,
anonymous, custom token) and their requests must pass your security rules, or when a server or tool uses a
service account or Application Default Credentials. Without it, requests carry no user, which is enough for
the emulator and open rules. It is not affiliated with or supported by Google or Firebase.

> **Status: 0.2.1.** Verified with unit tests and against the Firebase
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
| `FirebaseUserAuth`: anonymous, email and password, and custom-token sign-in over REST; token refresh; sign-out; account management; a session kept in your `AuthStorage` | apps with end users (VM, Flutter, web) | apply (`request.auth` is the user) | stable, emulator only |
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
| Keeping the user signed in across restarts: a file-backed `AuthStorage` | [`persistent_session.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/persistent_session.dart) | Auth emulator |
| Wiring a provider into Firestore; the rules see the user | [`firestore_wiring.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/firestore_wiring.dart) | Auth and Firestore emulators |
| A service account key, its path in an environment variable | [`service_account.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/service_account.dart) | a real project |
| Application Default Credentials on a server | [`adc_server.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/adc_server.dart) | a real project |

[`example/README.md`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/README.md) explains how to start the emulators.

This is **not** a port of the Firebase Auth SDK: it has the REST-backed operations of the JS SDK
(see [What is supported](#what-is-supported)), and no federated providers (Google, Apple, ...),
no popup or redirect flows, no phone sign-in, no email link sign-in and no multi-factor.

**Platforms.** The Dart VM (servers, command line tools, Flutter) and the web; `adc.dart` is VM
only. `FirebaseUserAuth` was run in Chrome against the Auth emulator.

## What is supported

`FirebaseUserAuth` compared with the modular JS SDK (`firebase/auth`). "Emulator" means tested
against the Firebase Auth emulator; nothing was run against the real service.

| JS SDK | `FirebaseUserAuth` | Tested |
| --- | --- | --- |
| `signInAnonymously` | `signInAnonymously()` | emulator, Chrome |
| `signInWithEmailAndPassword` | `signInWithEmailAndPassword(email, password)` | emulator |
| `createUserWithEmailAndPassword` | `createUserWithEmailAndPassword(email, password)` | emulator, Chrome |
| `signInWithCustomToken` | `signInWithCustomToken(token)` | emulator |
| `signOut` | `signOut()` | emulator |
| `onAuthStateChanged` / `onIdTokenChanged` / `beforeAuthStateChanged` | `userChanges` (also after profile changes) / `onTokenChanged` / – | unit |
| `user.getIdToken(forceRefresh)` / `getIdTokenResult` | `getAccessToken(forceRefresh:)` (a `GetTokenResult` with the claims) | emulator |
| `sendPasswordResetEmail(auth, email, settings)` | `sendPasswordResetEmail(email, actionCodeSettings:)` | emulator, Chrome |
| `confirmPasswordReset(auth, code, password)` | `confirmPasswordReset(code, newPassword)` | emulator |
| `verifyPasswordResetCode(auth, code)` | `verifyPasswordResetCode(code)` | emulator |
| `checkActionCode(auth, code)` | `checkActionCode(code)` (`ActionCodeInfo`, without the multi-factor info) | emulator |
| `applyActionCode(auth, code)` | `applyActionCode(code)` (does not reload the user, like JS) | emulator |
| `sendEmailVerification(user, settings)` | `sendEmailVerification(actionCodeSettings:)` | emulator, Chrome |
| `verifyBeforeUpdateEmail(user, email, settings)` | `verifyBeforeUpdateEmail(newEmail, actionCodeSettings:)` | emulator |
| `updateEmail(user, email)` | `updateEmail(newEmail)` | emulator |
| `updatePassword(user, password)` | `updatePassword(newPassword)` | emulator, Chrome |
| `updateProfile(user, {displayName, photoURL})` | `updateProfile(displayName:, photoUrl:)`; `''` removes a value (JS: `null`) | emulator, Chrome |
| `reauthenticateWithCredential(user, EmailAuthProvider.credential(...))` | `reauthenticateWithEmailAndPassword(email, password)` | emulator, Chrome |
| `user.reload()` | `reload()` | emulator, Chrome |
| `user.delete()` / `deleteUser(user)` | `deleteCurrentUser()` | emulator, Chrome |
| `fetchSignInMethodsForEmail(auth, email)` (deprecated upstream: empty with email enumeration protection) | `fetchSignInMethodsForEmail(email)` | emulator, Chrome |
| `connectAuthEmulator(auth, url)` | the `emulatorHost` argument | emulator, Chrome |
| `user.uid`, `email`, `emailVerified`, `isAnonymous`, `displayName`, `photoURL` | `currentUser` (`AuthUser`) | emulator |
| `setPersistence` | an `AuthStorage` (in memory by default) | unit |
| `ActionCodeSettings` (`url`, `handleCodeInApp`, `iOS`, `android`, `linkDomain`) | `ActionCodeSettings` (flattened; no `dynamicLinkDomain`) | unit |
| Federated providers, popup and redirect flows, `linkWithCredential`, `unlink` | – | |
| Phone sign-in, reCAPTCHA, multi-factor, TOTP, passkeys | – | |
| Email link sign-in (`sendSignInLinkToEmail`, `signInWithEmailLink`) | – | |
| `languageCode` / `X-Firebase-Locale`, `tenantId`, password policy, `user.metadata`, `providerData` | – | |

Error codes are those of the JS SDK: the map of server codes of `packages/auth/src/api/errors.ts`
(`EXPIRED_OOB_CODE` is `expired-action-code`, `USER_NOT_FOUND` is `user-token-expired`, ...), and
any other code of the backend in kebab case (`QUOTA_EXCEEDED` is `quota-exceeded`). Operations of
the signed-in user throw `null-user` when nobody is signed in, and sign the user out when the
backend answers `user-disabled` or `user-token-expired` (`_logoutIfInvalidated` of the JS SDK).

## Documentation

- **Guide**: [authentication and App Check](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md):
  the token lifecycle, a switch of users, keeping the user signed in (and where to store the
  session safely), the Auth emulator, server credentials, and how the providers were tested.
  [All guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md).
- **API reference**: [pub.dev/documentation/firebase_auth_providers_dart](https://pub.dev/documentation/firebase_auth_providers_dart/latest/).

## Limits

- Nothing was run against the real Firebase Auth service or Google's token endpoint: the
  providers were tested with unit tests and against the Firebase emulators. Application Default
  Credentials are delegated to `package:googleapis_auth` without a test of their own.
- Federated sign-in, popup and redirect flows, phone sign-in, email link sign-in and
  multi-factor are not there (the table above lists the rest).
- An account with a second factor cannot sign in: the sign-in and the reauthentication throw a
  `FirebaseAuthMultiFactorException` (`multi-factor-auth-required`, like the JS SDK) whose `hints`
  list the enrolled factors and whose `pendingCredential` lets your own code finish the sign-in
  over REST (`v2/accounts/mfaSignIn:start` and `:finalize`).
- The session is kept in memory unless you supply an `AuthStorage`. The stored value is a
  credential: keep it where the platform keeps secrets.
- `signOut()` forgets the session locally; it does not revoke the refresh token on the backend.
- The token providers are read once, when the Firestore instance is created: set them first.
- Service account and Application Default Credentials tokens bypass security rules: use them on
  trusted machines only.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
