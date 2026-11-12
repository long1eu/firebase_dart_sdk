# cloud_firestore_dart: API modernization plan

Status (updated at the end of the revival): stage 0 (hygiene) and the non-breaking part of stage 1 (aliases) are
merged. Several Stage 2-4 feature items were also delivered (see "Status at the end of the revival" below); the
idiom-level renames of stage 1-3 that change signatures are still a plan. Written 2026-11-12. The listings in
sections 0-4 describe the plan and the baseline at the time of writing and are not rewritten; the golden file
`test/unit/api/public_api.golden.txt` is the source of truth for the current surface.

Evidence legend. **[R]** = read in this repo (cloud_firestore_dart, null-safe branch). **[F]** = read from
FlutterFire `main` (`packages/cloud_firestore/cloud_firestore/lib/...`, fetched with curl: `cloud_firestore.dart`,
`firestore.dart`, `query.dart`, `document_reference.dart`, `collection_reference.dart`, `filters.dart`).
**[J]** = read from firebase-android-sdk (Dec 2019 checkout used for the model audit). **[U]** = from memory, unverified.

## 0. Current public surface (the baseline) [R]

`lib/cloud_firestore_dart.dart` exports: Blob, CollectionReference, DocumentChange, DocumentReference, DocumentSnapshot,
FieldPath, FieldValue, Firestore, FirestoreError (+FirestoreErrorCode), FirestoreSettings, GeoPoint, MetadataChanges,
Query, QueryDocumentSnapshot, QuerySnapshot, SetOptions, SnapshotMetadata, Source, Transaction,
`util/database.dart` (the SQLite abstraction), WriteBatch, Timestamp.
`ServerTimestampBehavior` is NOT exported although `DocumentSnapshot.getData/get` take it.
Everything else (core/local/remote/model/auth/util, `ListenOptions`, `UserDataConverter`) is under `src/` and not
exported, but is reachable by `package:cloud_firestore_dart/src/...` imports, and the public classes leak internals
(see 1.9).

## 1. Dart idioms the port lacks

### 1.1 Java-style accessors and names [R]
| Today | Idiomatic / official | Notes |
|---|---|---|
| `Firestore.getInstance(app, ...)` (Future) next to `Firestore.instance` getter | `Firestore.instance` / `instanceFor({app, databaseId})` | `getInstance` is async because the multi-db component is created lazily; keep a Future factory but name it `instanceFor`/`open`. |
| `Firestore.document(path)` | `doc(path)` | FlutterFire uses `doc` [F firestore.dart:204, collection_reference.dart:33]. |
| `CollectionReference.document([path])` | `doc([path])` | same |
| `DocumentSnapshot.getData(serverTimestampBehavior)`, `data` getter | `data()` method with optional options | FlutterFire `data()` is a method [U for DocumentSnapshot; the file was not fetched]. Today `data` is a getter plus `getData(...)`. |
| `getString/getInt/getBool/getDouble/getDate/getTimestamp/getBlob/getGeoPoint/getDocumentReference` | `snapshot.get<T>(field)` plus `snapshot[field]`, or extension methods | Typed getters are an Android-ism [J]; FlutterFire has only `get(field)` and `[]` [U]. |
| `Query.getSnapshots([changes])` and `snapshots` getter | `snapshots({includeMetadataChanges, source})` | `Stream<QuerySnapshot>` is already used [R query.dart:675-682]; just collapse the two entry points. |
| `QuerySnapshot.documents` (a `List<DocumentSnapshot>`), `documentChanges`, `getDocumentChanges(MetadataChanges)` | `docs`, `docChanges`, `docChanges` via options | QuerySnapshot also `extends Iterable<QueryDocumentSnapshot>` [R], which duplicates `documents`; and `documents` returns the less specific type. |
| `DocumentSnapshot.reference` | `ref` | FlutterFire name [U]. |
| `Query.whereEqualTo/whereEqualToField/whereLessThan...Field` (20 methods) | `where(Object field, {isEqualTo, isLessThan, ...})` | [F query.dart:154-170]. The `...Field` duplicates exist only because Java overloads on String/FieldPath. `field` as `Object` (String or FieldPath). |
| `Query.orderBy(field, [Direction])` | `orderBy(Object field, {bool descending = false})` | [F query.dart:103]. `Direction` enum is then unnecessary. |
| `startAt(List)`, `startAtDocument`, `endAtDocument`, ... | same names but `Iterable<Object?>` | already near parity [R]. `limitToLast` missing (see 2). |
| `DocumentReference.updateFromList(List)` / `update(Map<String,Object?>)` | `update(Map<Object, Object?>)` where keys may be String or FieldPath | [F document_reference.dart:44]. Same for WriteBatch/Transaction. |
| `FieldValue.getOperand()`, `isDelete`... | keep private/hide | implementation detail leaking [R field_value.dart:54-110]. |
| `FieldPath.documentId()` static method | `FieldPath.documentId` constant (static const / getter) | [F, used as `FieldPath.documentId` in docs of query.dart] |
| `SetOptions.mergeAllFields`, `mergeFields`, `mergeFieldPaths` | `SetOptions(merge: true, mergeFields: [...])` | [F exports SetOptions from the platform interface; constructor shape: U]. |
| `FirestoreError`/`FirestoreErrorCode` | `FirebaseException(plugin: 'cloud_firestore', code: 'not-found', message:)` | see 1.6. |

