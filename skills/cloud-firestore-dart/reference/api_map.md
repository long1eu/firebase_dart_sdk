# API map: FlutterFire and JS names to cloud_firestore_dart

For `cloud_firestore_dart` 0.1.x with `firebase_app_dart` and `firebase_auth_providers_dart`.
The source of truth for names and signatures is the golden listing of the main library:
<https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/cloud_firestore/cloud_firestore_dart/test/unit/api/public_api.golden.txt>.
FlutterFire names are those of `cloud_firestore` 7.1.0; JS names those of the modular JS SDK.

## The table

Left: what you may remember from FlutterFire `cloud_firestore` (FF) or the JS modular SDK (JS).
Right: the name in this client, or "not available".

| FlutterFire / JS | Here |
|---|---|
| `import 'package:cloud_firestore/cloud_firestore.dart'`, `firebase_core` | `package:cloud_firestore_dart/cloud_firestore_dart.dart`, `package:firebase_app_dart/firebase_app_dart.dart` |
| FF `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`; JS `initializeApp(config)` | `await Firebase.initializeApp(options: const FirebaseOptions(apiKey: ..., appId: ..., projectId: ...))`, or the synchronous `FirebaseApp.withOptions(...)` |
| FF `FirebaseFirestore.instance` (creates it); JS `getFirestore(app)` | `FirebaseFirestore.instanceFor(app: app)`. `FirebaseFirestore.instance` only returns an instance that `instanceFor` created, else throws `StateError` |
| FF `instanceFor(app: app, databaseId: 'db')`; JS `getFirestore(app, 'db')` | `FirebaseFirestore.instanceFor(app: app, databaseId: 'db')` |
| FF `firestore.settings = Settings(...)`; JS `initializeFirestore(app, {...})` | `FirebaseFirestore.instanceFor(app: app, settings: Settings(...))`; no setter |
| FF `useFirestoreEmulator('localhost', 8080)`; JS `connectFirestoreEmulator(db, host, port)` | `settings: Settings().withEmulator('127.0.0.1', 8080)` |
| FF `Settings(persistenceEnabled: true)`; JS `persistentLocalCache()`, `enableIndexedDbPersistence` | `openDatabase: sqliteOpener(directory: dir)` (`cloud_firestore_dart_sqlite`) plus `PersistentCacheSettings()`; without `openDatabase` the cache is in memory |
| JS `persistentMultipleTabManager()` | not available (one client per cache in a browser) |
| FF `Settings.CACHE_SIZE_UNLIMITED`; JS `CACHE_SIZE_UNLIMITED` | `Settings.cacheSizeUnlimited` |
| JS `doc(db, 'a/b')`, `collection(db, 'a')` | `firestore.doc('a/b')`, `firestore.collection('a')` |
| JS `getDoc`, `getDocFromCache`, `getDocFromServer` | `ref.get()`, `ref.get(const GetOptions(source: Source.cache))`, `ref.get(const GetOptions(source: Source.server))` |
| FF `get(const GetOptions(source: Source.cache))` | the same; `GetOptions` has only `source` |
| FF `set(data, SetOptions(merge: true))`; JS `setDoc(ref, data, {merge: true})` | `set(data, const SetOptions(merge: true))` |
| FF `SetOptions(mergeFields: [...])` | `SetOptions(mergeFields: ['a'])`, `SetOptions(mergeFields: [FieldPath(['a', 'b'])])` |
| FF `update({FieldPath(...): v})`; JS `updateDoc(ref, field, value, ...)` | `update(<Object, Object?>{'a.b': v, FieldPath(['c.d']): w})` (keys `String` or `FieldPath`) |
| JS `addDoc`, `deleteDoc` | `collection.add(data)`, `ref.delete()` |
| JS `deleteField()`, `serverTimestamp()`, `increment(n)`, `arrayUnion(a, b)` | `FieldValue.delete()`, `FieldValue.serverTimestamp()`, `FieldValue.increment(n)`, `FieldValue.arrayUnion([a, b])` (a list) |
| FF `snapshot.data()`; JS `snap.data()`, `snap.exists()` | `snapshot.data()` (a method), `snapshot.exists` (a getter) |
| FF `snapshot.reference` | `snapshot.reference` |
| FF `snapshot.get(FieldPath(...))` | `snapshot.get(FieldPath([...]))` |
| FF `ref.snapshots()`; JS `onSnapshot(ref, cb)` | `ref.snapshots().listen(cb)`; cancel the subscription to stop |
| FF `snapshots(includeMetadataChanges: true)` | `snapshots(includeMetadataChanges: true)` |
| FF `snapshots(source: ListenSource.cache)` | `snapshots(source: ListenSource.cache)` |
| FF `querySnapshot.size`; JS `snap.size`, `snap.empty` | `querySnapshot.size`, `isEmpty` |
| JS `snap.docChanges()` | `snap.docChanges` (a getter) |
| FF/JS `change.doc` | `change.doc` |
| JS `query(col, where('a', '==', 1), orderBy('a', 'desc'), limit(5))` | `col.where('a', isEqualTo: 1).orderBy('a', descending: true).limit(5)` |
| FF `orderBy('a', descending: true)` | `orderBy('a', descending: true)`, also with a `FieldPath` |
| FF `Filter('a', isEqualTo: 1)`; JS `where('a', '==', 1)` inside `or(...)` | `Filter('a', isEqualTo: 1)` |
| FF `Filter.or(f1, f2)`; JS `or(f1, f2)` | `Filter.or([f1, f2])`, `Filter.and([...])` (a list) |
| FF `FieldPath(['a', 'b'])`, `FieldPath.documentId`; JS `documentId()` | `FieldPath(['a', 'b'])`, `FieldPath.documentId` |
| FF `count().get()` then `.count`; JS `getCountFromServer(q)` then `.data().count` | `q.count().get()` then `.count` |
| FF `aggregate(sum('a'), average('a'))`; JS `getAggregateFromServer(q, {...})` | `q.aggregate([AggregateField.sum('a'), AggregateField.average('a')])` then `getSum('a')`, `getAverage('a')`, `get(field)`; named: `aggregateWithAliases({...})` then `data()` |
| FF `get(source: AggregateSource.server)` | the same |
| FF `runTransaction(fn, timeout: ..., maxAttempts: 5)`; JS `runTransaction(db, fn)` | `firestore.runTransaction(fn, maxAttempts: 5)`; no timeout |
| JS `writeBatch(db)` | `firestore.batch()` (writes chain), or `firestore.runBatch((batch) async {...})` |
| FF `Timestamp.millisecondsSinceEpoch`, `fromMillisecondsSinceEpoch` | the same |
| JS `Bytes` | `Blob` |
| FF `withConverter(fromFirestore: ..., toFirestore: ...)`; JS `withConverter(converter)` | `withConverter<T>(fromFirestore: ..., toFirestore: ...)`; `withoutConverter()` |
| FF `FirebaseException` with `e.code == 'permission-denied'`; JS `FirestoreError.code` string | `FirestoreException` (a `FirebaseException`) with `e.code == 'permission-denied'`, or `e.errorCode == FirestoreErrorCode.permissionDenied` |
| FF `snapshotsInSync()`; JS `onSnapshotsInSync` | `firestore.snapshotsInSync()` (a stream) |
| FF `namedQueryGet(name)`; JS `namedQuery(db, name)` | `firestore.namedQueryGet(name)`, or `firestore.namedQuery(name)` for the `Query` |
| FF `loadBundle(Uint8List)` | `loadBundle(List<int>)`, `loadBundleStream(stream)` |
| FF `persistentCacheIndexManager()` | `persistentCacheIndexManager` (a getter, null with a memory cache) |
| FF `FirebaseFirestore.setLoggingEnabled(true)`; JS `setLogLevel('debug')` | `FirebaseFirestore.setLogLevel(LogLevel.debug)` |
| JS `clearIndexedDbPersistence(db)`, `terminate(db)` | `firestore.terminate()`, then `firestore.clearPersistence()` |
| FF `FirebaseAuth.instance.signInWithEmailAndPassword(email: ..., password: ...)` | `final auth = await FirebaseUserAuth.forApp(app);` then `auth.signInWithEmailAndPassword(email, password)` (positional) |
| FF `FirebaseAuth.instance.currentUser?.uid`, `authStateChanges()` | `auth.uid`, `auth.currentUser`, `auth.userChanges()` |
| Google, Apple or other federated sign-in, phone, email link, multi-factor, `signInWithPopup` | not available |
| FF `webExperimentalForceLongPolling` | `Settings(webExperimentalForceLongPolling: true)` |
| FF `ignoreUndefinedProperties`, JS `Temporal` conversion | not available (not applicable to Dart) |
| Storage, Messaging, Realtime Database, Analytics, Remote Config | not available in these packages |

