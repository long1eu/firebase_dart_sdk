# Owners of the files of firebase_database_dart_platform

One builder per file; no file has two owners. A builder edits only its own files. A signature change in a file
another builder uses goes through the lead and test/skeleton_compile_test.dart in the same change. "Plan" is
`firebase_dart_sdk_revival_ref/rtdb_shim_plan.md`; where it and the client contract
(`rtdb/from_helper/14_api_contract.md`) or the lead's decisions differ, those win (see the skeleton report).

## lib/

| File | Owner | Needs from other files | Plan |
|---|---|---|---|
| `lib/firebase_database_dart_platform.dart` | A | `DartFirebaseDatabase` (`config`, `anyStarted`, `forApp`, `client`), `installCoreIfNeeded` | 2.2, 5.3 |
| `lib/src/app.dart` | A | none (copy of the Storage shim's) | 2 |
| `lib/src/core.dart` | A | none (copy of the Storage shim's) | 2, 5.3 |
| `lib/src/errors.dart` | A | none | 4.8 |
| `lib/src/firebase_database.dart` | A | `DartReference(database, path)` (B), `dartAppFor` | 3.1 rows 1-12, 4.2 |
| `lib/src/values.dart` | B | none | 4.3, 4.7 |
| `lib/src/query.dart` | B | `DartFirebaseDatabase.client` (A), `guard`, `guardStream` (A), `DartDataSnapshot`, `DartDatabaseEvent`, `clientEventType` | 3.2 rows 13-19, 4.4, 4.5, 7.3, 7.4 |
| `lib/src/reference.dart` | B | `guard` (A), `transformValue`, `runDartTransaction` (C), `DartOnDisconnect` (C) | 3.2 rows 20-31 |
| `lib/src/data_snapshot.dart` | B | `DartReference.ofClient`, `mutableCopy` | 3.3 rows 32-42, 7.1, 7.2 |
| `lib/src/transaction.dart` | C | `DartReference.clientRef`, `DartReference.database`, `DartDataSnapshot` (B), `transformValue`, `mutableCopy` (B), `guard` (A) | 3.3 rows 49-50, 4.6 |
| `lib/src/on_disconnect.dart` | C | `DartReference.clientRef` (B), `transformValue` (B), `guard` (A) | 3.3 rows 43-48 |

## Package files

| File | Owner | Plan |
|---|---|---|
| `pubspec.yaml`, `pubspec_overrides.yaml`, `analysis_options.yaml`, `.pubignore`, `.gitignore`, `LICENSE`, `NOTICE` | A | 2.1 |
| `README.md`, `CHANGELOG.md`, `example/main.dart` | C | 9.1 |

## test/

| File | Owner | What it pins | Plan |
|---|---|---|---|
| `test/harness.dart` | A (bodies first, before B and C run tests) | the rig: `server`, `registerForTests`, `newApp`, `createdClients`, `settle`, matchers | 2, R13 |
| `test/skeleton_compile_test.dart` | A | every public signature | - |
| `test/registration_test.dart` | A | `registerWith`/`use`/`isRegistered`, core install, `use` after start throws | 2.2 |
| `test/instance_test.dart` | A | instance cache and app re-creation, settings capture (emulator, persistence, cache size, logging) | 4.2 |
| `test/errors_test.dart` | A | the code table, same-object rethrow, stream errors | 4.8 |
| `test/values_test.dart` | B | `transformValue`, `mutableCopy` | 4.3, 4.7 |
| `test/query_test.dart` | B | modifiers in canonical order, streams (multi listen, cancel, error), `get`, `keepSynced` | 4.4, 4.5 |
| `test/snapshot_test.dart` | B | snapshots, events, `path`, `key`, `parent`, `root` | 3.3 |
| `test/quirks_test.dart` | B | the three quirk pins | 7.1-7.3 |
| `test/transaction_test.dart` | C | handler copy, abort, throw, `applyLocally`, `Transaction.success` tear-off | 4.6 |
| `test/on_disconnect_test.dart` | C | set, setWithPriority, update, cancel, remove | 3.3 |
| `test/emulator_test.dart` | C | smoke run against the emulator; skips without `FIREBASE_DATABASE_EMULATOR_HOST` | 6 |

Outside the package, builder C later owns the repository files of plan section 2 (`tool/` emulator scripts and
`tool/database_shim_gate/`, examples, CI, docs); not part of the three-builder fill of this package.
