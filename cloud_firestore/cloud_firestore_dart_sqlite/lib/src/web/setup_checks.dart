// Checks of the browser setup that the opener runs before it uses the
// IndexedDB storage: whether the resolved sqlite3 package can store what a
// write acknowledged, and why a sqlite3.wasm could not be loaded.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

import '../sqlite_web_setup_exception.dart';

/// Waits until every write that [fileSystem] was given before this call is
/// stored in IndexedDB. What a write future acknowledges rests on it.
///
/// One `flush()` is not enough with every sqlite3 version, so this calls it
/// twice. Why two calls are enough, from the source of
/// `IndexedDbFileSystem.flush()` and its work queue:
///
///  * 2.7.3 to 3.3.4: `flush()` adds a no-op item to the end of a queue that
///    runs one item at a time, in order, and returns that item's future: it
///    completes after every write queued before it. The first call is enough;
///    the second costs one more turn of the queue.
///  * 3.6.0 to 3.9.1: the queued writes are written in batches, one batch at a
///    time. `flush()` returns the batch being written, or, when none is,
///    starts one with every queued write and returns it. Writes queued while a
///    batch is being written wait for the next batch, which the first call
///    does not wait for: this is the bug that lost acknowledged transactions
///    when a tab was killed. When a batch is done, its completion handler
///    moves every queued write into the next batch and starts it before the
///    future of the first call completes. So the second call returns the
///    batch with the remaining writes, or, if that batch is done too, a later
///    batch or nothing to wait for.
///  * 3.4.0 to 3.5.2: `flush()` returns at once while a batch is being
///    written, without waiting for it. No number of calls is enough there,
///    and the file system has no other way to wait: [checkIndexedDbFlush]
///    refuses these versions.
///
/// A loop until nothing is pending is not possible: the file system does not
/// say whether writes are pending. Check this again before allowing a sqlite3
/// version whose `flush()` changed; the crash test in test/browser of the
/// repository catches a wait that is too short, and [checkIndexedDbFlush] a
/// wait that does not wait at all.
Future<void> flushAll(sqlite.IndexedDbFileSystem fileSystem) async {
  await fileSystem.flush();
  await fileSystem.flush();
}

/// The result of the probe of this page, once it ran: whether [flushAll]
/// waits for a write in progress with the resolved sqlite3 package.
Future<bool>? _flushWaits;

/// Fails with a [SqliteWebSetupException] when the resolved sqlite3 package
/// is one whose `IndexedDbFileSystem.flush()` does not wait for writes in
/// progress (3.4.0 to 3.5.2): with it the IndexedDB storage would report
/// transactions as stored that a tab killed a moment later loses.
///
/// There is no version constant of a package at run time, and the API of
/// those versions is the API of 3.6.0, so this looks at what `flush()` does,
/// once per page (a few milliseconds, in an IndexedDB database of its own
/// that it deletes again): see [_probeFlush].
Future<void> checkIndexedDbFlush({required String storagePrefix}) async {
  final Future<bool> probe = _flushWaits ??= _probeFlush(storagePrefix)
      .onError<Object>((Object error, StackTrace stackTrace) {
        // Tried again on the next open.
        _flushWaits = null;
        Error.throwWithStackTrace(error, stackTrace);
      });
  if (!await probe) {
    throw SqliteWebSetupException(
      SqliteWebSetupProblem.unsafeSqlite3,
      'This app resolves a version of the sqlite3 package (3.4.0 to 3.5.2) '
      'whose IndexedDB file system can lose writes that the offline cache '
      'reported as stored when the tab is closed or crashes a moment later: '
      'its flush() does not wait for the writes in progress. Fresh Flutter '
      'apps get 3.5.2 (Flutter 3.44 pins meta 1.18, and sqlite3 3.6.0 needs '
      'meta 1.19). Either pin a safe sqlite3 in your pubspec.yaml: '
      '`sqlite3: 3.3.4` (or `sqlite3: ^2.7.3`; with 2.x a Flutter Android app '
      'also needs sqlite3_flutter_libs) with Flutter 3.44, `sqlite3: ^3.6.0` '
      'with a Flutter or Dart SDK that allows meta 1.19; and put the '
      'sqlite3.wasm of that exact version next to the page. Or use the OPFS '
      'storage (sqliteOpener(opfsWorker: ...)), which does not use this file '
      'system. To keep this version and accept the risk, pass '
      'sqliteOpener(acceptIndexedDbWriteLoss: true).',
    );
  }
}

