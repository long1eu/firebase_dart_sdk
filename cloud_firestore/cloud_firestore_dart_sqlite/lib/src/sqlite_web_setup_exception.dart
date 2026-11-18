/// The browser storage of `sqliteOpener` can not be used as the app is set
/// up: the resolved `sqlite3` version, or the `sqlite3.wasm` file next to the
/// page. [message] says what is wrong and how to fix it.
///
/// A mistake of the build, not of the moment: opening again fails the same
/// way. `openWithMemoryFallback` rethrows it rather than falling back to a
/// memory cache, so that it is seen and fixed (catch it there to fall back
/// anyway).
///
/// Only thrown in a browser, by the first operation of an instance whose
/// `openDatabase` is a `sqliteOpener`.
class SqliteWebSetupException implements Exception {
  /// An error about [problem], described by [message]; [cause] is the error
  /// it explains, if any.
  SqliteWebSetupException(this.problem, this.message, [this.cause]);

  /// What is wrong.
  final SqliteWebSetupProblem problem;

  /// What is wrong and the ways out, in a sentence or three.
  final String message;

  /// The error this explains (for example the `LinkError` of a `sqlite3.wasm`
  /// of another version), or null.
  final Object? cause;

  @override
  String toString() => 'SqliteWebSetupException: $message';
}

/// What a [SqliteWebSetupException] is about.
enum SqliteWebSetupProblem {
  /// The resolved `sqlite3` package (3.4.0 to 3.5.2) can lose acknowledged
  /// writes with the IndexedDB storage: its `IndexedDbFileSystem.flush()`
  /// does not wait for the writes in progress.
  unsafeSqlite3,

  /// `sqlite3.wasm` is not the build of the resolved `sqlite3` package.
  wasmVersionMismatch,

  /// `sqlite3.wasm` is not at its URL, or is not WebAssembly (often the
  /// `index.html` a server sends for a missing file).
  wasmMissing,
}