### 1.2 Future / Stream
- Already good: `Future<DocumentSnapshot> get([Source])`, `Stream<...> snapshots`, `Future<T> runTransaction`-like `Firestore.runTransaction(TransactionCallback<T>)` [R firestore.dart:203], `BatchCallback` typedef.
- Replace `Source` arg of `get` by `GetOptions(source:)` (official) or keep `Source` and add `GetOptions` [F query.dart:74].
- `snapshots()` needs `{includeMetadataChanges, source: ListenSource}` instead of a `MetadataChanges` enum argument [F query.dart:87-90].
- `Firestore.runBatch(BatchCallback)` is Android's `runBatch`; fine, keep.
- Streams are created from the internal `EventManager` listener machinery. Make sure the public stream is a proper single-subscription stream whose `onCancel` unregisters the listener (verify; not read in detail) and that errors arrive as stream errors.
- `Firestore.enableNetwork/disableNetwork/shutdown` return Future: fine. `shutdown` -> alias `terminate` [F firestore.dart:307].

### 1.3 Named params, cascades, const [R]
- `FirestoreSettings` is already named-param with `copyWith` (good).
- `Firestore(databaseId, firebaseApp, client, scheduler)` is a public positional constructor marked `@visibleForTesting`; make it a private/ internal constructor and expose a `@visibleForTesting` factory.
- `DocumentChange`, `SnapshotMetadata` have positional ctors: fine (const where possible: `SnapshotMetadata` already const).
- `Query` ctor is `const Query(this.query, this.firestore)` taking the internal `core.Query` as a public parameter: internal type leak (1.9).
- Method chaining already returns `this`-like new objects; `WriteBatch`/`Transaction` return `this` so cascades work, no change needed.

### 1.4 Enums and constants
- `FirestoreErrorCode` is a hand-rolled class with `static const`s and a `_names` table [R]. Convert to an enhanced enum (`enum FirestoreErrorCode { ok(0, 'ok'), ... }` with `final int value`, `fromGrpc`). Keep `FirestoreErrorCode.notFound` etc. names, so source-compatible.
- `Direction`, `MetadataChanges`, `Source`, `ServerTimestampBehavior`, `DocumentChangeType` are already enums [R]. `Source.defaultSource` mirrors official `Source.serverAndCache` [U: official is `serverAndCache, server, cache`; verify]. Plan: rename with deprecated alias getter (`static const defaultSource = serverAndCache`).
- `FilterOperator.IN` / `graterThan` (typo) are internal in core/ [R query.dart:137]. Do not expose; fix the typo internally only with a regression-safe rename (touches core/filter.dart).
- `Blob` (`bytes`), `GeoPoint`, `Timestamp`: fine as value classes. GeoPoint has asserts using `identical(x, double.nan)` which never detects NaN; fix to `x.isNaN` (bug, S).

### 1.5 Extension methods / records / sealed
- Extensions: typed getters on `DocumentSnapshot` (`getString` etc.) can become `extension DocumentSnapshotGetters on DocumentSnapshot`, which lets the core class shrink and lets us deprecate cleanly. Also `QuerySnapshot` convenience (`docs`) and `Stream<QuerySnapshot>` helpers (`.docs`).
- Sealed classes: `FieldValue` sentinels (`_DeleteFieldValue`, `_ServerTimestampFieldValue`, ...) are an obvious `sealed class FieldValue` hierarchy, replacing the `isDelete/isArrayUnion/...` boolean getters with exhaustive `switch`. Same for the internal `model/value/FieldValue` (14 subclasses; leave, it is Java-faithful and internal).
- Records: low value. Candidate only for `Query.startAt` cursor bundles; skip.
- `SetOptions`: three factories + two consts + `merge`/`fieldMask`; could be a `final class` with named optional params. Low priority.

