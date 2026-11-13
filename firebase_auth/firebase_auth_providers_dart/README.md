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
| `FirebaseUserAuth`: anonymous, email and password, and custom-token sign-in over REST; token refresh; sign-out; a session kept in your storage | apps with end users (VM, Flutter, web) | apply (`request.auth` is the user) | stable |
| `OAuthTokenProvider.serviceAccount`: a service account key | servers | **bypassed** | stable |
| `applicationDefaultCredentials()` (`adc.dart`, VM only) | servers, command line tools | **bypassed** | stable, not exercised by tests |

This is **not** a port of the Firebase Auth SDK: there are no federated providers (Google, Apple,
...), no phone sign-in, no email actions, no multi-factor and no account management.

**Platforms.** The Dart VM (servers, command line tools, Flutter) and the web; `adc.dart` is VM
only. `FirebaseUserAuth` was run in Chrome against the Auth emulator. Dart 3.8 or later.

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
- **Example**: [`example/main.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_auth/firebase_auth_providers_dart/example/main.dart).

## Not done

- Federated sign-in, phone sign-in, email actions, multi-factor and account management.
- Persistent storage of the session: you supply an `AuthStorage` (the default keeps it in
  memory).
- Nothing was run against the real services, and Application Default Credentials are delegated
  to `package:googleapis_auth` without a test of their own.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
