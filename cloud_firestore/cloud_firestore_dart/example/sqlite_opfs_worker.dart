// The dedicated worker that keeps the database of the OPFS storage of
// sqlite_database_web.dart (`sqliteWebOpener(opfsWorker: ...)`).
//
// EXPERIMENTAL. Copy it into your app next to sqlite_database_web.dart and
// compile it to JavaScript, once per release of your app:
//
//     dart compile js -O2 -o web/sqlite_opfs_worker.js sqlite_opfs_worker.dart
//
// Then pass the URL of the compiled file to the opener (relative URLs are
// resolved against the page):
//
//     sqliteWebOpener(
//       sqlite3Wasm: Uri.parse('sqlite3.wasm'),
//       opfsWorker: Uri.parse('sqlite_opfs_worker.js'),
//     )
//
// Why a worker: SQLite reads and writes its files synchronously. The origin
// private file system (OPFS) has synchronous file access only through
// `FileSystemSyncAccessHandle`, and only in dedicated workers. This worker
// runs SQLite on `SimpleOpfsFileSystem` of package:sqlite3, which keeps such
// a handle open for the database file and its rollback journal: SQLite reads
// from the file what it needs, instead of keeping the whole database in
// memory as the IndexedDB storage does. It needs no cross-origin isolation
// (that is only needed by the `WasmVfs` of package:sqlite3, which waits for
// a second worker with `Atomics.wait`).
//
// The page talks to it with messages, one request at a time in the order
// they were sent. Requests are objects `{id, op, ...}`; every request gets
// one reply `{id, result}` or `{id, error}`. The operations:
//
//   load {wasm, path, waitMs}  loads SQLite from `wasm` and opens the files
//                              in the OPFS directory `path`. Replies
//                              `{supported: false}` without touching anything
//                              when this browser has no synchronous OPFS
//                              access, else `{supported: true, exists}`.
//   import {database, journal} writes the bytes of a database (and of its
//                              rollback journal, if any) that was stored
//                              elsewhere, before `open`.
//   open                       opens `/database` in SQLite.
//   execute {sql, args}        runs statements.
//   query {sql, args}          `{columns, rows}`.
//   delete {sql, args}         the number of changed rows.
//   rollback                   rolls back the open transaction, if any.
//   close                      closes the database and its file handles.
//
// Values travel as JavaScript values: null, numbers for integers within
// 2^53, strings, Uint8Arrays for blobs; other integers as `{i: '<decimal>'}`
// and floating point values as `{d: <number>}`, so that neither side has to
// guess whether a number was an integer. One thing is lost on the way: this
// worker is compiled to JavaScript, where a floating point value that is
// integral (a REAL 2.0) cannot be told from an integer and comes back as 2.
// Firestore's cache has no REAL columns.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

@JS('self')
external web.DedicatedWorkerGlobalScope get _self;

void main() {
  final _Host host = _Host();
  _self.onmessage = (web.MessageEvent event) {
    host.receive(event.data! as JSObject);
  }.toJS;
}

class _Host {
  sqlite.WasmSqlite3? _sqlite3;
  sqlite.SimpleOpfsFileSystem? _fileSystem;
  sqlite.CommonDatabase? _database;

  /// Requests run one after the other; `load` waits for the network and the
  /// file system, everything after it is synchronous.
  Future<void> _queue = Future<void>.value();

  void receive(JSObject request) {
    _queue = _queue.then((_) => _handle(request));
  }

  Future<void> _handle(JSObject request) async {
    final JSAny? id = request['id'];
    final JSObject reply = JSObject()..['id'] = id;
    try {
      reply['result'] = await _run(
        (request['op']! as JSString).toDart,
        request,
      );
    } catch (error) {
      reply['error'] = '$error'.toJS;
    }
    _self.postMessage(reply);
  }

  sqlite.CommonDatabase get _db =>
      _database ?? (throw StateError('The database is not open'));

  Future<JSAny?> _run(String op, JSObject request) async {
    switch (op) {
      case 'load':
        return _load(
          wasm: Uri.parse((request['wasm']! as JSString).toDart),
          path: (request['path']! as JSString).toDart,
          wait: Duration(
            milliseconds: (request['waitMs']! as JSNumber).toDartInt,
          ),
        );
      case 'import':
        _import(
          (request['database']! as JSUint8Array).toDart,
          (request['journal'] as JSUint8Array?)?.toDart,
        );
        return null;
      case 'open':
        _database = _sqlite3!.open('/database', vfs: _fileSystem!.name);
        return null;
      case 'execute':
        _db.execute(_sql(request), _args(request));
        return null;
      case 'delete':
        _db.execute(_sql(request), _args(request));
        return _db.updatedRows.toJS;
      case 'query':
        final sqlite.ResultSet rows = _db.select(_sql(request), _args(request));
        return JSObject()
          ..['columns'] = <JSString>[
            for (final String column in rows.columnNames) column.toJS,
          ].toJS
          ..['rows'] = <JSArray<JSAny?>>[
            for (final List<Object?> row in rows.rows)
              <JSAny?>[for (final Object? value in row) _encode(value)].toJS,
          ].toJS;
      case 'rollback':
        if (_database != null && !_database!.autocommit) {
          _database!.execute('ROLLBACK');
        }
        return null;
      case 'close':
        _database?.dispose();
        _database = null;
        if (_fileSystem != null) {
          _sqlite3!.unregisterVirtualFileSystem(_fileSystem!);
          _fileSystem!.close();
          _fileSystem = null;
        }
        return null;
    }
    throw ArgumentError.value(op, 'op', 'Unknown operation');
  }

