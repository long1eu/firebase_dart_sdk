# Examples

Small, complete Dart programs that use `cloud_firestore_dart` the way a server or a tool would.
Each directory is a package of its own with a `pubspec.yaml`, a README, and tests that run it
against the Firestore emulator.

| Directory | What it is |
| --- | --- |
| [`server_shelf/`](server_shelf/) | An HTTP API on `package:shelf`: reads and writes Firestore, and sends the changes of one real-time listener to every client as server-sent events. |
| [`cli/`](cli/) | A command-line tool on `package:args`: imports a JSON file with batched writes, exports a query to JSON, watches a query. |
| [`cloud_run_job/`](cloud_run_job/) | A one-shot job: an aggregation query, a transaction that writes once per execution, retries with backoff, and a `Dockerfile` for a native binary. |

The examples are command-line and server programs only. For the API one topic at a time, see
the programs in [`cloud_firestore/cloud_firestore_dart/example/`](../cloud_firestore/cloud_firestore_dart/example/README.md).

## Running them

All three read the backend from the environment, through the same
`lib/firestore_from_env.dart`:

- `FIRESTORE_EMULATOR_HOST=host:port`: the Firestore emulator. No credentials; the project
  is `demo-example` unless `FIREBASE_PROJECT_ID` says otherwise.
- Otherwise `FIREBASE_PROJECT_ID` (required), `FIRESTORE_DATABASE` (optional) and Application
  Default Credentials (`GOOGLE_APPLICATION_CREDENTIALS`, `gcloud auth application-default
  login`, or the metadata server on Google Cloud). These credentials bypass security rules.

No project id, key or token is in any file. Start an emulator, then, in an example's directory:

```sh
dart pub get
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
```

## Status

- Run against the Firestore emulator (v1.22.0) on macOS with Dart 3.12.2, by their tests and
  by hand.
- **Not run against a real Firebase project.** The Docker image of `cloud_run_job/` has not
  been built.
- The packages are not published yet, so each example takes them from this repository with
  `dependency_overrides` in its `pubspec.yaml`. Once they are on pub.dev, those lines go away.
- `firestore_from_env.dart` is copied, not shared, so that each directory can be copied out on
  its own.
