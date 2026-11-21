import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../auth_storage.dart';
import 'indexed_db_types.dart';
import 'web_auth_storage_web.dart';

/// An [AuthStorage] in an IndexedDB database of the origin (the JS SDK's `indexedDBLocalPersistence`).
///
/// The session survives closing the browser and is shared by the tabs and workers of the origin. Each value is a
/// string under its key in the object store [objectStoreName] of the database [databaseName], version
/// [databaseVersion]. This is not the JS SDK's format: it uses its own database (not `firebaseLocalStorageDb`), and
/// the JS SDK cannot read these sessions.
///
/// * [write] completes when the transaction has completed, with `durability: 'strict'`: the value is on disk then,
///   not only accepted by the browser.
/// * The calls on one instance run one at a time, in the order they were made.
/// * The connection is opened at the first call and kept. It is closed when another connection asks for a new
///   version or deletes the database (`versionchange`), and dropped when the browser closes it (the user cleared
///   the site data). The next call opens it again; a call that finds the connection closed under it reopens once
///   and tries again.
/// * A failure throws an [IndexedDbAuthStorageException], which names the operation, the key and the browser's
///   error, never the value. Nothing is logged.
///
/// Check [isAvailable] first where IndexedDB may be missing or refused (some private windows, blocked site data, a
/// worker without it), or use [BestWebAuthStorage], which does that and falls back to `localStorage` or memory.
///
/// **What the storage exposes.** Like `localStorage`, IndexedDB is readable by every script of the origin: a
/// cross-site scripting flaw gives the refresh token (which does not expire) away. See [WebAuthStorage].
///
/// Changes made by another tab are read at the next [read]; nothing tells this one about them (no cross-tab sync).
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
  /// A storage in the IndexedDB database [databaseName]. Does no I/O: the database is opened (and created) at the
  /// first [read] or [write].
  IndexedDbAuthStorage({this.databaseName = defaultDatabaseName}) {
    if (databaseName.isEmpty) {
      throw ArgumentError.value(
        databaseName,
        'databaseName',
        'must not be empty',
      );
    }
  }

  /// The database used when none is given.
  static const String defaultDatabaseName = 'firebase_auth_providers_dart';

  /// The object store that holds the sessions, by key.
  static const String objectStoreName = 'sessions';

  /// The version the database is opened with.
  static const int databaseVersion = 1;

  /// The key under which [isAvailable] writes, reads back and deletes its probe value.
  static const String probeKey = '.availability-probe';

  /// The name of the IndexedDB database.
  final String databaseName;

  web.IDBDatabase? _db;

  /// Counts the connections opened, so that the event of an older one does not drop a newer one.
  int _generation = 0;

  Future<void> _last = Future<void>.value();

  /// Whether IndexedDB can be used here: it exists, and a value written to [databaseName] (under [probeKey]) reads
  /// back the same and can be deleted. False in a private window or with site data blocked where the browser
  /// refuses IndexedDB, in a worker without it, on the Dart VM, and when the probe takes longer than [timeout] (a
  /// connection that blocks the open). Never throws.
  static Future<bool> isAvailable({
    String databaseName = defaultDatabaseName,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (databaseName.isEmpty || _factory() == null) {
      return false;
    }
    final IndexedDbAuthStorage storage = IndexedDbAuthStorage(
      databaseName: databaseName,
    );
    try {
      return await _probe(storage).timeout(timeout, onTimeout: () => false);
    } on Object {
      return false;
    } finally {
      // Queued behind the probe: a late open is closed when it completes.
      unawaited(storage.close().catchError((Object _) {}));
    }
  }

  static Future<bool> _probe(IndexedDbAuthStorage storage) async {
    final String value = 'probe ${DateTime.now().microsecondsSinceEpoch}';
    await storage.write(probeKey, value);
    final String? back = await storage.read(probeKey);
    await storage.write(probeKey, null);
    return back == value;
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

  /// Closes the connection once the calls made before have finished. A later [read] or [write] opens it again.
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
      final web.IDBDatabase db = await _database();
      final int generation = _generation;
      final web.IDBTransaction transaction;
      try {
        transaction = operation == IndexedDbOperation.read
            ? db.transaction(objectStoreName.toJS, 'readonly')
            : db.transaction(
                objectStoreName.toJS,
                'readwrite',
                web.IDBTransactionOptions(durability: 'strict'),
              );
      } on Object catch (e) {
        // InvalidStateError: the connection was closed (the database was deleted, or a versionchange closed it)
        // before this one heard of it.
        _drop();
        if (attempt == 0) {
          continue;
        }
        throw _error(operation, key, null, '$e');
      }
      try {
        return await _run(transaction, operation, key, value);
      } on IndexedDbAuthStorageException {
        // The connection closed while the transaction ran: open it again once.
        if (attempt == 0 && generation != _generation) {
          continue;
        }
        rethrow;
      }
    }
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
      return Future<String?>.error(_error(operation, key, null, '$e'));
    }
    JSAny? result;
    request.onsuccess = ((web.Event _) {
      result = request.result;
    }).toJS;
    transaction.oncomplete = ((web.Event _) {
      if (done.isCompleted) {
        return;
      }
      if (operation != IndexedDbOperation.read) {
        done.complete(null);
        return;
      }
      final JSAny? stored = result;
      if (stored.isUndefinedOrNull) {
        done.complete(null);
      } else if (stored.typeofEquals('string')) {
        done.complete((stored as JSString).toDart);
      } else {
        done.completeError(
          _error(operation, key, null, 'the stored entry is not a string'),
        );
      }
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(
          _error(
            operation,
            key,
            transaction.error ?? _requestError(request),
            'aborted',
          ),
        );
      }
    }).toJS;
    return done.future;
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

  IndexedDbAuthStorageException _error(
    IndexedDbOperation operation,
    String? key,
    web.DOMException? error,
    String fallback,
  ) => IndexedDbAuthStorageException(
    operation: operation,
    databaseName: databaseName,
    key: key,
    name: error?.name,
    message: error?.message ?? fallback,
  );

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
    final web.IDBFactory? factory = _factory();
    if (factory == null) {
      throw _error(
        IndexedDbOperation.open,
        null,
        null,
        'IndexedDB is not available here',
      );
    }
    final Completer<web.IDBDatabase> done = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request;
    try {
      request = factory.open(databaseName, databaseVersion);
    } on Object catch (e) {
      throw _error(IndexedDbOperation.open, null, null, '$e');
    }
    request.onupgradeneeded = ((web.Event _) {
      final web.IDBDatabase db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(objectStoreName)) {
        db.createObjectStore(objectStoreName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      done.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event event) {
      // Handled here: keeps the browser from reporting it as an uncaught error.
      event.preventDefault();
      if (!done.isCompleted) {
        done.completeError(
          _error(
            IndexedDbOperation.open,
            null,
            _requestError(request),
            'the open failed',
          ),
        );
      }
    }).toJS;
    final web.IDBDatabase db = await done.future;
    if (db.objectStoreNames.contains(objectStoreName)) {
      return db;
    }
    // A database of this name and version without the store (created by other code): it holds nothing of ours.
    // Delete it and create it again, once, as the JS SDK does.
    db.close();
    if (!recreate) {
      throw _error(
        IndexedDbOperation.open,
        null,
        null,
        'the database has no object store "$objectStoreName"',
      );
    }
    await _delete(factory);
    return _open(recreate: false);
  }

  Future<void> _delete(web.IDBFactory factory) {
    final Completer<void> done = Completer<void>();
    final web.IDBOpenDBRequest request = factory.deleteDatabase(databaseName);
    request.onsuccess = ((web.Event _) => done.complete()).toJS;
    request.onerror = ((web.Event event) {
      event.preventDefault();
      if (!done.isCompleted) {
        done.completeError(
          _error(
            IndexedDbOperation.open,
            null,
            _requestError(request),
            'the delete failed',
          ),
        );
      }
    }).toJS;
    return done.future;
  }

  /// The `indexedDB` of the window or worker; null where there is none, or where reading it throws (some private
  /// windows).
  static web.IDBFactory? _factory() {
    try {
      return globalContext.getProperty<web.IDBFactory?>('indexedDB'.toJS);
    } on Object {
      return null;
    }
  }
}

