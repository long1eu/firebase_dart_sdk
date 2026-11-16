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
