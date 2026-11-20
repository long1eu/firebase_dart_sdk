/// The IndexedDB database of the official Firebase JS SDK, as the import of its cache sees it (see
/// `js_sdk_importer.dart`). The web implementation is in `js_sdk_database_web.dart`; other platforms have none.
library;

/// An open connection to the JS SDK's database. Rows are JSON trees: the structured-clone values of IndexedDB through
/// `JSON.stringify` and `jsonDecode` (the JS SDK stores proto3 JSON and plain numbers, strings and arrays).
abstract class JsSdkDatabase {
  /// The schema version the database was last opened with (`SCHEMA_VERSION` of the JS SDK that wrote it). Opening it
  /// for the import does not upgrade it.
  int get version;

  /// Whether the database has the object store [name].
  bool hasStore(String name);

  /// The values of every row of the object store [name], in key order, read in one transaction.
  Future<List<Map<String, Object?>>> readAll(String name);

  /// The values of the rows of the object store [name], in key order, at most [count] at a time, each chunk read in
  /// a transaction of its own: a large store is never held whole.
  Stream<List<Map<String, Object?>>> readChunks(String name, int count);

  /// Removes, in one transaction, the rows of the `mutations` store with the keys [batchIds] for which [matches] is
  /// true, with their rows in `documentMutations` and the rows of `documentOverlays` (when the store exists) whose
  /// largest batch id is one of them, for the same user. Completes when the transaction committed, with the number of
  /// batches removed.
  Future<int> removeMutationBatches(
    Iterable<int> batchIds,
    bool Function(Map<String, Object?> row) matches,
  );

  /// Closes the connection.
  void close();
}
