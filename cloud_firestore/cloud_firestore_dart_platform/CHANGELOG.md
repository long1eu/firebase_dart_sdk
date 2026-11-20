## 0.1.1

- The constraint on `cloud_firestore_dart` is `>=0.2.0 <0.4.0` instead of `^0.2.0`, so that the package can be used with
  `cloud_firestore_dart` 0.3.0. No code change.
- README: records the first Windows run (Windows 11 x64, Flutter 3.47.8, against the emulator):
  `CloudFirestoreDart.use()` replaced the native Firestore of `cloud_firestore` in
  `examples/flutterfire_on_windows`, whose integration tests passed, sum and average aggregations included. No
  code change.
- README: the package was tried in a Flutter Linux desktop app (`examples/flutterfire_on_linux`, Debian 13 x86_64,
  Flutter 3.44.9): automatic registration, `Firebase.initializeApp`, listeners, writes, batch, transaction, query and
  the disk cache, against the emulator.

## 0.1.0

- First version, built against the 0.2 API of `cloud_firestore_dart`: an implementation of `FirebaseFirestorePlatform` (the platform interface of the official
  `cloud_firestore` plugin) on top of `cloud_firestore_dart`, so that an app keeps the official API.
- Registers itself on Linux; `CloudFirestoreDart.use()` selects it on any other platform.
- `DartFirebaseCore`: a small pure-Dart `firebase_core` implementation, installed on Linux, where `firebase_core` has
  none.
- Token providers for the signed-in user through `CloudFirestoreDart.use(tokenProviderFor: ...)`, for example
  `FlutterFireAuthTokenProvider` of `cloud_firestore_dart_flutterfire` or `FirebaseUserAuth` of
  `firebase_auth_providers_dart`.
- Not implemented: Pipelines (`pipeline`, `executePipeline`) and `TransactionPlatform.commands`; both throw
  `UnimplementedError`.
