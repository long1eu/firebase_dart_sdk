# firebase_installations_dart

Firebase Installations for pure Dart: the installation id (FID) of an app and the auth tokens that
prove it, on the Dart VM (macOS, Windows, Linux, servers) and the web. Remote Config
(`firebase_remote_config_dart`) uses it; you rarely need it on its own.

This is an unofficial client of the Firebase Installations REST API. Its protocol behaviour follows
the Firebase JavaScript SDK.

## Status

0.1.0: create, auth token, delete, id changes, persistence. Not published yet. No emulator exists for Firebase
Installations, so the package talks to the project of your app. The wire format was measured with probe
requests against a test project on 2026-11-27; the client has not run against production yet.

## Install

Only `firebase_app_dart` is on pub.dev. Depend on this package from the repository:

```yaml
dependencies:
  firebase_app_dart: ^0.2.0
  firebase_installations_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_installations/firebase_installations_dart
```

The `ref: main` lines assume the packages have landed on `main` with this change (until then, use the branch
that carries them).

Once it is published, `dart pub add firebase_installations_dart firebase_app_dart` does the same.

The app options come from a web app (or any app) registered in your Firebase project; the console has no desktop
app type, so desktop and server programs use the same options.

## Set up

Create one store per process (VM) or per page (web), and one `FirebaseInstallations` per app.

| Platform | Store | Notes |
|---|---|---|
| VM | `FileKeyValueStore` (`package:firebase_installations_dart/io.dart`) | a directory of the user |
| Web | `IndexedDbKeyValueStore` (`package:firebase_installations_dart/web.dart`) | shared by the tabs of the origin |
| Tests, short-lived tools | `MemoryKeyValueStore` | a new installation at every start |

```dart
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: your own key
      appId: '1:1234567890:web:abc',
      projectId: 'my-project',
    ),
  );
  final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    // HOME is not set on Windows; fall back to USERPROFILE.
    store: FileKeyValueStore('$home/.config/my_tool/firebase'),
  );
  print(await installations.getId());
  await installations.close();
  await installations.store.close();
}
```

The constructor reads and sends nothing. It throws `invalid-app-config` when the app's `apiKey`,
`appId` or `projectId` is missing or malformed.

### The file store (VM)

- **One process owns a directory.** The first call takes an OS lock on `<directory>/.owner.lock`; a
  second process gets `storage-error` ("the store directory is in use by another process"). Give each
  process its own directory. Isolates of one process must not share a directory on Linux and macOS
  (the OS lock does not separate them); two stores of one isolate on one directory throw a
  `StateError`.
- **Private directory.** The directory is created when missing. On Linux and macOS the store runs
  `chmod 700` on it and refuses to work (`storage-error`) when other users can access it. On Windows
  use a directory in the user's profile (`%APPDATA%\<app>` or `%LOCALAPPDATA%\<app>`).
- A stored record over its cap (64 KiB for the installation record, 16 MiB for any file) is treated as
  absent.

### Limits

- No encryption at rest: other processes of the same user on a desktop, and every script of a web
  origin, can read the refresh token.
- Two tabs on one IndexedDB store share the FID.
- `MemoryKeyValueStore` creates a new installation at every process start; when you pass a `logger`,
  the package logs one warning when it registers an installation in it.

## Get the id

```dart
final String id = await installations.getId();
```

The first call creates a FID and stores it; registration with the server starts in the background.
A failed registration is logged and surfaces at `getToken`.

## Get a token

```dart
final String token = await installations.getToken();
final String fresh = await installations.getToken(forceRefresh: true);
final ({String id, String token}) pair = await installations.getIdAndToken();
```

`getToken` waits for the registration and returns a token that lives at least one more hour.
`getIdAndToken` returns a token with the FID it was issued for. When the server no longer knows the
installation (401 or 404), the call creates and registers a new one and tries once more.

## Id changes

```dart
installations.onIdChange.listen((String id) => print('new id: $id'));
```

It emits when this instance creates a FID (the first time, after `delete`, after the server forgot the
installation) and when the server assigns a different one.

## Delete

```dart
await installations.delete();
```

Deletes the installation on the server and removes the record; the next `getId` creates a new FID.

## Restricted API keys

An API key restricted to Android or iOS apps refuses requests without the matching headers. Pass them:

```dart
final FirebaseInstallations installations = FirebaseInstallations(
  app,
  store: store,
  headers: const <String, String>{
    'X-Android-Package': 'com.example.app',
    'X-Android-Cert': '0123456789ABCDEF0123456789ABCDEF01234567',
  },
);
```

`headers` takes exactly `X-Android-Package` and `X-Android-Cert` (Android keys) or `X-Ios-Bundle-Identifier` (iOS
keys); other names throw an `ArgumentError`. Desktop programs should use a key without an application
restriction, or one of these. Whatever the restriction, the key must allow the Firebase Installations API (and,
for Remote Config, the Firebase Remote Config API and the Firebase Remote Config Realtime API). A key restricted
to HTTP referrers works on the web only. A page with a Content-Security-Policy needs
`https://firebaseinstallations.googleapis.com` in `connect-src`.

## Offline

`getId()` works offline: it creates and stores the FID, and registers it later. `getToken()` needs the network
and throws `network-error` without it.

## Errors

Every error is a `FirebaseInstallationsException` (plugin `firebase_installations`) with one of these
codes. `httpStatus`, `serverStatus` and `serverMessage` describe the server's answer; `retryAfter` says
when requests are allowed again.

| Code | When |
|---|---|
| `invalid-app-config` | the app's `apiKey`, `appId` or `projectId` is missing or malformed |
| `bad-config` | the server answered 400, 401, 403 or 404 to a create request, or the 24 h block after a 400 or 403 |
| `installation-not-found` | the server answered 401 or 404 to a token request after the recovery |
| `too-many-requests` | the server answered 429, or the backoff window that a 3xx, a 409 on create or another failure started (a call inside a 409's window gets this code, not the 409's) |
| `unavailable` | the server answered 5xx after the retry, or the call took more than 60 s |
| `network-error` | the request failed in transport or took more than 10 s |
| `invalid-response` | a 2xx body failing the checks, a 3xx (it also starts a backoff window), any other unexpected 4xx (for example 408; the status is kept in `httpStatus` and the call is not `bad-config`), or a second 409 on create in one call |
| `storage-error` | a store configuration failure, or a write failure where persistence is required |
| `installations-closed` | the instance was closed |

Messages never hold a token, the API key or a request body.
