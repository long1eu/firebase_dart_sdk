# Migrating from 0.1 to 0.2

Version 0.2 of `firebase_app_dart`, `firebase_auth_providers_dart` and `cloud_firestore_dart` changes the public API
so that it reads like Dart and like FlutterFire (`firebase_core`, `firebase_auth`, `cloud_firestore`), instead of
like the Android SDK the packages were ported from. The implementation underneath did not change: the same requests
go to the backend, and the cache, the listeners and the transactions behave as in 0.1. The few behaviour changes
are listed in [Behaviour changes](#behaviour-changes).

If you come from FlutterFire, most of your code compiles after you change the imports and create the app and the
Firestore instance as shown below. [Differences from FlutterFire](#differences-from-flutterfire) lists what still
differs.

```dart
// FlutterFire
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

// These packages
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
```

The 0.1 names were removed, not deprecated: the packages are at 0.x and a few days old. Two names are kept as
deprecated type aliases because almost every 0.1 program uses them: `Firestore` (now `FirebaseFirestore`) and
`FirestoreSettings` (now `Settings`). They will be removed in a later release.

Each table has four columns: the 0.1 API, the 0.2 API, the FlutterFire equivalent ("none" when FlutterFire has
nothing like it), and why it changed. Rows are grouped into renames, shape changes (same feature, other signature),
removals and additions.

## `cloud_firestore_dart`

The main library (`package:cloud_firestore_dart/cloud_firestore_dart.dart`) and Firestore Lite
(`package:cloud_firestore_dart/lite.dart`) changed the same way: every row applies to both unless it says otherwise.
The Pipelines preview (`package:cloud_firestore_dart/pipelines.dart`) did not change, apart from the types it
names (`FirebaseFirestore`).

### Renames

| 0.1 | 0.2 | FlutterFire | Why |
| --- | --- | --- | --- |
| `Firestore` (class) | `FirebaseFirestore` | `FirebaseFirestore` | The name of the class in FlutterFire and Android. `Firestore` stays as a deprecated alias. |
| `FirestoreSettings` | `Settings` | `Settings` | FlutterFire name. `FirestoreSettings` stays as a deprecated alias. |
| `Firestore.instanceFor(database: ...)` | `FirebaseFirestore.instanceFor(databaseId: ...)` | `instanceFor(databaseId: ...)` | FlutterFire parameter name. |
| `Firestore.getNamedQuery(name)` | `FirebaseFirestore.namedQuery(name)` | none (`namedQueryGet`, see additions) | No `get` prefix on a Dart method that is not a getter; the JS SDK name. |
| `Firestore.setIndexConfiguration(json)` (deprecated) | `FirebaseFirestore.setIndexConfigurationFromJSON(json)` (still deprecated) | `setIndexConfigurationFromJSON(json)` | FlutterFire name. Use `persistentCacheIndexManager` instead. |
| `TransactionCallback<T>` | `TransactionHandler<T>` | `TransactionHandler<T>` | FlutterFire name. |
| `FirestoreError` | `FirestoreException` | `FirebaseException` | It reports a failed operation, which is an `Exception` in Dart, not an `Error` (a bug in the program). See shape changes for its members. |
| `DocumentSnapshot.ref` | `DocumentSnapshot.reference` | `reference` | FlutterFire name. |
| `DocumentChange.document` | `DocumentChange.doc` | `doc` | FlutterFire name. |
| `FieldPath.of(names)` | `FieldPath(names)` | `FieldPath(components)` | Unnamed constructor, as in FlutterFire. |
| `FieldPath.fromDotSeparatedPath(path)` | `FieldPath.fromString(path)` | `FieldPath.fromString(path)` | FlutterFire name. |
| `FieldPath.documentIdField` | `FieldPath.documentId` | `FieldPath.documentId` | FlutterFire name; it is a getter now (the deprecated method of the same name is gone). |
| `Timestamp.fromMillis(ms)` | `Timestamp.fromMillisecondsSinceEpoch(ms)` | same | Names of `DateTime` and FlutterFire. |
| `Timestamp.toMillis()` | `Timestamp.millisecondsSinceEpoch` (getter) | same | Same. |
| `LoadBundleTaskProgress` | `LoadBundleTaskSnapshot` | `LoadBundleTaskSnapshot` | FlutterFire name. |
| `ExperimentalLongPollingOptions` | `WebExperimentalLongPollingOptions` | same | FlutterFire name; the option only affects the web transport. |
| `Settings.experimentalForceLongPolling`, `experimentalAutoDetectLongPolling`, `experimentalLongPollingOptions` | `webExperimentalForceLongPolling`, `webExperimentalAutoDetectLongPolling`, `webExperimentalLongPollingOptions` | same | FlutterFire names; web transport only. |
| `FieldValue.increment(num l)`, `maximum(num l)`, `minimum(num l)` | parameter `value` | `value` | The parameter was named after Java's `long`. Calls do not change. |

### Shape changes

| 0.1 | 0.2 | FlutterFire | Why |
| --- | --- | --- | --- |
| `Firestore.instance` throws until `instanceFor` ran | `FirebaseFirestore.instance` returns the instance of the default app, and creates it (default settings, no disk cache) if needed | same | FlutterFire behaviour: `FirebaseFirestore.instance` works once the default app exists. |
| `DocumentSnapshot.data` (getter), `getData(ServerTimestampBehavior)` | `data({ServerTimestampBehavior serverTimestamps = ServerTimestampBehavior.none})` | `data()` | One method, as in FlutterFire; the behaviour is a named argument. `QueryDocumentSnapshot.data()` is non-nullable. |
| `DocumentSnapshot.get(String field, [ServerTimestampBehavior])`, `getField(FieldPath, [ServerTimestampBehavior])`, `operator [](String)` | `get(Object field, {ServerTimestampBehavior serverTimestamps = ServerTimestampBehavior.none})`, `operator [](Object field)`: `field` is a `String` or a `FieldPath` | `get(Object field)`, `[](Object field)` | Dart has no overloads; one method takes both kinds of path, as in FlutterFire. Returns `Object?`. |
| `DocumentSnapshot.contains(String)`, `containsPath(FieldPath)` | `contains(Object field)` | none | Same reason. |
| `DocumentReference.get([Source])`, `Query.get([Source])` | `get([GetOptions? options])`, `GetOptions({Source source = Source.serverAndCache})` | `get([GetOptions? options])` | FlutterFire shape. `GetOptions` has no `serverTimestampBehavior`: pass it to `data()` / `get()`. |
| `DocumentReference.snapshots` and `Query.snapshots` (getters), `getSnapshots([MetadataChanges])`, `getSnapshotsWithOptions(SnapshotListenOptions)` | `snapshots({bool includeMetadataChanges = false, ListenSource source = ListenSource.defaultSource})` | same | One method with named arguments instead of a getter and two Java-style variants. `ref.snapshots.listen(...)` becomes `ref.snapshots().listen(...)`. |
| `FirebaseFirestore.snapshotsInSync` (getter) | `snapshotsInSync()` | `snapshotsInSync()` | FlutterFire and JS shape; every call is a new stream. |
| `documentSnapshotsFromJson(json, {SnapshotListenOptions options, converter})`, `querySnapshotsFromJson(...)` | `{bool includeMetadataChanges = false, ListenSource source = ListenSource.defaultSource, converter}` | none | Same named arguments as `snapshots()`. |
| `QuerySnapshot.docChanges` (always without metadata-only changes), `getDocumentChanges(MetadataChanges)` | `docChanges` follows the listen: with `includeMetadataChanges: true` it also lists the documents whose metadata changed | `docChanges` | FlutterFire behaviour; the Java-style method is gone. |
| `Query.orderBy(String, [Direction])`, `orderByField(FieldPath, [Direction])` | `orderBy(Object field, {bool descending = false})` | same | FlutterFire shape; `field` is a `String` or a `FieldPath`. |
| `Query.startAt(List<Object?>)`, `startAfter`, `endAt`, `endBefore` | take an `Iterable<Object?>` | same | FlutterFire type; every `List` still works. |
| `Query.withConverter(FirestoreDataConverter<R>)`, same on `CollectionReference` and `DocumentReference` | `withConverter<R>({required FromFirestore<R> fromFirestore, required ToFirestore<R> toFirestore})` | same | FlutterFire shape. `FirestoreDataConverter` stays for `fromJson` and the `converter` property. |
| `Query.findNearest(String field, Object vector, int limit, DistanceMeasure m, {...})`, `findNearestField(FieldPath, ...)` | `findNearest({required Object vectorField, required Object queryVector, required int limit, required DistanceMeasure distanceMeasure, String? distanceResultField, double? distanceThreshold})` | none | Named arguments (the JS SDK passes an options object); `vectorField` is a `String` or a `FieldPath`. |
| `VectorQuery` (not generic), `VectorQuery.get()` ignored the converter, `VectorQuery.vectorField` was an internal path type | `VectorQuery<T>`, `get()` returns `VectorQuerySnapshot<T>` read through the converter of the query, `vectorField` is a `FieldPath` | none | Bug fix: the converter of the query was dropped. |
| `DocumentReference.update(Map<String, Object?>)`, `updateFromList(List)`; the same on `WriteBatch` and `Transaction` | `update(Map<Object, Object?> data)`: each key is a `String` (dot-separated) or a `FieldPath` | `update(Map<Object, Object?>)` | FlutterFire shape. A field whose name contains a dot is written with a `FieldPath` key instead of the alternating list. |
| `DocumentReference.parent` was `CollectionReference<Map<String, Object?>>` | `CollectionReference<T>` (keeps the converter) | `CollectionReference<T>` | FlutterFire type. |
| `SetOptions.overwrite`, `SetOptions.mergeAllFields`, `SetOptions.mergeFields(List<String>)`, `SetOptions.mergeFieldPaths(List<FieldPath>)` | `SetOptions({bool merge = false, List<Object>? mergeFields})`, `mergeFields` entries are `String` or `FieldPath` | `SetOptions({bool? merge, List<Object>? mergeFields})` | FlutterFire shape: one constructor with named arguments. Omit the options to overwrite. |
| `runTransaction(fn, {TransactionOptions options})` | `runTransaction(fn, {int maxAttempts = 5, bool readOnly = false, Timestamp? readTime})` | `runTransaction(fn, {Duration timeout, int maxAttempts = 5})` | Named arguments instead of an options object. FlutterFire's `timeout` is not supported. |
| `Filter.equalTo(field, v)`, `Filter.equalToField(path, v)` and 20 more static pairs | `Filter(Object field, {isEqualTo, isNotEqualTo, isLessThan, isLessThanOrEqualTo, isGreaterThan, isGreaterThanOrEqualTo, arrayContains, arrayContainsAny, whereIn, whereNotIn, isNull})` | same | FlutterFire shape; the same arguments as `Query.where`. `Filter.and(List<Filter>)` and `Filter.or(List<Filter>)` are unchanged. |
| `AggregateField.sum(String)`, `sumField(FieldPath)`, `average(String)`, `averageField(FieldPath)` | `AggregateField.sum(Object field)`, `AggregateField.average(Object field)` | `sum(field)`, `average(field)` | One method per aggregation; `field` is a `String` or a `FieldPath`. |
| `AggregateQuery.get([AggregateSource])` | `get({AggregateSource source = AggregateSource.server})` | same | FlutterFire shape. |
| `AggregateQuerySnapshot.getCount()`, `getInt(field)`, `getDouble(field)` | `int? get count`, `num? getSum(Object field)`, `double? getAverage(Object field)`; `get(AggregateField)` and `data()` are unchanged | `count`, `getSum`, `getAverage` | FlutterFire names. `count` is null when the query did not ask for it. `getSum` returns an `int` for a sum of integers (FlutterFire always returns a `double`). |
| `FirestoreError(String message, FirestoreErrorCode code, [Object? cause, StackTrace? stackTrance])`, `code` a `FirestoreErrorCode`; `toString()` was `FirestoreError: [code=notFound]: ...` | `FirestoreException({required FirestoreErrorCode errorCode, required String message, Object? cause, StackTrace? stackTrace})`; it extends `FirebaseException`: `code` is the FlutterFire string (`'not-found'`), `plugin` is `'cloud_firestore'`, `errorCode` is the enum; `toString()` is `[cloud_firestore/not-found] ...` | `FirebaseException` with `code: 'not-found'` | FlutterFire convention, so `on FirebaseException catch (e) { if (e.code == 'not-found') ... }` works. **Watch out:** `e.code == FirestoreErrorCode.notFound` still compiles but is always false: compare `e.errorCode` instead. |
| `FirestoreErrorCode` (a class with constants) | an `enum` with the same values, plus `code` (`'not-found'`) and `value` (the gRPC number) | none | A plain Dart enum: `switch` is exhaustive. |
| `LoadBundleTask`: `addOnProgressListener(listener)`, `isComplete`, `isSuccessful`, `exception`, `snapshot`, `future`, `stream` | `stream`, `future` and `snapshot` (`snapshot.taskState`, `snapshot.exception`) | `stream` | A `Stream` instead of a listener registration and Android task getters. |
| `Firestore.setLoggingEnabled({bool loggingEnabled = false})` | `FirebaseFirestore.setLoggingEnabled(bool enabled)` | `setLoggingEnabled(bool enabled)` | FlutterFire shape. |
| `ExperimentalLongPollingOptions({num timeoutSeconds})` | `WebExperimentalLongPollingOptions({Duration? timeoutDuration})` | same | A `Duration` instead of a number of seconds. |
| `FirebaseFirestore.app` was nullable | `FirebaseApp get app` | `FirebaseApp app` | Every instance a program can get has an app. |

### Removals

| 0.1 | Use instead | FlutterFire | Why |
| --- | --- | --- | --- |
| `Firestore.getInstance(app, ...)` (deprecated) | `FirebaseFirestore.instanceFor(app: app, ...)` | `instanceFor` | Java name. |
| `Firestore.document(path)`, `CollectionReference.document([path])` (deprecated) | `doc(path)` | `doc` | Duplicates. |
| `Firestore.shutdown()` (deprecated) | `terminate()` | `terminate` | Duplicate. |
| `Firestore.firebaseApp` | `app` | `app` | Duplicate. |
| `FirebaseFirestore` typedef of 0.1 | the class itself | | It is the class now. |
| `Settings` typedef of 0.1 | the class itself | | It is the class now. |
| `DocumentSnapshot.reference` of 0.1 (deprecated alias of `ref`) | `reference` (the new name, see renames) | | |
| `DocumentSnapshot.getString`, `getInt`, `getBool`, `getDouble`, `getDate`, `getTimestamp`, `getBlob`, `getGeoPoint`, `getDocumentReference`, `getVectorValue`, `getInt32Value`, `getDecimal128Value`, `getBsonObjectId`, `getBsonTimestamp`, `getRegexValue`, `getMinKey`, `getMaxKey` | `get(field) as String?` and so on; `(get(field) as num?)?.toInt()` for `getInt`, `(get(field) as num?)?.toDouble()` for `getDouble`, `(get(field) as Timestamp?)?.toDate()` for `getDate` | `get(field)` | Android typed getters; a cast says the same in Dart. A wrong type now throws a `TypeError` instead of a `StateError`. |
| `QuerySnapshot.documents`, `documentChanges` (deprecated) | `docs`, `docChanges` | same | Duplicates. |
| `QuerySnapshot.getDocumentChanges(MetadataChanges)` | `docChanges` (see shape changes) | `docChanges` | Java shape. |
| `Query.whereEqualTo`, `whereNotEqualTo`, `whereLessThan`, `whereLessThanOrEqualTo`, `whereGreaterThan`, `whereGreaterThanOrEqualTo`, `whereArrayContains`, `whereArrayContainsAny`, `whereIn`, `whereNotIn` and their `...Field(FieldPath, ...)` twins (20 methods) | `where(field, isEqualTo: v)` and the other named arguments | `where` | Java overloads; `where` takes a `String` or a `FieldPath`. A null named argument counts as not given, as in FlutterFire: `whereEqualTo(f, null)` is `where(f, isNull: true)`, `whereNotEqualTo(f, null)` is `where(f, isNull: false)`, and a comparison of another kind with null (`whereArrayContains(f, null)`) has no equivalent. |
| `Query.orderByField` | `orderBy(fieldPath)` | `orderBy` | Java overload. |
| `Direction` | `orderBy(field, descending: true)` | none | Only used by the old `orderBy`. |
| `Query.findNearestField` | `findNearest(vectorField: fieldPath, ...)` | none | Java overload. |
| `MetadataChanges`, `SnapshotListenOptions` | `snapshots(includeMetadataChanges: true, source: ...)` | none | Only used by the removed methods. |
| `Source.defaultSource` (deprecated) | `Source.serverAndCache` | same | Duplicate. |
| `FieldPath.fromSegments(segments)` | `FieldPath(segments)` | `FieldPath(components)` | Duplicate of the constructor (without its checks). |
| `FieldPath.documentId()` (deprecated method) | `FieldPath.documentId` (getter) | same | |
| `FieldValue.vector(values)` | `VectorValue(values)` | `VectorValue(values)` | Not a field value sentinel; one way to make a vector. |
| `AggregateQuerySnapshot.getCount()`, `getInt`, `getDouble` | `count`, `getSum`, `getAverage`, `get` | | See shape changes. |
| `OnProgressListener` | `LoadBundleTask.stream` | | Listener typedef. |
| `LoadBundleTaskProgress(...)` constructor and `LoadBundleTaskProgress.initial` | none | none | Only the SDK creates progress values. |
| `FirestoreErrorCode.fromValue(GrpcError)` | none | none | Internal; it named an internal type. |
| `LogLevel.info` | `LogLevel.warn` | none | It behaved exactly like `warn`: the SDK writes no message at that level. |
| `TransactionOptions` (also in Firestore Lite) | the named arguments of `runTransaction` | none | Options object. |

### Additions

| 0.2 | FlutterFire | Why |
| --- | --- | --- |
| `GetOptions({Source source})` | `GetOptions` | Argument of `get`. |
| `FromFirestore<T>`, `ToFirestore<T>` typedefs | same | Arguments of `withConverter`. |
| `FirebaseFirestore.settings` (getter and setter) | `settings` | Read the settings of an instance; set them before its first use. After the first use the setter throws a `FirestoreException` with `failed-precondition`. |
| `FirebaseFirestore.useFirestoreEmulator(host, port, {sslEnabled = false})` | same | Before the first use only, like the setter. |
| `runTransaction(..., {Duration timeout = 30 s})` | `timeout` | Fails with `deadline-exceeded` after the timeout and starts no new attempt. The attempt in flight is not cancelled: if it was committing, its writes may still take effect. |
| `FirebaseFirestore.namedQueryGet(name, {GetOptions? options})` | `namedQueryGet` | Runs a named query of a loaded bundle; throws a `FirestoreException` with `not-found` when there is no such query. |
| `QuerySnapshot.size` | `size` | FlutterFire name for the number of documents (`length` stays: `QuerySnapshot` is an `Iterable`). |
| `FieldPath.components` | `components` | The field names of the path. |
| `Timestamp.fromMicrosecondsSinceEpoch(us)`, `Timestamp.microsecondsSinceEpoch` | same | Names of `DateTime`. |
| `FirestoreErrorCode.code` | none | The FlutterFire string of each code. |

## `firebase_app_dart`

### Renames

| 0.1 | 0.2 | FlutterFire | Why |
| --- | --- | --- | --- |
| `FirebaseOptions.applicationId` | `appId` | `appId` | FlutterFire name. |
| `FirebaseOptions.gcmSenderId` | `messagingSenderId` | `messagingSenderId` | FlutterFire name. |
| `FirebaseOptions.databaseUrl` | `databaseURL` | `databaseURL` | FlutterFire name. |
| `FirebaseOptions.gaTrackingId` | `trackingId` | `trackingId` | FlutterFire name. |
| `FirebaseError` | `FirebaseException` | `FirebaseException` | An `Exception`, not an `Error`; the FlutterFire class. |
| `FirebaseNoSignedInUserError` | `FirebaseNoSignedInUserException` | none | Same reason. |
| `FirebaseApiNotAvailableError` | `FirebaseApiNotAvailableException` | none | Same reason. |
| `FirebaseApp.dataCollectionDefaultEnabled` | `isAutomaticDataCollectionEnabled` | same | FlutterFire name. |
| `FirebaseApp.defaultAppName` | `defaultFirebaseAppName` (top-level constant) | same | FlutterFire name. |
| `InternalTokenProvider` | `AuthTokenProvider` | none | It is the supported way to plug in authentication, not an internal type. |
| `InternalTokenResult` | `AuthTokenChange` | none | Same reason; it is the event of `AuthTokenProvider.onTokenChanged`. |
| `InternalAppCheckTokenProvider` | `AppCheckTokenProvider` | none | Same reason. |

### Shape changes

| 0.1 | 0.2 | FlutterFire | Why |
| --- | --- | --- | --- |
| `FirebaseError(String message, [StackTrace? stackTrace])` implements `Error` | `FirebaseException({required String plugin, String? message, String? code, StackTrace? stackTrace})` implements `Exception`; `code` defaults to `'unknown'` | same | FlutterFire class. |
| `FirebaseApp.setDataCollectionDefaultEnabled({required bool enabled})` | `Future<void> setAutomaticDataCollectionEnabled(bool enabled)` | same | FlutterFire shape. |
| `FirebaseApp.setAutomaticResourceManagementEnabled({required bool enabled})` | `Future<void> setAutomaticResourceManagementEnabled(bool enabled)` | same | FlutterFire shape. |
| `void FirebaseApp.delete()` | `Future<void> delete()` | same | FlutterFire shape. |
| `FirebaseOptions.fromJson` / `toJson` dropped `dataCollectionEnabled` | both keep it (key `data_collection_enabled`) | none | Bug fix: a round trip lost the value. |

### Removals

| 0.1 | Use instead | FlutterFire | Why |
| --- | --- | --- | --- |
| `FirebaseApp.getInstance(name)` | `Firebase.app(name)` | `Firebase.app(name)` | Java name. |
| `FirebaseApp.apps` | `Firebase.apps` | `Firebase.apps` | Moved to `Firebase`. |
| `FirebaseNetworkError`, `FirebaseTooManyRequestsError`, `FirebaseApiError` (the Android auth error numbers) | `FirebaseException` and the codes of the packages | none | Nothing threw or read them. |

### Additions

| 0.2 | FlutterFire | Why |
| --- | --- | --- |
| `Firebase.initializeApp({String? name, FirebaseOptions? options, PlatformDependencies? dependencies})` | `Firebase.initializeApp({name, options})` | The FlutterFire entry point. It returns the existing app when one with the same name and options exists; `options` is required for a new app. `FirebaseApp.withOptions` stays as the synchronous way. |
| `Firebase.app([String name])`, `Firebase.apps` | same | FlutterFire lookups. |
| `FirebaseOptions.authDomain`, `measurementId`, `deepLinkURLScheme`, `androidClientId`, `iosClientId`, `iosBundleId`, `appGroupId` | same | So that an options file generated by the FlutterFire CLI compiles. These packages do not read them. |
| `FirebaseOptions.copyWith(...)` | `copyWith` | FlutterFire method. |

## `firebase_auth_providers_dart`

This package is not a port of `firebase_auth`: it is a token provider for Firestore. Where it has the same
operation as FlutterFire's `FirebaseAuth`, it now takes the same arguments.

### Renames

| 0.1 | 0.2 | FlutterFire | Why |
| --- | --- | --- | --- |
| `FirebaseAuthProviderException` | `FirebaseAuthException`, which extends `FirebaseException` (`plugin: 'firebase_auth'`) | `FirebaseAuthException` | FlutterFire name; the codes were already FlutterFire's. |

### Shape changes

| 0.1 | 0.2 | FlutterFire | Why |
| --- | --- | --- | --- |
| `FirebaseAuthProviderException(String code, String message, {serverCode, httpStatus})` | `FirebaseAuthException({required String code, String? message, String? serverCode, int? httpStatus})` | `FirebaseAuthException({required code, message, ...})` | FlutterFire shape. |
| `signInWithEmailAndPassword(email, password)` | `signInWithEmailAndPassword({required String email, required String password})` | same | FlutterFire shape. Returns an `AuthUser` (FlutterFire returns a `UserCredential`). |
| `createUserWithEmailAndPassword(email, password)` | `createUserWithEmailAndPassword({required String email, required String password})` | same | Same. |
| `reauthenticateWithEmailAndPassword(email, password)` | `reauthenticateWithEmailAndPassword({required String email, required String password})` | `reauthenticateWithCredential(...)` | Same shape as the sign-in methods. |
| `sendPasswordResetEmail(email, [ActionCodeSettings?])` | `sendPasswordResetEmail({required String email, ActionCodeSettings? actionCodeSettings})` | same | FlutterFire shape. |
| `confirmPasswordReset(code, newPassword)` | `confirmPasswordReset({required String code, required String newPassword})` | same | FlutterFire shape. |
| `userChanges` (getter) | `userChanges()` | `userChanges()` | FlutterFire shape. |
| `AuthTokenProvider` (was `InternalTokenProvider`) | | | See `firebase_app_dart`. |

## Behaviour changes

- An instance starts (opens its cache, connects) at its first use, not when `instanceFor` returns, so the
  `settings` setter and `useFirestoreEmulator` can still change it. `instanceFor(settings: ...)` still starts it
  right away. A cache that cannot be opened now fails the first operation rather than `instanceFor`.
- A new instance of an app name and database waits until a terminated instance of the same app name and database
  has closed its cache, also when that instance was terminated by `await app.delete()` before the new one was
  asked for.
- `FirebaseFirestore.instance` creates the instance of the default app when there is none, instead of throwing.
- `QuerySnapshot.docChanges` includes metadata-only changes when the listen asked for them
  (`snapshots(includeMetadataChanges: true)`); in 0.1 it never did.
- `VectorQuery.get()` reads the documents through the converter of its query.
- `FirebaseOptions.toJson` writes `dataCollectionEnabled`, and `fromJson` reads it.
- Errors of failed operations are `FirestoreException`, `FirebaseAuthException` and `FirebaseException`, which
  implement `Exception`: `on Exception catch` now catches them, `on Error catch` no longer does.
- `DocumentSnapshot.get(field) as T` throws a `TypeError` where the removed typed getters threw a `StateError`.
- `where(field, isEqualTo: null)` throws an `ArgumentError` (no non-null argument), where `whereEqualTo(field, null)`
  compared with null: use `isNull: true`.
- `Firebase.app(name)` throws a `FirebaseException` with the code `no-app`, where `FirebaseApp.getInstance` threw a
  `StateError`.
- The texts of some errors and of `toString()` changed with the names: `FirestoreException`, `Settings`,
  `WebExperimentalLongPollingOptions`, `LoadBundleTaskSnapshot`, `FirebaseOptions`, and the messages that named
  `Firestore.instanceFor`, `FieldPath.of`, `SetOptions.merge()`, `Source.SERVER` or `updateFromList`.

## Differences from FlutterFire

Places where these packages keep a shape of their own, on purpose:

- `FirebaseFirestore.instanceFor` also takes the `settings` (and an `openDatabase` function for the disk cache);
  with settings it starts the instance at once, so the setter and `useFirestoreEmulator` then throw.
- `Settings.host` does not include the port: the port is `Settings.port`. `Settings` is not `const`: it validates its
  values when it is made.
- `useFirestoreEmulator('localhost', ...)` does not become `10.0.2.2` on the Android emulator; pass that host
  yourself.
- Snapshot data is `Map<String, Object?>` and `get` returns `Object?`, where FlutterFire uses `dynamic`: cast the
  value (`snap.get('name') as String`).
- `GetOptions` has no `serverTimestampBehavior`; pass `serverTimestamps:` to `data()` or `get()`.
- `Query.aggregate` and `Filter.and` / `Filter.or` take a `List`, not up to 30 positional arguments, and the
  aggregate fields are `AggregateField.count()`, `AggregateField.sum(field)` and `AggregateField.average(field)`.
- The `runTransaction` timeout cannot cancel an attempt that is committing: its writes may still take
  effect after the returned future failed.
- A filter that compares a field with null other than `==` and `!=` (`arrayContains: null`) cannot be written: a null
  named argument counts as not given, as in FlutterFire.
- `persistentCacheIndexManager` is a getter, not a method.
- `QuerySnapshot` is an `Iterable` of its documents (`for (final doc in snapshot)`).
- `LoadBundleTask` reports a failure as a last event with `taskState == LoadBundleTaskState.error` and an
  `exception`, and has a `future`.
- `firebase_auth_providers_dart` returns an `AuthUser` from the sign-in methods, not a `UserCredential`, and has no
  `authStateChanges()` or `idTokenChanges()`.
- Pipelines follow the JS SDK, not FlutterFire's preview (for example `PipelineResult.ref`, `PipelineSnapshot.results`).

## Not supported

FlutterFire settings with no equivalent here:

- `Settings.ignoreUndefinedProperties`: Dart has no `undefined`; a `null` value is written as null.
- `Settings.cacheSizeBytes` as `Settings.CACHE_SIZE_UNLIMITED`: the Dart-style name is `Settings.cacheSizeUnlimited`
  (the same value, `-1`).
- `Settings.webPersistentTabManager` (multi-tab persistence on the web).
- `FirebaseFirestore.enablePersistence` (the web call of FlutterFire): set `persistenceEnabled` or `cacheSettings`.
