// The types of IndexedDbAuthStorage and BestWebAuthStorage that exist on every platform, so that
// code which also runs on the Dart VM can name them (catch the exception, switch on the kind).

/// What an `IndexedDbAuthStorage` was doing when it failed.
enum IndexedDbOperation {
  /// Opening (or creating) the database.
  open,

  /// Reading a session.
  read,

  /// Writing a session.
  write,

  /// Deleting a session (a write of null).
  delete,

  /// Moving a session from `localStorage` to IndexedDB (`BestWebAuthStorage`): the copy read back
  /// from IndexedDB differed from the one written. `localStorage` still holds the session.
  migrate,
}

/// An operation of `IndexedDbAuthStorage` failed.
///
/// It names the operation, the database and the key, and the `DOMException` of the browser by its
/// [name] and [message]. It never holds the stored value.
class IndexedDbAuthStorageException implements Exception {
  /// An exception for [operation] on [databaseName].
  const IndexedDbAuthStorageException({
    required this.operation,
    required this.databaseName,
    this.key,
    this.name,
    this.message,
  });

  /// What failed.
  final IndexedDbOperation operation;

  /// The name of the IndexedDB database.
  final String databaseName;

  /// The key of the session, as `FirebaseUserAuth` passes it; null for [IndexedDbOperation.open].
  final String? key;

  /// The name of the browser's `DOMException`, for example `QuotaExceededError`,
  /// `InvalidStateError` or `UnknownError`; `TimeoutError` for an [IndexedDbTimeoutException],
  /// `BlockedError` for an open or deletion blocked by another connection; null when there was
  /// none (IndexedDB is missing, an entry that is not a string).
  final String? name;

  /// The message of the browser's `DOMException`, or a description of the failure.
  final String? message;

  @override
  String toString() {
    final String what = key == null ? 'the database' : 'the session "$key"';
    final String cause = <String?>[
      name,
      message,
    ].whereType<String>().where((String s) => s.isNotEmpty).join(': ');
    return 'IndexedDbAuthStorageException: could not ${operation.name} $what in the IndexedDB '
        'database "$databaseName"${cause.isEmpty ? '' : ' ($cause)'}.';
  }
}

/// A request of `IndexedDbAuthStorage` (opening, deleting or a transaction) did not finish within
/// [timeout]: its transaction was aborted, or the late connection is closed when it opens.
///
/// Browsers leave a request pending when another connection blocks it (a tab that ignores a
/// `versionchange`, a transaction of a frozen background tab) or, in some versions, forever. The
/// calls queued behind it go on.
class IndexedDbTimeoutException extends IndexedDbAuthStorageException {
  /// An exception for [operation] on [databaseName] that took longer than [timeout].
  IndexedDbTimeoutException({
    required super.operation,
    required super.databaseName,
    required this.timeout,
    super.key,
  }) : super(
         name: 'TimeoutError',
         message: 'no answer within ${timeout.inMilliseconds} ms',
       );

  /// The limit of one request (`IndexedDbAuthStorage.requestTimeout`).
  final Duration timeout;
}

/// Where a `BestWebAuthStorage` keeps the sessions, decided once by the availability checks.
enum WebAuthStorageKind {
  /// An `IndexedDbAuthStorage` (the JS SDK's `indexedDBLocalPersistence`).
  indexedDb,

  /// `WebAuthStorage.local` (`browserLocalPersistence`).
  localStorage,

  /// An `InMemoryAuthStorage` (`inMemoryPersistence`): the user signs in again after a reload.
  memory,
}
