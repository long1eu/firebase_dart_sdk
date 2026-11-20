/// The checks of the contract of a `CacheStore` (see `package:cloud_firestore_dart/cache_store.dart`),
/// for the tests of a store. They need no test framework: each check throws when the store breaks the contract.
///
/// ```dart
/// import 'package:cloud_firestore_dart/cache_store_testing.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
///     test(check.name, () => check.run(() => MyStore(newEmptyFile())));
///   }
/// }
/// ```
library;

export 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_checks.dart'
    show CacheStoreCheck, cacheStoreConformanceChecks;
