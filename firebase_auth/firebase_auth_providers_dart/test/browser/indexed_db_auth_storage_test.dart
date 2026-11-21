// IndexedDbAuthStorage and BestWebAuthStorage in a browser: the round trip, the order of the calls,
// a database deleted between calls, the retries, the time limits, the move from localStorage, the
// writes made without IndexedDB and the fallback when IndexedDB is unavailable. No emulator.
//
// Some tests replace methods of the IndexedDB prototypes for one call (see _patch) to reach
// failures a browser does not produce on demand.
//
//     dart test -p chrome test/browser/indexed_db_auth_storage_test.dart               # dart2js
//     dart test -p chrome -c dart2wasm test/browser/indexed_db_auth_storage_test.dart  # dart2wasm

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// What goes before the `localStorage` keys of this file. The browser test files run side by side
/// on one origin and share `localStorage`, so each file uses and cleans its own keys only.
const String _p = 'idb_auth_storage_test:';

/// The `localStorage` keys of this file.
List<String> _ownKeys() => <String>[
  for (int i = 0; i < web.window.localStorage.length; i++)
    if (web.window.localStorage.key(i) case final String key
        when key.startsWith(_p))
      key,
];

void _clearOwnKeys() {
  for (final String key in _ownKeys()) {
    web.window.localStorage.removeItem(key);
  }
}

int _databases = 0;

/// The databases the current test used, deleted after it.
final List<String> _used = <String>[];

/// The undo functions of the prototype patches of the current test, called after it.
final List<JSFunction> _patches = <JSFunction>[];

/// A database name of its own for each test.
String _newDatabase() {
  final String name =
      'idb_auth_storage_test_${DateTime.now().microsecondsSinceEpoch}_${_databases++}';
  _used.add(name);
  return name;
}

Future<void> _deleteDatabase(String name) {
  final Completer<void> done = Completer<void>();
  final web.IDBOpenDBRequest request = web.window.indexedDB.deleteDatabase(
    name,
  );
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('deleteDatabase($name) failed'),
  )).toJS;
  return done.future;
}

/// Opens [databaseName] at the version of the storage without the storage, creating the object
/// stores [stores] when it creates the database. The connection ignores `versionchange`, so it
/// blocks a delete until it is closed.
Future<web.IDBDatabase> _openRaw(
  String databaseName, {
  List<String> stores = const <String>[IndexedDbAuthStorage.objectStoreName],
}) {
  final Completer<web.IDBDatabase> opened = Completer<web.IDBDatabase>();
  final web.IDBOpenDBRequest open = web.window.indexedDB.open(
    databaseName,
    IndexedDbAuthStorage.databaseVersion,
  );
  open.onupgradeneeded = ((web.Event _) {
    final web.IDBDatabase db = open.result as web.IDBDatabase;
    for (final String store in stores) {
      db.createObjectStore(store);
    }
  }).toJS;
  open.onsuccess = ((web.Event _) => opened.complete(
    open.result as web.IDBDatabase,
  )).toJS;
  open.onerror = ((web.Event _) => opened.completeError(
    StateError('open failed'),
  )).toJS;
  return opened.future;
}

/// Writes [value] under [key] in the store of [databaseName] without the storage, for an entry it
/// did not write.
Future<void> _putRaw(String databaseName, String key, JSAny value) async {
  final web.IDBDatabase db = await _openRaw(databaseName);
  final Completer<void> done = Completer<void>();
  final web.IDBTransaction transaction = db.transaction(
    IndexedDbAuthStorage.objectStoreName.toJS,
    'readwrite',
  );
  transaction
      .objectStore(IndexedDbAuthStorage.objectStoreName)
      .put(value, key.toJS);
  transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
  transaction.onabort = ((web.Event _) => done.completeError(
    StateError('put failed'),
  )).toJS;
  await done.future;
  db.close();
}

/// Calls the JS function [source], which patches a prototype and returns the function that
/// undoes it; the undo runs after the test.
void _patch(String source) {
  final JSFunction undo = globalContext.callMethod<JSFunction>(
    'eval'.toJS,
    '($source)()'.toJS,
  );
  _patches.add(undo);
}

