import 'dart:typed_data';

/// **Experimental.** An ordered key-value store that holds the persistent cache of a Firestore instance, for an app
/// that brings its own storage (see `keyValueCacheSettings` of `package:cloud_firestore_dart/cache_store.dart`).
///
/// The store only keeps bytes: keys and values are byte arrays, and keys are ordered by their unsigned bytes, the
/// first differing byte deciding, and a key that is a prefix of another before it (the order of `memcmp`, of LevelDB,
/// of a SQLite `BLOB` primary key and of IndexedDB array buffers). The SDK lays its documents, pending writes, targets
/// and the rest out in that order, in a format of its own that it versions itself; the store never needs to look
/// inside a key or a value.
///
/// All reads and writes happen in a [transaction]. The contract, which `cacheStoreConformanceChecks` of
/// `package:cloud_firestore_dart/cache_store_testing.dart` checks:
///
/// * **Atomic.** The writes of a transaction whose body completes are all kept, durably once the future of
///   [transaction] completes. The writes of a transaction whose body throws are all dropped, and [transaction] throws
///   that error. A crash in between keeps all or none of them.
/// * **Read your writes.** Inside a transaction, [CacheStoreTransaction.get] and [CacheStoreTransaction.scan] see the
///   writes the transaction made before.
/// * **Isolated.** Two transactions that run at the same time behave as if one ran after the other: neither sees half
///   of the other's writes. The simplest way is to run one transaction at a time (a lock); the SDK itself never
///   starts a transaction on a store before its previous one finished.
/// * **Ordered.** [CacheStoreTransaction.scan] returns the entries of a range in key order, or in reverse order.
///
/// The store belongs to one Firestore instance at a time. The SDK calls [open] when the instance starts and [close]
/// when it is terminated; a store that was closed can be opened again (a new instance with the same settings after
/// `terminate`). The arrays the SDK passes are not changed afterwards, so the store may keep them; the store may hand
/// out arrays it keeps, the SDK does not change them.
///
/// A store must not import `dart:io` to be usable on the web; this interface does not.
abstract interface class CacheStore {
  /// Opens the storage. Called once before the first transaction, and again after [close] when the store is used by
  /// another instance.
  Future<void> open();

  /// Closes the storage. No transaction runs at that time and none runs after it until [open] is called again.
  Future<void> close();

  /// Runs [body] in a transaction and returns what it returns, after the writes are committed.
  ///
  /// When [body] throws, the writes it made are dropped and the error is rethrown. When [readOnly] is true the body
  /// only reads: the store may run it with less locking, and may throw on a write.
  Future<T> transaction<T>(
    Future<T> Function(CacheStoreTransaction transaction) body, {
    bool readOnly = false,
  });
}

/// The reads and writes of one [CacheStore.transaction]. Valid only until the future of the body completes.
abstract interface class CacheStoreTransaction {
  /// The value stored under [key], or null when there is none.
  Future<Uint8List?> get(Uint8List key);

  /// Stores [value] under [key], replacing the value that was there.
  Future<void> put(Uint8List key, Uint8List value);

  /// Removes [key] and its value. Removing a key that does not exist does nothing.
  Future<void> delete(Uint8List key);

  /// The entries whose keys are at least [start] and less than [end], in key order, or in reverse key order (from the
  /// largest key below [end] down to [start]) when [reverse] is true. With a [limit], only the first [limit] entries
  /// in that order.
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  });
}

/// A key and its value, as [CacheStoreTransaction.scan] returns them.
final class CacheStoreEntry {
  /// Creates an entry.
  const CacheStoreEntry(this.key, this.value);

  /// The key.
  final Uint8List key;

  /// The value stored under [key].
  final Uint8List value;

  @override
  String toString() => 'CacheStoreEntry(${key.length} B, ${value.length} B)';
}

/// Compares two keys in the order of a [CacheStore]: by their unsigned bytes, the first differing byte deciding, and a
/// key that is a prefix of another before it. For stores that keep their keys in a Dart collection (a `SplayTreeMap`
/// with this as its comparator, for example).
int compareCacheStoreKeys(List<int> a, List<int> b) {
  final int length = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < length; i++) {
    final int difference = a[i] - b[i];
    if (difference != 0) {
      return difference;
    }
  }
  return a.length - b.length;
}
