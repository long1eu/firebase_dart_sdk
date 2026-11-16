import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// Creates the instance with the persistent cache of [openDatabase], or with a
/// memory cache when that cache can't be used here because another client
/// has it (in a browser: another tab).
///
/// `Firestore.instanceFor` returns at once and opens the cache in the
/// background, so the error of a cache that can't be opened comes from the
/// first operation, not from `instanceFor`. This waits for a first operation
/// that only reads the cache (looking up a named query that does not exist),
/// and on `failedPrecondition` terminates that instance (which frees the app
/// for a new one) and creates one with a memory cache. Every other error is
/// rethrown.
///
/// ```dart
/// final Firestore firestore = await openWithMemoryFallback(
///   app: app,
///   openDatabase: sqliteOpener(),
/// );
/// // Null with the memory cache.
/// print(firestore.persistentCacheIndexManager != null);
/// ```
Future<Firestore> openWithMemoryFallback({
  required FirebaseApp app,
  required OpenDatabase openDatabase,
  FirestoreSettings? settings,
}) async {
  final Firestore persistent = Firestore.instanceFor(
    app: app,
    openDatabase: openDatabase,
    settings: settings,
  );
  try {
    await persistent.getNamedQuery('openWithMemoryFallback');
    return persistent;
  } on FirestoreError catch (e) {
    if (e.code != FirestoreErrorCode.failedPrecondition) {
      rethrow;
    }
    await persistent.terminate();
    return Firestore.instanceFor(
      app: app,
      settings: (settings ?? FirestoreSettings()).copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
  }
}