/// The first [times] calls of `IDBDatabase.prototype.transaction` throw an `InvalidStateError`,
/// as on a connection that closed before the storage heard of it.
void _transactionThrows(int times) => _patch('''
(function () {
  const proto = IDBDatabase.prototype;
  const original = proto.transaction;
  let left = $times;
  proto.transaction = function (...args) {
    if (left > 0) {
      left--;
      throw new DOMException('closed under the storage', 'InvalidStateError');
    }
    return original.apply(this, args);
  };
  return function () { proto.transaction = original; };
})''');

/// The first [times] requests (get, put, delete) abort their transaction from script right after
/// they are made: the abort carries no error of its own, as when the browser closes a connection.
void _requestsAbort(int times) => _patch('''
(function () {
  const proto = IDBObjectStore.prototype;
  const originals = {};
  let left = $times;
  for (const name of ['get', 'put', 'delete']) {
    originals[name] = proto[name];
    proto[name] = function (...args) {
      const request = originals[name].apply(this, args);
      if (left > 0) {
        left--;
        this.transaction.abort();
      }
      return request;
    };
  }
  return function () {
    for (const name of ['get', 'put', 'delete']) { proto[name] = originals[name]; }
  };
})''');

/// Counts the calls of `indexedDB.open` for [databaseName] in the returned list's first element.
List<int> _countOpens(String databaseName) {
  final List<int> count = <int>[0];
  final JSFunction counter = ((JSString name) {
    if (name.toDart == databaseName) {
      count[0]++;
    }
  }).toJS;
  globalContext['__countOpen'] = counter;
  _patch('''
(function () {
  const proto = IDBFactory.prototype;
  const original = proto.open;
  proto.open = function (...args) {
    globalThis.__countOpen(String(args[0]));
    return original.apply(this, args);
  };
  return function () { proto.open = original; delete globalThis.__countOpen; };
})''');
  return count;
}

/// Makes `indexedDB` of the window null, as in a context without IndexedDB.
void _hideIndexedDb() => _patch('''
(function () {
  let owner = globalThis;
  while (!Object.getOwnPropertyDescriptor(owner, 'indexedDB')) {
    owner = Object.getPrototypeOf(owner);
  }
  const original = Object.getOwnPropertyDescriptor(owner, 'indexedDB');
  Object.defineProperty(globalThis, 'indexedDB', { value: null, configurable: true });
  return function () {
    if (owner === globalThis) {
      Object.defineProperty(globalThis, 'indexedDB', original);
    } else {
      delete globalThis.indexedDB;
    }
  };
})''');

/// Keeps a readwrite transaction on the store of [databaseName] busy (one get after another) until
/// the returned function is called.
Future<void Function()> _holdStore(String databaseName) async {
  final web.IDBDatabase db = await _openRaw(databaseName);
  bool held = true;
  final web.IDBObjectStore store = db
      .transaction(IndexedDbAuthStorage.objectStoreName.toJS, 'readwrite')
      .objectStore(IndexedDbAuthStorage.objectStoreName);
  void next() {
    final web.IDBRequest request = store.get('busy'.toJS);
    request.onsuccess = ((web.Event _) {
      if (held) {
        next();
      }
    }).toJS;
  }

  next();
  void release() {
    held = false;
    db.close();
  }

  // Also after a failure, so that the deletion of the database after the test is not blocked.
  addTearDown(release);
  return release;
}

/// A connection that ignores `versionchange` and a deletion of [databaseName] waiting for it: an
/// open of the database waits behind that deletion until the returned function closes it.
Future<void Function()> _blockOpens(String databaseName) async {
  final web.IDBDatabase holder = await _openRaw(databaseName);
  final Completer<void> blocked = Completer<void>();
  final web.IDBOpenDBRequest deletion = web.window.indexedDB.deleteDatabase(
    databaseName,
  );
  deletion.onblocked = ((web.Event _) => blocked.complete()).toJS;
  await blocked.future;
  // Also after a failure, so that the deletion of the database after the test is not blocked.
  void release() => holder.close();
  addTearDown(release);
  return release;
}

