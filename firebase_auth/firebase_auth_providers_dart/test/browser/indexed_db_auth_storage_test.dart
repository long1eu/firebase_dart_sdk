// IndexedDbAuthStorage and BestWebAuthStorage in a browser: the round trip, the order of the calls, a database
// deleted between calls, the move from localStorage and the fallback when IndexedDB is unavailable. No emulator.
//
//     dart test -p chrome test/browser/indexed_db_auth_storage_test.dart                 # dart2js
//     dart test -p chrome -c dart2wasm test/browser/indexed_db_auth_storage_test.dart    # dart2wasm

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

int _databases = 0;

/// The databases the current test used, deleted after it.
final List<String> _used = <String>[];

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

/// Writes [value] under [key] in the store of [databaseName] without the storage, for an entry it did not write.
Future<void> _putRaw(String databaseName, String key, JSAny value) async {
  final Completer<web.IDBDatabase> opened = Completer<web.IDBDatabase>();
  final web.IDBOpenDBRequest open = web.window.indexedDB.open(
    databaseName,
    IndexedDbAuthStorage.databaseVersion,
  );
  open.onsuccess = ((web.Event _) => opened.complete(
    open.result as web.IDBDatabase,
  )).toJS;
  open.onerror = ((web.Event _) => opened.completeError(
    StateError('open failed'),
  )).toJS;
  final web.IDBDatabase db = await opened.future;
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

void main() {
  final List<IndexedDbAuthStorage> open = <IndexedDbAuthStorage>[];

  IndexedDbAuthStorage newStorage(String databaseName) {
    final IndexedDbAuthStorage storage = IndexedDbAuthStorage(
      databaseName: databaseName,
    );
    open.add(storage);
    return storage;
  }

  tearDown(() async {
    for (final IndexedDbAuthStorage storage in open) {
      await storage.close();
    }
    open.clear();
    for (final String name in _used) {
      await _deleteDatabase(name);
    }
    _used.clear();
    web.window.localStorage.clear();
  });

  group('IndexedDbAuthStorage', () {
    test('is available in this browser; an empty name is not', () async {
      expect(
        await IndexedDbAuthStorage.isAvailable(databaseName: _newDatabase()),
        isTrue,
      );
      expect(await IndexedDbAuthStorage.isAvailable(databaseName: ''), isFalse);
    });

    test('the probe leaves nothing behind', () async {
      final String name = _newDatabase();
      expect(
        await IndexedDbAuthStorage.isAvailable(databaseName: name),
        isTrue,
      );
      expect(
        await newStorage(name).read(IndexedDbAuthStorage.probeKey),
        isNull,
      );
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

    test('a write is complete when its future completes', () async {
      final String name = _newDatabase();
      final IndexedDbAuthStorage storage = newStorage(name);
      await storage.write('k', 'v');
      // Another connection sees it at once.
      expect(await newStorage(name).read('k'), 'v');
    });

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
            isA<IndexedDbAuthStorageException>()
                .having(
                  (IndexedDbAuthStorageException e) => e.operation,
                  'operation',
                  IndexedDbOperation.read,
                )
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
  });

  group('BestWebAuthStorage', () {
    test('chooses IndexedDB in this browser', () async {
      final String name = _newDatabase();
      final BestWebAuthStorage storage = BestWebAuthStorage(databaseName: name);
      expect(await storage.kind, WebAuthStorageKind.indexedDb);
      await storage.write('k', 'v');
      expect(await newStorage(name).read('k'), 'v');
      expect(web.window.localStorage.getItem('k'), isNull);
    });

    test('moves a session from localStorage to IndexedDB', () async {
      final String name = _newDatabase();
      web.window.localStorage.setItem('app:k', 'old');
      final BestWebAuthStorage storage = BestWebAuthStorage(
        databaseName: name,
        localStoragePrefix: 'app:',
      );
      expect(await storage.read('k'), 'old');
      expect(web.window.localStorage.getItem('app:k'), isNull);
      expect(await newStorage(name).read('k'), 'old');
      // Read again: from IndexedDB.
      expect(await storage.read('k'), 'old');
    });

    test('a session IndexedDB already has wins over localStorage', () async {
      final String name = _newDatabase();
      await newStorage(name).write('k', 'new');
      web.window.localStorage.setItem('k', 'old');
      final BestWebAuthStorage storage = BestWebAuthStorage(databaseName: name);
      expect(await storage.read('k'), 'new');
      expect(await newStorage(name).read('k'), 'new');
      // The stale copy is deleted.
      expect(web.window.localStorage.getItem('k'), isNull);
    });

    test('a sign-out deletes the key from localStorage too', () async {
      final String name = _newDatabase();
      final BestWebAuthStorage storage = BestWebAuthStorage(databaseName: name);
      await storage.write('k', 'v');
      web.window.localStorage.setItem('k', 'stale');
      await storage.write('k', null);
      expect(web.window.localStorage.getItem('k'), isNull);
      expect(await storage.read('k'), isNull);
    });

    test('keys of other prefixes stay in localStorage', () async {
      web.window.localStorage.setItem('other:k', 'theirs');
      final BestWebAuthStorage storage = BestWebAuthStorage(
        databaseName: _newDatabase(),
        localStoragePrefix: 'app:',
      );
      expect(await storage.read('k'), isNull);
      expect(web.window.localStorage.getItem('other:k'), 'theirs');
    });

    test('falls back to localStorage without IndexedDB', () async {
      final String name = _newDatabase();
      final BestWebAuthStorage storage = BestWebAuthStorage(
        databaseName: name,
        indexedDbAvailable: () async => false,
      );
      expect(await storage.kind, WebAuthStorageKind.localStorage);
      await storage.write('k', 'v');
      expect(web.window.localStorage.getItem('k'), 'v');
      expect(await storage.read('k'), 'v');
      expect(await newStorage(name).read('k'), isNull);
      await storage.write('k', null);
      expect(web.window.localStorage.getItem('k'), isNull);
    });

    test('a check that throws counts as unavailable', () async {
      final BestWebAuthStorage storage = BestWebAuthStorage(
        databaseName: _newDatabase(),
        indexedDbAvailable: () => Future<bool>.error(StateError('boom')),
      );
      expect(await storage.kind, WebAuthStorageKind.localStorage);
    });

    test('falls back to memory without IndexedDB and localStorage', () async {
      final String name = _newDatabase();
      final BestWebAuthStorage storage = BestWebAuthStorage(
        databaseName: name,
        indexedDbAvailable: () async => false,
        localStorageAvailable: () => false,
      );
      expect(await storage.kind, WebAuthStorageKind.memory);
      await storage.write('k', 'v');
      expect(await storage.read('k'), 'v');
      expect(web.window.localStorage.getItem('k'), isNull);
      expect(await newStorage(name).read('k'), isNull);
      // Memory belongs to the object.
      expect(
        await BestWebAuthStorage(
          databaseName: name,
          indexedDbAvailable: () async => false,
          localStorageAvailable: () => false,
        ).read('k'),
        isNull,
      );
    });

    test('decides once', () async {
      int checks = 0;
      final BestWebAuthStorage storage = BestWebAuthStorage(
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
        storage: BestWebAuthStorage(databaseName: name),
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
  });
}
