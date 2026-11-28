# firebase_remote_config_dart examples

Small command-line programs. There is no emulator for Remote Config or Installations, so they talk to
the project you name; each run creates an installation in a new temporary directory.

```sh
cd firebase_remote_config/firebase_remote_config_dart && dart pub get
dart run example/fetch_and_activate.dart --api-key <key> --app-id <app id> --project-id <project id>
```

| File | Shows |
|---|---|
| `main.dart` | `fetchAndActivate()` and one read, with positional arguments (the pub.dev example). |
| `fetch_and_activate.dart` | `fetch()` with its `FetchResult` (`updated`, `unchanged`, `cached`), `activate()`, `getAll()` and `info`. |
| `defaults.dart` | Defaults, typed reads and their fall-through, the static value of an unknown key. |
| `custom_signals.dart` | `setCustomSignals`: numbers as text, removal with `null`, the limits, and the fetch that skips the cache after a change. |
| `realtime.dart` | `onConfigUpdated`: updated keys, `activate()`, errors that do not end the stream. |

`common.dart` parses the three options with `package:args` and builds a `FirebaseRemoteConfig` over a
`FirebaseInstallations` and a `FileKeyValueStore` in a temporary directory.
