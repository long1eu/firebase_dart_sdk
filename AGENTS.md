# AGENTS.md

For coding agents working inside this repository. To write code that *uses* the published
packages, read [docs/guides/for_ai_agents.md](docs/guides/for_ai_agents.md) instead.

## Layout

Maintained, tested and published (`cloud_firestore_dart` 0.3.2, Dart `^3.8.0`):

| Package | Path |
|---|---|
| `cloud_firestore_dart` | `cloud_firestore/cloud_firestore_dart` |
| `firebase_app_dart` | `firebase_core/firebase_app_dart` |
| `firebase_auth_providers_dart` | `firebase_auth/firebase_auth_providers_dart` |
| `secure_flow` (0.2.0; the browser flows of the Auth client) | `secure_flow/secure_flow` |
| `cloud_firestore_dart_sqlite` (0.1.3) | `cloud_firestore/cloud_firestore_dart_sqlite` |
| `cloud_firestore_dart_flutterfire` (0.1.2, Flutter) | `cloud_firestore/cloud_firestore_dart_flutterfire` |
| `cloud_firestore_dart_platform` (0.1.2, Flutter) | `cloud_firestore/cloud_firestore_dart_platform` |
| `firebase_auth_dart_platform` (0.2.0, Flutter) | `firebase_auth/firebase_auth_dart_platform` |
| `firebase_storage_dart` (0.1.0) | `firebase_storage/firebase_storage_dart` |
| `firebase_storage_dart_platform` (0.1.0, Flutter) | `firebase_storage/firebase_storage_dart_platform` |
| `firebase_admin_dart` (0.1.0; trusted code only, never ship a service account key) | `firebase_admin/firebase_admin_dart` |
| `firebase_database_dart` (0.1.0) | `firebase_database/firebase_database_dart` |
| `firebase_database_dart_sqlite` (0.1.0) | `firebase_database/firebase_database_dart_sqlite` |
| `firebase_database_dart_platform` (0.1.0, Flutter) | `firebase_database/firebase_database_dart_platform` |

- `examples/`: complete example packages (`server_shelf`, `cli`, `storage_cli`, `cloud_run_job`).
- `docs/`: guides (`docs/guides/`), parity, support policy, how we test, upstream sync records.
  Adding a new Firebase product: [docs/contributing_a_product.md](docs/contributing_a_product.md).
  The SVG figures in `docs/images/` follow the palette and light/dark rules of
  `docs/images/README.md`; check them with `dart tool/check_figures.dart`.
- `tool/`: test, emulator and size scripts; `tool/README.md` describes each one.
- Legacy code from the original project, not maintained and not part of the tested set:
  `firebase_auth/firebase_auth_dart`, `firebase_auth/firebase_auth_vm`,
  `firebase_core/firebase_core_dart`, `google_sign_in_dart`, and `dev/`
  (unchanged since 2021). Leave them alone unless the task names them.
- Inside the repository, `pubspec_overrides.yaml` makes the packages resolve each other from
  their sibling directories.

## Checks

From the repository root:

    ./tool/test_all.sh            # pub get, analyze lib, unit tests of the three packages; analyze examples/

Integration tests need the Firestore emulator (Java, and the Firebase CLI installed in
`.emulator/`, see `tool/README.md`):

    ./tool/start_emulator.sh                 # 127.0.0.1:8080, project demo-test
    ./tool/test_integration.sh standard
    ./tool/stop_emulator.sh

In `cloud_firestore/cloud_firestore_dart`:

- Every ```` ```dart ```` block of the READMEs, `docs/migrating_from_vm_packages.md` and
  `docs/guides/*.md` is compiled by a test. After changing one, regenerate and analyze:

      UPDATE_GOLDEN=1 dart test test/unit/api/readme_snippets_test.dart
      dart analyze test/readme

  Fix what the analyzer reports in the Markdown, not in the generated file. Blocks fenced as
  `dart lite` are checked against `lite.dart`; other info strings are not compiled. The Realtime
  Database guides (`database.md`, `database_flutter.md`) are compiled by the snippet tests of the
  database packages instead (`_guidesCheckedElsewhere` in the test).
- `test/unit/api/public_api.golden.txt` lists the public API. A failing
  `public_api_golden_test.dart` means the public surface changed; if intended, regenerate with
  `UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart` and review the diff.
- Formatting: `dart format lib example` in each of the three packages (CI checks it on Dart
  3.8.0). Do not format `test/readme/readme_snippets.dart`, which is generated.

## Rules

- **Never contact production Firebase.** Tests run against the emulator. The integration suite
  reaches a real project only when `FIRESTORE_TEST_PROJECT_ID` is set and
  `FIRESTORE_EMULATOR_HOST` is not; the production verification kit only with the user's own
  credentials and `--yes`. Do not set these up yourself.
- **Use a private emulator for heavy or web runs.** The web transport and browser tests use
  `tool/start_private_emulator.sh [port]` / `tool/stop_private_emulator.sh [port]` (default
  8090), never the shared emulator on 8080. The stop scripts signal only the pid their start
  script recorded; stop only what you started.
- **No credentials in the repository.** Do not commit key files; samples use placeholders such
  as `my-project` and `demo-` project ids.
- **Publishing is the maintainer's manual step.** `release.yml` validates a tag and never
  publishes; CI has no pub.dev credentials.
- Do not weaken or remove assertions to make a test pass; report flaky tests instead.
- Where the port deliberately differs from upstream, `docs/ARCHITECTURE.md` lists the deviation
  and the test that pins it.
