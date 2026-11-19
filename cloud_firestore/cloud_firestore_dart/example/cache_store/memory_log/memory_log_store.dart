// A CacheStore in plain Dart: a sorted map in memory, made durable by an append-only log file.
//
// Every committed transaction appends one record to the log: its puts and deletes. Opening the store replays the log
// into the map. A record that a crash cut short is ignored, so a transaction is kept whole or not at all. When the
// log has grown to several times the size of the data, opening the store rewrites it as one record (compaction).
//
// Transactions run one at a time, so a transaction can write into the map directly: nobody else looks at it in the
// meantime. It remembers what each write replaced, and puts that back if the body throws.

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';

class MemoryLogStore implements CacheStore {
  /// A store whose log is the file at [path], or a store in memory only when [path] is null (for tests: the data
  /// then lives as long as this object, across [close] and [open]).
  MemoryLogStore([this.path]);

  final String? path;

  /// The data, in the order of the keys.
  final SplayTreeMap<Uint8List, Uint8List> _data =
      SplayTreeMap<Uint8List, Uint8List>(compareCacheStoreKeys);

  /// The log, open for appending while the store is open.
  RandomAccessFile? _log;

  /// The end of the last transaction: the next one starts after it.
  Future<void> _lastTransaction = Future<void>.value();

  // Opening and closing.

  @override
  Future<void> open() async {
    final String? path = this.path;
    if (path == null) {
      return;
    }
    _data.clear();
    final File file = File(path);
    int logSize = 0;
    if (file.existsSync()) {
      final Uint8List log = await file.readAsBytes();
      logSize = log.length;
      _replay(log);
    }
    if (logSize > 4 * _dataSize() + 4096) {
      await _compact(file);
    }
    _log = await file.open(mode: FileMode.append);
  }

  @override
  Future<void> close() async {
    await _lastTransaction;
    await _log?.close();
    _log = null;
  }

  // Transactions.

  @override
  Future<T> transaction<T>(
    Future<T> Function(CacheStoreTransaction transaction) body, {
    bool readOnly = false,
  }) {
    final Future<T> result = _lastTransaction.then((_) => _run(body, readOnly));
    _lastTransaction = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<T> _run<T>(
    Future<T> Function(CacheStoreTransaction transaction) body,
    bool readOnly,
  ) async {
    final _Transaction transaction = _Transaction(this, readOnly);
    final T result;
    try {
      result = await body(transaction);
    } catch (_) {
      transaction.undo();
      rethrow;
    } finally {
      transaction.done = true;
    }
    if (transaction.writes.isNotEmpty) {
      try {
        await _append(transaction.writes);
      } catch (_) {
        // Not durable: not committed either.
        transaction.undo();
        rethrow;
      }
    }
    return result;
  }

  // The log. A record is the length of its body (4 bytes), then the body: for each write, 1 for a put or 0 for a
  // delete, the key (length and bytes) and, for a put, the value (length and bytes).

  Future<void> _append(List<_Write> writes) async {
    final RandomAccessFile? log = _log;
    if (log == null) {
      return; // In memory only.
    }
    final BytesBuilder body = BytesBuilder(copy: false);
    for (final _Write write in writes) {
      body.addByte(write.value == null ? 0 : 1);
      _writeBytes(body, write.key);
      if (write.value != null) {
        _writeBytes(body, write.value!);
      }
    }
    final BytesBuilder record = BytesBuilder(copy: false);
    _writeLength(record, body.length);
    record.add(body.takeBytes());
    await log.writeFrom(record.takeBytes());
    await log.flush();
  }

  void _replay(Uint8List log) {
    final ByteData view = ByteData.sublistView(log);
    int offset = 0;
    while (offset + 4 <= log.length) {
      final int length = view.getUint32(offset);
      final int end = offset + 4 + length;
      if (end > log.length) {
        break; // A record cut short by a crash: its transaction did not commit.
      }
      offset += 4;
      while (offset < end) {
        final bool isPut = log[offset++] == 1;
        final int keyLength = view.getUint32(offset);
        final Uint8List key = Uint8List.sublistView(
          log,
          offset + 4,
          offset + 4 + keyLength,
        );
        offset += 4 + keyLength;
        if (isPut) {
          final int valueLength = view.getUint32(offset);
          _data[key] = Uint8List.sublistView(
            log,
            offset + 4,
            offset + 4 + valueLength,
          );
          offset += 4 + valueLength;
        } else {
          _data.remove(key);
        }
      }
    }
  }

  /// Rewrites the log as one record that puts every key, through a temporary file and a rename.
  Future<void> _compact(File file) async {
    final File temporary = File('${file.path}.compact');
    final RandomAccessFile out = await temporary.open(mode: FileMode.write);
    final BytesBuilder body = BytesBuilder(copy: false);
    _data.forEach((Uint8List key, Uint8List value) {
      body.addByte(1);
      _writeBytes(body, key);
      _writeBytes(body, value);
    });
    final BytesBuilder record = BytesBuilder(copy: false);
    _writeLength(record, body.length);
    record.add(body.takeBytes());
    await out.writeFrom(record.takeBytes());
    await out.flush();
    await out.close();
    await temporary.rename(file.path);
  }

  int _dataSize() {
    int size = 0;
    _data.forEach((Uint8List key, Uint8List value) {
      size += key.length + value.length + 9;
    });
    return size;
  }

  static void _writeBytes(BytesBuilder builder, Uint8List bytes) {
    _writeLength(builder, bytes.length);
    builder.add(bytes);
  }

  static void _writeLength(BytesBuilder builder, int length) {
    builder.add((ByteData(4)..setUint32(0, length)).buffer.asUint8List());
  }
}

/// A put (with a value) or a delete (without), and the value it replaced.
class _Write {
  _Write(this.key, this.value, this.previous);

