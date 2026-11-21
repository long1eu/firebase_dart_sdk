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
