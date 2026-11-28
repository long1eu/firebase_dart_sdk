import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:firebase_installations_dart/src/exception.dart';
import 'package:firebase_installations_dart/src/store/key_value_store.dart';
import 'package:web/web.dart' as web;

const String _objectStore = 'kv';

/// A [KeyValueStore] in an IndexedDB database of the page's origin (web).
///
/// The database (version 1) has one object store, `kv`, of string values under string keys. Each
/// [update] is one `readwrite` transaction, so it is atomic across every tab of the origin. After each
/// committed write that changed the value the store announces the key (never the value) on a
/// `BroadcastChannel` named [databaseName]; [changes] emits the keys other stores and tabs announce. An
/// [update] whose transform returns the value it was given writes nothing and announces nothing.
///
/// When the browser closes the connection (site data cleared, a version change, a storage error) the
/// next call opens a new one. Where `BroadcastChannel` is missing the store works without announcing.
///
/// Every script of the origin can read the database, including the installation's refresh token.
final class IndexedDbKeyValueStore implements KeyValueStore {
  /// A store in the IndexedDB database [databaseName]. Nothing is opened until the first call.
  IndexedDbKeyValueStore({this.databaseName = 'firebase_dart_kv'});

  /// The name of the IndexedDB database and of the `BroadcastChannel` that announces changes.
  final String databaseName;

  Future<web.IDBDatabase>? _database;
  web.BroadcastChannel? _channel;
  bool _channelFailed = false;
  bool _closed = false;
  late final StreamController<String> _changes =
      StreamController<String>.broadcast(onListen: _ensureChannel);

  @override
  Future<String?> read(String key) =>
      _inTransaction('readonly', (web.IDBTransaction transaction) {
        final web.IDBRequest request = transaction
            .objectStore(_objectStore)
            .get(key.toJS);
        final Completer<String?> result = Completer<String?>();
        void fail(web.Event _) {
          if (!result.isCompleted) {
            result.completeError(_storageError('a value could not be read'));
          }
        }

        request.onsuccess = ((web.Event _) {
          if (!result.isCompleted) {
            result.complete(_asString(request.result));
          }
        }).toJS;
        request.onerror = fail.toJS;
        transaction.onabort = fail.toJS;
        return result.future;
      });

  @override
  Future<void> write(String key, String? value) =>
      update(key, (String? _) => value);

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => _inTransaction('readwrite', (web.IDBTransaction transaction) {
    final web.IDBObjectStore objects = transaction.objectStore(_objectStore);
    final Completer<String?> result = Completer<String?>();
    String? next;
    bool changed = false;
    Object? failure;
    StackTrace? failureTrace;
    final web.IDBRequest get = objects.get(key.toJS);
    get.onsuccess = ((web.Event _) {
      final String? current = _asString(get.result);
      try {
        next = transform(current);
      } on Object catch (error, stackTrace) {
        failure = error;
        failureTrace = stackTrace;
        transaction.abort();
        return;
      }
      final String? value = next;
      if (value == current && (value != null || get.result == null)) {
        return;
      }
      changed = true;
      if (value == null) {
        objects.delete(key.toJS);
      } else {
        objects.put(value.toJS, key.toJS);
      }
    }).toJS;
    transaction.oncomplete = ((web.Event _) {
      result.complete(next);
      if (changed) {
        _announce(key);
      }
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (result.isCompleted) {
        return;
      }
      final Object? error = failure;
      if (error != null) {
        result.completeError(error, failureTrace);
      } else {
        result.completeError(_storageError('a value could not be written'));
      }
    }).toJS;
    return result.future;
  });

