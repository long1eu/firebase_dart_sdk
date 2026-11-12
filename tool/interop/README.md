# tool/interop

Node harness for the interop tests between `cloud_firestore_dart` and the real JS SDK
(`firebase`, plus `firebase-admin` for bundles). It only talks to the Firestore emulator and
needs no credentials.

```sh
cd tool/interop && npm install          # node_modules is git-ignored
tool/start_emulator.sh                  # emulator on 127.0.0.1:8080, project demo-test
cd cloud_firestore/cloud_firestore_dart
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration/firebase/firestore/js_interop_test.dart
```

The tests are skipped (with the reason) when `node`, `node_modules` or the emulator host is
missing. `harness.mjs <command> <input.json> <output.json>` is run by the Dart tests, one Node
process (and so one JS SDK instance with an empty cache) per command:

| command | what the JS side does |
| --- | --- |
| `write-snapshots` | writes documents and returns `toJSON()` of document and query snapshots |
| `read-snapshots` | `documentSnapshotFromJSON` / `querySnapshotFromJSON` / `onSnapshotResume` of JSON written by Dart |
| `values-to-json`, `values-from-json` | `toJSON()` / `fromJSON()` of Timestamp, GeoPoint, Bytes, DocumentReference, VectorValue |
| `write-data`, `read-data` | writes / reads documents described by a tagged value format shared with the Dart tests |
| `build-bundle` | builds a bundle with `firebase-admin` (`firestore.bundle()`) |

Known differences the tests pin down (JS SDK 13.3.0):

- `toJSON()` of a `limitToLast()` query snapshot writes the inverted query without the `LAST`
  limit type; of a subcollection query it writes the database root as the parent. Both read
  back as a different query, in the JS SDK too. Dart writes the form `firebase-admin` writes,
  which the JS SDK reads correctly.
- `toJSON()` of a missing document writes an empty bundle, which the JS SDK cannot read back
  (`documentSnapshotFromJSON` and `onSnapshotResume` fail). Dart reads it as a missing document.
- The JS SDK has one number type: it writes doubles that are safe integers (except -0) as
  integers, and reads integers outside of the safe range as the nearest double.