Names that are the same here: `collection`, `doc`, `collectionGroup`, `add`, `delete`,
`where(field, isEqualTo: ..., isGreaterThan: ..., arrayContains: ..., whereIn: ...)`, `limit`,
`limitToLast`, `startAt` / `startAfter` / `endAt` / `endBefore` (a `List`) and their
`...Document` forms, `docs`, `metadata.isFromCache`, `metadata.hasPendingWrites`, `GeoPoint`,
`Timestamp(seconds, nanoseconds)`, `Timestamp.now()`, `toDate()`, `VectorValue`,
`enableNetwork`, `disableNetwork`, `waitForPendingWrites`, `terminate`, `clearPersistence`.
`FirebaseFirestore` and `Settings` exist only as typedefs of `Firestore` and
`Settings`; write the real names.

## Only here

Not in FlutterFire's API reference (and, for most, not in the JS client SDK):

- `snapshot.data(serverTimestamps: ServerTimestampBehavior.estimate)` and
  `get(field, serverTimestamps: ...)` for server timestamps that are not set yet.
- `Query.findNearest(vectorField: ..., queryVector: ..., limit: ..., distanceMeasure: DistanceMeasure.cosine)` (vector search, server only).
- `runTransaction(..., readOnly: true, readTime: ...)` with `transaction.getQuery(query)` and
  `transaction.getAggregate(aggregateQuery)`.
- `toJson()` / `fromJson(...)` on snapshots and references, and
  `firestore.querySnapshotsFromJson(json)` to resume a listener.
- BSON value types of Enterprise edition databases: `MinKey`, `MaxKey`, `Int32Value`,
  `Decimal128Value`, `BsonObjectId`, `BsonTimestamp`, `RegexValue`, `Blob.bsonBinary`.
- `withEmulator(host, port, mockUserToken: {'sub': 'alice'})`.
