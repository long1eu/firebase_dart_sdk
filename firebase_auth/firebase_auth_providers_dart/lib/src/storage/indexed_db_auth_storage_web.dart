import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_auth_providers_dart/src/auth_storage.dart';
import 'package:firebase_auth_providers_dart/src/storage/indexed_db_types.dart';
import 'package:firebase_auth_providers_dart/src/storage/web_auth_storage_web.dart';
import 'package:meta/meta.dart';
import 'package:web/web.dart' as web;

/// An [AuthStorage] in an IndexedDB database of the origin (the JS SDK's
/// `indexedDBLocalPersistence`).
///
/// The session survives closing the browser and is shared by the tabs and workers of the origin.
/// Each value is a string under its key in the object store [objectStoreName] of the database
/// [databaseName], version [databaseVersion]. This is not the JS SDK's format: it uses its own
/// database (not `firebaseLocalStorageDb`), and the JS SDK cannot read these sessions.
///
/// * [write] completes when the transaction has completed, with `durability: 'strict'`: the browser
///   has committed it then, not only accepted it.
/// * The calls on one instance run one at a time, in the order they were made.
/// * Every request (the open, a transaction) has [requestTimeout] to finish. A request that takes
///   longer is aborted and throws an [IndexedDbTimeoutException]; the calls behind it go on.
/// * The connection is opened at the first call and kept. It is closed when another connection
///   asks for a new version or deletes the database (`versionchange`), and dropped when the browser
///   closes it (the user cleared the site data). The next call opens it again. A call that
///   finds the connection closed when its transaction starts, or whose transaction is aborted
///   without an error of its own (or with an `AbortError`, as when the browser closes the
///   connection), reopens once and tries again.
/// * A failure throws an [IndexedDbAuthStorageException], which names the operation, the key and
///   the browser's error, never the value. Nothing is logged.
///
/// Check [isAvailable] first where IndexedDB may be missing or refused (some private windows,
/// blocked site data, a worker without it), or use [BestWebAuthStorage], which does that and falls
/// back to `localStorage` or memory.
///
/// **What the storage exposes.** Like `localStorage`, IndexedDB is readable by every script of the
/// origin: a cross-site scripting flaw gives the refresh token (which does not expire) away. See
/// [WebAuthStorage].
///
/// Changes made by another tab are read at the next [read]; nothing tells this one about them (no
/// cross-tab sync).
///
/// On the Dart VM the constructor throws an [UnsupportedError] and [isAvailable] returns false.
///
/// ```dart
/// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
///   app,
///   storage: IndexedDbAuthStorage(),
/// );
/// ```
class IndexedDbAuthStorage implements AuthStorage {
  /// A storage in the IndexedDB database [databaseName], whose requests each have [requestTimeout]
  /// to finish. Does no I/O: the database is opened (and created) at the first [read] or [write].
  IndexedDbAuthStorage({
    this.databaseName = defaultDatabaseName,
    this.requestTimeout = defaultRequestTimeout,
  }) {
    if (databaseName.isEmpty) {
      throw ArgumentError.value(
        databaseName,
        'databaseName',
        'must not be empty',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
  }

  /// The database used when none is given. Only a database of this name is deleted and created
  /// again when it exists without the object store [objectStoreName].
  static const String defaultDatabaseName = 'firebase_auth_providers_dart';

  /// The object store that holds the sessions, by key.
  static const String objectStoreName = 'sessions';

  /// The version the database is opened with.
  // Raising it locks out the tabs that still run older code: their versionchange handler closes
  // their connection, and every open they make afterwards asks for the lower version and fails
  // with a VersionError until they reload.
  static const int databaseVersion = 1;

  /// The time one request has when none is given (the JS SDK's limit).
  static const Duration defaultRequestTimeout = Duration(milliseconds: 2500);

  /// The key under which [isAvailable] writes, reads back and deletes its probe value.
  static const String probeKey = '.availability-probe';

  /// The name of the IndexedDB database.
  final String databaseName;

  /// The time each request (the open, the deletion of a database, a transaction) has to finish.
  final Duration requestTimeout;

  web.IDBDatabase? _db;

  /// Counts the connections opened, so that the event of an older one does not drop a newer one.
  int _generation = 0;

  Future<void> _last = Future<void>.value();

  /// Whether IndexedDB can be used here: it exists, and a value written to [databaseName] (under
  /// [probeKey]) reads back the same and can be deleted. False in a private window or with site
  /// data blocked where the browser refuses IndexedDB, in a worker without it, on the Dart VM, and
  /// when a request of the probe takes longer than [timeout] (a connection that blocks the open).
  /// Never throws.
  static Future<bool> isAvailable({
    String databaseName = defaultDatabaseName,
    Duration timeout = defaultRequestTimeout,
  }) async {
    if (databaseName.isEmpty || timeout <= Duration.zero) {
      return false;
    }
    final IndexedDbAuthStorage storage = IndexedDbAuthStorage(
      databaseName: databaseName,
      requestTimeout: timeout,
    );
    try {
      return await storage._available();
    } finally {
      // Queued behind the probe; never fails.
      unawaited(storage.close());
    }
  }

  /// The probe of [isAvailable] on this storage's own connection, which stays open for the calls
  /// that follow. The probe key is written with `durability: 'relaxed'`. Never throws.
  Future<bool> _available() async {
    if (_factory() == null) {
      return false;
    }
    final String value = 'probe ${DateTime.now().microsecondsSinceEpoch}';
    try {
      await write(probeKey, value);
      final String? back = await read(probeKey);
      await write(probeKey, null);
      return back == value;
    } on Object {
      // The answer is "not available"; what failed does not matter to the caller.
      return false;
    }
  }

  @override
  Future<String?> read(String key) =>
      _serial(() => _transact(IndexedDbOperation.read, key, null));

  @override
  Future<void> write(String key, String? value) => _serial(
    () => _transact(
      value == null ? IndexedDbOperation.delete : IndexedDbOperation.write,
      key,
      value,
    ),
  );

  /// Closes the connection once the calls made before have finished. A later [read] or [write]
  /// opens it again. Never fails.
  Future<void> close() => _serial(() async => _drop());

  Future<T> _serial<T>(Future<T> Function() operation) {
    final Future<T> next = _last.then((_) => operation());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _drop() {
    final web.IDBDatabase? db = _db;
    _db = null;
    _generation++;
    if (db != null) {
      try {
        db.close();
      } on Object {
        // Already closed.
      }
    }
  }

  Future<String?> _transact(
    IndexedDbOperation operation,
    String key,
    String? value,
  ) async {
    for (int attempt = 0; ; attempt++) {
      final bool mayRetry = attempt == 0;
      final web.IDBDatabase db = await _database();
      final web.IDBTransaction transaction;
      try {
        transaction = _begin(db, operation, key);
      } on Object catch (e) {
        // InvalidStateError: the connection was closed (the database was deleted, or a
        // versionchange closed it) before this one heard of it.
        _drop();
        if (mayRetry) {
          continue;
        }
        throw _error(operation, key, e, 'the transaction could not start');
      }
      try {
        return await _run(transaction, operation, key, value);
      } on _AbortedByBrowser catch (aborted) {
        // A forced close (site data cleared) aborts the transactions before the close event bumps
        // the generation: reopen whatever the generation says.
        _drop();
        if (mayRetry) {
          continue;
        }
        throw aborted.exception;
      }
    }
  }

  static web.IDBTransaction _begin(
    web.IDBDatabase db,
    IndexedDbOperation operation,
    String key,
  ) {
    if (operation == IndexedDbOperation.read) {
      return db.transaction(objectStoreName.toJS, 'readonly');
    }
    return db.transaction(
      objectStoreName.toJS,
      'readwrite',
      web.IDBTransactionOptions(
        durability: key == probeKey ? 'relaxed' : 'strict',
      ),
    );
  }

  Future<String?> _run(
    web.IDBTransaction transaction,
    IndexedDbOperation operation,
    String key,
    String? value,
  ) {
    final Completer<String?> done = Completer<String?>();
    final web.IDBRequest request;
    try {
      final web.IDBObjectStore store = transaction.objectStore(objectStoreName);
      request = switch (operation) {
        IndexedDbOperation.read => store.get(key.toJS),
        IndexedDbOperation.write => store.put(value!.toJS, key.toJS),
        _ => store.delete(key.toJS),
      };
    } on Object catch (e) {
      _abort(transaction);
      return Future<String?>.error(
        _error(operation, key, e, 'the request could not start'),
      );
    }
    JSAny? result;
    request.onsuccess = ((web.Event _) {
      result = request.result;
    }).toJS;
    transaction.oncomplete = ((web.Event _) {
      if (!done.isCompleted) {
        _completeRead(done, operation, key, result);
      }
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (done.isCompleted) {
        return;
      }
      final web.DOMException? error =
          transaction.error ?? _requestError(request);
      final IndexedDbAuthStorageException exception = _error(
        operation,
        key,
        error,
        'aborted',
      );
      done.completeError(
        error == null || error.name == 'AbortError'
            ? _AbortedByBrowser(exception)
            : exception,
      );
    }).toJS;
    return _limited(done, operation, key, () => _abort(transaction));
  }

  void _completeRead(
    Completer<String?> done,
    IndexedDbOperation operation,
    String key,
    JSAny? stored,
  ) {
    if (operation != IndexedDbOperation.read || stored.isUndefinedOrNull) {
      done.complete(null);
    } else if (stored.typeofEquals('string')) {
      done.complete((stored as JSString).toDart);
    } else {
      done.completeError(
        _error(operation, key, null, 'the stored entry is not a string'),
      );
    }
  }

  /// Waits for [done] at most [requestTimeout]. When the time is up first, the wait ends with an
  /// [IndexedDbTimeoutException], then [cancel] runs (it aborts the transaction).
  Future<T> _limited<T>(
    Completer<T> done,
    IndexedDbOperation operation,
    String? key,
    void Function() cancel,
  ) {
    final Timer timer = Timer(requestTimeout, () {
      if (done.isCompleted) {
        return;
      }
      done.completeError(
        IndexedDbTimeoutException(
          operation: operation,
          databaseName: databaseName,
          key: key,
          timeout: requestTimeout,
        ),
      );
      cancel();
    });
    return done.future.whenComplete(timer.cancel);
  }

  static web.DOMException? _requestError(web.IDBRequest request) {
    try {
      return request.error;
    } on Object {
      // InvalidStateError: the request has not finished.
      return null;
    }
  }

  static void _abort(web.IDBTransaction transaction) {
    try {
      transaction.abort();
    } on Object {
      // Already finished.
    }
  }

  /// An exception for [operation] on [key] with the `name` and `message` of [cause] (a
  /// `DOMException` or another JS error), read through interop; [fallback] when it has none.
  IndexedDbAuthStorageException _error(
    IndexedDbOperation operation,
    String? key,
    Object? cause,
    String fallback,
  ) => IndexedDbAuthStorageException(
    operation: operation,
    databaseName: databaseName,
    key: key,
    name: _jsString(cause, 'name'),
    message: _jsString(cause, 'message') ?? fallback,
  );

  /// The string [property] of the JS object [cause]; null when [cause] is not a JS object or the
  /// property is not a non-empty string.
  static String? _jsString(Object? cause, String property) {
    if (cause == null) {
      return null;
    }
    try {
      final JSAny? value = (cause as JSObject).getProperty<JSAny?>(
        property.toJS,
      );
      if (value.typeofEquals('string')) {
        final String text = (value as JSString).toDart;
        return text.isEmpty ? null : text;
      }
    } on Object {
      // Not a JS object (a Dart error): the fallback describes the failure.
    }
    return null;
  }

  Future<web.IDBDatabase> _database() async {
    final web.IDBDatabase? current = _db;
    if (current != null) {
      return current;
    }
    final web.IDBDatabase db = await _open(recreate: true);
    final int generation = ++_generation;
    db.onversionchange = ((web.Event _) {
      // Another connection deletes the database or upgrades it: let it.
      db.close();
      if (_generation == generation) {
        _db = null;
        _generation++;
      }
    }).toJS;
    db.onclose = ((web.Event _) {
      // Closed by the browser: the site data was cleared, or the disk failed.
      if (_generation == generation) {
        _db = null;
        _generation++;
      }
    }).toJS;
    return _db = db;
  }

  Future<web.IDBDatabase> _open({required bool recreate}) async {
    final web.IDBFactory factory = _factoryOrThrow();
    final Completer<web.IDBDatabase> done = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request;
    try {
      request = factory.open(databaseName, databaseVersion);
    } on Object catch (e) {
      throw _error(IndexedDbOperation.open, null, e, 'the open failed');
    }
    request.onupgradeneeded = ((web.Event _) {
      final web.IDBDatabase db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(objectStoreName)) {
        db.createObjectStore(objectStoreName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final web.IDBDatabase db = request.result as web.IDBDatabase;
      if (done.isCompleted) {
        // Opened after the wait ended (timed out or blocked): nobody uses it.
        db.close();
        return;
      }
      done.complete(db);
    }).toJS;
    _failOn(request, done, 'the open failed', 'the open is blocked');
    final web.IDBDatabase db = await _limited(
      done,
      IndexedDbOperation.open,
      null,
      () {},
    );
    if (db.objectStoreNames.contains(objectStoreName)) {
      return db;
    }
    db.close();
    if (!recreate || databaseName != defaultDatabaseName) {
      throw _error(
        IndexedDbOperation.open,
        null,
        null,
        'the database has no object store "$objectStoreName": other code created it',
      );
    }
    // The default database without the store (created by other code): it holds nothing of ours.
    // Delete it and create it again, once, as the JS SDK does.
    await _delete(factory);
    return _open(recreate: false);
  }

  Future<void> _delete(web.IDBFactory factory) {
    final Completer<void> done = Completer<void>();
    final web.IDBOpenDBRequest request;
    try {
      request = factory.deleteDatabase(databaseName);
    } on Object catch (e) {
      return Future<void>.error(
        _error(IndexedDbOperation.open, null, e, 'the delete failed'),
      );
    }
    request.onsuccess = ((web.Event _) {
      if (!done.isCompleted) {
        done.complete();
      }
    }).toJS;
    _failOn(request, done, 'the delete failed', 'the delete is blocked');
    return _limited(done, IndexedDbOperation.open, null, () {});
  }

  /// Ends [done] with an error when [request] fails or is blocked by another connection that does
  /// not close (the request stays pending in the browser; a late open is closed by its handler).
  void _failOn(
    web.IDBOpenDBRequest request,
    Completer<Object?> done,
    String failed,
    String blocked,
  ) {
    request.onerror = ((web.Event event) {
      // Handled here: keeps the browser from reporting it as an uncaught error.
      event.preventDefault();
      if (!done.isCompleted) {
        done.completeError(
          _error(IndexedDbOperation.open, null, _requestError(request), failed),
        );
      }
    }).toJS;
    request.onblocked = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(
          IndexedDbAuthStorageException(
            operation: IndexedDbOperation.open,
            databaseName: databaseName,
            name: 'BlockedError',
            message: '$blocked by another connection of the database',
          ),
        );
      }
    }).toJS;
  }

  web.IDBFactory _factoryOrThrow() =>
      _factory() ??
      (throw _error(
        IndexedDbOperation.open,
        null,
        null,
        'IndexedDB is not available here',
      ));

  /// The `indexedDB` of the window or worker; null where there is none, or where reading it throws
  /// (some private windows).
  static web.IDBFactory? _factory() {
    try {
      return globalContext.getProperty<web.IDBFactory?>('indexedDB'.toJS);
    } on Object {
      return null;
    }
  }
}

/// A transaction aborted without an error of its own, or with an `AbortError`: what the browser
/// does to the transactions of a connection it closes. Retried once, then [exception] is thrown.
class _AbortedByBrowser implements Exception {
  _AbortedByBrowser(this.exception);

