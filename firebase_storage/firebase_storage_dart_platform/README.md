# firebase_storage_dart_platform

An unofficial implementation of the platform interface of the official
[`firebase_storage`](https://pub.dev/packages/firebase_storage) Flutter plugin, on top of
[`firebase_storage_dart`](https://pub.dev/packages/firebase_storage_dart), a pure-Dart client of the Cloud Storage
for Firebase REST API. Your app keeps the official API (`FirebaseStorage.instance.ref('a.png').putData(...)`,
`getDownloadURL()`, `listAll()`, ...), and the Dart client does the work underneath, without the native Firebase
SDKs.

You need it for a Flutter app on Linux desktop, where `firebase_storage` and `firebase_core` have no implementation
of their own: add it to `pubspec.yaml` and it registers itself. On other platforms it is an opt-in. It is not
affiliated with or endorsed by Google or Firebase.

> **Status: 0.1.2.** Unit-tested with `flutter test` through the classes of `firebase_storage` 14.1.0
> (`firebase_storage_platform_interface` 6.1.0), against a fake backend. The client underneath is tested against the
> Storage emulator in its own package. This package has not yet run in a Linux desktop build, against the emulator,
> or against a production project.

## How to enable it

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_storage: ^14.1.0
  firebase_storage_dart_platform: ^0.1.0
```

**On Linux** nothing else is needed for open rules or the emulator: Flutter calls `FirebaseStorageDart.registerWith()`
before `main()`. Pass the options to `Firebase.initializeApp` (there is no native configuration file to read them
from), with a `storageBucket`:

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
await FirebaseStorage.instance.ref('notes/today.txt').putString('Hello');
```

**On any other platform**, call `FirebaseStorageDart.use()` at the start of `main()`, before the first use of
`Firebase` or `FirebaseStorage`. There `firebase_core` keeps its native implementation, and the native Storage SDK
is still built into the app, unused.

### The signed-in user

Requests carry the user that `tokenProviderFor` returns, as with the Firestore platform package of this repository.
With `firebase_auth_dart_platform`:

```dart
FirebaseStorageDart.use(
  tokenProviderFor: (FirebaseApp app) => FirebaseAuthDart.userAuthFor(app),
);
```

With the official `firebase_auth` (its native implementation), through `cloud_firestore_dart_flutterfire`:

```dart
FirebaseStorageDart.use(
  tokenProviderFor: (FirebaseApp app) =>
      FlutterFireAuthTokenProvider(FirebaseAuth.instanceFor(app: app)),
);
```

Without it, requests carry no user, which is enough for the emulator and for open rules. When the Firestore platform
package already set up the app (it keeps a `firebase_app_dart` app per FlutterFire app), Storage uses that app and its
token provider, and `tokenProviderFor` is not called.

### App Check

With the official [`firebase_app_check`](https://pub.dev/packages/firebase_app_check), requests carry its token in
the `X-Firebase-AppCheck` header once you pass `appCheckProviderFor`. The provider is the `FlutterFireAppCheckProvider`
of [`cloud_firestore_dart_flutterfire`](https://pub.dev/packages/cloud_firestore_dart_flutterfire), the same one the
Firestore bridge takes; neither package depends on `firebase_app_check`, so an app without App Check does not get
the plugin and its native SDKs.

```dart
FirebaseStorageDart.use(
  appCheckProviderFor: (FirebaseApp app) {
    final FirebaseAppCheck appCheck = FirebaseAppCheck.instanceFor(app: app);
    return FlutterFireAppCheckProvider(
      getToken: appCheck.getToken,
      onTokenChange: appCheck.onTokenChange,
    );
  },
);
```

Activate App Check (`FirebaseAppCheck.instance.activate(...)`) as usual. Without `appCheckProviderFor`, or when it
returns null, requests have no App Check header. A token that cannot be had (App Check throws or returns none) fails
nothing: the request goes without the header and the backend decides, as with the App Check SDKs. A
`firebase_app_dart` app set up by the Firestore platform package keeps its token provider and gets this App Check
provider when it has none.

### Options of `use`

| Argument | Default | What it does |
| --- | --- | --- |
| `tokenProviderFor` | none: no user | Returns the token provider of a FlutterFire app; called once per app. |
| `appCheckProviderFor` | none: no App Check header | Returns the App Check token provider of a FlutterFire app (above); called once per app. |
| `httpClient` | one for all instances | The `http.Client` of the requests (tests, proxies). |
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs a small pure-Dart `firebase_core`. Pass `true` to force it (tests), `false` to never do it. |

`use()` throws a `StateError` once an instance has sent a request, because the configuration is read then.

### `firebase_core` on Linux

`firebase_core` has no Linux implementation either. This package installs a small one (apps in memory,
`initializeApp` needs `options`) only while `firebase_core` still has its default implementation. The Firestore and
Auth platform packages of this repository do the same with their own, so they can be in one app: whichever registers
first provides `firebase_core`, and the others keep it. Under `flutter test`, the registration on Linux leaves
`firebase_core` alone, so that `setupFirebaseCoreMocks` keeps working; call `use()` to choose otherwise.

## What is implemented

| Official API | Underneath | Notes |
| --- | --- | --- |
| `FirebaseStorage.instanceFor(app:, bucket:)` | one `firebase_storage_dart` client per app and bucket | `gs://` is accepted |
| `setMaxOperationRetryTime`, `setMaxUploadRetryTime`, `setMaxDownloadRetryTime` and their getters | the client's `StorageRetryPolicy` | defaults 2, 10 and 10 minutes |
| `useStorageEmulator` | the client's `emulatorHost` | see below |
| `ref`, `refFromURL`, `child`, `parent`, `root` | | paths as FlutterFire keeps them (the root is `/`) |
| `getMetadata`, `updateMetadata` | `metadata`, `updateMetadata` | a null field is left as it is |
| `getDownloadURL`, `delete` | `downloadUrl`, `delete` | |
| `list`, `listAll` | `list`, `listAll` | |
| `getData(maxSize)` | `getBytes(maxSize:)` | `download-size-exceeded` above `maxSize` |
| `putData`, `putString` | resumable `startUpload` | `putString` decodes the string first (`invalid-format` when it does not match) |
| `putFile` | resumable upload streamed from the disk | without a content type, it comes from the file's extension, as on Android and iOS |
| `writeToFile` | `openRead` into a temporary file next to the target, renamed over it at the end | progress, pause, resume and cancel; `totalBytes` from the object's metadata, read first |
| `Task`: `snapshotEvents`, `snapshot`, awaiting it, `pause`, `resume`, `cancel` | the client's `UploadTask` (`progress`, `result`) | `cancel` works from `paused` too |

Errors are `FirebaseException`s of `firebase_core` with the plugin `firebase_storage` and the client's code, which is
the JS SDK's without its `storage/` prefix (`object-not-found`, `unauthorized`, `unauthenticated`, `canceled`,
`retry-limit-exceeded`, `quota-exceeded`, ...), the codes the official plugin reports.

`FirebaseStorageDart.clientFor(app, bucket: ...)` returns the client behind an instance, for what the official API
does not have: `openRead` (a streamed, ranged download), `listPages`, and the `httpStatus` and `serverResponse` of
its `FirebaseStorageException`s.

### Not supported

- **`putBlob`** throws an `UnimplementedError`, as on Android and iOS: a `Blob` exists only on the web. Use `putData`.

## How it differs from the official plugin

- **`useStorageEmulator`** may be called at any time, not only before the first operation; the operations started
  before keep their target. `firebase_storage` itself skips the call on Windows (it prints "The Storage Emulator is not
  available on Windows" and never reaches this package); there, set `FIREBASE_STORAGE_EMULATOR_HOST=host:port` in the
  environment, which every instance reads when it is created.
- **`setMax*RetryTime`** applies to the operations started afterwards.
- **Error details**: the official exception has no HTTP status or response body; `clientFor` gives the client's
  exceptions, which have both.
- **App Check** is opt-in: pass `appCheckProviderFor` (see "App Check" above). The official plugin picks up
  `firebase_app_check` by itself.
- **`updateMetadata`** cannot remove a field: a null field means "leave it", and the official API has no other way to
  say "remove it". `clientFor(app).ref(path).updateMetadata` with `SettableMetadata.delete` can.
- **Tasks** are not resumed after the app restarts, as on the web.

## Platforms

| Platform | Selected by | Notes |
| --- | --- | --- |
| Linux | automatic (`dartPluginClass`) | `firebase_core` is installed too, unless another package did it first |
| Windows, macOS, Android, iOS | `FirebaseStorageDart.use()` | `firebase_core` stays native |
| Web | not supported | use the official plugin |
