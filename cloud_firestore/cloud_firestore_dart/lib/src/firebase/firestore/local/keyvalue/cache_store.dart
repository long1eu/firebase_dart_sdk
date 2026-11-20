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
/// The store needs no transactions of its own. The SDK keeps the writes of each of its transactions in memory, serves
/// the reads of that transaction from the store and those writes, and hands the store all of the writes at once, in
/// one [write], when the transaction commits; a transaction that fails never reaches the store. The contract, which
/// `cacheStoreConformanceChecks` of `package:cloud_firestore_dart/cache_store_testing.dart` checks:
///
/// * **Ordered.** [scan] returns the entries of a range in key order, or in reverse order.
/// * **Atomic and durable writes.** [write] keeps all of its puts and deletes, or none of them, also when the app
///   crashes or the device turns off in between; once its future completes they are durable.
/// * **Reads see the completed writes.** A [get] or [scan] that starts after a [write] completed sees it.
///
/// When a call of the store throws, the SDK takes it that the transaction that needed it did not take effect (a
/// [write] that throws wrote nothing) and that the store may work again later, as the JS SDK takes a failed IndexedDB
/// transaction: the listen or write that needed it fails with `unavailable`, an acknowledgement or a remote change is
/// kept and stored again later, and the client goes offline and tries the store again with a backoff until it works.
/// The state the SDK keeps in memory is read again from the store before its next transaction.
///
/// What the store may assume:
///
/// * The store belongs to one Firestore instance at a time, and nothing else changes its data while the instance
///   runs. The SDK calls [open] when the instance starts and [close] when it is terminated; a store that was closed
///   can be opened again (a new instance with the same settings after `terminate`).
/// * The SDK never calls [write] while another [write] runs, and never reads while a [write] runs. Reads ([get] and
///   [scan]) may run at the same time as each other.
/// * Each read stands on its own: the SDK does not need two reads to see the same snapshot, since nobody writes
///   between them.
/// * The arrays the SDK passes are not changed afterwards, so the store may keep them; the store may hand out arrays
///   it keeps, the SDK does not change them.
///
/// A store must not import `dart:io` to be usable on the web; this interface does not.
abstract interface class CacheStore {
  /// Opens the storage. Called once before the first read or write, and again after [close] when the store is used by
  /// another instance.
  Future<void> open();

  /// Closes the storage. No read or write runs at that time and none runs after it until [open] is called again.
  Future<void> close();

  /// The value stored under [key], or null when there is none.
  Future<Uint8List?> get(Uint8List key);

  /// The entries whose keys are at least [start] and less than [end], in key order, or in reverse key order (from the
  /// largest key below [end] down to [start]) when [reverse] is true. With a [limit], only the first [limit] entries
  /// in that order.
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  });

  /// Stores the value of each of [puts] under its key, replacing the value that was there, and removes the keys of
  /// [deletes] (removing a key that does not exist does nothing), all of them or none, durably once the future
  /// completes. A key appears at most once in the two lists together.
  ///
  /// When the future throws, the SDK takes it that nothing was written.
  Future<void> write(List<CacheStoreEntry> puts, List<Uint8List> deletes);
}

/// A key and its value, as [CacheStore.scan] returns them and [CacheStore.write] takes them.
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
