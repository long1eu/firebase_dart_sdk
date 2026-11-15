# firebase_app_dart examples

Small command-line programs, one per task. None of them needs an emulator, credentials or the
network. From `firebase_core/firebase_app_dart`:

```sh
dart run example/main.dart
```

| File | Shows |
| --- | --- |
| `main.dart` | The shortest program: the default app and a named app, looked up again. |
| `default_and_named_apps.dart` | The default app and named apps: `instance`, `getInstance` (names are trimmed), `apps`, and the `StateError`s of a taken or unknown name. |
| `options_from_json.dart` | `FirebaseOptions.fromJson` from a file (`dart run example/options_from_json.dart options.json`) or the built-in sample, `toJson`, the `ArgumentError` of a missing key, and mapping the config object of a web app. |
| `platform_dependencies.dart` | A `PlatformDependencies` subclass with a connectivity `BehaviorSubject` that the app hands to its services, and a `LocalStorage` of its own. |
| `app_deletion.dart` | `delete`: `onDeleteApp`, the `StateError` of a deleted app, deleting twice, reusing the name, `getPersistenceKeyFor`. |

To use an app with Firestore, see the examples of
[`cloud_firestore_dart`](https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart/example);
for token providers, those of
[`firebase_auth_providers_dart`](https://github.com/long1eu/firebase_dart_sdk/tree/main/firebase_auth/firebase_auth_providers_dart/example).

`test/example_test.dart` runs `main.dart` and checks what it prints; the other programs were
run by hand.