  Future<JSObject> _load({
    required Uri wasm,
    required String path,
    required Duration wait,
  }) async {
    if (!_opfsAvailable) {
      return JSObject()..['supported'] = false.toJS;
    }
    _sqlite3 = await sqlite.WasmSqlite3.loadFromUrl(wasm);
    await _waitForHandles(path, wait);
    final sqlite.SimpleOpfsFileSystem fileSystem = await sqlite
        .SimpleOpfsFileSystem.loadFromStorage(path, vfsName: 'opfs-$path');
    _fileSystem = fileSystem;
    _sqlite3!.registerVirtualFileSystem(fileSystem);
    return JSObject()
      ..['supported'] = true.toJS
      ..['exists'] = _exists('/database').toJS;
  }

  bool _exists(String file) {
    final sqlite.SimpleOpfsFileSystem fileSystem = _fileSystem!;
    if (fileSystem.xAccess(file, 0) == 0) {
      return false;
    }
    final sqlite.VirtualFileSystemFile opened = fileSystem
        .xOpen(
          sqlite.Sqlite3Filename(file),
          sqlite.SqlFlag.SQLITE_OPEN_READWRITE,
        )
        .file;
    try {
      return opened.xFileSize() > 0;
    } finally {
      opened.xClose();
    }
  }

  /// Writes a database read from another storage into the files that SQLite
  /// opens next. The journal, when there is one, is a hot journal: SQLite
  /// rolls back the transaction it belongs to on the open.
  void _import(Uint8List database, Uint8List? journal) {
    final sqlite.SimpleOpfsFileSystem fileSystem = _fileSystem!;
    void write(String file, Uint8List bytes) {
      final sqlite.VirtualFileSystemFile opened = fileSystem
          .xOpen(
            sqlite.Sqlite3Filename(file),
            sqlite.SqlFlag.SQLITE_OPEN_CREATE |
                sqlite.SqlFlag.SQLITE_OPEN_READWRITE,
          )
          .file;
      try {
        opened
          ..xTruncate(0)
          ..xWrite(bytes, 0)
          ..xSync(0);
      } finally {
        opened.xClose();
      }
    }

    // The journal first: a database without its hot journal could be torn.
    if (journal != null && journal.isNotEmpty) {
      write('/database-journal', journal);
    }
    write('/database', database);
  }
}

/// Whether this context has the origin private file system with synchronous
/// access handles (a dedicated worker of a browser that supports them).
bool get _opfsAvailable {
  final JSObject? storage =
      (globalContext['navigator']! as JSObject)['storage'] as JSObject?;
  if (storage == null || !storage.has('getDirectory')) {
    return false;
  }
  final JSObject? handle = globalContext['FileSystemFileHandle'] as JSObject?;
  return handle != null &&
      (handle['prototype']! as JSObject).has('createSyncAccessHandle');
}

/// Waits up to [wait] until the files of [path] can be opened.
///
/// A synchronous access handle is exclusive. The worker of a page that was
/// just reloaded may still hold them for a moment after the Web Lock of the
/// page was released. `SimpleOpfsFileSystem.loadFromStorage` keeps the
/// handles it opened when a later one fails, so it is only called once all
/// of them can be opened.
Future<void> _waitForHandles(String path, Duration wait) async {
  web.FileSystemDirectoryHandle directory = await _self.navigator.storage
      .getDirectory()
      .toDart;
  for (final String segment in path.split('/')) {
    directory = await directory
        .getDirectoryHandle(
          segment,
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
  }
  final Stopwatch watch = Stopwatch()..start();
  while (true) {
    try {
      for (final String name in <String>['meta', 'database', 'journal']) {
        final web.FileSystemFileHandle file = await directory
            .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
            .toDart;
        (await file.createSyncAccessHandle().toDart).close();
      }
      return;
    } catch (error) {
      if (watch.elapsed >= wait) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

JSAny? _encode(Object? value) {
  if (value == null) {
    return null;
  } else if (value is int &&
      value <= 9007199254740991 &&
      value >= -9007199254740991) {
    return value.toJS;
  } else if (value is double) {
    // Compiled to JavaScript every number is a double (and an int): only
    // those that are not safe integers get here.
    return JSObject()..['d'] = value.toJS;
  } else if (value is int || value is BigInt) {
    // This worker is compiled to JavaScript, where package:sqlite3 returns
    // the integers beyond 2^53 as BigInts.
    return JSObject()..['i'] = value.toString().toJS;
  } else if (value is String) {
    return value.toJS;
  } else if (value is Uint8List) {
    return value.toJS;
  } else if (value is bool) {
    return (value ? 1 : 0).toJS;
  }
  throw ArgumentError.value(value, 'value', 'Not a SQLite value');
}

Object? _decode(JSAny? value) {
  if (value == null) {
    return null;
  } else if (value.typeofEquals('number')) {
    return (value as JSNumber).toDartInt;
  } else if (value.typeofEquals('string')) {
    return (value as JSString).toDart;
  } else if (value.isA<JSUint8Array>()) {
    return (value as JSUint8Array).toDart;
  }
  final JSObject object = value as JSObject;
  if (object.has('i')) {
    // A BigInt, which package:sqlite3 binds as a 64 bit integer: compiled to
    // JavaScript an int cannot hold it.
    return BigInt.parse((object['i']! as JSString).toDart);
  }
  return (object['d']! as JSNumber).toDartDouble;
}

String _sql(JSObject request) => (request['sql']! as JSString).toDart;

List<Object?> _args(JSObject request) {
  final JSArray<JSAny?>? args = request['args'] as JSArray<JSAny?>?;
  if (args == null) {
    return const <Object?>[];
  }
  return <Object?>[for (final JSAny? value in args.toDart) _decode(value)];
}
