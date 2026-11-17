# Examples of firebase_admin_dart

| Example | What it shows | Needs |
| --- | --- | --- |
| [`main.dart`](main.dart) | The loop: create a user, mint a custom token with claims, sign in with `firebase_auth_providers_dart`, read the claims, verify the ID token, delete the user | Auth emulator |
| [`integration_test_helper.dart`](integration_test_helper.dart) | A helper for Flutter integration tests: users on demand from `--dart-define` values | Auth emulator or a test project |
| [`production_check.dart`](production_check.dart) | The check to run by hand against a real test project; prints PASS or FAIL. Its keyless mode passed against a real project on 2026-11-18 | a Web API key, and either a key file or (keyless) gcloud Application Default Credentials and a service account to sign as |

Start the Auth emulator with the firebase CLI, in a folder of your choice:

```shell
firebase emulators:start --only auth --project demo-test
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 dart run example/main.dart
```

In this repository, `tool/start_auth_emulators.sh` starts it (and prints the export).

`production_check.dart` has two modes, keyless and with a key file; "Checking a real project" in
the package README has the setup of each. Run with no variables, it prints its usage.