  final IndexedDbAuthStorageException exception;
}

/// The best persistent [AuthStorage] the browser offers, like the JS SDK's `getAuth`: an
/// [IndexedDbAuthStorage] when IndexedDB passes the probe of [IndexedDbAuthStorage.isAvailable],
/// else `localStorage` ([WebAuthStorage.local]) when it can be written, else memory
/// (`InMemoryAuthStorage`: the user signs in again after a reload).
///
/// The choice ([kind]) is made once, before the first [read] or [write], and kept for the life of
/// the object. The probe runs on the connection the sessions then use. The checks never throw.
///
/// **Moving from `localStorage`.** When IndexedDB is the choice, a [read] of a key that IndexedDB
/// does not have moves the session from `localStorage` (where an earlier version of the app kept
/// it with [WebAuthStorage.local] and [localStoragePrefix]): it is read there, written to
/// IndexedDB, read back and compared, and only then deleted from `localStorage`.
///
/// * IndexedDB already has a session for the key: it wins, and the copy in `localStorage` is
///   deleted, unless the marker below says otherwise.
/// * The copy read back differs: the copy in IndexedDB is deleted, `localStorage` keeps the
///   session, and an [IndexedDbAuthStorageException] with [IndexedDbOperation.migrate] is thrown.
///   The next read tries again.
/// * IndexedDB fails: its exception is thrown and `localStorage` is left as it was.
/// * `localStorage` cannot be read: the read returns null, and the `onMigrationIssue` of the
///   constructor is called.
/// * `localStorage` cannot delete the key: the read returns the session, and the
///   `onMigrationIssue` of the constructor is called; a copy remains there.
///
/// **Writes without IndexedDB.** When `localStorage` or memory holds the sessions (IndexedDB failed
/// its probe on this load), every [write] also leaves a marker for the key in `localStorage` (when
/// it works) and tries to delete the key from IndexedDB, without waiting and ignoring a failure. At
/// the next load that picks IndexedDB, a marked key takes its state from `localStorage`: the
/// session there is moved to IndexedDB, or, after a sign-out, the copy in IndexedDB is deleted. So
/// an older session in IndexedDB does not come back.
///
/// A write of null (a sign-out) deletes the key from `localStorage` too, so that a session the move
/// never reached cannot come back. The calls run one at a time, in order.
///
/// On the Dart VM the constructor throws an [UnsupportedError].
///
/// ```dart
/// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
///   app,
///   storage: BestWebAuthStorage(),
/// );
/// ```
class BestWebAuthStorage implements AuthStorage {
  /// A storage that chooses between IndexedDB (the database [databaseName]), `localStorage` (keys
  /// under [localStoragePrefix]) and memory.
  ///
  /// [onMigrationIssue] receives the key and the error of a step of the move from `localStorage`
  /// that failed without failing the read (see [BestWebAuthStorage]); by default they are ignored.
  /// It never receives a value.
  BestWebAuthStorage({
    String databaseName = IndexedDbAuthStorage.defaultDatabaseName,
    String localStoragePrefix = '',
    void Function(String key, Object error)? onMigrationIssue,
  }) : this.forTesting(
         databaseName: databaseName,
         localStoragePrefix: localStoragePrefix,
         onMigrationIssue: onMigrationIssue,
       );

