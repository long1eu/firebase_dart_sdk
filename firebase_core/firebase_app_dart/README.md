# firebase_app_dart

An unofficial, pure-Dart `FirebaseApp` and `FirebaseOptions` for Dart servers, command line tools
and Flutter apps: the app layer of
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart). You need it to create a
Firestore instance; on its own it holds the configuration of a Firebase project and connects the
services to the platform (storage, connectivity, auth and App Check tokens). It is not affiliated
with or endorsed by Google or Firebase.

> **Status: 0.1.0.** Unit tests, plus `cloud_firestore_dart`'s integration
> suite against the Firestore emulator. Against production it was only used by the short
> verification kit of `cloud_firestore_dart`, on one Firestore database.

## Features

| Feature | Status |
| --- | --- |
| `FirebaseApp`: the default app and named apps, `FirebaseOptions` (also from JSON) | stable |
| `PlatformDependencies`: connectivity events, storage, auth and App Check token providers | stable |
| `onBackgroundChanged` and `headersBuilder` (kept from the original project; no service here uses them) | unused |
| `package:firebase_app_dart/internal.dart`: plumbing shared with `cloud_firestore_dart` | **not public API** |

**Platforms.** Android, iOS, Linux, macOS and Windows (the Dart VM, including Flutter apps);
developed and tested on macOS. The web, experimentally: tried in Chrome with
`cloud_firestore_dart`. Dart 3.8 or later.

## Install

```shell
dart pub add firebase_app_dart
```

## Quickstart

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    applicationId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);
print(identical(FirebaseApp.instance, app)); // the default app
```

Then pass the app to a service, for example `Firestore.instanceFor(app: app)` of
`cloud_firestore_dart`.

## Documentation

- **Guide**: [configuring the FirebaseApp](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/firebase_app.md)
  (where the options come from, application ids for desktop and servers, platform dependencies);
  [all guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md).
- **API reference**: [pub.dev/documentation/firebase_app_dart](https://pub.dev/documentation/firebase_app_dart/latest/).
- **Example**: [`example/main.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/main.dart).

**Coming from `firebase_core_vm`?** This package was published as
[`firebase_core_vm`](https://pub.dev/packages/firebase_core_vm): replace the dependency and the
import (`package:firebase_app_dart/firebase_app_dart.dart`); class names did not change. The
[migration guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md)
has the details.

## Not done

- Only Firestore uses it. There is no Firebase Auth SDK, Storage or Realtime Database on top of
  it in this repository (tokens come from `firebase_auth_providers_dart` or your own provider).
- No heartbeat or analytics: `dataCollectionEnabled` and `gaTrackingId` are stored, not used.
- Against production Firebase it was only used by the verification kit of `cloud_firestore_dart`
  (`tool/verify_production` in the repository), on one Firestore database.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`. `firebase_core_vm` was licensed under BSD-3-Clause.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
