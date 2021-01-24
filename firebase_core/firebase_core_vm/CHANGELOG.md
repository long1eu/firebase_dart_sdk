## 0.0.9

- add heart beat support

## 0.0.8

- add firebase_platform_dependencies in the example app
- make FirebaseError extend Error

## 0.0.7

- refactor to use the new platform interface
- add linux example app
- require a Hive Box for persistent storage
- add linux connectivity implementation
- make authProvider null by default so FirebaseAuth can register itself
- add generated firebase options for the example app

## 0.0.6

- remove SharedPreferences from the example and require a Hive Box for persistent storage

## 0.0.5

- Move default implementation for PlatformDependency
- Drop the _dataCollectionDefaultEnabled and read directly from store
- Add missing field to FirebaseOptions

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