TypeMatcher<IndexedDbAuthStorageException> _storageError(
  IndexedDbOperation operation, {
  String? name,
}) => isA<IndexedDbAuthStorageException>()
    .having(
      (IndexedDbAuthStorageException e) => e.operation,
      'operation',
      operation,
    )
    .having(
      (IndexedDbAuthStorageException e) => e.name,
      'name',
      name ?? anything,
    );

/// The `localStorage` of the tests, whose read or delete can be made to throw.
class _FlakyLocal extends WebAuthStorage {
  _FlakyLocal() : super.local(prefix: _p);

  bool readThrows = false;
  bool deleteThrows = false;

  @override
  String? read(String key) {
    if (readThrows) {
      throw StateError('localStorage read refused');
    }
    return super.read(key);
  }

  @override
  void write(String key, String? value) {
    if (value == null && deleteThrows) {
      throw StateError('localStorage delete refused');
    }
    super.write(key, value);
  }
}

/// An IndexedDB storage whose read after a write returns another value once, as if another context
/// had written in between.
class _OverwrittenIndexedDb extends IndexedDbAuthStorage {
  _OverwrittenIndexedDb(String databaseName)
    : super(databaseName: databaseName);

  bool _written = false;
  bool _lied = false;

  @override
  Future<void> write(String key, String? value) {
    _written = value != null;
    return super.write(key, value);
  }

  @override
  Future<String?> read(String key) async {
    final String? stored = await super.read(key);
    if (_written && !_lied) {
      _lied = true;
      return 'written by someone else';
    }
    return stored;
  }
}

void main() {
  final List<IndexedDbAuthStorage> open = <IndexedDbAuthStorage>[];

  IndexedDbAuthStorage newStorage(
    String databaseName, {
    Duration requestTimeout = IndexedDbAuthStorage.defaultRequestTimeout,
  }) {
    final IndexedDbAuthStorage storage = IndexedDbAuthStorage(
      databaseName: databaseName,
      requestTimeout: requestTimeout,
    );
    open.add(storage);
    return storage;
  }

  tearDown(() async {
    for (final JSFunction undo in _patches.reversed) {
      undo.callAsFunction();
    }
    _patches.clear();
    for (final IndexedDbAuthStorage storage in open) {
      await storage.close();
    }
    open.clear();
    for (final String name in _used) {
      await _deleteDatabase(name);
    }
    _used.clear();
    _clearOwnKeys();
  });

  group('IndexedDbAuthStorage', () {
    _roundTripTests(newStorage);
    _retryTests(newStorage);
    _limitTests(newStorage);
    _databaseTests(newStorage);
  });

  group('BestWebAuthStorage', () {
    _choiceTests(newStorage);
    _migrationTests(newStorage);
    _fallbackWriteTests(newStorage);
  });
}

typedef _NewStorage =
    IndexedDbAuthStorage Function(
      String databaseName, {
      Duration requestTimeout,
    });

