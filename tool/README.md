# tool/

- `test_all.sh [package ...]`: pub get, analyze and test the two published packages, firebase_app_dart and cloud_firestore_dart (unit tests only for cloud_firestore_dart).
- `start_emulator.sh`, `stop_emulator.sh`: run the Firestore emulator on 127.0.0.1:8080 (project `demo-test`).
  The Firebase CLI is installed locally in `.emulator/` (git-ignored): `mkdir -p .emulator && cd .emulator && npm init -y && npm install firebase-tools`.
  Override the location with `EMULATOR_DIR`. Java is required; the emulator JAR downloads on first start.
- `test_integration.sh [standard|enterprise|both] [dart test arguments...]`: run the cloud_firestore_dart integration tests against emulators that are already running (it never starts or stops one).
  - `standard` (default): `test/integration` against the Standard edition emulator (`FIRESTORE_EMULATOR_HOST`, default 127.0.0.1:8080).
  - `enterprise`: `test/integration` against the Enterprise edition emulator (`FIRESTORE_ENTERPRISE_EMULATOR_HOST`, default 127.0.0.1:8181), then `test/integration_enterprise`.
  - `both`: one after the other. Extra arguments replace the default paths, e.g. `tool/test_integration.sh enterprise test/integration/firebase/firestore/query_test.dart`.
  - `--transport=webchannel` (after the edition): run the same tests over the web transport (REST and WebChannel through `dart:io` HTTP) instead of gRPC, still on the VM. The standard suite passes over it (462 passed, 19 skipped against emulator v1.22.0, the same as over gRPC).
  - The full output of each run goes to `TEST_LOG_DIR` (default: a new temp dir); the script prints the failed tests and a summary and exits non-zero on failure.
- By hand, from `cloud_firestore/cloud_firestore_dart`: `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration`.
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
  | `FIRESTORE_EMULATOR_EDITION` | `standard` or `enterprise`: the edition of the emulator behind `FIRESTORE_EMULATOR_HOST`. `test_integration.sh` sets it; with `enterprise` the tests of the standard suite whose expectations only hold for the Standard edition are skipped. Unset, the edition is Enterprise exactly when both host variables name the same emulator. |
  | `FIRESTORE_TEST_PROJECT_ID` | Opt-in: run the integration suite against this real Firebase project (only while `FIRESTORE_EMULATOR_HOST` is unset). |
  | `FIRESTORE_TEST_DATABASE_ID` | Optional database id in that project (default `(default)`). |
  | `GOOGLE_APPLICATION_CREDENTIALS` | Standard Application Default Credentials variable: path of a service-account key file used for the real project. Without it the gcloud application-default credentials are used. |

  The real-project mode is described in the Testing section of `cloud_firestore/cloud_firestore_dart/README.md`. It is never used unless you set `FIRESTORE_TEST_PROJECT_ID`.
- The standard suite on the Enterprise edition emulator (v1.22.0): everything passes except ten tests, which `tool/test_integration.sh enterprise` skips with a reason. Eight are behaviour differences of the edition and two are an emulator bug:

  | Difference on Enterprise | Tests skipped |
  | --- | --- |
  | Equality filters (`in`, `array-contains`, `array-contains-any`) match `null` and `NaN`; on Standard they never do. | `query_test`: `testQueriesCanUseInFilters`, `testQueriesCanUseArrayContainsFilters`, `testQueriesCanUseArrayContainsAnyFilters` |
  | `sum` over no documents is `null`, not `0`. | `aggregation_test`: `testPerformsSumAndAverageOverZeroDocuments`; `composite_index_query_test`: `testPerformsAggregationWhenUsingArrayContainsAnyOperator` |
  | No limit of 5 aggregations per query. | `aggregation_test`: `testCannotPerformMoreThanMaxAggregations` |
  | An integer `sum` that overflows 64 bits (also only while accumulating) fails with `INVALID_ARGUMENT: Long overflow`; Standard returns a double. | `aggregation_test`: `testPerformsSumThatOverflowsMaxLong`, `testPerformsSumThatIsNegative` |
  | Emulator bug: a Listen with `!=` or `not-in` on the document id fails with `__key__ filter value must be a Key`, although the client sends a reference value and the identical query succeeds with RunQuery on the same emulator (and with Listen on the Standard one). | `query_test`: `testQueriesCanUseNotEqualFiltersWithDocIds`, `testQueriesCanUseNotInFiltersWithDocIds` |

  The first four rows are pinned by `test/integration_enterprise/edition_differences_test.dart`. All of this was observed with the emulator only, not with a production Enterprise database. The JS SDK skips its counterparts of rows 1 to 3 on Enterprise (`it.skipEnterprise`); it has no counterpart of row 4 with real 64-bit integers.
- CI (`.github/workflows/ci.yml`) has six jobs: unit tests (`test_all.sh`), the standard suite on the Standard emulator (`test_integration.sh standard`), the same suite over the web transport (`test_integration.sh standard --transport=webchannel`), the browser tests in headless Chrome (`dart test -p chrome test/browser`, compiled with dart2wasm and with dart2js), the Enterprise tests (`test/integration_enterprise` with both emulators), and the standard suite on the Enterprise emulator (`test_integration.sh enterprise test/integration`). The standard jobs also install `interop/` so that the JS interop tests run. All jobs but the unit tests are allowed to fail. The workflow has not been run yet.
- `interop/`: Node harness for the interop tests with the JS SDK and firebase-admin (`npm install` there; see its README).
- `bench/`: micro-benchmarks for hot paths.
- Regenerating the Firestore protos: `cloud_firestore/cloud_firestore_dart/tool/gen_protos.sh` (needs `protoc_plugin` 25.1.0, matching protobuf 6.x; set `PROTOC_GEN_DART` to use a `protoc-gen-dart` that is not on `PATH`). The well-known types (`google/protobuf/*.proto`) are not generated: they come from `package:protobuf/well_known_types`. If `protoc` is unusable, set up `tool/protoc_wrap.sh` (see its header) and pass `PROTOC="$PWD/tool/protoc_wrap.sh"`.
