## 0.1.0

- First version: an implementation of `FirebaseFirestorePlatform` (the platform interface of the official
  `cloud_firestore` plugin) on top of `cloud_firestore_dart`, so that an app keeps the official API.
- Registers itself on Linux; `CloudFirestoreDart.use()` selects it on any other platform.
- `DartFirebaseCore`: a small pure-Dart `firebase_core` implementation, installed on Linux, where `firebase_core` has
  none.
- Token providers for the signed-in user through `CloudFirestoreDart.use(tokenProviderFor: ...)`.
- Not implemented: Pipelines (`pipeline`, `executePipeline`) and `TransactionPlatform.commands`; both throw
  `UnimplementedError`.
