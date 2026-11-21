## 0.1.2

- `FirebaseStorageDart.use` takes `appCheckProviderFor`: the App Check token of each FlutterFire app goes in the
  `X-Firebase-AppCheck` header. With `firebase_app_check`, return a `FlutterFireAppCheckProvider` of
  `cloud_firestore_dart_flutterfire` built on `FirebaseAppCheck.instanceFor(app: app)`. Without it, or when App
  Check has no token, requests go without the header and nothing fails. A `firebase_app_dart` app that already
  exists without an App Check provider gets this one.

## 0.1.1

- `FirebaseStorageDart.use` takes `maxConcurrentUploads` and `maxUploadChunkSize`, passed to each
  `firebase_storage_dart` client (0.1.1): uploads are queued per app and bucket, and on the VM an upload of bytes
  or a file goes as one streamed request unless chunks are set.

## 0.1.0

- First version: an implementation of `FirebaseStoragePlatform` (the platform interface of the official
  `firebase_storage` plugin) on top of `firebase_storage_dart`, so that an app keeps the official API.
- Registers itself on Linux; `FirebaseStorageDart.use()` selects it on any other platform. Under `flutter test` the
  registration leaves `firebase_core` alone.
- A small pure-Dart `firebase_core` implementation, installed on Linux only while `firebase_core` has no other one.
- Instances per app and bucket, the three retry times, `useStorageEmulator` (and `FIREBASE_STORAGE_EMULATOR_HOST`),
  references, metadata, download URLs, delete, list, `getData`, and tasks for `putData`, `putString`, `putFile` and
  `writeToFile` with progress, pause, resume and cancel.
- `tokenProviderFor` gives the requests a user; `FirebaseStorageDart.clientFor(app)` returns the client behind an
  instance.
- Not supported: `putBlob` (web only).