void _roundTripTests(_NewStorage newStorage) {
  test('is available in this browser; an empty name is not', () async {
    expect(
      await IndexedDbAuthStorage.isAvailable(databaseName: _newDatabase()),
      isTrue,
    );
    expect(await IndexedDbAuthStorage.isAvailable(databaseName: ''), isFalse);
  });

  test('the probe leaves nothing behind', () async {
    final String name = _newDatabase();
    expect(await IndexedDbAuthStorage.isAvailable(databaseName: name), isTrue);
    expect(await newStorage(name).read(IndexedDbAuthStorage.probeKey), isNull);
  });

  test('stores, reads and overwrites a value', () async {
    final IndexedDbAuthStorage storage = newStorage(_newDatabase());
    expect(await storage.read('k'), isNull);
    await storage.write('k', 'v1');
    expect(await storage.read('k'), 'v1');
    await storage.write('k', 'v2');
    expect(await storage.read('k'), 'v2');
  });

  test('null deletes the value', () async {
    final IndexedDbAuthStorage storage = newStorage(_newDatabase());
    await storage.write('k', 'v');
    await storage.write('k', null);
    expect(await storage.read('k'), isNull);
    // Deleting a missing key is not an error.
    await storage.write('k', null);
    expect(await storage.read('k'), isNull);
  });

  test('two keys are kept apart', () async {
    final IndexedDbAuthStorage storage = newStorage(_newDatabase());
    await storage.write('a', 'va');
    await storage.write('b', 'vb');
    expect(await storage.read('a'), 'va');
    expect(await storage.read('b'), 'vb');
    await storage.write('a', null);
    expect(await storage.read('a'), isNull);
    expect(await storage.read('b'), 'vb');
  });

  test('a new instance reads what an earlier one wrote', () async {
    final String name = _newDatabase();
    final IndexedDbAuthStorage first = newStorage(name);
    await first.write('k', 'v');
    // While the first connection is open, and after it closed.
    expect(await newStorage(name).read('k'), 'v');
    await first.close();
    expect(await newStorage(name).read('k'), 'v');
    // Another database does not see it.
    expect(await newStorage(_newDatabase()).read('k'), isNull);
  });

  test('calls made without waiting are applied in order', () async {
    final IndexedDbAuthStorage storage = newStorage(_newDatabase());
    final List<Future<Object?>> calls = <Future<Object?>>[
      storage.write('k', 'a'),
      storage.read('k'),
      storage.write('k', 'b'),
      storage.read('k'),
      storage.write('k', null),
      storage.read('k'),
      storage.write('k', 'c'),
      storage.read('k'),
    ];
    final List<Object?> results = await Future.wait(calls);
    expect(
      <Object?>[results[1], results[3], results[5], results[7]],
      <Object?>['a', 'b', null, 'c'],
    );
    expect(await newStorage(storage.databaseName).read('k'), 'c');
  });

  // What this shows: once the future of a write completed, a new connection reads the value. It
  // does not show that the write waits for the transaction's complete event rather than the
  // request's success: IndexedDB orders the readonly transaction of the second connection after
  // the readwrite one either way, and no public API aborts a transaction after its request
  // succeeded.
  test('another connection reads a write once its future completed', () async {
    final String name = _newDatabase();
    final IndexedDbAuthStorage storage = newStorage(name);
    await storage.write('k', 'v');
    expect(await newStorage(name).read('k'), 'v');
  });

  test('works again after close', () async {
    final IndexedDbAuthStorage storage = newStorage(_newDatabase());
    await storage.write('k', 'v');
    await storage.close();
    expect(await storage.read('k'), 'v');
  });

  test(
    'an entry that is not a string fails the read without its value',
    () async {
      final String name = _newDatabase();
      final IndexedDbAuthStorage storage = newStorage(name);
      await storage.write('other', 'x'); // creates the database and store
      await _putRaw(name, 'k', <JSString>['s3cret-value'.toJS].toJS);
      await expectLater(
        storage.read('k'),
        throwsA(
          _storageError(IndexedDbOperation.read)
              .having((IndexedDbAuthStorageException e) => e.key, 'key', 'k')
              .having(
                (IndexedDbAuthStorageException e) => '$e',
                'toString()',
                isNot(contains('s3cret-value')),
              ),
        ),
      );
      // The failure does not stop the calls behind it.
      expect(await storage.read('other'), 'x');
    },
  );
}

void _retryTests(_NewStorage newStorage) {
  test('a database deleted between two calls is opened again', () async {
    final String name = _newDatabase();
    final IndexedDbAuthStorage storage = newStorage(name);
    await storage.write('k', 'v');
    // The open connection closes on versionchange, so the delete is not blocked.
    await _deleteDatabase(name);
    expect(await storage.read('k'), isNull);
    await storage.write('k', 'w');
    expect(await storage.read('k'), 'w');
    expect(await newStorage(name).read('k'), 'w');
  });

  test(
    'a connection found closed when the transaction starts is opened again once',
    () async {
      final String name = _newDatabase();
      final IndexedDbAuthStorage storage = newStorage(name);
      await storage.write('k', 'v');
      _transactionThrows(1);
      expect(await storage.read('k'), 'v');
      _transactionThrows(2);
      // Twice in a row: the second failure is thrown, with the browser's name and message.
      await expectLater(
        storage.write('k', 'w'),
        throwsA(
          _storageError(
            IndexedDbOperation.write,
            name: 'InvalidStateError',
          ).having(
            (IndexedDbAuthStorageException e) => e.message,
            'message',
            'closed under the storage',
          ),
        ),
      );
      expect(await storage.read('k'), 'v');
    },
  );

  test('a transaction aborted without an error is tried again once', () async {
    final String name = _newDatabase();
    final IndexedDbAuthStorage storage = newStorage(name);
    await storage.write('k', 'v');
    _requestsAbort(1);
    await storage.write('k', 'w');
    expect(await storage.read('k'), 'w');
    _requestsAbort(2);
    await expectLater(
      storage.read('k'),
      throwsA(_storageError(IndexedDbOperation.read, name: 'AbortError')),
    );
    expect(await storage.read('k'), 'w');
  });
}