  final Uint8List key;
  final Uint8List? value;
  final Uint8List? previous;
}

class _Transaction implements CacheStoreTransaction {
  _Transaction(this._store, this._readOnly);

  final MemoryLogStore _store;
  final bool _readOnly;
  final List<_Write> writes = <_Write>[];
  bool done = false;

  SplayTreeMap<Uint8List, Uint8List> get _data {
    if (done) {
      throw StateError('The transaction is over');
    }
    return _store._data;
  }

  @override
  Future<Uint8List?> get(Uint8List key) async => _data[key];

  @override
  Future<void> put(Uint8List key, Uint8List value) async {
    _checkWritable();
    writes.add(_Write(key, value, _data[key]));
    _data[key] = value;
  }

  @override
  Future<void> delete(Uint8List key) async {
    _checkWritable();
    writes.add(_Write(key, null, _data[key]));
    _data.remove(key);
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    final SplayTreeMap<Uint8List, Uint8List> data = _data;
    final List<CacheStoreEntry> result = <CacheStoreEntry>[];
    // The first key in the range, then the next one, until the other end of the range or the limit.
    Uint8List? key = reverse
        ? data.lastKeyBefore(end)
        : (data.containsKey(start) ? start : data.firstKeyAfter(start));
    while (key != null && (limit == null || result.length < limit)) {
      final bool inRange = reverse
          ? compareCacheStoreKeys(key, start) >= 0
          : compareCacheStoreKeys(key, end) < 0;
      if (!inRange) {
        break;
      }
      result.add(CacheStoreEntry(key, data[key]!));
      key = reverse ? data.lastKeyBefore(key) : data.firstKeyAfter(key);
    }
    return result;
  }

  /// Puts back what the writes replaced, newest first.
  void undo() {
    for (final _Write write in writes.reversed) {
      if (write.previous == null) {
        _store._data.remove(write.key);
      } else {
        _store._data[write.key] = write.previous!;
      }
    }
    writes.clear();
  }

  void _checkWritable() {
    if (_readOnly) {
      throw StateError('A write in a read-only transaction');
    }
  }
}
