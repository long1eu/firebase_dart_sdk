# cloud_firestore_dart_platform

An unofficial implementation of the platform interface of the official
[`cloud_firestore`](https://pub.dev/packages/cloud_firestore) Flutter plugin, on top of the pure-Dart client
[`cloud_firestore_dart`](https://pub.dev/packages/cloud_firestore_dart). Your app keeps the official API
(`FirebaseFirestore.instance.collection(...)`, `withConverter`, `snapshots()`, `runTransaction`, ...), and
`cloud_firestore_dart` does the work underneath, in Dart, without the native Firebase SDKs.

It is not affiliated with or endorsed by Google or Firebase.

> **Status: 0.1.0, not published.** Tested with `flutter test` against the Firestore emulator through the
> classes of `cloud_firestore` 7.1.0. It has not run inside a Flutter app on a device or a desktop yet.

## When to use it

- **Linux desktop.** Neither `cloud_firestore` nor `firebase_core` has a Linux implementation. With this package
  they work there: it registers itself on Linux, and also installs a small Dart implementation of `firebase_core`.
- **One implementation everywhere.** On Android, iOS, macOS, Windows and the web you can choose to run Firestore
  through `cloud_firestore_dart` instead of the native SDK, for example to get the same behaviour on every
  platform, or where the official plugin is incomplete (Windows).

## How to enable it

Add it next to the official packages:

```yaml
dependencies:
  cloud_firestore: ^7.1.0
  firebase_core: ^5.1.0
  cloud_firestore_dart_platform: ^0.1.0
```

**On Linux** nothing else is needed: Flutter calls `CloudFirestoreDart.registerWith()` before `main()`. Pass the
options to `Firebase.initializeApp` (there is no native configuration file to read them from):

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
await FirebaseFirestore.instance.doc('cities/SF').set({'name': 'San Francisco'});
```

**On any other platform**, call `CloudFirestoreDart.use()` at the start of `main()`, before the first use of
`Firebase` or `FirebaseFirestore`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CloudFirestoreDart.use();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
```

`use()` replaces `FirebaseFirestorePlatform.instance` and `FieldValueFactoryPlatform.instance`. It runs after the
plugin registrant, so it wins over the official implementation. On Android, iOS, macOS and Windows,
`firebase_core` keeps its native implementation (it provides the `FirebaseApp` and its options), and the native
Firestore SDK of `cloud_firestore` is still built into the app, unused.

### Options of `use`

| Argument | Default | What it does |
| --- | --- | --- |
| `openDatabase` | none: cache in memory | Opens the SQLite database of the offline cache (`Firestore.instanceFor(openDatabase:)` of `cloud_firestore_dart`; see its guides for an opener built on `sqlite3`). `Settings(persistenceEnabled: false)` turns it off for an instance. |
| `tokenProviderFor` | none: requests without a user | Returns the token provider (`InternalTokenProvider` of `firebase_app_dart`) for the requests of a FlutterFire app. |
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs `DartFirebaseCore`. Pass `true` to force it (tests), `false` to never do it. |

`use()` throws a `StateError` once a Firestore instance has started, because the configuration is read when an
instance starts. Calling it again before that replaces the configuration (for example after the automatic
registration on Linux).

### Signed-in users

The package does not depend on `firebase_auth`. It asks `tokenProviderFor` once per app, when the app's first
Firestore instance starts:

- With the official `firebase_auth` (Android, iOS, macOS, Windows, web): return a provider that reads the user and
  the ID token from `FirebaseAuth`, such as `FlutterFireAuthTokenProvider` of the companion bridge package
  (`cloud_firestore_dart_flutterfire`, in this repository, not released yet).
- On Linux, where `firebase_auth` has no implementation: return a `FirebaseUserAuth` of
  [`firebase_auth_providers_dart`](https://pub.dev/packages/firebase_auth_providers_dart).
- If a `firebase_app_dart` app with the same name as the FlutterFire app already exists (because another package
  set it up), it is used as it is, with its own token providers, and `tokenProviderFor` is not called.

Without a provider, requests carry no user: enough for the emulator and for open rules.

```dart
CloudFirestoreDart.use(
  tokenProviderFor: (FirebaseApp app) => myTokenProviderFor(app),
);
```

## How to enforce it in a project

Selection happens at run time, so the reliable way to enforce this implementation is the explicit call:

1. Call `CloudFirestoreDart.use()` first thing in `main()` (and in the setup of integration tests).
2. Check it where it matters, for example `assert(CloudFirestoreDart.isRegistered);` after `Firebase.initializeApp`.

How the plugin tooling resolves implementations, and what `dependency_overrides` can and cannot do:

- Flutter picks one implementation of `cloud_firestore` per platform. On Linux this package is the only one, so it
  is used even as a transitive dependency. If `cloud_firestore` ever gains an endorsed Linux implementation, a
  **direct** dependency on this package still wins over that default (the Flutter tool prefers a direct dependency
  that `implements` the plugin); two direct dependencies that both implement it are a build error, and the fix is
  to remove one.
- `dependency_overrides` cannot remove a plugin or change which one registers. Use it only to force a version, for
  example when a newer `cloud_firestore` needs a `cloud_firestore_platform_interface` outside this package's range
  (`^8.1.0`). Such an override builds, but the interface may have changed under this package: run your tests.
- This package does not register itself on Windows, macOS, Android, iOS or the web, because that would change the
  behaviour of every app that only adds it. There, the explicit `use()` call is what selects it.

## Support matrix

What `cloud_firestore` can ask of a platform implementation, and what this one does. "Tested" means covered by
`test/` through `cloud_firestore`'s own classes against the emulator (or without it, for the unit tests).

| Area | Status |
| --- | --- |
| Documents: `get` (with `Source`), `set` (with `merge` and `mergeFields`), `update` (dotted strings and `FieldPath`s with dots), `delete`, `add` | implemented, tested |
| Typed converters (`withConverter`) | implemented, tested |
| Queries: `==`, `!=`, `<`, `<=`, `>`, `>=`, `array-contains`, `array-contains-any`, `in`, `not-in`, `isNull`, `FieldPath.documentId`, `Filter.or` / `Filter.and` | implemented, tested |
| `orderBy` (with `descending`), `limit`, `limitToLast`, `startAt`, `startAfter`, `endAt`, `endBefore`, `startAfterDocument`, `endAtDocument`, `collectionGroup` | implemented, tested |
| `startAtDocument`, `endBeforeDocument` | implemented, untested (same code path as the tested ones) |
| Aggregations: `count()`, `aggregate(count(), sum(), average())` | implemented, tested |
| Listeners: document and query `snapshots(includeMetadataChanges:)`, `docChanges` with `oldIndex` / `newIndex`, `ListenSource.cache` | implemented, tested |
| Snapshot metadata (`hasPendingWrites`, `isFromCache`) | implemented, tested |
| `GetOptions.serverTimestampBehavior` (`none`, `estimate`, `previous`) | implemented, tested |
| Write batches | implemented, tested |
| Transactions: `get`, `set`, `update`, `delete`, an error in the handler | implemented, tested |
| Transaction `timeout` and `maxAttempts` | implemented, untested (see the differences) |
| Field values: `serverTimestamp`, `increment`, `arrayUnion`, `arrayRemove`, `delete`, `minimum`, `maximum` | implemented, tested |
| Values: null, bool, int (64 bit), double, String, `Timestamp`, `DateTime` (stored as a `Timestamp`), `GeoPoint`, `Blob`, `DocumentReference`, `VectorValue`, nested maps and lists | implemented, tested (round trip) |
| Errors: `FirebaseException` with `plugin: 'cloud_firestore'` and the official `code` strings (`not-found`, `failed-precondition`, ...) | implemented, tested for `not-found` and `failed-precondition`; all 17 codes unit-tested |
| `enableNetwork`, `disableNetwork`, `waitForPendingWrites`, `snapshotsInSync` | implemented, tested |
| `terminate`, `clearPersistence` (refused while running, allowed after `terminate`) | implemented, tested |
| `settings`, `useFirestoreEmulator` | implemented, tested (host, port, SSL); `cacheSizeBytes` passed on, untested |
| `loadBundle`, `namedQueryGet` | implemented, tested |
| `persistentCacheIndexManager()`, `setIndexConfigurationFromJSON` | implemented, untested (they need a disk cache) |
| Disk cache through `openDatabase` | implemented, untested in this package (tested in `cloud_firestore_dart`) |
| Several databases (`instanceFor(databaseId:)`), several apps | implemented, untested (the emulator has one database) |
| `FirebaseFirestore.setLoggingEnabled` | implemented (switches `cloud_firestore_dart` logging), untested |
| Signed-in user through `tokenProviderFor` | implemented, tested that the provider is asked for a token; the emulator runs open rules, so the backend's view of the user is not checked |
| `firebase_core` on Linux (`DartFirebaseCore`): `initializeApp`, `app`, `apps`, `delete` | implemented, unit-tested |
| Pipelines (`FirebaseFirestore.pipeline()`) | **not implemented**: throws `UnimplementedError`. Use `package:cloud_firestore_dart/pipelines.dart` directly |
| `TransactionPlatform.commands` | **not implemented** (`UnimplementedError`); `cloud_firestore` does not read it |

## How it differs from the official plugin

- **Offline cache.** The native SDKs keep a disk cache by default. Here the cache is in memory unless you pass
  `openDatabase` to `use()`.
- **Settings after start.** Changing `settings` (or calling `useFirestoreEmulator`) after the first operation throws
  a `failed-precondition` `FirebaseException` at once. After `terminate()` they may change again.
- **Transaction timeout.** When `timeout` passes, the future fails with `deadline-exceeded`, but the attempt that is
  running is not cancelled and may still commit.
- **Error messages.** The `code` strings are the official ones; the `message` texts are those of
  `cloud_firestore_dart`. Two codes are this package's own: `no-options` (`Firebase.initializeApp` without options
  under `DartFirebaseCore`) and `load-bundle-error` (a bundle that fails with an error that is not a Firestore
  error).
- **BSON types** of Enterprise databases (`Int32Value`, `BsonObjectId`, ...) have no FlutterFire equivalent. They
  are returned as the `cloud_firestore_dart` classes and can be written the same way.
- **`firebase_core` on Linux** keeps its apps in memory, needs `options`, and does not know the other FlutterFire
  plugins; `firebase_auth`, `firebase_storage` and the rest still have no Linux implementation.
- **Windows**: `cloud_firestore` itself throws `UnimplementedError` for `snapshots(source: ListenSource.cache)` and
  `persistentCacheIndexManager()` on Windows, whichever implementation is selected, because it checks the platform
  before it calls the implementation.

## Platforms

| Platform | Selected by | Notes |
| --- | --- | --- |
| Linux | automatic (`dartPluginClass`) | `DartFirebaseCore` is installed too; registration checked with `flutter pub get` in a throwaway app only |
| Windows, macOS, Android, iOS | `CloudFirestoreDart.use()` | `firebase_core` stays native; not run on these platforms yet |
| Web | `CloudFirestoreDart.use()` | `cloud_firestore_dart` on the web is experimental; not run through this package |

## Running the tests

From the repository root, with a private emulator:

```sh
./tool/start_private_emulator.sh 8090
cd cloud_firestore/cloud_firestore_dart_platform
FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 flutter test
cd ../.. && ./tool/stop_private_emulator.sh 8090
```

Without `FIRESTORE_EMULATOR_HOST` only the unit tests run; the emulator tests are skipped.

## License

Apache License 2.0; see `LICENSE` and `NOTICE`.