int _probes = 0;

/// Whether [flushAll] waits for a write that is in progress when it is
/// called, with the sqlite3 package this program was built with.
///
/// The probe holds a read-write IndexedDB transaction of its own on a scratch
/// database, so that the file system's write of a new file there cannot
/// finish: IndexedDB runs transactions on the same stores in the order they
/// were created. While it is held, [flushAll] is called after a second file
/// was created behind the first. With 2.7.3 to 3.3.4 and 3.6.0 or later its
/// future cannot complete before the held transaction ends, because it waits
/// for the write. With 3.4.0 to 3.5.2 it completes at once. The held
/// transaction lasts 16 IndexedDB requests, each a turn of the event loop,
/// while [flushAll] of those versions needs a few microtasks (or, compiled
/// with dart2js in a worker, a few timers). Then it is released and
/// everything finishes either way.
Future<bool> _probeFlush(String storagePrefix) async {
  final int salt = Random().nextInt(1 << 30);
  final String name = '$storagePrefix/sqlite3-flush-probe-$salt';
  final web.IDBFactory factory = globalContext.getProperty<web.IDBFactory>(
    'indexedDB'.toJS,
  );

  final sqlite.IndexedDbFileSystem fileSystem =
      await sqlite.IndexedDbFileSystem.open(
        dbName: name,
        vfsName: 'flush-probe-${_probes++}',
      );
  web.IDBDatabase? database;
  try {
    database = await _openIndexedDb(factory, name);

    final Completer<bool> verdict = Completer<bool>();
    bool flushed = false;
    final web.IDBObjectStore files = database
        .transaction(<JSString>['files'.toJS, 'blocks'.toJS].toJS, 'readwrite')
        .objectStore('files');
    int turns = 0;
    void hold() {
      final web.IDBRequest request = files.count();
      request.onsuccess = (web.Event _) {
        if (++turns < 16) {
          hold();
        } else if (!verdict.isCompleted) {
          verdict.complete(!flushed);
        }
      }.toJS;
      request.onerror = (web.Event _) {
        if (!verdict.isCompleted) {
          verdict.completeError(
            StateError('The flush probe could not use IndexedDB'),
          );
        }
      }.toJS;
    }

    hold();

    // The first file starts the write of a batch (3.4.0 and later) or queues
    // it (earlier); the second is queued behind it.
    for (final String file in <String>['/a', '/b']) {
      fileSystem
          .xOpen(
            sqlite.Sqlite3Filename(file),
            sqlite.SqlFlag.SQLITE_OPEN_CREATE |
                sqlite.SqlFlag.SQLITE_OPEN_READWRITE,
          )
          .file
          .xClose();
    }
    final Future<void> flush = flushAll(fileSystem).then((_) {
      flushed = true;
    });

    final bool waits = await verdict.future;
    await flush;
    return waits;
  } finally {
    database?.close();
    await fileSystem.close();
    try {
      await sqlite.IndexedDbFileSystem.deleteDatabase(name);
    } catch (_) {
      // Left behind; it holds two empty files.
    }
  }
}

Future<web.IDBDatabase> _openIndexedDb(web.IDBFactory factory, String name) {
  final Completer<web.IDBDatabase> opened = Completer<web.IDBDatabase>();
  final web.IDBOpenDBRequest request = factory.open(name);
  request.onsuccess = (web.Event _) {
    opened.complete(request.result! as web.IDBDatabase);
  }.toJS;
  request.onerror = (web.Event _) {
    opened.completeError(
      StateError('The flush probe could not open IndexedDB: ${request.error}'),
    );
  }.toJS;
  return opened.future;
}

