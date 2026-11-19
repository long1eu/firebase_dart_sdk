// A CacheStore in plain Dart: a sorted map in memory, made durable by an append-only log file.
//
// Every write appends one record to the log: its puts and deletes. Opening the store replays the log into the map. A
// record that a crash cut short is ignored, so a write is kept whole or not at all. When the log has grown to several
// times the size of the data, opening the store rewrites it as one record (compaction).
//
// The SDK never writes while another write or a read runs, so a write changes the map directly. If the log cannot be
// written, it puts back what it replaced.

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
    await _log?.close();
    _log = null;
  }

  // Reads and writes.

  @override
  Future<Uint8List?> get(Uint8List key) async => _data[key];

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    final List<CacheStoreEntry> result = <CacheStoreEntry>[];
    // The first key in the range, then the next one, until the other end of the range or the limit.
    Uint8List? key = reverse
        ? _data.lastKeyBefore(end)
        : (_data.containsKey(start) ? start : _data.firstKeyAfter(start));
    while (key != null && (limit == null || result.length < limit)) {
      final bool inRange = reverse
          ? compareCacheStoreKeys(key, start) >= 0
          : compareCacheStoreKeys(key, end) < 0;
      if (!inRange) {
        break;
      }
      result.add(CacheStoreEntry(key, _data[key]!));
      key = reverse ? _data.lastKeyBefore(key) : _data.firstKeyAfter(key);
    }
    return result;
  }

  @override
  Future<void> write(
    List<CacheStoreEntry> puts,
    List<Uint8List> deletes,
  ) async {
    if (puts.isEmpty && deletes.isEmpty) {
      return;
    }
    // What the write replaces, to put it back if the log cannot be written.
    final Map<Uint8List, Uint8List?> previous = <Uint8List, Uint8List?>{};
    for (final CacheStoreEntry entry in puts) {
      previous[entry.key] = _data[entry.key];
      _data[entry.key] = entry.value;
    }
    for (final Uint8List key in deletes) {
      previous[key] = _data.remove(key);
    }
    try {
      await _append(puts, deletes);
    } catch (_) {
      // Not durable: not written either.
      previous.forEach((Uint8List key, Uint8List? value) {
        if (value == null) {
          _data.remove(key);
        } else {
          _data[key] = value;
        }
      });
      rethrow;
    }
  }

  // The log. A record is the length of its body (4 bytes), then the body: for each write, 1 for a put or 0 for a
  // delete, the key (length and bytes) and, for a put, the value (length and bytes).

  Future<void> _append(
    List<CacheStoreEntry> puts,
    List<Uint8List> deletes,
  ) async {
    final RandomAccessFile? log = _log;
    if (log == null) {
      return; // In memory only.
    }
    final BytesBuilder body = BytesBuilder(copy: false);
    for (final CacheStoreEntry entry in puts) {
      body.addByte(1);
      _writeBytes(body, entry.key);
      _writeBytes(body, entry.value);
    }
    for (final Uint8List key in deletes) {
      body.addByte(0);
      _writeBytes(body, key);
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
        break; // A record cut short by a crash: its write did not happen.
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
