## 0.1.0

First release under the new name. This package was published as `firebase_core_vm` (last
version 0.0.4); it is the same code base, revived as part of the Firestore port. Verified with
its unit tests and through `cloud_firestore_dart`'s emulator suite; nothing was run against
production Firebase.

### Renamed package

- `firebase_core_vm` is now `firebase_app_dart`: import
  `package:firebase_app_dart/firebase_app_dart.dart` instead of
  `package:firebase_core_vm/firebase_core_vm.dart`. Class names (`FirebaseApp`,
  `FirebaseOptions`, `PlatformDependencies`, ...) are unchanged.
- `_firebase_internal_vm` is folded into this package. Its utilities are reachable through
  `package:firebase_app_dart/internal.dart`, which exists for `cloud_firestore_dart` and is
  **not public API**.
- Migration guide:
  [docs/migrating_from_vm_packages.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/migrating_from_vm_packages.md).

### Breaking changes

- Dart 3 (`sdk: ^3.0.0`) with sound null safety. `FirebaseOptions.projectId`, `databaseUrl`,
  `storageBucket`, `gcmSenderId` and `gaTrackingId` are nullable; `apiKey` and `applicationId`
  are required.
- `FirebaseApp.setDataCollectionDefaultEnabled` takes a required named `enabled`.
- `FirebaseApp.persistenceKey` uses URL-safe base64 without padding; keys computed by older
  versions differ.
- The Flutter example app is replaced by a command-line `example/main.dart`.
- `GetTokenResult.toString()` and `InternalTokenResult.toString()` no longer contain the token
  (or, for `GetTokenResult`, the claims); they print `<redacted>`.
- `FirebaseApp.withOptions` throws an `ArgumentError` for options with an empty application id
  in every build; the check was an `assert` of the `const` `FirebaseOptions` constructor only.

### Added

- `PlatformDependencies.appCheckProvider` (`InternalAppCheckTokenProvider`,
  `AppCheckTokenResult`), used by `cloud_firestore_dart` to send the App Check header.
- `FirebaseOptions` equality and `FirebaseOptions.fromJson`.
- Experimental web support: `FirebaseApp.withOptions` no longer throws `UnimplementedError` on
  the web, so that `cloud_firestore_dart` can run there. Only creating an app and using it with
  Firestore was tried in a browser (Chrome).
- Every exported class and member has a doc comment; `dart doc` runs without warnings.

### Fixed

- `FirebaseApp.delete` removes the app by name.
- `GetTokenResult` tolerates tokens with missing claims.

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