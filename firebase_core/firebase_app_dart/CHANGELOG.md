## 0.1.0

First release under the new name. This package was published as `firebase_core_vm` (last
version 0.0.4); it is the same code base, revived as part of the Firestore port. Class names
(`FirebaseApp`, `FirebaseOptions`, `PlatformDependencies`, ...) are unchanged; import
`package:firebase_app_dart/firebase_app_dart.dart` instead of
`package:firebase_core_vm/firebase_core_vm.dart`.

- `_firebase_internal_vm` is folded into this package. Its utilities are reachable through
  `package:firebase_app_dart/internal.dart`, which exists for `cloud_firestore_dart` and is
  **not public API**.
- `FirebaseApp.withOptions` no longer throws `UnimplementedError` on the web, so that
  `cloud_firestore_dart` can run there. Only creating an app and using it with Firestore was
  tried in a browser (Chrome).
- Migrated to Dart 3 (`sdk: ^3.0.0`) with sound null safety.
- Breaking: `FirebaseApp.setDataCollectionDefaultEnabled` takes a required named `enabled`;
  `persistenceKey` uses URL-safe base64 without padding.
- `FirebaseApp.delete` removes the app by name; `appCheckProvider` added; tolerant `GetTokenResult`;
  `FirebaseOptions` equality and `fromJson`.
- The Flutter example app is replaced by a command-line `example/main.dart`.
- Every exported class and member has a doc comment; `dart doc` runs without warnings.
- Migration guide:
  [docs/migrating_from_vm_packages.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md).
- Verified with unit tests, and through `cloud_firestore_dart`'s emulator suite.

## Versions published as `firebase_core_vm`

## 0.0.4

- Expose `isWeb`, `isMobile` and `isDesktop` based on conditional imports
- Throw unimplemented error when trying to create a FirebaseApp in a js/html context

## 0.0.3

- Rename library from `firebase_common` to `firebase_core`

## 0.0.2

- Add flutter example
- Update README

## 0.0.1

- Initial release