# tool/

- `test_all.sh [package ...]`: pub get, analyze and test the two published packages, firebase_app_dart and cloud_firestore_dart (unit tests only for cloud_firestore_dart).
- `start_emulator.sh`, `stop_emulator.sh`: run the Firestore emulator on 127.0.0.1:8080 (project `demo-test`).
  The Firebase CLI is installed locally in `.emulator/` (git-ignored): `mkdir -p .emulator && cd .emulator && npm init -y && npm install firebase-tools`.
  Override the location with `EMULATOR_DIR`. Java is required; the emulator JAR downloads on first start.
- Integration tests: `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` from `cloud_firestore/cloud_firestore_dart`.
- `start_enterprise_emulator.sh`, `stop_enterprise_emulator.sh`: run a second Firestore emulator in **Enterprise edition** on 127.0.0.1:8181 (project `demo-test`), next to the standard one.
  - It runs the emulator JAR directly (`java -jar ... --database-edition enterprise`), without the Firebase CLI. The JAR is the newest `cloud-firestore-emulator-v*.jar` in `~/.cache/firebase/emulators` (the CLI downloads it on the first start of the standard emulator, or with `firebase setup:emulators:firestore`); set `FIRESTORE_EMULATOR_JAR` to use another one.
  - `ENTERPRISE_EMULATOR_PORT` changes the port, `EMULATOR_DIR` the directory of `enterprise_emulator.pid` and `enterprise_emulator.log` (default `.emulator/`).
  - The pid file holds the pid of that java process. The stop script signals only that pid, and only after checking that it still is a Firestore emulator started with `--database-edition enterprise`; it never touches the standard emulator. The start script refuses to start when the port is already taken by something else.
- Enterprise tests: `FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise` from `cloud_firestore/cloud_firestore_dart`. Without the variable they are skipped (with a reason). Tests that compare the two editions also need `FIRESTORE_EMULATOR_HOST`.
- Environment variables read by the tests (`cloud_firestore/cloud_firestore_dart/test/util/test_backend.dart`):

  | Variable | Meaning |
  | --- | --- |
  | `FIRESTORE_EMULATOR_HOST` | `host:port` of the standard emulator. When set it always wins over a real project. |
  | `FIRESTORE_ENTERPRISE_EMULATOR_HOST` | `host:port` of the Enterprise edition emulator, for `test/integration_enterprise`. |
  | `FIRESTORE_TEST_PROJECT_ID` | Opt-in: run the integration suite against this real Firebase project (only while `FIRESTORE_EMULATOR_HOST` is unset). |
  | `FIRESTORE_TEST_DATABASE_ID` | Optional database id in that project (default `(default)`). |
  | `GOOGLE_APPLICATION_CREDENTIALS` | Standard Application Default Credentials variable: path of a service-account key file used for the real project. Without it the gcloud application-default credentials are used. |

  The real-project mode is described in the Testing section of `cloud_firestore/cloud_firestore_dart/README.md`. It is never used unless you set `FIRESTORE_TEST_PROJECT_ID`.
- CI (`.github/workflows/ci.yml`) has three jobs: unit tests, the standard-emulator integration suite, and the enterprise-emulator tests. The workflow has not been run yet.
- `interop/`: Node harness for the interop tests with the JS SDK and firebase-admin (`npm install` there; see its README).
- `bench/`: micro-benchmarks for hot paths.
- Regenerating the Firestore protos: `cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh` (needs `protoc_plugin` 21.1.2, matching protobuf 3.x). If `protoc` is unusable, set up `tool/protoc_wrap.sh` (see its header) and pass `PROTOC="$PWD/tool/protoc_wrap.sh"`.