/// The best persistent [AuthStorage] the browser offers, like the JS SDK's `getAuth`: an [IndexedDbAuthStorage]
/// when [IndexedDbAuthStorage.isAvailable], else `localStorage` ([WebAuthStorage.local]) when it can be written,
/// else memory (`InMemoryAuthStorage`: the user signs in again after a reload).
///
/// The choice ([kind]) is made once, before the first [read] or [write], and kept for the life of the object. The
/// checks never throw.
///
/// **Moving from `localStorage`.** When IndexedDB is the choice, a [read] of a key that IndexedDB does not have
/// moves the session from `localStorage` (where an earlier version of the app kept it with
/// [WebAuthStorage.local] and [localStoragePrefix]): it is read there, written to IndexedDB, read back and
/// compared, and only then deleted from `localStorage`.
///
/// * IndexedDB already has a session for the key: it wins, and the copy in `localStorage` is deleted.
/// * The copy read back differs: the copy in IndexedDB is deleted, `localStorage` keeps the session, and an
///   [IndexedDbAuthStorageException] with [IndexedDbOperation.migrate] is thrown. The next read tries again.
/// * IndexedDB fails: its exception is thrown and `localStorage` is left as it was.
/// * `localStorage` cannot be read: the read returns null, and the `onMigrationIssue` of the constructor is called.
/// * `localStorage` cannot delete the key: the read returns the session, and the `onMigrationIssue` of the constructor is called; a copy
///   remains there.
///
/// A write of null (a sign-out) deletes the key from `localStorage` too, so that a session the move never reached
/// cannot come back. The calls run one at a time, in order.
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
  /// A storage that chooses between IndexedDB (the database [databaseName]), `localStorage` (keys under
  /// [localStoragePrefix]) and memory.
  ///
  /// [onMigrationIssue] receives the key and the error of a step of the move from `localStorage` that failed
  /// without failing the read (see [BestWebAuthStorage]); by default they are ignored. It never receives a value.
  ///
  /// [indexedDbAvailable] and [localStorageAvailable] replace the availability checks, for tests; by default
  /// [IndexedDbAuthStorage.isAvailable] for [databaseName], and a write and delete of a probe key in
  /// `localStorage`. They must not throw.
  BestWebAuthStorage({
    String databaseName = IndexedDbAuthStorage.defaultDatabaseName,
    this.localStoragePrefix = '',
    void Function(String key, Object error)? onMigrationIssue,
    Future<bool> Function()? indexedDbAvailable,
    bool Function()? localStorageAvailable,
  }) : _indexedDb = IndexedDbAuthStorage(databaseName: databaseName),
       _onMigrationIssue = onMigrationIssue ?? _ignoreIssue,
       _indexedDbAvailable =
           indexedDbAvailable ??
           (() => IndexedDbAuthStorage.isAvailable(databaseName: databaseName)),
       _localStorageAvailable = localStorageAvailable ?? _localStorageWorks;

  /// What goes before every key in `localStorage`, when the sessions are kept there or moved from there.
  final String localStoragePrefix;

  final IndexedDbAuthStorage _indexedDb;
  final void Function(String key, Object error) _onMigrationIssue;
  final Future<bool> Function() _indexedDbAvailable;
  final bool Function() _localStorageAvailable;

  late final WebAuthStorage _local = WebAuthStorage.local(
    prefix: localStoragePrefix,
  );

  /// Whether `localStorage` can be used; checked once. Without it there is nothing to move from.
  late final bool _localWorks = _check(_localStorageAvailable);
  final InMemoryAuthStorage _memory = InMemoryAuthStorage();

  Future<WebAuthStorageKind>? _kind;
  Future<void> _last = Future<void>.value();

  /// Where the sessions are kept; the checks run at the first use of this getter, [read] or [write].
  Future<WebAuthStorageKind> get kind => _kind ??= _decide();

  Future<WebAuthStorageKind> _decide() async {
    bool indexedDb;
    try {
      indexedDb = await _indexedDbAvailable();
    } on Object {
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
        if (value == null && _localWorks) {
          _deleteOld(key);
        }
      case WebAuthStorageKind.localStorage:
        _local.write(key, value);
      case WebAuthStorageKind.memory:
        _memory.write(key, value);
    }
  });

  Future<T> _serial<T>(Future<T> Function() operation) {
    final Future<T> next = _last.then((_) => operation());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<String?> _readIndexedDb(String key) async {
    final String? stored = await _indexedDb.read(key);
    if (!_localWorks) {
      return stored;
    }
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
            'the session read back from IndexedDB differs from the one written; localStorage still holds it',
      );
    }
    _deleteOld(key);
    return old;
  }

  /// The session of [key] in `localStorage`; null when there is none or it cannot be read.
  String? _readOld(String key) {
    try {
      return _local.read(key);
    } on Object {
      return null;
    }
  }

  void _deleteOld(String key) {
    try {
      _local.write(key, null);
    } on Object catch (e) {
      _onMigrationIssue(key, e);
    }
  }

  static void _ignoreIssue(String key, Object error) {}

  /// Whether `localStorage` exists and takes a write (a worker has none; a browser with site data blocked throws).
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