void _limitTests(_NewStorage newStorage) {
  test(
    'an open that does not finish in time fails, and the calls behind it go on',
    () async {
      final String name = _newDatabase();
      final void Function() release = await _blockOpens(name);
      final IndexedDbAuthStorage storage = newStorage(
        name,
        requestTimeout: const Duration(milliseconds: 200),
      );
      final Future<void> write = storage.write('k', 'v');
      final Future<String?> read = storage.read('k');
      await expectLater(
        write,
        throwsA(
          isA<IndexedDbTimeoutException>()
              .having(
                (IndexedDbTimeoutException e) => e.operation,
                'operation',
                IndexedDbOperation.open,
              )
              .having(
                (IndexedDbTimeoutException e) => e.name,
                'name',
                'TimeoutError',
              ),
        ),
      );
      await expectLater(read, throwsA(isA<IndexedDbTimeoutException>()));
      release();
      // The deletion runs, the late opens are closed, and the next call opens the database again.
      expect(await storage.read('k'), isNull);
      await storage.write('k', 'w');
      expect(await storage.read('k'), 'w');
    },
  );

  test('a transaction that does not finish in time is aborted', () async {
    final String name = _newDatabase();
    final IndexedDbAuthStorage storage = newStorage(
      name,
      requestTimeout: const Duration(milliseconds: 200),
    );
    await storage.write('k', 'v');
    final void Function() release = await _holdStore(name);
    await expectLater(
      storage.write('k', 'w'),
      throwsA(
        isA<IndexedDbTimeoutException>().having(
          (IndexedDbTimeoutException e) => e.operation,
          'operation',
          IndexedDbOperation.write,
        ),
      ),
    );
    release();
    // Aborted: the value did not change.
    expect(await storage.read('k'), 'v');
  });

  test('isAvailable is false when the probe does not finish in time', () async {
    final String name = _newDatabase();
    final void Function() release = await _blockOpens(name);
    final Stopwatch watch = Stopwatch()..start();
    expect(
      await IndexedDbAuthStorage.isAvailable(
        databaseName: name,
        timeout: const Duration(milliseconds: 200),
      ),
      isFalse,
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    release();
  });

  test('a time limit that is not positive is refused', () {
    expect(
      () => IndexedDbAuthStorage(requestTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}

void _databaseTests(_NewStorage newStorage) {
  test(
    'without IndexedDB: unavailable, and a call fails at the open',
    () async {
      _hideIndexedDb();
      expect(
        await IndexedDbAuthStorage.isAvailable(databaseName: _newDatabase()),
        isFalse,
      );
      await expectLater(
        newStorage(_newDatabase()).read('k'),
        throwsA(_storageError(IndexedDbOperation.open)),
      );
      final BestWebAuthStorage best = BestWebAuthStorage(
        localStoragePrefix: _p,
        databaseName: _newDatabase(),
      );
      expect(await best.kind, WebAuthStorageKind.localStorage);
      await best.write('k', 'v');
      expect(await best.read('k'), 'v');
    },
  );

  test('the default database without the store is created again', () async {
    _used.add(IndexedDbAuthStorage.defaultDatabaseName);
    await _deleteDatabase(IndexedDbAuthStorage.defaultDatabaseName);
    (await _openRaw(
      IndexedDbAuthStorage.defaultDatabaseName,
      stores: <String>[],
    )).close();
    final IndexedDbAuthStorage storage = newStorage(
      IndexedDbAuthStorage.defaultDatabaseName,
    );
    await storage.write('k', 'v');
    expect(await storage.read('k'), 'v');
  });

  test('a database of another name without the store is left alone', () async {
    final String name = _newDatabase();
    (await _openRaw(name, stores: <String>['theirs'])).close();
    await expectLater(
      newStorage(name).write('k', 'v'),
      throwsA(_storageError(IndexedDbOperation.open)),
    );
    final web.IDBDatabase db = await _openRaw(name, stores: <String>[]);
    expect(db.objectStoreNames.contains('theirs'), isTrue);
    expect(
      db.objectStoreNames.contains(IndexedDbAuthStorage.objectStoreName),
      isFalse,
    );
    db.close();
  });

  test('a deletion blocked by another connection fails at once', () async {
    _used.add(IndexedDbAuthStorage.defaultDatabaseName);
    await _deleteDatabase(IndexedDbAuthStorage.defaultDatabaseName);
    final web.IDBDatabase holder = await _openRaw(
      IndexedDbAuthStorage.defaultDatabaseName,
      stores: <String>[],
    );
    final IndexedDbAuthStorage storage = newStorage(
      IndexedDbAuthStorage.defaultDatabaseName,
      requestTimeout: const Duration(seconds: 20),
    );
    final Stopwatch watch = Stopwatch()..start();
    await expectLater(
      storage.write('k', 'v'),
      throwsA(_storageError(IndexedDbOperation.open, name: 'BlockedError')),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    holder.close();
  });
}

void _choiceTests(_NewStorage newStorage) {
  test(
    'chooses IndexedDB in this browser, probing on its own connection',
    () async {
      final String name = _newDatabase();
      final List<int> opens = _countOpens(name);
      final BestWebAuthStorage storage = BestWebAuthStorage(
        localStoragePrefix: _p,
        databaseName: name,
      );
      expect(await storage.kind, WebAuthStorageKind.indexedDb);
      await storage.write('k', 'v');
      expect(await storage.read('k'), 'v');
      expect(opens[0], 1);
      await storage.close();
      expect(await newStorage(name).read('k'), 'v');
      expect(
        await newStorage(name).read(IndexedDbAuthStorage.probeKey),
        isNull,
      );
      expect(web.window.localStorage.getItem('${_p}k'), isNull);
    },
  );

  test('keys of other prefixes stay in localStorage', () async {
    web.window.localStorage.setItem('${_p}other:k', 'theirs');
    final BestWebAuthStorage storage = BestWebAuthStorage(
      databaseName: _newDatabase(),
      localStoragePrefix: '${_p}app:',
    );
    expect(storage.localStoragePrefix, '${_p}app:');
    expect(await storage.read('k'), isNull);
    expect(web.window.localStorage.getItem('${_p}other:k'), 'theirs');
  });

  test('falls back to localStorage without IndexedDB', () async {
    final String name = _newDatabase();
    final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
      localStoragePrefix: _p,
      databaseName: name,
      indexedDbAvailable: () async => false,
    );
    expect(await storage.kind, WebAuthStorageKind.localStorage);
    await storage.write('k', 'v');
    expect(web.window.localStorage.getItem('${_p}k'), 'v');
    expect(await storage.read('k'), 'v');
    expect(await newStorage(name).read('k'), isNull);
    await storage.write('k', null);
    expect(web.window.localStorage.getItem('${_p}k'), isNull);
  });

  test('a check that throws counts as unavailable', () async {
    final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
      localStoragePrefix: _p,
      databaseName: _newDatabase(),
      indexedDbAvailable: () => Future<bool>.error(StateError('boom')),
    );
    expect(await storage.kind, WebAuthStorageKind.localStorage);
  });

  test('falls back to memory without IndexedDB and localStorage', () async {
    final String name = _newDatabase();
    final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
      localStoragePrefix: _p,
      databaseName: name,
      indexedDbAvailable: () async => false,
      localStorageAvailable: () => false,
    );
    expect(await storage.kind, WebAuthStorageKind.memory);
    await storage.write('k', 'v');
    expect(await storage.read('k'), 'v');
    expect(web.window.localStorage.getItem('${_p}k'), isNull);
    expect(await newStorage(name).read('k'), isNull);
    // Memory belongs to the object.
    expect(
      await BestWebAuthStorage.forTesting(
        localStoragePrefix: _p,
        databaseName: name,
        indexedDbAvailable: () async => false,
        localStorageAvailable: () => false,
      ).read('k'),
      isNull,
    );
  });

  test('decides once', () async {
    int checks = 0;
    final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
      localStoragePrefix: _p,
      databaseName: _newDatabase(),
      indexedDbAvailable: () async {
        checks++;
        return false;
      },
    );
    await Future.wait(<Future<Object?>>[
      storage.read('a'),
      storage.write('b', 'v'),
      storage.kind,
    ]);
    await storage.read('b');
    expect(checks, 1);
  });

  test('a FirebaseUserAuth restores its session from it', () async {
    final String name = _newDatabase();
    await newStorage(name).write(
      'firebase_auth_providers_dart:key',
      '{"version":2,"uid":"u1","refreshToken":"r"}',
    );
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'key',
      storage: BestWebAuthStorage(localStoragePrefix: _p, databaseName: name),
    );
    await auth.restore();
    expect(auth.uid, 'u1');
    await auth.signOut();
    expect(
      await newStorage(name).read('firebase_auth_providers_dart:key'),
      isNull,
    );
    await auth.dispose();
  });
}

void _migrationTests(_NewStorage newStorage) {
  test('moves a session from localStorage to IndexedDB', () async {
    final String name = _newDatabase();
    web.window.localStorage.setItem('${_p}app:k', 'old');
    final BestWebAuthStorage storage = BestWebAuthStorage(
      databaseName: name,
      localStoragePrefix: '${_p}app:',
    );
    expect(await storage.read('k'), 'old');
    expect(web.window.localStorage.getItem('${_p}app:k'), isNull);
    expect(await newStorage(name).read('k'), 'old');
    // Read again: from IndexedDB.
    expect(await storage.read('k'), 'old');
  });

  test(
    'a session IndexedDB already has wins over an unmarked localStorage copy',
    () async {
      final String name = _newDatabase();
      await newStorage(name).write('k', 'new');
      web.window.localStorage.setItem('${_p}k', 'old');
      final BestWebAuthStorage storage = BestWebAuthStorage(
        localStoragePrefix: _p,
        databaseName: name,
      );
      expect(await storage.read('k'), 'new');
      expect(await newStorage(name).read('k'), 'new');
      // The stale copy is deleted.
      expect(web.window.localStorage.getItem('${_p}k'), isNull);
    },
  );

  test('a sign-out deletes the key from localStorage too', () async {
    final String name = _newDatabase();
    final BestWebAuthStorage storage = BestWebAuthStorage(
      localStoragePrefix: _p,
      databaseName: name,
    );
    await storage.write('k', 'v');
    web.window.localStorage.setItem('${_p}k', 'stale');
    await storage.write('k', null);
    expect(web.window.localStorage.getItem('${_p}k'), isNull);
    expect(await storage.read('k'), isNull);
  });

  test(
    'a copy read back that differs fails the move and keeps localStorage',
    () async {
      final String name = _newDatabase();
      web.window.localStorage.setItem('${_p}k', 'old');
      final List<String> issues = <String>[];
      final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
        localStoragePrefix: _p,
        indexedDb: _OverwrittenIndexedDb(name),
        indexedDbAvailable: () async => true,
        onMigrationIssue: (String key, Object _) => issues.add(key),
      );
      await expectLater(
        storage.read('k'),
        throwsA(_storageError(IndexedDbOperation.migrate)),
      );
      expect(web.window.localStorage.getItem('${_p}k'), 'old');
      expect(await newStorage(name).read('k'), isNull);
      expect(issues, isEmpty);
      // The next read tries again.
      expect(await storage.read('k'), 'old');
      expect(web.window.localStorage.getItem('${_p}k'), isNull);
      await storage.close();
    },
  );

  test(
    'a localStorage that cannot be read gives null and reports it',
    () async {
      final String name = _newDatabase();
      web.window.localStorage.setItem('${_p}k', 'old');
      final List<(String, Object)> issues = <(String, Object)>[];
      final _FlakyLocal local = _FlakyLocal()..readThrows = true;
      final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
        databaseName: name,
        localStorage: local,
        onMigrationIssue: (String key, Object error) =>
            issues.add((key, error)),
      );
      expect(await storage.read('k'), isNull);
      expect(issues, hasLength(1));
      expect(issues.single.$1, 'k');
      expect(issues.single.$2, isA<StateError>());
      expect(await newStorage(name).read('k'), isNull);
      await storage.close();
    },
  );

  test(
    'a localStorage that cannot delete keeps a copy and reports it',
    () async {
      final String name = _newDatabase();
      web.window.localStorage.setItem('${_p}k', 'old');
      final List<String> issues = <String>[];
      final _FlakyLocal local = _FlakyLocal()..deleteThrows = true;
      final BestWebAuthStorage storage = BestWebAuthStorage.forTesting(
        databaseName: name,
        localStorage: local,
        onMigrationIssue: (String key, Object error) =>
            issues.add('$key: $error'),
      );
      expect(await storage.read('k'), 'old');
      expect(await newStorage(name).read('k'), 'old');
      expect(web.window.localStorage.getItem('${_p}k'), 'old');
      expect(issues, <String>['k: Bad state: localStorage delete refused']);
      // The report names the key and the error, never the session.
      expect(issues.single, isNot(contains('old')));
      await storage.close();
    },
  );
}

