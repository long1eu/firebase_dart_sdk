## Unreleased

- Migrated to Dart 3 (`sdk: ^3.0.0`) with sound null safety.
- Breaking: `FirebaseApp.setDataCollectionDefaultEnabled` takes a required named `enabled`;
  `persistenceKey` uses URL-safe base64 without padding.
- `FirebaseApp.delete` removes the app by name; `appCheckProvider` added; tolerant `GetTokenResult`;
  `FirebaseOptions` equality and `fromJson`.
- Verified with unit tests only.
- Maintained as part of the Firestore revival; see the repository README.

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