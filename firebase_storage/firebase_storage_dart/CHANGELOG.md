## 0.1.0 (unreleased)

- First version: `FirebaseStorage` (bucket from the app's options or `gs://`, emulator host, retry policy),
  `Reference` (path operations, `metadata`, `updateMetadata`, `downloadUrl`, `delete`, `list`, `listAll`,
  `listPages`, `getBytes`, `putBytes`, `putString` with `StringFormat.raw`, `base64`, `base64Url` and
  `dataUrl`), `FullMetadata`, `SettableMetadata`, `ListResult` and `FirebaseStorageException`. Requests carry
  the Firebase Auth token of `app.authProvider` (refreshed once after a 401) and the App Check token of
  `app.appCheckProvider`, and are retried with the backoff of the JS SDK.