  /// A storage whose parts are replaced, for tests: [indexedDb] and [localStorage] replace the
  /// storages made from [databaseName] and [localStoragePrefix]; [indexedDbAvailable] replaces the
  /// probe of IndexedDB, and [localStorageAvailable] the write and delete of a probe key in
  /// `localStorage`. The checks must not throw.
  @visibleForTesting
  BestWebAuthStorage.forTesting({
    String databaseName = IndexedDbAuthStorage.defaultDatabaseName,
    String localStoragePrefix = '',
    void Function(String key, Object error)? onMigrationIssue,
    IndexedDbAuthStorage? indexedDb,
    WebAuthStorage? localStorage,
    Future<bool> Function()? indexedDbAvailable,
    bool Function()? localStorageAvailable,
  }) : _indexedDb =
           indexedDb ?? IndexedDbAuthStorage(databaseName: databaseName),
       _local =
           localStorage ?? WebAuthStorage.local(prefix: localStoragePrefix),
       _onMigrationIssue = onMigrationIssue ?? _ignoreIssue,
       _indexedDbAvailable = indexedDbAvailable,
       _localStorageAvailable = localStorageAvailable ?? _localStorageWorks;

  /// The suffix of the key of the marker that a write without IndexedDB leaves in `localStorage`.
  static const String _markerSuffix = '.written-without-indexeddb';

