## 0.1.0

- First version: an implementation of `FirebaseRemoteConfigPlatform` (the platform interface of the official
  `firebase_remote_config` plugin) on top of `firebase_remote_config_dart` and `firebase_installations_dart`, so that
  an app keeps the official API.
- Registers itself on Linux; `FirebaseRemoteConfigDart.use()` selects it on any other platform. Under `flutter test`
  the registration leaves `firebase_core` alone.
- A small pure-Dart `firebase_core` implementation, installed on Linux only while `firebase_core` has no other one.
- One Installations and one Remote Config client per app, sharing one store per isolate by default (a file store
  under the application support directory on the VM, IndexedDB on the web); `use(store:)` replaces it.
- Every error that leaves the adapter is a `FirebaseException` of the plugin `firebase_remote_config` with an
  interface code; anything unclassified is `internal`. `onConfigUpdated` reports errors through its stream. An app
  re-created under the same name with other options is not supported on the native and web cores until restart.
- `use(httpClient:)` serves both Installations and Remote Config.
- `fetch`, `activate`, `fetchAndActivate`, `ensureInitialized`, the getters, `getAll`, `setConfigSettings`,
  `setDefaults`, `setCustomSignals`, `lastFetchTime`, `lastFetchStatus` and `onConfigUpdated` (realtime, on every
  platform).
