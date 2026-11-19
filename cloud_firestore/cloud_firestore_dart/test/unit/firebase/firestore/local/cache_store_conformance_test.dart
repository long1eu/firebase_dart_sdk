import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cache_store_testing.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../../../example/cache_store/sqlite/sqlite_cache_store.dart';

/// The contract checks of `package:cloud_firestore_dart/cache_store_testing.dart` on the two example stores.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('cache_store_test_');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  group('MemoryLogStore in memory', () {
    for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
      test(check.name, () => check.run(() => MemoryLogStore()));
    }
  });

  group('MemoryLogStore with a log file', () {
    for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
      test(
        check.name,
        () => check.run(() => MemoryLogStore('${directory.path}/cache.log')),
      );
    }

    test('a record cut short by a crash is ignored', () async {
      final String path = '${directory.path}/cache.log';
      final MemoryLogStore store = MemoryLogStore(path);
      await store.open();
      await store.transaction((tx) => tx.put(_bytes('a'), _bytes('1')));
      await store.transaction((tx) => tx.put(_bytes('b'), _bytes('2')));
      await store.close();
      final File file = File(path);
      final List<int> log = file.readAsBytesSync();
      file.writeAsBytesSync(log.sublist(0, log.length - 1));

      await store.open();
      await store.transaction((tx) async {
        expect(await tx.get(_bytes('a')), _bytes('1'));
        expect(await tx.get(_bytes('b')), isNull);
      });
      await store.close();
    });
  });

  group('a broken store', () {
    // The checks are worth something only if they fail on a store that breaks the contract.
    Future<void> expectFailure(String name) async {
      final CacheStoreCheck check = cacheStoreConformanceChecks.singleWhere(
        (CacheStoreCheck check) => check.name == name,
      );
      await expectLater(check.run(_BrokenStore.new), throwsStateError);
    }

    test('fails the key order check', () {
      return expectFailure('keys are ordered by their unsigned bytes');
    });

    test('fails the rollback check', () {
      return expectFailure('a transaction whose body throws is rolled back');
    });
  });

  group('SqliteCacheStore', () {
    for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
      test(
        check.name,
        () => check.run(() => SqliteCacheStore('${directory.path}/cache.db')),
      );
    }
  });
}

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);

/// Compares keys as signed bytes: the mistake of [_BrokenStore].
int _signedCompare(Uint8List a, Uint8List b) {
  for (int i = 0; i < a.length && i < b.length; i++) {
    final int difference = a[i].toSigned(8) - b[i].toSigned(8);
    if (difference != 0) {
      return difference;
    }
  }
  return a.length - b.length;
}

/// A store with two mistakes the checks must catch: keys compared as signed bytes, and writes that a failing body
/// leaves behind.
class _BrokenStore implements CacheStore {
  final SplayTreeMap<Uint8List, Uint8List> _data =
      SplayTreeMap<Uint8List, Uint8List>(_signedCompare);

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<T> transaction<T>(
    Future<T> Function(CacheStoreTransaction transaction) body, {
    bool readOnly = false,
  }) => body(_BrokenTransaction(_data));
}

class _BrokenTransaction implements CacheStoreTransaction {
  _BrokenTransaction(this._data);

  final SplayTreeMap<Uint8List, Uint8List> _data;

  @override
  Future<Uint8List?> get(Uint8List key) async => _data[key];

  @override
  Future<void> put(Uint8List key, Uint8List value) async => _data[key] = value;

  @override
  Future<void> delete(Uint8List key) async => _data.remove(key);

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    final List<CacheStoreEntry> entries = <CacheStoreEntry>[
      for (final MapEntry<Uint8List, Uint8List> entry in _data.entries)
        if (_signedCompare(entry.key, start) >= 0 &&
            _signedCompare(entry.key, end) < 0)
          CacheStoreEntry(entry.key, entry.value),
    ];
    final List<CacheStoreEntry> ordered = reverse
        ? entries.reversed.toList()
        : entries;
    return limit == null ? ordered : ordered.take(limit).toList();
  }
}
