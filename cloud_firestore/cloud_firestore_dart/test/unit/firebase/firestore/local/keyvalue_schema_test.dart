// The stored format of the key-value cache (docs/keyvalue_cache_format.md): the stores written by every schema version
// open and read correctly, and the format written today is the one of the fixture of the current version, so that a
// change of the format cannot land without a new schema version and a migration.
//
// After a deliberate change of the format (with kvSchemaVersion bumped and its migration added), write the fixture of
// the new version with
//
//   UPDATE_GOLDEN=1 dart test test/unit/firebase/firestore/local/keyvalue_schema_test.dart
//
// which only writes the fixture of the current version; the fixtures of older versions are never rewritten.

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_codec.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import 'keyvalue_fixture.dart';
import 'persistence_test_helpers.dart';

File _fixture(int version) => File('test/res/keyvalue/schema_$version.json');

/// A store in memory that holds [entries].
Future<MemoryLogStore> _storeWith(List<CacheStoreEntry> entries) async {
  final MemoryLogStore store = MemoryLogStore();
  await store.open();
  await store.write(entries, const <Uint8List>[]);
  await store.close();
  return store;
}

final DatabaseId dbIdForTests = DatabaseId.forProject('projectId');
final LocalSerializer serializerForTests = LocalSerializer(
  RemoteSerializer(dbIdForTests),
);
const LruGarbageCollectorParams lruParamsForTests = LruGarbageCollectorParams();

Uint8List _versionKey() => KvKeyWriter().string('meta').string('version').bytes;

