# tool/

- `test_all.sh [package ...]`: pub get, analyze and test the two published packages, firebase_app_dart and cloud_firestore_dart (unit tests only for cloud_firestore_dart).
- `start_emulator.sh`, `stop_emulator.sh`: run the Firestore emulator on 127.0.0.1:8080 (project `demo-test`).
  The Firebase CLI is installed locally in `.emulator/` (git-ignored): `mkdir -p .emulator && cd .emulator && npm init -y && npm install firebase-tools`.
  Override the location with `EMULATOR_DIR`. Java is required; the emulator JAR downloads on first start.
- Integration tests: `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` from `cloud_firestore/cloud_firestore_dart`.
- `bench/`: micro-benchmarks for hot paths.
- Regenerating the Firestore protos: `cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh` (needs `protoc_plugin` 21.1.2, matching protobuf 3.x). If `protoc` is unusable, set up `tool/protoc_wrap.sh` (see its header) and pass `PROTOC="$PWD/tool/protoc_wrap.sh"`.
