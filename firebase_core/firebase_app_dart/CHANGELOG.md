## 0.2.4

- Doc comments of `isAutomaticDataCollectionEnabled` name its reader.

## 0.2.3

- Documentation: point S8 of the provider contract: a `getToken(forceRefresh: true)` that cannot run answers with
  the cached token when it is still valid, with no error; callers never throttle forced refreshes themselves. S2
  gains one exception: a refresh that fails while the cached token has not expired yet answers with that token and
  the error, as the JS SDK does.
- `LimitedUseAppCheckTokenProvider`: a second interface, with `getLimitedUseToken()`, for a provider that can mint
  a token for one request to a backend that consumes App Check tokens. `AppCheckTokenProvider` itself is
  unchanged, so every existing provider compiles as before. A provider that does not implement it gives no App
  Check token on a limited-use request; nothing falls back to `getToken`.
- `AppCheckTokenProvider.responseDeadline` (8 s): how long a provider may take to answer. A closed provider answers
  with an empty token.
- `AppCheckTokenResult.failure(error)` and `AppCheckTokenResult.placeholderToken`: the result of a failed request
  carries the placeholder token of the JS and iOS SDKs (the base64 form of `{"error":"UNKNOWN_ERROR"}`). Services
  send it, so that the backend can tell a failed attestation from an app without App Check.
- Documentation: the contract of a provider. A result without an error carries a token with at least 5 minutes of
  life left (half of the lifetime for a token that lives under 10 minutes); a failure is reported with
  `AppCheckTokenResult.failure` and not thrown; `onTokenChanged` is a broadcast stream of successes without
  replay.
- `AppCheckTokenResult.toString()` shows neither the token nor the text of the error:
  `AppCheckTokenResult(token: <redacted>)`, with `error: <runtime type>` when there is an error.
- Documentation: the `authProvider` and `appCheckProvider` rows of the `PlatformDependencies` table name every
  package that reads the provider. Firestore, `FirebaseUserAuth` and the Realtime Database read the App Check
  provider once, when they are created; the other services read it at each request.

## 0.2.2

- Documentation: an `AuthTokenChange` is a signal. An empty token means signed out; a token that is not empty may
  be a placeholder, so callers take the token from `AuthTokenProvider.getAccessToken`. No change in behaviour.

## 0.2.1

- `GetTokenResult.signInSecondFactor`: the second factor of the sign-in (`firebase.sign_in_second_factor`), or null.

## 0.2.0

Breaking: the API takes the names and shapes of FlutterFire's `firebase_core`. Every change is in
[docs/api_migration_0_2.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/api_migration_0_2.md).

- `Firebase.initializeApp`, `Firebase.app` and `Firebase.apps`; `FirebaseApp.getInstance` and
  `FirebaseApp.apps` are removed. `defaultFirebaseAppName`.
- `FirebaseOptions` uses FlutterFire's field names (`appId`, `messagingSenderId`, `databaseURL`,
  `trackingId`) and accepts its other fields, so a generated options file compiles; `copyWith`.
- `FirebaseException` (plugin, code, message) implements `Exception` and replaces
  `FirebaseError`; the unused Android error classes are removed.
- `delete`, `setAutomaticDataCollectionEnabled` and `setAutomaticResourceManagementEnabled`
  return futures and take the value positionally; `isAutomaticDataCollectionEnabled`.
- The token provider interfaces are `AuthTokenProvider`, `AuthTokenChange` and
  `AppCheckTokenProvider`.
- Fix: `FirebaseOptions.toJson` and `fromJson` keep `dataCollectionEnabled`.

## 0.1.1

Documentation and examples only. No code change.

- Doc comments with compiling samples across the public API.
- A rewritten README, and one example per task in `example/`: default and named apps, options
  from JSON, platform dependencies and app deletion.

## 0.1.0

First release under the new name. This package continues `firebase_core_vm` 0.0.4 (March 2020),
the version `cloud_firestore_vm` 0.0.7 depends on; it is the same code base, revived as part of
the Firestore port. `firebase_core_vm` 0.0.5 to 0.0.8 on pub.dev (August and September 2020) were
published from another branch, and this package does not continue from them. Verified with
its unit tests and through `cloud_firestore_dart`'s emulator suite; against production Firebase
it was only used by the verification kit of `cloud_firestore_dart`, on one Firestore database.

### Renamed package

- **License:** Apache-2.0 (see `LICENSE` and `NOTICE`). `firebase_core_vm` was licensed under
  BSD-3-Clause.
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

- Dart 3.8 (`sdk: ^3.8.0`, the floor of `cloud_firestore_dart` and the lowest SDK the CI runs)
  with sound null safety. `FirebaseOptions.projectId`, `databaseUrl`,
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