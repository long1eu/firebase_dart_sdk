---
name: cloud-firestore-dart
description: Use when writing or reviewing Dart or Flutter code that uses cloud_firestore_dart, firebase_app_dart or firebase_auth_providers_dart, the unofficial pure-Dart Cloud Firestore client (not FlutterFire's cloud_firestore, not the JS SDK). Also when such a project has FlutterFire or JS Firestore names that do not compile.
---

# cloud_firestore_dart

`cloud_firestore_dart` is a pure-Dart port of the Firebase Android SDK's Firestore client. It is
not FlutterFire: there is no `firebase_core`, no `Firebase.initializeApp()`, no plugin, no
platform channel, no `firebase_options.dart`. Many names differ from FlutterFire and the JS SDK.
The source of truth for every public name and signature is the golden listing:
<https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/cloud_firestore/cloud_firestore_dart/test/unit/api/public_api.golden.txt>.
A name that is not in it does not exist.

## Workflow

1. **Check the versions.** Read the project's `pubspec.yaml` (and `pubspec.lock`). Expect
   `cloud_firestore_dart`, `firebase_app_dart` and, for sign-in or server credentials,
   `firebase_auth_providers_dart`, all `^0.1.0`, Dart SDK `^3.8.0`. For a disk cache: `sqlite3`
   pinned to 2.x (`^2.7.3`) and, in Flutter, `sqlite3_flutter_libs: ^0.5.0`. If the project is on
   another version than 0.1.x, check names against the golden listing of that version's tag.
2. **Fix the imports.** Only these:
   - `package:cloud_firestore_dart/cloud_firestore_dart.dart` (the client)
   - `package:firebase_app_dart/firebase_app_dart.dart` (`FirebaseApp`, `FirebaseOptions`)
   - `package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart`
     (`FirebaseUserAuth`, `OAuthTokenProvider.serviceAccount`)
   - `package:firebase_auth_providers_dart/adc.dart` (`applicationDefaultCredentials()`;
     needs `dart:io`)
   - `package:cloud_firestore_dart/lite.dart` instead of the main library for Firestore Lite
     (experimental); `package:cloud_firestore_dart/pipelines.dart` for Pipelines (preview,
     Enterprise edition only).
   Remove `package:cloud_firestore/...`, `package:firebase_core/...`, `package:firebase_auth/...`
   from code that targets this client.
3. **Write the setup** in this order: `FirebaseApp.withOptions(...)` (synchronous), then the token
   provider if any, then `Firestore.instanceFor(app: app, settings: ..., openDatabase: ...)` once.
   Templates: [reference/setup.md](reference/setup.md).
4. **Translate remembered names** with the table below; the full table is
   [reference/api_map.md](reference/api_map.md).
5. **Apply the rules** below to every write, listener, transaction and shutdown path.
   Error handling and offline detail: [reference/offline_and_errors.md](reference/offline_and_errors.md).
6. **Verify.** `dart analyze` (or `flutter analyze`) with no errors, then run the code against the
   Firestore emulator (below). Done means: analyzer clean, the main path ran against the emulator,
   and every rule below checked.

## This, not that (short form)

| Remembered (FlutterFire / JS) | Here |
|---|---|
| `Firebase.initializeApp(options: ...)` / `initializeApp(config)` | `FirebaseApp.withOptions(const FirebaseOptions(apiKey:, applicationId:, projectId:))` |
| `FirebaseFirestore.instance` / `getFirestore()` | `Firestore.instanceFor(app: app)`; `Firestore.instance` throws until that ran |
| `firestore.settings = Settings(...)` / `initializeFirestore` | `instanceFor(settings: FirestoreSettings(...))` |
| `useFirestoreEmulator(h, p)` / `connectFirestoreEmulator` | `FirestoreSettings().withEmulator(h, p)` |
| `persistenceEnabled: true` | `openDatabase: sqliteOpener(dir)` + `PersistentCacheSettings()` |
| `snapshot.data()` | `snapshot.data` |
| `ref.snapshots()` / `onSnapshot` | `ref.snapshots` (getter), `getSnapshots(MetadataChanges.include)` |
| `get(GetOptions(source: Source.cache))` | `get(Source.cache)` |
| `SetOptions(merge: true)` | `SetOptions.mergeAllFields` |
| `orderBy('a', descending: true)` | `orderBy('a', Direction.descending)` |
| `Filter('a', isEqualTo: 1)`, `Filter.or(a, b)` | `Filter.equalTo('a', 1)`, `Filter.or([a, b])` |
| `FieldPath(['a'])`, `FieldPath.documentId` | `FieldPath.of(['a'])`, `FieldPath.documentIdField` |
| `querySnapshot.size`, `change.doc` | `querySnapshot.length`, `change.document` |
| `count().get()` then `.count` | `count().get()` then `.getCount()` |
| `Timestamp.millisecondsSinceEpoch` | `toMillis()` |
| `FirebaseException`, `e.code == 'permission-denied'` | `FirestoreError`, `e.code == FirestoreErrorCode.permissionDenied` |
| `runTransaction(fn, timeout: ...)` | `runTransaction(fn, options: TransactionOptions(maxAttempts: 5))` |
| `FirebaseAuth.instance.signIn...` | `await FirebaseUserAuth.forApp(app)` then `auth.signInWithEmailAndPassword(email, password)` |
| Google/Apple/phone sign-in, Storage, Messaging | not available |

## Rules

1. **One instance per app and database**, created once and shared (never per request).
2. **Settings and `openDatabase` only at creation.** Different settings later throw `StateError`;
   `terminate()` first to change them.
3. **Token provider before `instanceFor`**: `app.authProvider = ...` or `FirebaseUserAuth.forApp(app)`.
4. **A write future completes on server acknowledgement.** Offline it waits. In UI code do not
   await it; listeners show the write at once. Attach an error handler.
5. **`terminate()` on exit** (a VM process does not exit otherwise); `waitForPendingWrites()` first
   if unacknowledged writes matter.
6. **Memory cache by default.** Without `openDatabase` nothing is on disk. The opener is a file
   the app copies (`example/sqlite_database.dart`, or `sqlite_database_web.dart` for the web).
7. **`dart:io` only where needed**: `adc.dart`, the SQLite opener, `Platform.environment`. The
   main libraries compile for the web (experimental, Chrome only).
8. **Errors**: `FirestoreError` is an `Error`, not an `Exception`; catch `on FirestoreError`.
9. **Transactions rerun** their callback (keep it free of side effects); `getQuery` and
   `getAggregate` need `TransactionOptions(readOnly: true)`.
10. **Server credentials bypass security rules.** ADC and service accounts only on machines you
    control; end-user apps use `FirebaseUserAuth`. No key files in the repository.
11. **Experimental or preview**: the web, Lite, Pipelines. Say so in code comments or reviews when
    the project depends on them.

## Verify with the emulator

```shell
firebase emulators:start --only firestore --project demo-my-app
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run bin/main.dart   # or dart test
```

The package does not read `FIRESTORE_EMULATOR_HOST`; the code passes it to `withEmulator`. Use a
`demo-` project id. In tests give each test its own app name, `await` every operation and call
`terminate()` then `clearPersistence()` in `tearDown`. Test template and more:
[reference/setup.md](reference/setup.md#tests-against-the-emulator).

## More

- Guide for agents, full: <https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/guides/for_ai_agents.md>
- What is missing: <https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/docs/guides/features.md>
- Runnable examples: <https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart/example>
