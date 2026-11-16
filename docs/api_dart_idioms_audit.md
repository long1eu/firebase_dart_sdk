# API audit: where `cloud_firestore_dart` is shaped like Java rather than Dart

Written while mapping FlutterFire's platform interface (`cloud_firestore_platform_interface` 8.1.0, used by
`cloud_firestore` 7.1.0) onto the public API of `cloud_firestore_dart` 0.1.1 at `origin/main` (`eb33218a`), for the
package `cloud_firestore/cloud_firestore_dart_platform`. Each row is a place where the mapping needed glue code
because of the shape of our API. The source of truth for our surface is
`cloud_firestore/cloud_firestore_dart/test/unit/api/public_api.golden.txt` (it drops nullability; the code was read
where nullability mattered).

Columns: our current API, FlutterFire's equivalent (the app-facing `cloud_firestore` package unless the row says
platform interface), what the adapter had to do, and a suggested Dart-idiomatic shape. "Adapter" refers to files in
`cloud_firestore/cloud_firestore_dart_platform/lib/src/`. Facts only; nothing in `lib/` of the published packages was
changed.

## 1. Naming: getters, `getX`, Java overloads

| # | Ours today | FlutterFire | Adapter glue | Suggested shape |
|---|---|---|---|---|
| 1.1 | `DocumentSnapshot.data` is a getter, plus `getData(ServerTimestampBehavior)` | `data()` method; the server timestamp behaviour comes from `GetOptions` | calls `getData(behavior)` | `T? data({ServerTimestampBehavior serverTimestamps = .none})`; drop `getData` |
| 1.2 | `DocumentReference.snapshots` and `Query.snapshots` are getters, plus `getSnapshots([MetadataChanges])` and `getSnapshotsWithOptions(SnapshotListenOptions)` | `snapshots({bool includeMetadataChanges = false, ListenSource source = .defaultSource})` | builds a `SnapshotListenOptions` from the bool | one method `snapshots({includeMetadataChanges, source})`; drop the getter, `getSnapshots`, `getSnapshotsWithOptions` and the `MetadataChanges` enum from the public API |
| 1.3 | `Firestore.snapshotsInSync` getter | `snapshotsInSync()` method | none (trivial) | method, like FlutterFire and the JS SDK |
| 1.4 | `Firestore.persistentCacheIndexManager` getter (nullable) | `persistentCacheIndexManager()` method | none | method |
| 1.5 | Typed getters on `DocumentSnapshot`: `getString`, `getInt`, `getBool`, `getDouble`, `getDate`, `getTimestamp`, `getBlob`, `getGeoPoint`, `getDocumentReference`, `getVectorValue`, `getInt32Value`, ... (Android `getX`) | only `get(field)` and `[]` | not needed (the adapter converts the whole map) | `T? get<T>(Object field)` with `field` a `String` or `FieldPath`; move typed getters to an extension or drop them |
| 1.6 | `DocumentSnapshot.get(String field, [ServerTimestampBehavior])` and `getField(FieldPath, ...)` | `get(Object field)` (String or FieldPath) | not needed | one `get(Object field)` |
| 1.7 | `Query.whereEqualTo` / `whereEqualToField` and 18 more `where*` / `where*Field` pairs, next to the named-argument `where(...)` | only `where(Object field, {isEqualTo, ...})` and `where(Filter)` | not used; the adapter builds `Filter`s | keep `where` with named arguments and `where(Filter)`; drop the `where*` and `*Field` methods |
| 1.8 | `Filter.equalTo(String, v)` / `Filter.equalToField(FieldPath, v)` and 20 more static pairs; `Filter.and(List)`, `Filter.or(List)` | `Filter(Object field, {isEqualTo, ...})`, `Filter.and(f1, f2, [...])`, `Filter.or(...)` | maps each FlutterFire operator string (`'=='`, `'array-contains'`, ...) to the matching static; 11-way switch twice (String vs FieldPath variant avoided by always using `*Field`) | `Filter(Object field, {isEqualTo, ...})` constructor with `field` as `String`/`FieldPath`; keep `and`/`or` taking a `List` (more Dart-like than FlutterFire's 30 optional positionals) |
| 1.9 | `Query.orderBy(String, [Direction])` and `orderByField(FieldPath, [Direction])`; `Direction` enum | `orderBy(Object field, {bool descending = false})` | `descending ? Direction.descending : Direction.ascending`, always `orderByField` | `orderBy(Object field, {bool descending = false})`; drop `Direction` and `orderByField` |
| 1.10 | `FieldPath.of(List)`, `FieldPath.fromSegments(List)`, `FieldPath.fromDotSeparatedPath(String)`; `FieldPath.documentIdField` getter next to the deprecated `documentId()` method | `FieldPath(List<String>)`, `FieldPath.fromString(String)`, `FieldPath.documentId` (a `FieldPathType` sentinel) | `FieldPath.of(components)`; `FieldPathType.documentId` to `FieldPath.documentIdField` | unnamed constructor `FieldPath(List<String>)`, `FieldPath.fromString`, `static const documentId`; remove the two duplicate constructors and the method |
| 1.11 | `CollectionReference.document`, `Firestore.document`, `DocumentSnapshot.reference`, `QuerySnapshot.documents`, `documentChanges`, `Firestore.shutdown`, `Firestore.getInstance`, `Source.defaultSource` (all `@Deprecated`) | `doc`, `reference`, `docs`, `docChanges`, `terminate`, `instanceFor`, `Source.serverAndCache` | none | remove the deprecated names in the breaking release. Note that FlutterFire's snapshot getter is `reference`, ours is `ref` (the JS name); pick one |
| 1.12 | `Firestore.firebaseApp` and `Firestore.app` (both) | `app` | none | keep `app` only |
| 1.13 | `Firestore.getNamedQuery(name)`: `Future<Query?>` | `namedQueryGet(name, {GetOptions options})`: `Future<QuerySnapshot>` (and `namedQueryWithConverterGet`) | null is turned into a `not-found` error, then `get(source)` | keep the JS shape (`namedQuery` returning `Future<Query?>`) but name it `namedQuery`; the `get` prefix is the Java accessor style |
| 1.14 | `QuerySnapshot extends Iterable<QueryDocumentSnapshot>` with `length`, plus `docs` | `docs`, `size` | uses `docs` | do not extend `Iterable`; add `size` |
| 1.15 | `AggregateQuerySnapshot.getCount()`, `getInt(field)`, `getDouble(field)`, `get(field)` | `count` getter (nullable), `getSum(String)`, `getAverage(String)` | `getCount()` only when count was requested; `getDouble(AggregateField.sum(f))` | `int? get count`, `num? getSum(Object field)`, `double? getAverage(Object field)`; keep `get(AggregateField)` |
| 1.16 | `Firestore.setLoggingEnabled({bool loggingEnabled = false})` static | `static Future<void> setLoggingEnabled(bool enabled)` | adapter passes the bool by name | positional bool, or only `setLogLevel(LogLevel)` |

## 2. Writes: maps keyed by `String` only, varargs lists

| # | Ours today | FlutterFire | Adapter glue | Suggested shape |
|---|---|---|---|---|
| 2.1 | `DocumentReference.update(Map<String, Object?>)` takes dotted strings only; a field name that contains a dot needs `updateFromList([field, value, field, value, ...])` (the JS varargs form) | `update(Map<Object, Object?>)` whose keys are `String` or `FieldPath`; the platform interface hands `Map<FieldPath, dynamic>` | flattens every `Map<FieldPath, dynamic>` into the alternating list for `updateFromList` | `update(Map<Object, Object?> data)` accepting `String` and `FieldPath` keys; drop `updateFromList` |
| 2.2 | Same for `WriteBatch.update` / `updateFromList` and `Transaction.update` / `updateFromList` | `update(ref, Map<Object, Object?>)` | same flattening | same |
| 2.3 | `SetOptions.mergeAllFields` (static const), `SetOptions.overwrite`, `SetOptions.mergeFields(List<String>)`, `SetOptions.mergeFieldPaths(List<FieldPath>)` | `SetOptions({bool? merge, List<Object>? mergeFields})` with `String` or `FieldPath` entries | `merge == true` to `mergeAllFields`; `mergeFields` to `mergeFieldPaths` | `const SetOptions({bool merge = false, List<Object>? mergeFields})` |
| 2.4 | `FieldValue.increment(num l)`, `.maximum(num l)`, `.minimum(num l)`: positional parameter named `l` (Java `long`) | `increment(num value)` | none | rename the parameter to `value` |
| 2.5 | `FieldValue.vector(List<double>)` returns a `VectorValue` although it is not a sentinel | `VectorValue(List<double>)` (no factory on FieldValue) | none | keep `VectorValue(...)`; drop `FieldValue.vector` or document it as a shortcut |
| 2.6 | `FieldValue` is an abstract class with `@internal` `isX` getters and private subclasses | `FieldValue` with static factories over a platform delegate | the FlutterFire `FieldValue` objects carry our `FieldValue` as their delegate (custom `FieldValueFactoryPlatform`) | `sealed class FieldValue` with public subtypes, or keep opaque; but remove the `@internal` members from the public class |

## 3. Reads and listens: options objects

| # | Ours today | FlutterFire | Adapter glue | Suggested shape |
|---|---|---|---|---|
| 3.1 | `get([Source source])` on references and queries; the server timestamp behaviour is a parameter of every snapshot getter | `get([GetOptions(source:, serverTimestampBehavior:)])` | splits `GetOptions` into `Source` for the call and the behaviour for `getData` | `get({Source source = .serverAndCache})`, and keep the behaviour at the read site (`data(serverTimestamps:)`), or add `GetOptions` as FlutterFire does |
| 3.2 | `Source` has a deprecated `defaultSource` constant next to `serverAndCache` | `Source { serverAndCache, server, cache }` | name-for-name map | drop `defaultSource` |
| 3.3 | `QuerySnapshot.getDocumentChanges(MetadataChanges)` and `docChanges` | `docChanges` (respects the listen's metadata setting) | calls `getDocumentChanges(include)` | `docChanges` that follows the listen options; drop the method |
| 3.4 | `SnapshotOptions(serverTimestamps:)` passed to converters, `ServerTimestampBehavior` passed to getters | `SnapshotOptions` only in converters | none | one way: a named argument on `data()` |
| 3.5 | `AggregateQuery.get([AggregateSource])` | `get({AggregateSource source = .server})` | none | named argument |

## 4. Errors

| # | Ours today | FlutterFire | Adapter glue | Suggested shape |
|---|---|---|---|---|
| 4.1 | `FirestoreError extends FirebaseError` (from `firebase_app_dart`), and `FirebaseError implements Error`, not `Exception` | `FirebaseException implements Exception` with `plugin: 'cloud_firestore'`, `code: 'not-found'`, `message` | every Future and Stream of the adapter catches `FirestoreError` and rethrows `FirebaseException` with the kebab-case code | `FirestoreException implements Exception` with `String code` (`'not-found'`), `String? message`, `StackTrace? stackTrace`; an `Error` should mean a programming bug, which a `not-found` or `unavailable` is not |
| 4.2 | `FirestoreError.code` is a `FirestoreErrorCode` (a class with 17 `static const`s, a private `_names` table and `values`) | `String code` | switch over the 17 constants to kebab-case strings | enhanced `enum FirestoreErrorCode { ok, cancelled, ... }` with a `String get code` (`'not-found'`), and `FirestoreException.code` a `String` |
| 4.3 | `FirestoreErrorCode.fromValue(GrpcError)` is public (marked `@internal`) and names an internal type (`util/grpc_status.dart`) | none | not used | remove from the public class |
| 4.4 | `FirestoreError(String message, FirestoreErrorCode code, [Object? cause, StackTrace? stackTrance])`: positional, and the parameter name is misspelled (`stackTrance`) | named `FirebaseException({required plugin, code, message, stackTrace})` | none | named parameters; fix the spelling |
| 4.5 | Invalid arguments throw `ArgumentError` from `checkNotNull` / `checkArgument` (Guava style), and `StateError` for misuse | `ArgumentError`, `StateError`, `AssertionError`, `FirebaseException` | passed through unchanged | fine, but the 27 `checkNotNull` calls on non-nullable parameters in the public files are dead code under null safety (counted with grep in `lib/src/firebase/firestore/*.dart`) |

## 5. Instances, settings, apps

| # | Ours today | FlutterFire | Adapter glue | Suggested shape |
|---|---|---|---|---|
| 5.1 | `FirestoreSettings` with separate `host` and `port`, `withEmulator(host, port, {mockUserToken})`; settings are fixed when the instance is created (`instanceFor(settings:)`) | `Settings` with `host` as `'host:port'`, a settings setter that works until first use, `useFirestoreEmulator(host, port)` | parses `'host:port'`; keeps the settings and creates the instance lazily on first use | add `Firestore.useEmulator(host, port)` and a settings setter that is allowed until the first operation (both JS and FlutterFire behave so); keep `copyWith` |
| 5.2 | `FirestoreSettings.persistenceEnabled` is true by default, but persistence needs an `openDatabase` function passed to `instanceFor`; without it the cache is in memory | `persistenceEnabled` alone switches the disk cache on native | the adapter takes an `OpenDatabase` once at registration | a `LocalCacheSettings` object that carries the opener (`PersistentCacheSettings(open: ...)`) rather than a separate `instanceFor` argument |
| 5.3 | `Firestore.runTransaction(callback, {TransactionOptions options})` with `maxAttempts` in an options object; no timeout | `runTransaction(handler, {Duration timeout = 30 s, int maxAttempts = 5})` | `.timeout(...)` around the call (does not cancel the attempt) | named `timeout` and `maxAttempts` (keep `TransactionOptions` for `readOnly` / `readTime` if wanted) |
| 5.4 | `Firestore.loadBundle(List<int>)` returns a `LoadBundleTask` with `addOnProgressListener(listener)` (Android task style), `future`, `stream`, `snapshot`, `isComplete`, `isSuccessful` | `loadBundle(Uint8List)` returning a task with only a `stream`; failure is an error on the stream | maps `stream` events and replays them to late listeners; a final `error` event becomes a stream error | keep `stream` and `future`; drop `addOnProgressListener`, `isComplete`, `isSuccessful` |
| 5.5 | Auth is plugged in through `InternalTokenProvider` (`firebase_app_dart`), a public interface whose name says internal; `FirebaseApp.authProvider` setter | `FirebaseAuth` plugin, no provider interface | the adapter takes an `InternalTokenProvider` per app | rename to `TokenProvider` (or `AuthTokenProvider`) and export it as a supported extension point |
| 5.6 | `FirebaseOptions(apiKey, applicationId, gcmSenderId, databaseUrl, gaTrackingId, ...)` (Android names) | `FirebaseOptions(apiKey, appId, messagingSenderId, projectId, databaseURL, storageBucket, measurementId, ...)` | field by field copy (`appId` to `applicationId`, `messagingSenderId` to `gcmSenderId`, `databaseURL` to `databaseUrl`, `trackingId` to `gaTrackingId`) | use FlutterFire's names: `appId`, `messagingSenderId`, `databaseURL` (or `databaseUrl`), `measurementId` |
| 5.7 | `FirebaseApp.withOptions(options, {name})` factory, `FirebaseApp.getInstance(name)`, `FirebaseApp.instance` | `Firebase.initializeApp({name, options})`, `Firebase.app([name])`, `Firebase.apps` | the adapter looks up an existing app by name through `FirebaseApp.apps` (no lookup that returns null) | `FirebaseApp.initialize(...)`, `FirebaseApp.app([name])`; a non-throwing lookup |
| 5.8 | `Firestore.instanceFor({app, database})` | `instanceFor({app, databaseId})` | none | the parameter name differs (`database` vs `databaseId`) |
| 5.9 | `Firestore.instanceFor` throws `ArgumentError('FirebaseOptions.getProjectId() cannot be null')` (a Java getter name in the message) and a `StateError` when called again with other settings | not compared | passed through unchanged | message in Dart terms (`FirebaseOptions.projectId`) |

## 6. Values

| # | Ours today | FlutterFire | Adapter glue | Suggested shape |
|---|---|---|---|---|
| 6.1 | Own `Timestamp`, `GeoPoint`, `Blob`, `VectorValue`, `FieldPath` classes, with the same fields as FlutterFire's | same names in `cloud_firestore_platform_interface` | a two-way value codec in the adapter (`value_codec.dart`) | nothing to change for Dart idiom; same names mean an app that imports both packages needs a prefix |
| 6.2 | `DateTime` written as a value is accepted (`user_data_converter.dart` converts it to a `Timestamp`) | FlutterFire accepts `DateTime` and stores a `Timestamp` | the adapter converts to `Timestamp.fromDate` itself | no change |
| 6.3 | `Blob(Uint8List)` has a `subtype` and `Blob.bsonBinary` | `Blob(Uint8List bytes)` | BSON binary data loses the subtype on the way to FlutterFire | keep; FlutterFire has no BSON types |
| 6.4 | BSON types (`Int32Value`, `BsonObjectId`, `BsonTimestamp`, `Decimal128Value`, `RegexValue`, `MinKey`, `MaxKey`) | none | passed through unchanged (an app sees our classes) | no change; document |

## 7. Anything the adapter had to reach into `src/` or `internal.dart` for

| # | What | Why | Proposal |
|---|---|---|---|
| 7.1 | none from `cloud_firestore_dart` | the public API was enough | n/a |
| 7.2 | `package:firebase_app_dart/firebase_app_dart.dart` `InternalTokenProvider` | it is exported publicly despite the name; no `internal.dart` import needed | see 5.5 |

## 8. Status of `cloud_firestore/cloud_firestore_dart/docs/api_modernization_plan.md`

Its own closing table ("Status at the end of the revival") is accurate against the golden file, with one exception:
it says `instanceFor` "still returns a `Future`", but `Firestore.instanceFor` is synchronous on `main`
(`static Firestore instanceFor({...})` in `lib/src/firebase/firestore/firestore.dart`).

| Plan item | Status on `main` |
|---|---|
| 1 export `ServerTimestampBehavior`, `@internal` | done |
| 2 `GeoPoint` asserts, `@required` sweep | done |
| 3 aliases `doc`, `docs`, `docChanges`, `ref`, `terminate`, `instanceFor`, `documentIdField`, `serverAndCache` | done (deprecated old names still present) |
| 4 `FirebaseFirestore` / `Settings` typedefs | done |
| 5 `FirestoreErrorCode` enum, `FirebaseException` alignment | not done (rows 4.1 to 4.4) |
| 6 drop dead `checkNotNull` | not done (row 4.5) |
| 7 `where({named})`, `orderBy({descending})`, `update(Map<Object, Object?>)` | partly: `where` named arguments done; rows 1.9 and 2.1 open |
| 8 `snapshots` options method, `GetOptions` | partly: `getSnapshotsWithOptions` added; rows 1.2 and 3.1 open |
| 9 sealed `FieldValue` | not done (row 2.6) |
| 10 typed getters as extensions, `get<T>`, `[]` | partly: `[]` done; row 1.5 open |
| 11 `useFirestoreEmulator`, `waitForPendingWrites`, `clearPersistence` | done (`withEmulator` on settings rather than a method on the instance, row 5.1) |
| 12 `limitToLast` | done |
| 13 `!=`, `not-in`, `isNull` | done |
| 14 generics, `withConverter` | done |
| 15 aggregates | done |
| 16 `Filter.or` / `and` | done |
| 17 breaking clean-up | partly (deprecated names and `@internal` constructors remain) |
| 18 bundles | done |
| 19 golden surface tests, CI | done |
