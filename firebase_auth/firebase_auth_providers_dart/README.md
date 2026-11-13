# firebase_auth_providers_dart

Unofficial, pure-Dart token providers for
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart) and
[`firebase_app_dart`](https://pub.dev/packages/firebase_app_dart): what Firestore needs to send
a token with its requests. For apps whose users sign in with Firebase Auth, and for servers and
tools that use a service account or Application Default Credentials. It is not affiliated with
or supported by Google or Firebase.

> **Status: 0.1.0, not published yet.** Verified with unit tests and against the Firebase
> emulators only: nothing was run against the real Firebase Auth service or Google's token
> endpoint.

## Features

| Provider | For | Security rules | Status |
| --- | --- | --- | --- |
| `FirebaseUserAuth`: anonymous, email and password, and custom-token sign-in over REST; token refresh; sign-out; account management (password reset, email verification, email, password and profile updates, reauthentication, deletion); a session kept in your storage | apps with end users (VM, Flutter, web) | apply (`request.auth` is the user) | stable |
| `OAuthTokenProvider.serviceAccount`: a service account key | servers | **bypassed** | stable |
| `applicationDefaultCredentials()` (`adc.dart`, VM only) | servers, command line tools | **bypassed** | stable, not exercised by tests |

This is **not** a port of the Firebase Auth SDK: it has the REST-backed operations of the JS SDK
(see [What is supported](#what-is-supported)), and no federated providers (Google, Apple, ...),
no popup or redirect flows, no phone sign-in, no email link sign-in and no multi-factor.

**Platforms.** The Dart VM (servers, command line tools, Flutter) and the web; `adc.dart` is VM
only. `FirebaseUserAuth` was run in Chrome against the Auth emulator. Dart 3.8 or later.

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

## Install

```shell
dart pub add firebase_auth_providers_dart
```

## Quickstart

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

// Before the Firestore instance is created: it becomes the token provider of the app.
final auth = await FirebaseUserAuth.forApp(app);
final firestore = Firestore.instanceFor(app: app);

await auth.signInWithEmailAndPassword('ada@example.com', password);
await firestore.doc('users/${auth.uid}/notes/first').set({'text': 'hello'});
await auth.signOut();
```

A server uses `app.authProvider = OAuthTokenProvider.serviceAccount(keyJson)` or
`app.authProvider = applicationDefaultCredentials()` instead.

## Documentation

- **Guide**: [authentication and App Check](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/authentication.md):
  the token lifecycle, a switch of users, keeping the user signed in (and where to store the
  session safely), the Auth emulator, server credentials, and how the providers were tested.
  [All guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md).
- **API reference**: [pub.dev/documentation/firebase_auth_providers_dart](https://pub.dev/documentation/firebase_auth_providers_dart/latest/).
- **Examples**: [`example/main.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/main.dart) (anonymous sign-in), [`example/account_flows.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/account_flows.dart) (email verification, password reset, account deletion; Auth emulator).

## Not done

- Federated sign-in, popup and redirect flows, phone sign-in, email link sign-in and
  multi-factor (the table above lists the rest).
- Persistent storage of the session: you supply an `AuthStorage` (the default keeps it in
  memory).
- Nothing was run against the real services, and Application Default Credentials are delegated
  to `package:googleapis_auth` without a test of their own.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
