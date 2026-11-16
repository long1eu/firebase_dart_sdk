# firebase_app_dart

An unofficial, pure-Dart `FirebaseApp` and `FirebaseOptions` for Dart servers, command line tools
and Flutter apps: the app layer of
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart). You need it to create a
Firestore instance; on its own it holds the configuration of a Firebase project and connects the
services to the platform (storage, connectivity, auth and App Check tokens). It is not affiliated
with or endorsed by Google or Firebase.

> **Status: 0.1.1.** Unit tests, plus `cloud_firestore_dart`'s integration
> suite against the Firestore emulator. Against production it was only used by the short
> verification kit of `cloud_firestore_dart`, on one Firestore database.

## Install

```shell
dart pub add firebase_app_dart
```

Dart 3.8 or later. To use Firestore, add `cloud_firestore_dart` too; for signed-in users or
service accounts, `firebase_auth_providers_dart`.

## Quick start

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

// The default app. The values are in the Firebase console, Project settings, Your apps.
final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<YOUR_API_KEY>',
    appId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);
print(identical(FirebaseApp.instance, app)); // true

// Set token providers on the app (app.authProvider = ...) here, before the service reads them.

// Hand the app to a service.
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
await firestore.doc('greetings/first').set(<String, Object?>{'text': 'hello'});
await firestore.terminate();
```

On desktop and servers, where Firebase registers no apps, any unique application id of the form
`1:<project number>:<platform>:<suffix>` works, for example `1:1234567890:linux:my-tool`.

## What it offers

| What | API | Example |
| --- | --- | --- |
| The default app and named apps, looked up by name | `FirebaseApp.withOptions`, `FirebaseApp.instance`, `FirebaseApp.getInstance`, `Firebase.apps` | [`default_and_named_apps.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/default_and_named_apps.dart) |
| Options in code or from a JSON map, and back | `FirebaseOptions`, `FirebaseOptions.fromJson`, `toJson` | [`options_from_json.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/options_from_json.dart) |
| Connectivity events and storage from your platform | `PlatformDependencies` (`package:firebase_app_dart/platform_dependencies.dart`), `LocalStorage` | [`platform_dependencies.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/platform_dependencies.dart) |
| Deleting an app, which shuts down its Firestore instances and frees its name | `FirebaseApp.delete`, `onDeleteApp` | [`app_deletion.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/app_deletion.dart) |
| Token providers for Firestore requests | `app.authProvider`, `app.appCheckProvider`, `AuthTokenProvider`, `AppCheckTokenProvider` | `firebase_auth_providers_dart` |

What you put into the app, and when Firestore reads it (once, when its instance is created):

![A FirebaseApp holds the options from withOptions, an authProvider (set by FirebaseUserAuth.forApp, OAuthTokenProvider or your own; without one requests carry no token), an appCheckProvider and the platform dependencies (onNetworkConnected, storage). FirebaseFirestore.instanceFor(app: app) reads the options, both providers and the connectivity events once, when it is created. app.delete() terminates the app's Firestore instances.](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/images/readme/firebase_app.svg)

The shortest program is [`example/main.dart`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/main.dart);
[`example/README.md`](https://github.com/long1eu/firebase_dart_sdk/blob/main/firebase_core/firebase_app_dart/example/README.md)
lists them all. None of them needs an emulator or the network.

**Platforms.** Android, iOS, Linux, macOS and Windows (the Dart VM, including Flutter apps);
developed and tested on macOS. The web, experimentally: tried in Chrome with
`cloud_firestore_dart`.

## Documentation

- **Guide**: [configuring the FirebaseApp](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/firebase_app.md)
  (where the options come from, application ids for desktop and servers, platform dependencies);
  [all guides](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/README.md).
- **API reference**: [pub.dev/documentation/firebase_app_dart](https://pub.dev/documentation/firebase_app_dart/latest/).

**Coming from `firebase_core_vm`?** This package was published as
[`firebase_core_vm`](https://pub.dev/packages/firebase_core_vm): replace the dependency and the
import (`package:firebase_app_dart/firebase_app_dart.dart`); class names did not change. The
[migration guide](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md)
has the details.

## Limits

- Only Firestore uses it. There is no Firebase Auth SDK, Storage or Realtime Database on top of
  it in this repository (tokens come from `firebase_auth_providers_dart` or your own provider).
- No heartbeat or analytics: `dataCollectionEnabled`, `trackingId`, `databaseURL`,
  `storageBucket` and `messagingSenderId` are stored, not used.
- `onBackgroundChanged`, `headersBuilder` and `setAutomaticResourceManagementEnabled` are kept
  from the original project; no service here reads them.
- `FirebaseOptions.fromJson` reads its own key names (those of `toJson`), not
  `google-services.json` or the web config object.
- The app reads its `PlatformDependencies` once, when it is created, and Firestore reads the
  token providers once, when its instance is created: set them first.
- `package:firebase_app_dart/internal.dart` is plumbing shared with `cloud_firestore_dart`. It is
  **not public API** and can change in any release.
- Against production Firebase it was only used by the verification kit of `cloud_firestore_dart`
  (`tool/verify_production` in the repository), on one Firestore database.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`. `firebase_core_vm` was licensed under BSD-3-Clause.

Issues and pull requests: https://github.com/long1eu/firebase_dart_sdk