### 1.6 Errors
- `FirestoreError extends FirebaseError` (from `firebase_app_dart`) with `FirestoreErrorCode code`, `cause` [R]. Official convention: `FirebaseException` with a string `code` like `'not-found'` and `plugin: 'cloud_firestore'` [F cloud_firestore.dart exports FirebaseException; field names U].
- Plan: keep `FirestoreError` as a subtype of whatever base `firebase_app_dart` offers; if `firebase_app_dart` adds `FirebaseException`, make `FirestoreError implements FirebaseException` with `code` string getter (`'not-found'`) while keeping the typed `errorCode`. Because `code` currently is `FirestoreErrorCode` (not String), this is a breaking change if renamed in place: add `errorCode` first, deprecate `code` typing in the next major.
- `toString` prints `$runtimeType:$code $message $cause $stackTrace`; trim.
- Argument validation uses `checkNotNull`/`checkArgument` (throws ArgumentError) and `hardAssert` (AssertionError): in the public layer, use `ArgumentError`/`StateError` and remove runtime `checkNotNull` of non-nullable params (dead under null safety, [R] e.g. firestore.dart:77, 151, 159).

### 1.7 Honest nullability, and where `Object?` widening is wrong
- Done in migration: `data: Map<String, Object?>?`, `get(field)` returns `Object?`, `getString` etc. return `T?`.
- Where `Object?` widening is lossy: `Map<String, Object?>` for set/update is right (null is a valid field value). But `whereIn(List<Object?>)`, `startAt(List<Object?>)` accept nulls that are legal in Firestore (null equality filter), so keep. What is wrong: `FieldValue.arrayUnion(List<Object>)` etc. should stay `List<Object?>` too since null is a legal array element [U: Android allows null? verify in `UserDataConverter`]. Test code had to switch to `<Object>[...]` for this (mutation_test.dart), suggesting `arrayUnion` was left non-null; decide by consulting Java `parseArray` rules.
- `QueryDocumentSnapshot.data` returns non-null `Map` while `DocumentSnapshot.data` is nullable: correct, mirrors Java `@NonNull` override.
- `Firestore.firebaseApp` is `FirebaseApp?` [R] - Java's `getApp()` is nullable for tests only; fine.
- Replace `dynamic`-returning callbacks and `Function task` (e.g. `ExponentialBackoff.backoffAndRun(Function)`) with `FutureOr<void> Function()` (internal).
- `@required` leftovers: none remain in model/util/auth; the other dirs were migrated by other agents (re-run `grep -rn "@required" lib test` as the first checklist step: unverified for core/local/remote).

### 1.8 Typed collections (the large missing feature) [F]
FlutterFire is generic: `CollectionReference<T>`, `DocumentReference<T>`, `Query<T>`, `DocumentSnapshot<T>`, `QuerySnapshot<T>`, with `withConverter<R>({fromFirestore, toFirestore})` [F query.dart:188, document_reference.dart:92]. This port has no generics. Adding them is the single biggest public-API change (see 2, section "real features").

### 1.9 Library layout and public vs src
- One barrel (`cloud_firestore_dart.dart`) is right. Problems [R]:
  - exports `util/database.dart` (SQLite abstraction + `OpenDatabase` typedefs with non-null-safe optional named params like `{int version, OnConfigure onConfigure ...}`; **this file still had non-null-safe signatures when read**, check it); it should be a separate `package:cloud_firestore_dart/persistence.dart` entry point (needed by embedders who supply a database), not part of the main API.
  - `ServerTimestampBehavior` is not exported; `MetadataChanges`, `Direction` are.
  - Public classes expose internals as public fields/constructor params: `Query(core.Query query, Firestore firestore)`, `DocumentReference(DocumentKey key, Firestore)`, `DocumentSnapshot(firestore, key, Document?, ...)`, `Firestore(databaseId, app, client, scheduler)`, `QuerySnapshot(query, ViewSnapshot, firestore)`, `DocumentChange.changesFromSnapshot`. Make these constructors library-private via `@internal` (package:meta) now, and change to real privacy when the facade lands (section 3).
  - Tests import `package:cloud_firestore_dart/src/...` extensively; fine for internals, but test helpers (`test/util/test_util.dart`) construct public types via those internals, which is the reason the constructors cannot simply be made private.
  - FlutterFire uses `part` files in a single library; we do not need that.

## 2. API parity

Compared with FlutterFire `main` [F] and Android [J/U].