  final IndexedDbAuthStorage _indexedDb;
  final WebAuthStorage _local;
  final void Function(String key, Object error) _onMigrationIssue;
  final Future<bool> Function()? _indexedDbAvailable;
  final bool Function() _localStorageAvailable;

  /// What goes before every key in `localStorage`, when the sessions are kept there or moved from
  /// there.
  String get localStoragePrefix => _local.prefix;

  /// Whether `localStorage` can be used; checked once. Without it there is nothing to move from.
  late final bool _localWorks = _check(_localStorageAvailable);
  final InMemoryAuthStorage _memory = InMemoryAuthStorage();

  Future<WebAuthStorageKind>? _kind;
  Future<void> _last = Future<void>.value();

  /// Where the sessions are kept; the checks run at the first use of this getter, [read] or
  /// [write].
  Future<WebAuthStorageKind> get kind => _kind ??= _decide();

  Future<WebAuthStorageKind> _decide() async {
    bool indexedDb;
    try {
      indexedDb = await (_indexedDbAvailable ?? _indexedDb._available)();
    } on Object {
      // A replaced check that throws counts as unavailable.
      indexedDb = false;
    }
    if (indexedDb) {
      return WebAuthStorageKind.indexedDb;
    }
    return _localWorks
        ? WebAuthStorageKind.localStorage
        : WebAuthStorageKind.memory;
  }