void main() {
  test('the format written today is the fixture of the current version', () async {
    final MemoryLogStore store = MemoryLogStore();
    final CacheStorePersistence persistence = await createKeyValuePersistence(
      store: store,
    );
    await writeFixtureCache(persistence);
    await persistence.shutdown();
    final List<List<String>> written = await dumpStore(store);

    final File file = _fixture(kvSchemaVersion);
    if (Platform.environment['UPDATE_GOLDEN'] == '1' && !file.existsSync()) {
      writeFixtureFile(file, kvSchemaVersion, written);
    }
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'No fixture of schema version $kvSchemaVersion: write it with UPDATE_GOLDEN=1 (see the top of this file).',
    );
    final List<List<String>> expected = <List<String>>[
      for (final CacheStoreEntry entry in readFixtureFile(file))
        <String>[
          for (final Uint8List bytes in <Uint8List>[entry.key, entry.value])
            bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
        ],
    ];
    expect(
      written,
      expected,
      reason:
          'The key-value cache writes another format than the one of schema version $kvSchemaVersion. A change of '
          'the stored format needs a new schema version (kvSchemaVersion), a migration of the stores of the older '
          'versions (kvMigrations) and a fixture of the new version; see docs/keyvalue_cache_format.md.',
    );
  });

  for (int version = 1; version <= kvSchemaVersion; version++) {
    test('a store written by schema version $version opens and reads', () async {
      final File file = _fixture(version);
      expect(file.existsSync(), isTrue, reason: 'Missing ${file.path}');
      final MemoryLogStore store = await _storeWith(readFixtureFile(file));

      CacheStorePersistence persistence = await createKeyValuePersistence(
        store: store,
      );
      await expectFixtureCache(persistence);
      await persistence.shutdown();

      // The store is now at the current version, and opens again without a migration.
      expect(
        KvKeyReader((await _peek(store, _versionKey()))!).integer(),
        kvSchemaVersion,
      );
      persistence = await createKeyValuePersistence(store: store);
      await expectFixtureCache(persistence);
      await persistence.shutdown();
    });
  }

  group('the schema version', () {
    test('a store of a newer version is refused, unchanged', () async {
      final List<CacheStoreEntry> entries = readFixtureFile(
        _fixture(kvSchemaVersion),
      );
      final MemoryLogStore store = await _storeWith(entries);
      await store.open();
      await store.write(<CacheStoreEntry>[
        CacheStoreEntry(
          _versionKey(),
          KvKeyWriter().integer(kvSchemaVersion + 1).bytes,
        ),
      ], const <Uint8List>[]);
      await store.close();
      final List<List<String>> before = await dumpStore(store);

      await expectLater(
        createKeyValuePersistence(store: store),
        throwsA(
          isA<FirestoreException>()
              .having(
                (FirestoreException e) => e.errorCode,
                'errorCode',
                FirestoreErrorCode.failedPrecondition,
              )
              .having(
                (FirestoreException e) => e.message,
                'message',
                allOf(
                  contains('version ${kvSchemaVersion + 1}'),
                  contains('newer'),
                ),
              ),
        ),
      );
      expect(await dumpStore(store), before);
      // The store was released: it can be cleared and used again.
      final CacheStorePersistence persistence = CacheStorePersistence(
        store,
        databaseId: dbIdForTests,
        serializer: serializerForTests,
        lruParams: lruParamsForTests,
      );
      await persistence.clearPersistence();
      expect(await dumpStore(store), isEmpty);
    });

    test('a store with data and no version is refused', () async {
      final MemoryLogStore store = await _storeWith(<CacheStoreEntry>[
        CacheStoreEntry(
          Uint8List.fromList(<int>[1, 2]),
          Uint8List.fromList(<int>[3]),
        ),
      ]);
      await expectLater(
        createKeyValuePersistence(store: store),
        throwsA(isA<FirestoreException>()),
      );
    });

    test(
      'migrations run in order, in the transaction that opens the store',
      () async {
        final MemoryLogStore store = await _storeWith(
          readFixtureFile(_fixture(1)),
        );
        final List<String> ran = <String>[];
        final CacheStorePersistence persistence = CacheStorePersistence(
          store,
          databaseId: dbIdForTests,
          serializer: serializerForTests,
          lruParams: lruParamsForTests,
          schemaVersion: kvSchemaVersion + 2,
          migrations: <int, KvMigration>{
            ...kvMigrations,
            kvSchemaVersion + 2: (KvTransaction context) async {
              ran.add('to ${kvSchemaVersion + 2}');
            },
            kvSchemaVersion + 1: (KvTransaction context) async {
              ran.add('to ${kvSchemaVersion + 1}');
              await context.put(
                Uint8List.fromList(<int>[0xfe]),
                Uint8List.fromList(<int>[1]),
              );
            },
          },
        );
        await persistence.start();
        expect(ran, <String>[
          'to ${kvSchemaVersion + 1}',
          'to ${kvSchemaVersion + 2}',
        ]);
        await persistence.shutdown();
        expect(
          KvKeyReader((await _peek(store, _versionKey()))!).integer(),
          kvSchemaVersion + 2,
        );
        expect(await _peek(store, Uint8List.fromList(<int>[0xfe])), <int>[1]);
      },
    );

    test('a migration that fails leaves the store as it was', () async {
      final MemoryLogStore store = await _storeWith(
        readFixtureFile(_fixture(kvSchemaVersion)),
      );
      final List<List<String>> before = await dumpStore(store);
      final CacheStorePersistence persistence = CacheStorePersistence(
        store,
        databaseId: dbIdForTests,
        serializer: serializerForTests,
        lruParams: lruParamsForTests,
        schemaVersion: kvSchemaVersion + 1,
        migrations: <int, KvMigration>{
          ...kvMigrations,
          kvSchemaVersion + 1: (KvTransaction context) async {
            await context.put(
              Uint8List.fromList(<int>[0xfe]),
              Uint8List.fromList(<int>[1]),
            );
            throw StateError('boom');
          },
        },
      );
      await expectLater(persistence.start(), throwsStateError);
      expect(await dumpStore(store), before);
    });

    test('a missing migration is an error', () async {
      final MemoryLogStore store = await _storeWith(
        readFixtureFile(_fixture(kvSchemaVersion)),
      );
      final CacheStorePersistence persistence = CacheStorePersistence(
        store,
        databaseId: dbIdForTests,
        serializer: serializerForTests,
        lruParams: lruParamsForTests,
        schemaVersion: kvSchemaVersion + 1,
        migrations: kvMigrations,
      );
      await expectLater(persistence.start(), throwsStateError);
    });

    test('every version after 1 has its migration', () {
      for (int version = 2; version <= kvSchemaVersion; version++) {
        expect(kvMigrations, contains(version));
      }
      expect(kvMigrations.keys.where((int v) => v > kvSchemaVersion), isEmpty);
    });
  });
}

Future<Uint8List?> _peek(MemoryLogStore store, Uint8List key) async {
  await store.open();
  try {
    return await store.get(key);
  } finally {
    await store.close();
  }
}
