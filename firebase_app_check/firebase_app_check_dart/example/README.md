# firebase_app_check_dart examples

Small command-line programs. There is no App Check emulator, so the debug-token examples talk to the project you
name and use a debug token that you register in the Firebase console yourself (App Check, Apps, Manage debug
tokens). A debug token is a secret: put it in the environment variable `FIREBASE_APPCHECK_DEBUG_TOKEN`, never on a
command line, and delete it in the console afterwards. None of these programs prints a token.

```sh
cd firebase_app_check/firebase_app_check_dart && dart pub get
FIREBASE_APPCHECK_DEBUG_TOKEN=<debug token> \
  dart run example/debug_provider.dart --api-key <key> --app-id <app id> --project-id <project id>
```

| File | Shows |
|---|---|
| `main.dart` | A custom provider whose callback returns a fixed token read from the command line; prints the token's length and expiry (the pub.dev example; contacts no server). |
| `debug_provider.dart` | `debugProviderFromEnvironment()`, one `getToken()`, `close()`. |
| `limited_use.dart` | `getLimitedUseToken()`: never cached, one exchange per call. |
| `custom_provider.dart` | A callback that asks an HTTP endpoint of your own server for a token, and what `limitedUse` and `forceRefresh` mean to it. |

`common.dart` parses `--api-key`, `--app-id` and `--project-id` with `package:args`, builds the `FirebaseApp` and
writes the log lines of the package to stderr.

The examples pass `autoRefresh: false` and call `close()`: an instance that holds a token keeps a timer for the next
refresh, so a program that should exit by itself does one or the other.