  static bool _check(bool Function() available) {
    try {
      return available();
    } on Object {
      // A replaced check that throws counts as unavailable.
      return false;
    }
  }

  @override
  Future<String?> read(String key) => _serial(() async {
    switch (await kind) {
      case WebAuthStorageKind.indexedDb:
        return _readIndexedDb(key);
      case WebAuthStorageKind.localStorage:
        return _local.read(key);
      case WebAuthStorageKind.memory:
        return _memory.read(key);
    }
  });

  @override
  Future<void> write(String key, String? value) => _serial(() async {
    switch (await kind) {
      case WebAuthStorageKind.indexedDb:
        await _indexedDb.write(key, value);
        if (_localWorks) {
          _afterIndexedDbWrite(key, value);
        }
      case WebAuthStorageKind.localStorage:
        _local.write(key, value);
        _invalidateIndexedDb(key);
      case WebAuthStorageKind.memory:
        _memory.write(key, value);
        _invalidateIndexedDb(key);
    }
  });

  /// Closes the IndexedDB connection once the calls made before (and the deletions they started)
  /// have finished. A later [read] or [write] opens it again. Never fails.
  Future<void> close() => _serial(_indexedDb.close);

  Future<T> _serial<T>(Future<T> Function() operation) {
    final Future<T> next = _last.then((_) => operation());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// A write without IndexedDB: mark the key, and try to delete the older copy in IndexedDB.
  void _invalidateIndexedDb(String key) {
    if (_localWorks) {
      _local.write(_markerOf(key), '1');
    }
    // Best effort: IndexedDB may be what failed. When the delete fails, the marker decides.
    unawaited(
      _indexedDb.write(key, null).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// IndexedDB holds the newest state of [key]: a copy or marker in `localStorage` is stale.
  void _afterIndexedDbWrite(String key, String? value) {
    final bool marked = _marked(key);
    if (value == null || marked) {
      _deleteOld(key);
    }
    if (marked) {
      _deleteOld(_markerOf(key), issueKey: key);
    }
  }

  Future<String?> _readIndexedDb(String key) async {
    if (!_localWorks) {
      return _indexedDb.read(key);
    }
    if (_marked(key)) {
      return _takeMarkedState(key);
    }
    final String? stored = await _indexedDb.read(key);
    if (stored != null) {
      if (_readOld(key) != null) {
        _deleteOld(key);
      }
      return stored;
    }
    final String? old;
    try {
      old = _local.read(key);
    } on Object catch (e) {
      _onMigrationIssue(key, e);
      return null;
    }
    if (old == null) {
      return null;
    }
    await _move(key, old);
    return old;
  }

  /// A write made without IndexedDB marked [key]: the state in `localStorage` is the newest. It
  /// replaces the one in IndexedDB; the marker goes once IndexedDB holds it.
  Future<String?> _takeMarkedState(String key) async {
    final String? newest;
    try {
      newest = _local.read(key);
    } on Object catch (e) {
      // Never fall back to IndexedDB's copy here: it may be the one the marked write replaced.
      _onMigrationIssue(key, e);
      return null;
    }
    if (newest == null) {
      await _indexedDb.write(key, null);
    } else {
      await _move(key, newest);
    }
    _deleteOld(_markerOf(key), issueKey: key);
    return newest;
  }

  /// Writes [old] to IndexedDB, reads it back and compares, then deletes it from `localStorage`.
  Future<void> _move(String key, String old) async {
    await _indexedDb.write(key, old);
    final String? back = await _indexedDb.read(key);
    if (back != old) {
      try {
        await _indexedDb.write(key, null);
      } on IndexedDbAuthStorageException catch (e) {
        _onMigrationIssue(key, e);
      }
      throw IndexedDbAuthStorageException(
        operation: IndexedDbOperation.migrate,
        databaseName: _indexedDb.databaseName,
        key: key,
        message:
            'the session read back from IndexedDB differs from the one written; '
            'localStorage still holds it',
      );
    }
    _deleteOld(key);
  }

  static String _markerOf(String key) => '$key$_markerSuffix';

  bool _marked(String key) => _readOld(_markerOf(key)) != null;

  /// The entry of [key] in `localStorage`; null when there is none or it cannot be read.
  String? _readOld(String key) {
    try {
      return _local.read(key);
    } on Object {
      // Unreadable counts as absent; the read of the session itself reports a failure.
      return null;
    }
  }

  /// Deletes [key] from `localStorage`; a failure goes to `onMigrationIssue` under [issueKey]
  /// (the session's key), else [key].
  void _deleteOld(String key, {String? issueKey}) {
    try {
      _local.write(key, null);
    } on Object catch (e) {
      _onMigrationIssue(issueKey ?? key, e);
    }
  }

  static void _ignoreIssue(String key, Object error) {}

  /// Whether `localStorage` exists and takes a write (a worker has none; a browser with site data
  /// blocked throws).
  static bool _localStorageWorks() {
    try {
      const String probe = '.firebase_auth_providers_dart.probe';
      final web.Storage storage = web.window.localStorage;
      storage.setItem(probe, '1');
      storage.removeItem(probe);
      return true;
    } on Object {
      return false;
    }
  }
}