/// Explains why [sqlite3Wasm] could not be loaded with [error], when the
/// cause is the file: missing, not WebAssembly, or the build of another
/// sqlite3 version than the package this program was built with. Returns
/// null when the file looks right (the error is then about something else).
Future<SqliteWebSetupException?> explainWasmFailure(
  Uri sqlite3Wasm,
  Object error,
) async {
  final String url = sqlite3Wasm.toString();
  final web.Response response;
  try {
    // A window or a worker.
    response = await globalContext
        .callMethod<JSPromise<web.Response>>('fetch'.toJS, url.toJS)
        .toDart;
  } catch (_) {
    // The network: not the file's fault, as far as we know.
    return null;
  }
  if (!response.ok) {
    return SqliteWebSetupException(
      SqliteWebSetupProblem.wasmMissing,
      'sqlite3.wasm is not at $url (HTTP ${response.status}). Put the '
      'sqlite3.wasm of the exact sqlite3 version in pubspec.lock next to the '
      'page (`dart run cloud_firestore_dart_sqlite:setup_web` prints its URL), '
      'or pass its URL as sqliteOpener(sqlite3Wasm: ...).',
      error,
    );
  }

  final JSObject webAssembly = globalContext.getProperty<JSObject>(
    'WebAssembly'.toJS,
  );
  final JSArrayBuffer bytes;
  try {
    bytes = await response.arrayBuffer().toDart;
  } catch (_) {
    return null;
  }
  // Every WebAssembly binary starts with "\0asm".
  final ByteBuffer buffer = bytes.toDart;
  final Uint8List head = buffer.asUint8List(
    0,
    buffer.lengthInBytes < 4 ? buffer.lengthInBytes : 4,
  );
  if (head.length < 4 ||
      head[0] != 0x00 ||
      head[1] != 0x61 ||
      head[2] != 0x73 ||
      head[3] != 0x6d) {
    return SqliteWebSetupException(
      SqliteWebSetupProblem.wasmMissing,
      '$url is not WebAssembly (a server that answers a missing file with '
      'the page, for example). Put the sqlite3.wasm of the exact sqlite3 '
      'version in pubspec.lock there (`dart run '
      'cloud_firestore_dart_sqlite:setup_web` prints its URL).',
      error,
    );
  }
  final JSObject module;
  try {
    module = await webAssembly
        .callMethod<JSPromise<JSObject>>('compile'.toJS, bytes)
        .toDart;
  } catch (_) {
    // WebAssembly, but not compiled here (a Content-Security-Policy without
    // 'wasm-unsafe-eval', a damaged file): the original error says more.
    return null;
  }

  // A LinkError (a function the module imports is missing) or a TypeError
  // (a module of imports is missing, e.g. `env` of the 2.x builds) when it
  // is instantiated: the module and the package do not fit.
  if (!error.toString().toLowerCase().contains('import')) {
    return null;
  }
  final JSObject moduleClass = webAssembly.getProperty<JSObject>('Module'.toJS);
  final Set<String> exports = <String>{
    for (final JSObject export
        in moduleClass
            .callMethod<JSArray<JSObject>>('exports'.toJS, module)
            .toDart)
      (export['name']! as JSString).toDart,
  };
  // The 2.x builds import their memory and export `_initialize`; the 3.x
  // builds export their memory.
  final String? line = exports.contains('_initialize')
      ? '2.x'
      : exports.contains('memory')
      ? '3.x'
      : null;
  return SqliteWebSetupException(
    SqliteWebSetupProblem.wasmVersionMismatch,
    '$url is ${line == null ? 'a sqlite3.wasm' : 'the sqlite3.wasm of a sqlite3 $line release'}, and the '
    'sqlite3 package of this app could not load it: it is the build of '
    'another sqlite3 version. sqlite3.wasm must be the build of the exact '
    'version in pubspec.lock (2.x and 3.x builds are not interchangeable, '
    'and neither are the minor versions): '
    'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm '
    '(`dart run cloud_firestore_dart_sqlite:setup_web` prints it).',
    error,
  );
}