void _fallbackWriteTests(_NewStorage newStorage) {
  /// A storage that falls back to localStorage on [name], as on a load where the probe failed.
  BestWebAuthStorage fallback(String name) => BestWebAuthStorage.forTesting(
    localStoragePrefix: _p,
    databaseName: name,
    indexedDbAvailable: () async => false,
  );

  test('a write without IndexedDB deletes its older copy there', () async {
    final String name = _newDatabase();
    await newStorage(name).write('k', 'A');
    final BestWebAuthStorage storage = fallback(name);
    await storage.write('k', 'B');
    // Waits for the deletion it started.
    await storage.close();
    expect(await newStorage(name).read('k'), isNull);
  });

  test(
    'a sign-out without IndexedDB is kept at the next load with IndexedDB',
    () async {
      final String name = _newDatabase();
      final BestWebAuthStorage first = fallback(name);
      await first.write('k', null);
      await first.close();
      // The deletion in IndexedDB did not happen (it failed, or another tab wrote): the marker
      // decides.
      await newStorage(name).write('k', 'A');
      final BestWebAuthStorage next = BestWebAuthStorage(
        localStoragePrefix: _p,
        databaseName: name,
      );
      expect(await next.read('k'), isNull);
      expect(await newStorage(name).read('k'), isNull);
      expect(_ownKeys(), isEmpty);
      await next.close();
    },
  );

  test(
    'a sign-in without IndexedDB wins over an older IndexedDB session',
    () async {
      final String name = _newDatabase();
      final BestWebAuthStorage first = fallback(name);
      await first.write('k', 'B');
      await first.close();
      await newStorage(name).write('k', 'A');
      final BestWebAuthStorage next = BestWebAuthStorage(
        localStoragePrefix: _p,
        databaseName: name,
      );
      expect(await next.read('k'), 'B');
      expect(await newStorage(name).read('k'), 'B');
      // Moved: neither the copy nor the marker stays in localStorage.
      expect(_ownKeys(), isEmpty);
      // From now on IndexedDB wins again.
      await newStorage(name).write('k', 'C');
      expect(await next.read('k'), 'C');
      await next.close();
    },
  );

  test(
    'a write with IndexedDB clears the marker of an earlier write without it',
    () async {
      final String name = _newDatabase();
      final BestWebAuthStorage first = fallback(name);
      await first.write('k', 'B');
      await first.close();
      final BestWebAuthStorage next = BestWebAuthStorage(
        localStoragePrefix: _p,
        databaseName: name,
      );
      await next.write('k', 'C');
      expect(_ownKeys(), isEmpty);
      expect(await next.read('k'), 'C');
      await next.close();
    },
  );
}
