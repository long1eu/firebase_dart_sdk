# firebase_auth_providers_dart examples

Small command-line programs, one per task. Each one runs on its own; the comment at the top of
each file says how and what it needs. Without the environment variables it needs, a program
prints a note and exits.

## With the emulators

Most examples run against the Firebase Auth emulator, and `firestore_wiring.dart` also against
a Firestore emulator whose security rules require a signed-in user. From the repository root
(needs the Firebase CLI, and java for the Firestore emulator):

```sh
tool/start_auth_emulators.sh                # prints the two exports below
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197
export FIRESTORE_AUTH_RULES_EMULATOR_HOST=127.0.0.1:8197
cd firebase_auth/firebase_auth_providers_dart
dart run example/main.dart
...
tool/stop_auth_emulators.sh                 # from the repository root
```

| File | Shows |
| --- | --- |
| `main.dart` | The shortest program: anonymous sign-in, `userChanges`, the ID token and its expiry. |
| `email_password.dart` | Sign-up, sign-out and sign-in with an email and a password, and the error codes a sign-in form handles (`wrong-password` or `invalid-credential`, `email-already-in-use`, `weak-password`, `invalid-email`). |
| `account_flows.dart` | Email verification, `updateProfile`, a password reset with its action code, reauthentication and account deletion. Reads the action codes from the emulator in place of an inbox. |
| `custom_token.dart` | `signInWithCustomToken` and the custom claims in the ID token. The emulator accepts an unsigned token; a real one comes from your server. |
| `persistent_session.dart` | A file-backed `AuthStorage` (owner-only file on macOS and Linux): a second run finds the user signed in. |
| `firestore_wiring.dart` | `FirebaseUserAuth.forApp` before `FirebaseFirestore.instanceFor`: a write refused while signed out, accepted for the signed-in user, and a read of another user's document refused. |

## With a real project

These need a project of your own and network access; there is no emulator for them. They print
nothing secret, and the key file stays outside the repository.

| File | Shows | Run with |
| --- | --- | --- |
| `service_account.dart` | `OAuthTokenProvider.serviceAccount` from a key file whose path is in an environment variable, set as `app.authProvider`. | `FIREBASE_SERVICE_ACCOUNT_KEY_FILE=/path/to/key.json dart run example/service_account.dart` |
| `adc_server.dart` | `applicationDefaultCredentials()` with Firestore on a server: reads one document. | `FIREBASE_PROJECT_ID=my-project dart run example/adc_server.dart [document path]` |

Service accounts and Application Default Credentials bypass the security rules: access is
decided by IAM. Use them on trusted machines only.

## Tests

`test/example_test.dart` runs every program without its variables (each prints its note), and
the emulator programs against the emulators when `FIREBASE_AUTH_EMULATOR_HOST` (and, for
`firestore_wiring.dart`, `FIRESTORE_AUTH_RULES_EMULATOR_HOST`) is set, checking what they print.
`service_account.dart` and `adc_server.dart` were not run against a real project.
