import 'dart:io';
import 'dart:typed_data';

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
