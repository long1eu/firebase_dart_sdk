/// An error that SQLite (or the file system) reported in the OPFS worker.
///
/// The errors that may go away on their own, and after which nothing of the
/// failed statement or its transaction can have been stored, come as a
/// `TransientDatabaseException` with this as its cause instead (the worker
/// decides): Firestore then goes offline and retries. An I/O error at a COMMIT
/// that may have stored the transaction stays a [SqliteOpfsException], fatal
/// for the operation, because running it again would apply it twice.
///
/// Only thrown in a browser, by the OPFS storage of `sqliteOpener`.
class SqliteOpfsException implements Exception {
  /// An error with SQLite's [message] and, when SQLite reported it, its
  /// primary [resultCode].
  SqliteOpfsException(this.message, [this.resultCode]);

  /// The message of SQLite, without the statement or its arguments.
  final String message;

  /// The primary SQLite result code, when SQLite reported the error.
  final int? resultCode;

  @override
  String toString() => 'SqliteOpfsException: $message';
}