### 2.1 Cheap renames (aliases + `@Deprecated`, no behavior change)
| Item | Today | Target | Strategy |
|---|---|---|---|
| Class name | `Firestore` | `FirebaseFirestore` (both Android and FlutterFire) | `typedef Firestore = FirebaseFirestore;` keep until next major. Rename the class, typedef the old name (typedef works for static members and constructors). |
| Doc accessor | `Firestore.document`, `CollectionReference.document` | `doc` | add `doc`, `@Deprecated` forwarders `document`. |
| Snapshot docs | `QuerySnapshot.documents` | `docs`; `documentChanges` -> `docChanges` | add getters, deprecate old. |
| Reference | `DocumentSnapshot.reference` | `ref` [U] | add getter. |
| Terminate | `shutdown` | `terminate` | add, deprecate. |
| Documents id | `FieldPath.documentId()` | `FieldPath.documentId` getter/const | `static FieldPath get documentId` conflicts with the method of the same name, so a clean alias is impossible: add `FieldPath.documentIdField`, remove in the major. |
| Instance | `Firestore.getInstance`, `newInstance` | `instance`, `instanceFor({app})` | add `instanceFor`, deprecate. |
| Source enum | `Source.defaultSource` | `serverAndCache` [U] | add member; keep old as deprecated static const. |
| Snapshots | `getSnapshots([changes])` | `snapshots({includeMetadataChanges})` | `snapshots` is currently a getter; changing it to a method breaks `ref.snapshots.listen`. Plan: add method `snapshotsWith({...})` first, flip in the major. |
| Error | `FirestoreError.code` | `FirebaseException.code` string | see 1.6; breaking in the end. |
| Settings | `FirestoreSettings` | `Settings` [F] | `typedef`; fields `host`, `sslEnabled`, `persistenceEnabled`, `cacheSizeBytes` already match [R]. `port` has no FlutterFire equivalent (host includes port there [U]). |
| WriteBatch.updateFromList, Transaction.updateFromList, DocumentReference.updateFromList | separate | `update(Map<Object, Object?>)` | add overload by widening key type; keep `updateFromList` deprecated. |