  @override
  Stream<String> get changes => _changes.stream;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final Future<web.IDBDatabase>? database = _database;
    _database = null;
    if (database != null) {
      try {
        (await database).close();
      } on FirebaseInstallationsException {
        // The database never opened; nothing to close.
      }
    }
    _channel?.close();
    _channel = null;
    await _changes.close();
  }

  /// Opens a transaction of [mode] on the object store and runs [body] in the same turn (a transaction
  /// with no request closes at the end of the turn). A connection the browser closed makes
  /// `transaction()` throw: the store forgets it and tries once more on a new one.
  Future<T> _inTransaction<T>(
    String mode,
    Future<T> Function(web.IDBTransaction transaction) body,
  ) async {
    for (int attempt = 0; ; attempt++) {
      final Future<web.IDBDatabase> opening = _open();
      final web.IDBDatabase database = await opening;
      final web.IDBTransaction transaction;
      try {
        transaction = database.transaction(_objectStore.toJS, mode);
      } on Object catch (error, stackTrace) {
        _forget(opening);
        if (attempt == 0 && !_closed) {
          continue;
        }
        Error.throwWithStackTrace(
          _storageError('the database connection is closed', error),
          stackTrace,
        );
      }
      return body(transaction);
    }
  }

  Future<web.IDBDatabase> _open() {
    if (_closed) {
      throw StateError('The IndexedDbKeyValueStore was closed.');
    }
    _ensureChannel();
    final Future<web.IDBDatabase>? cached = _database;
    if (cached != null) {
      return cached;
    }
    late final Future<web.IDBDatabase> opening;
    opening = _openDatabase(() => _forget(opening)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _forget(opening);
      Error.throwWithStackTrace(error, stackTrace);
    });
    return _database = opening;
  }

  /// Drops the cached connection [opening], so the next call opens a new one.
  void _forget(Future<web.IDBDatabase> opening) {
    if (identical(_database, opening)) {
      _database = null;
    }
  }

  /// Opens the database; [onLost] runs when the connection stops being usable (`versionchange`, or the
  /// browser closing it).
  Future<web.IDBDatabase> _openDatabase(void Function() onLost) {
    final Completer<web.IDBDatabase> result = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request;
    try {
      request = web.window.indexedDB.open(databaseName, 1);
    } on Object catch (error, stackTrace) {
      return Future<web.IDBDatabase>.error(
        _storageError('IndexedDB is not available', error),
        stackTrace,
      );
    }
    request.onupgradeneeded = ((web.Event _) {
      final web.IDBDatabase database = request.result! as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_objectStore)) {
        database.createObjectStore(_objectStore);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final web.IDBDatabase database = request.result! as web.IDBDatabase;
      database.onversionchange = ((web.Event _) {
        database.close();
        onLost();
      }).toJS;
      database.onclose = ((web.Event _) {
        onLost();
      }).toJS;
      result.complete(database);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!result.isCompleted) {
        result.completeError(_storageError('the database could not be opened'));
      }
    }).toJS;
    // A blocked open waits until the other connection closes; nothing to do on `blocked`.
    return result.future;
  }

  /// Creates the announcement channel once. Where the browser has none the store runs without it:
  /// announcements are a hint, and waiters poll.
  void _ensureChannel() {
    if (_channel != null || _channelFailed || _closed) {
      return;
    }
    final web.BroadcastChannel channel;
    try {
      channel = web.BroadcastChannel(databaseName);
    } on Object {
      _channelFailed = true;
      return;
    }
    channel.onmessage = ((web.MessageEvent event) {
      final String? key = _keyOf(event.data);
      if (key != null && !_changes.isClosed) {
        _changes.add(key);
      }
    }).toJS;
    _channel = channel;
  }

  void _announce(String key) {
    _channel?.postMessage(jsonEncode(<String, String>{'key': key}).toJS);
  }

  static String? _keyOf(JSAny? data) {
    final String? text = _asString(data);
    if (text == null) {
      return null;
    }
    try {
      final Object? json = jsonDecode(text);
      final Object? key = json is Map<String, Object?> ? json['key'] : null;
      return key is String ? key : null;
    } on FormatException {
      return null;
    }
  }

  static String? _asString(JSAny? value) =>
      value != null && value.isA<JSString>()
      ? (value as JSString).toDart
      : null;

  static FirebaseInstallationsException _storageError(
    String problem, [
    Object? cause,
  ]) => FirebaseInstallationsException(
    code: 'storage-error',
    message: 'IndexedDbKeyValueStore: $problem.',
    cause: cause,
  );
}
