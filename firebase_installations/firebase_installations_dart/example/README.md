# firebase_installations_dart examples

Small command-line programs. There is no emulator for Firebase Installations, so they talk to the
project you name; each run creates an installation in a new temporary directory.

```sh
cd firebase_installations/firebase_installations_dart && dart pub get
dart run example/get_id.dart --api-key <key> --app-id <app id> --project-id <project id>
```

| File | Shows |
|---|---|
| `main.dart` | The id and a token, with positional arguments (the pub.dev example). |
| `get_id.dart` | `getId()` and `onIdChange`. |
| `get_token.dart` | `getIdAndToken()`, `getToken(forceRefresh: true)` and `FirebaseInstallationsException`. |
| `delete.dart` | `delete()`, and the new id the next `getId()` creates. |

`common.dart` parses the three options with `package:args` and builds a `FirebaseInstallations` over a
`FileKeyValueStore` in a temporary directory. Run `delete.dart` to leave nothing behind in the project.