### 2.2 Query API reshaping (medium)
- `where(field, {isEqualTo: ...})` with ~12 named args, `orderBy(field, {descending})`, `startAt(Iterable)`. New methods can sit beside old ones with no conflicts (`where` and `orderBy` are new names or compatible): `orderBy(String, [Direction])` vs `orderBy(Object, {bool descending})` conflict on the second parameter, so `orderBy` needs the major bump or a rename (`orderByField`). 
- Missing operators: `isNotEqualTo` (`!=`), `whereNotIn`, `isNull` shorthand [F query.dart:154]. These require core support (`FilterOperator.notEqual`, `notIn`): real feature, L (core/ + remote serializer + proto fields). Verify proto has `NOT_EQUAL`/`NOT_IN` (the proto dir was regenerated; check `StructuredQuery.FieldFilter.Operator`).
- `limitToLast`: real feature (core `Query.limitToLast` + View handling of `limitToLast`, which this port's view.dart lacks: it uses only `hasLimit` [R view.dart:84,168], the Java version I audited has `hasLimitToFirst/hasLimitToLast`). M-L.

### 2.3 Real features missing vs FlutterFire/Android (not renames)
1. Generics + `withConverter` [F]: M-L, touches every public class; additive if default type is `Map<String, Object?>`.
2. `Filter.or/and`, `Filter(field, isEqualTo...)` composite filters [F filters.dart:46-235]: L (core filter model, query planning, serializer `CompositeFilter`, local index/matching). Requires multi-disjunction handling.
3. Aggregations: `count()`, `aggregate(sum/average/count)` [F query.dart:193-197]: M for count (RunAggregationQuery RPC in remote/datastore + proto), M more for sum/average.
4. `LoadBundle`/`loadBundle`, `namedQueryGet` [F firestore.dart:105,157,170]: L (bundle parsing, local store named queries).
5. `snapshotsInSync`, `waitForPendingWrites`, `clearPersistence`, `useFirestoreEmulator`, `terminate` [F firestore.dart]: waitForPendingWrites M (sync engine: Android `waitForPendingWrites` [U]); clearPersistence S-M (persistence delete); `useFirestoreEmulator` S (set host/port/ssl); `snapshotsInSync` M.
6. `ListenSource` (cache-only listeners) [F]: M.
7. `GetOptions`: S.
8. Index configuration (`setIndexConfigurationFromJSON`), `PersistentCacheIndexManager`, `VectorValue`, Pipelines [F]: out of scope; mark as non-goals.
9. `SnapshotOptions` (Android): this port exposes the same through `ServerTimestampBehavior` params; add a `SnapshotOptions` wrapper only if API parity with Android is the goal [U].
10. `Firestore.collection` etc. path validation messages: fine.

### 2.4 Already at parity [R]
`Source`, `SetOptions` (merge variants), `Transaction`, `WriteBatch`, `FieldValue.delete/serverTimestamp/arrayUnion/arrayRemove/increment`, `SnapshotMetadata`, `DocumentChange(+type)`, `GeoPoint`, `Blob`, `Timestamp`, `FieldPath`, `startAt/startAfter/endAt/endBefore` (+document variants), `limit`, persistence/cache size settings, network enable/disable, `collectionGroup`.

## 3. Migration path

### 3.1 Principle: a thin public facade over the Java-faithful internals
Keep `core/ local/ remote/ model/ auth/ util/ proto/` exactly as they are (their names track the Android SDK, which makes upstream diffs/port updates possible). All API changes go in the ~25 top-level files in `lib/src/firebase/firestore/*.dart` (3392 lines [R]) plus the barrel. Do not touch internal names such as `getFirstDocument`, `getData`, `FilterOperator.IN`; internals are not part of the public contract once `src/` classes stop leaking.
Facade steps:
1. Introduce `lib/src/api/` (new public layer) with the new classes (`FirebaseFirestore`, `Query<T>`, ...) implemented by delegating to the existing top-level classes, which become internal ("impl") classes. Initially the old classes stay exported; new ones are exported under new names.
2. Make the internal classes' constructors `@internal`.
3. In the major release, remove the old exports and move impl classes out of the barrel.

### 3.2 Ordering
1. **Stage 0 (no API change, S):** hygiene: export `ServerTimestampBehavior`; `@internal` on leaking constructors/fields; fix `GeoPoint` NaN assert; fix remaining `@required`; move `util/database.dart` export to its own entry point (this one is breaking for anyone importing it from the main library: do it in Stage 3, or keep exporting + add the new entry point).
2. **Stage 1 (additive, aliases only; minor version 0.1.x):** `doc`, `docs`, `docChanges`, `ref`, `instanceFor`, `terminate`, `GetOptions`, `useFirestoreEmulator`, `FirebaseFirestore`/`Settings` typedefs, nullable `getFirstDocument` (done), `FieldPath.documentIdField`, `Source.serverAndCache`; old names `@Deprecated('Use X')`. Also `where({...})` named-param form as a new method (no clash) plus `descending` via new `orderByField(field, {descending})`.
3. **Stage 2 (additive features, minor):** `limitToLast`, `count()`, `snapshots` options method, `waitForPendingWrites`, `clearPersistence`, `isNotEqualTo/whereNotIn` (needs core), generics/`withConverter` (additive when type argument defaults to `Map<String, Object?>`; existing code that writes `DocumentSnapshot` still compiles because a raw generic type infers its default bound/`dynamic`; check `Query<Object?>`-style inference to avoid `dynamic` creeping in).
4. **Stage 3 (breaking, 1.0 / semver major, because the package is 0.0.7 any minor can break by semver rules, but still announce):** remove deprecated names; flip `snapshots` getter to method; `FirestoreErrorCode` enum + `FirebaseException` conventions; convert `orderBy` signature; remove `util/database.dart` from the barrel; private constructors.
5. **Stage 4 (large features):** `Filter.or/and`, aggregates beyond `count`, bundles, `ListenSource`.

What aliases can do: renames, new overloads with new names, getters alongside methods (different names). What they cannot: same-name signature changes (`orderBy`, `snapshots` getter-to-method, `FieldPath.documentId()` vs getter, `FirestoreError.code` type, `Source.defaultSource` if the enum value is truly renamed) - those wait for Stage 3.

### 3.3 Verification
- Keep the existing suite green after every stage: unit suite (446 tests per coordinator; `find test -name '*_test.dart'` lists 65 files [R]) via `dart test test/unit`, and the emulator integration tests in `test/integration/firebase/firestore/` (array_transforms, cursor, fields, firestore, numeric_transformas [sic], query, remote/, server_timestamp, smoke, source, stream_subscription, transaction, type, validation, write_batch) against the Firestore emulator (needs `firebase emulators:start --only firestore` and the project id those tests expect; I did not run them).
- Add an API-compat test: `test/api/deprecated_aliases_test.dart` that calls both old and new names and asserts equal results; run `dart analyze --fatal-infos` with `deprecated_member_use` allowed only in that file.
- Add `dart doc` + a golden listing of exported symbols (`dart pub global run dart_apitool` or a simple script over `lib/cloud_firestore_dart.dart` exports) to detect accidental public surface changes.
- Tests needing renames when the new names land (only call-sites; no behavior): `collection_reference_test.dart` (`document` -> `doc`), `document_reference_test.dart`, `document_snapshot_test.dart` (`getData`, `reference`), `query_snapshot_test.dart` (`documents`, `documentChanges`), `query_test.dart` (unit and integration: `whereEqualTo*`, `orderBy`, `Direction`, `getSnapshots`), `document_change_test.dart`, `snapshot_metadata_test.dart`, all of `test/integration/**` (they use the public API heavily), `test/util/test_util.dart` (`ref()` uses `TestAccessHelper.createDocumentReference`, `FieldPath.documentId`), `test/unit/firebase/firestore/test_util.dart`, spec tests under `test/unit/firebase/firestore/spec` are internal and should not change. Internal-only tests (`core/`, `local/`, `remote/`, `model/`, `util/`) should not need renames if the facade rule holds.
- Run the unit suite with both the old exports and the new exports present to prove the aliases do not shadow each other.

## 4. Prioritized checklist

Sizes: S < 0.5 day, M ~ 1-3 days, L > 3 days. "Files" are under `lib/src/firebase/firestore/` unless noted.

| # | Item | Size | Files touched |
|---|---|---|---|
| 1 | Export `ServerTimestampBehavior`; `@internal` on leaking ctors/fields | S | `cloud_firestore_dart.dart`, `firestore.dart`, `query.dart`, `document_reference.dart`, `document_snapshot.dart`, `query_snapshot.dart`, `document_change.dart` |
| 2 | Fix `GeoPoint` NaN/infinity asserts (bug); `grep @required` sweep; re-check `util/database.dart` null safety | S | `geo_point.dart`, `util/database.dart`, any file with `@required` |
| 3 | Add `doc`, `docs`, `docChanges`, `ref`, `terminate`, `instanceFor`, `FieldPath.documentIdField`, `Source.serverAndCache`; deprecate old names | S-M | `firestore.dart`, `collection_reference.dart`, `document_reference.dart`, `query_snapshot.dart`, `document_snapshot.dart`, `field_path.dart`, `source.dart` |
| 4 | `typedef FirebaseFirestore`/`Settings`; or rename class + typedef old | S (typedef) / M (rename: imports in tests) | `firestore.dart`, `firestore_settings.dart`, barrel, ~all tests that name `Firestore` |
| 5 | `FirestoreErrorCode` -> enhanced enum, `errorCode`, string `code`, `FirebaseException` alignment | M | `firestore_error.dart`, `remote/*` callers constructing errors, `util/util.dart` `exceptionFromStatus`, tests that compare codes |
| 6 | Drop dead `checkNotNull` of non-nullable params in public layer | S | `firestore.dart`, `document_reference.dart`, `collection_reference.dart`, `query.dart`, `write_batch.dart`, `transaction.dart`, `field_path.dart` |
| 7 | `where({named})`, `orderByField(field, {descending})`, `update(Map<Object, Object?>)` overload; deprecate `*Field` and `updateFromList` | M | `query.dart`, `document_reference.dart`, `write_batch.dart`, `transaction.dart`, `user_data_converter.dart` |
| 8 | `snapshots` options method; `GetOptions`; `ListenSource.defaultSource` only | S-M | `query.dart`, `document_reference.dart`, new `get_options.dart` |
| 9 | `sealed class FieldValue` public hierarchy, hide `isX`/`getOperand` | S | `field_value.dart`, `user_data_converter.dart` |
| 10 | Typed accessors as extension on `DocumentSnapshot`; add `get<T>`/`operator []` | S | `document_snapshot.dart` (+ new extension file) |
| 11 | `useFirestoreEmulator`, `waitForPendingWrites`, `clearPersistence` | M | `firestore.dart`, `firestore_settings.dart`, `core/firestore_client.dart`, `core/sync_engine.dart`, `local/*persistence*` |
| 12 | `limitToLast` (+ View support) | M-L | `query.dart`, `core/query.dart`, `core/view.dart`, `core/target.dart`-equivalent, serializer in `remote/` |
| 13 | `isNotEqualTo`, `whereNotIn`, `isNull` | L | `query.dart`, `core/filter.dart` (+`FilterOperator`), `remote/remote_serializer.dart`, proto check, local matching |
| 14 | Generics + `withConverter` | L | every public file; `query_snapshot.dart`, `document_snapshot.dart`, `collection_reference.dart`, `document_reference.dart`, `query.dart`, `write_batch.dart`, `transaction.dart`, tests |
| 15 | `count()` aggregate | M | `query.dart`, `remote/datastore.dart`, `remote/remote_serializer.dart`, proto |
| 16 | `Filter.or/and` | L | `query.dart`, new `filter.dart`, `core/*` (composite filters, DNF), serializer |
| 17 | Move `util/database.dart` to separate entry point; private ctors; remove deprecated names (the 1.0 breaking release) | M | barrel, `util/database.dart`, all deprecations |
| 18 | Bundles (`loadBundle`, `namedQueryGet`) | L | new `core/bundle*`, `local/` named query store, `firestore.dart` |
| 19 | Compat/golden-surface tests, CI for emulator tests | M | `test/api/*`, CI config |

### Risks / open questions
- Several FlutterFire facts here came from its public interface at `main` (a very recent API with pipelines); older FlutterFire pins may differ. Specific points marked [U] (DocumentSnapshot method shapes, `Source` member names, SetOptions ctor) should be confirmed by fetching `document_snapshot.dart` and the platform-interface package before implementing.
- The Android API at the current head is far ahead of the 2019/2020 port the internals follow [J]: items 12, 13, 15, 16, 18 each require porting internals from newer Java, not just public glue.
- Version/semver: package is 0.0.7; treat Stage 3 as 0.1.0 or 1.0.0.

## Implementation status (branch wave/api-hygiene)

### Done
| Item | What changed | Where |
|---|---|---|
| Export `ServerTimestampBehavior` | added to the barrel (it is used in `DocumentSnapshot.getData/get` signatures) | `lib/cloud_firestore_dart.dart` |
| `@internal` on constructors that leak internals | `Query`, `CollectionReference`, `DocumentReference` (ctor and `forPath`), `DocumentSnapshot` (ctor, `fromDocument`, `fromNoDocument`), `QueryDocumentSnapshot.fromDocument`, `QuerySnapshot`, `DocumentChange` (ctor and `changesFromSnapshot`), `WriteBatch`, `Transaction`. They stay usable inside the package (tests build them); outside callers get an analyzer warning. `Firestore(...)` was already `@visibleForTesting`. | the matching files in `lib/src/firebase/firestore/` |
| `GeoPoint` NaN assert | `identical(x, double.nan)` never matched a computed NaN, so the NaN messages were dead (NaN was only caught by the range check, with a misleading message). Now `x == x` (so it works in a const initializer), both infinities are rejected with a precise message. Still an `assert` (debug/test only), as before. | `geo_point.dart`, `test/unit/firebase/firestore/geo_point_test.dart` |
| `@required` leftovers | none left in `lib/` (grep) | n/a |
| `util/database.dart` export | kept: `Firestore.getInstance(openDatabase: ...)` exposes `OpenDatabase`/`Database` in its public signature, so moving them out of the barrel is breaking (stage 3). The file is null-safe; the `OpenDatabase` typedef declares non-nullable optional named parameters, which every caller passes, so no change was needed. | n/a |
| `FirebaseFirestore` typedef | `typedef FirebaseFirestore = Firestore;` in a new `aliases.dart`. Verified in `test/unit/api/deprecated_aliases_test.dart`: construction (`super(...)` through the alias in a subclass), `extends FirebaseFirestore`, `is Firestore`, `identical(FirebaseFirestore, Firestore)`, and identical tear-offs of the statics (`getInstance`, `newInstance`, `instanceFor`, `setLoggingEnabled`). | `aliases.dart` |
| `Settings` typedef | `typedef Settings = FirestoreSettings;` (constructor, statics and `copyWith` verified through the alias) | `aliases.dart` |
| `doc` | `Firestore.doc`, `CollectionReference.doc`; `document` kept, `@Deprecated('Use doc instead.')` | `firestore.dart`, `collection_reference.dart` |
| `instanceFor` | `Firestore.instanceFor({required app, database, openDatabase, settings})` delegating to `getInstance`; `getInstance` `@Deprecated`. Still returns a `Future` (the official one is synchronous), so it is a rename, not full parity. | `firestore.dart` |
| `ref` | `DocumentSnapshot.ref`; `reference` `@Deprecated` | `document_snapshot.dart` |
| `docs`, `docChanges` | `QuerySnapshot.docs` (typed `List<QueryDocumentSnapshot>`), `QuerySnapshot.docChanges`; `documents` and `documentChanges` `@Deprecated` | `query_snapshot.dart` |
| `FieldPath.documentIdField` | static getter; `documentId()` `@Deprecated` (a getter named `documentId` cannot exist next to the method) | `field_path.dart` |
| `Source.serverAndCache` | `static const Source serverAndCache = defaultSource;` inside the enum; `defaultSource` `@Deprecated`. Not a new enum value, so existing `switch` statements stay exhaustive; use the enum values themselves in a `switch`. | `source.dart` |
| Alias compatibility test | old and new names compared in one file that is the only place allowed to call deprecated members | `test/unit/api/deprecated_aliases_test.dart` |
| Golden listing of exported symbols | dart:mirrors based listing of classes, enums, typedefs, members, parameter names, `@deprecated` and `@internal`; regenerate with `UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart`. Mirrors do not expose nullability, so `T` and `T?` look the same. | `test/unit/api/public_api_golden_test.dart`, `public_api.golden.txt` |

Both new test files live under `test/unit/` so `tool/test_all.sh` runs them.

### Deliberately not done here (other agents or breaking)
- `terminate`, `waitForPendingWrites`, `addSnapshotsInSyncListener`: another agent.
- `whereNotEqualTo`, `whereNotIn`, `count`/aggregates, `Filter.or`/`and`: other agents.
- Same-name signature changes (stage 3): `orderBy(field, {descending})`, `snapshots` getter to method, `FirestoreError.code` type, flipping `FieldPath.documentId` to a getter, `update(Map<Object, Object?>)`.
- The new-name `where({isEqualTo...})` form and `orderByField`: they touch `query.dart`, where other agents are adding operators; left to a follow-up to keep this merge small.

### Remaining from the stage 0/1 list
- `where(field, {named})`, `orderByField`, `update(Map<Object, Object?>)` overload, `GetOptions`, `useFirestoreEmulator`, `snapshots` options method, typed accessors as extensions, `sealed FieldValue`, `FirestoreErrorCode` as an enhanced enum (`errorCode`), dropping dead `checkNotNull` calls in the public layer.
- Internal call sites still use the deprecated names (they show up as infos in `dart analyze`); convert them when the files are not being edited by other agents.
- Moving `util/database.dart` out of the barrel, private constructors and removal of the deprecated names are the breaking release.

## Status at the end of the revival

Checklist items from section 4, as of the head of `revival/dart3-null-safety` (derived from the golden API file and
the merge history; verified on the emulator only, never against production Firestore).

| # | Item | Status |
|---|---|---|
| 1 | Export `ServerTimestampBehavior`, `@internal` | done |
| 2 | `GeoPoint` assert, `@required` sweep | done |
| 3 | `doc`, `docs`, `docChanges`, `ref`, `terminate`, `instanceFor`, `documentIdField`, `Source.serverAndCache` | done (`instanceFor` still returns a `Future`) |
| 4 | `FirebaseFirestore` / `Settings` typedefs | done |
| 5 | `FirestoreErrorCode` as enhanced enum / `FirebaseException` alignment | not done |
| 6 | Drop dead `checkNotNull` in the public layer | not done |
| 7 | `where({named})`, `orderByField`, `update(Map<Object, Object?>)` | not done (Java-style `where*` kept; `where(Filter)` added) |
| 8 | `snapshots` options method, `GetOptions` | partly: `SnapshotListenOptions` and `ListenSource` exist; `GetOptions` not added |
| 9 | `sealed` FieldValue hierarchy | not done (`FieldValue.maximum/minimum/vector` added) |
| 10 | Typed accessors as extensions, `get<T>`, `[]` | not done |
| 11 | `useFirestoreEmulator`, `waitForPendingWrites`, `clearPersistence` | `FirestoreSettings.withEmulator` and `waitForPendingWrites` done; `clearPersistence` pending an API decision |
| 12 | `limitToLast` | done (Query/Target split) |
| 13 | `!=`, `not-in` | done (`whereNotEqualTo`, `whereNotIn`); `isNull` shorthand not added |
| 14 | Generics + `withConverter` | not done |
| 15 | `count()` | done, plus `sum`, `average` and `aggregate([...])` |
| 16 | `Filter.or/and` | done (`Filter` class, `where(Filter)`) |
| 17 | Breaking release: move `util/database.dart`, private constructors, remove deprecated names | not done |
| 18 | Bundles | done (`loadBundle`, `loadBundleStream`, `getNamedQuery`) |
| 19 | Golden surface test, emulator CI | golden test done; CI workflow exists (`.github/workflows/ci.yml`) |

Also added beyond the original list: vector values and `Query.findNearest`, cache settings
(`PersistentCacheSettings`, `MemoryCacheSettings`), `TransactionOptions`, `snapshotsInSync`, App Check plumbing.
Read-only transactions (`TransactionOptions.readOnly`) were added later and are not counted here.
