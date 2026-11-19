import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_transaction.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';

/// The writes of a transaction of the key-value cache stay in memory until the commit; its reads lay them over the
/// store. Compared with a model (a sorted map with the writes applied) on random data.
void main() {
  Uint8List key(int i) => Uint8List.fromList(<int>[i ~/ 7, i % 7]);

  List<String> show(List<CacheStoreEntry> entries) => <String>[
    for (final CacheStoreEntry entry in entries)
      '${entry.key.join('.')}=${entry.value.join('.')}',
  ];

  for (int seed = 0; seed < 40; seed++) {
    test('random writes and reads, seed $seed', () async {
      final Random random = Random(seed);
      final MemoryLogStore store = MemoryLogStore();
      await store.open();
      final SplayTreeMap<Uint8List, Uint8List> model =
          SplayTreeMap<Uint8List, Uint8List>(compareCacheStoreKeys);
      final List<CacheStoreEntry> initial = <CacheStoreEntry>[
        for (int i = 0; i < 100; i++)
          if (random.nextInt(3) > 0)
            CacheStoreEntry(key(i), Uint8List.fromList(<int>[0, i])),
      ];
      await store.write(initial, const <Uint8List>[]);
      for (final CacheStoreEntry entry in initial) {
        model[entry.key] = entry.value;
      }

      final KvTransaction transaction = KvTransaction(store);
      for (int step = 0; step < 300; step++) {
        final int i = random.nextInt(100);
        switch (random.nextInt(4)) {
          case 0:
            final Uint8List value = Uint8List.fromList(<int>[1, step % 256]);
            await transaction.put(key(i), value);
            model[key(i)] = value;
          case 1:
            await transaction.delete(key(i));
            model.remove(key(i));
          case 2:
            expect(await transaction.get(key(i)), model[key(i)]);
          default:
            final int a = random.nextInt(101);
            final int b = random.nextInt(101);
            final Uint8List start = key(min(a, b));
            final Uint8List end = key(max(a, b));
            final bool reverse = random.nextBool();
            final int? limit = random.nextBool() ? random.nextInt(12) : null;
            Iterable<MapEntry<Uint8List, Uint8List>> expected = model.entries
                .where(
                  (MapEntry<Uint8List, Uint8List> e) =>
                      compareCacheStoreKeys(e.key, start) >= 0 &&
                      compareCacheStoreKeys(e.key, end) < 0,
                );
            if (reverse) {
              expected = expected.toList().reversed;
            }
            if (limit != null) {
              expected = expected.take(limit);
            }
            expect(
              show(
                await transaction.scan(
                  start,
                  end,
                  reverse: reverse,
                  limit: limit,
                ),
              ),
              show(<CacheStoreEntry>[
                for (final MapEntry<Uint8List, Uint8List> e in expected)
                  CacheStoreEntry(e.key, e.value),
              ]),
              reason: 'scan ${min(a, b)} to ${max(a, b)}, reverse $reverse, '
                  'limit $limit',
            );
        }
      }
      await transaction.commit();
      expect(
        show(await store.scan(Uint8List(0), Uint8List.fromList(<int>[0xff]))),
        show(<CacheStoreEntry>[
          for (final MapEntry<Uint8List, Uint8List> e in model.entries)
            CacheStoreEntry(e.key, e.value),
        ]),
      );
      await store.close();
    });
  }

  test('a transaction that is dropped writes nothing', () async {
    final MemoryLogStore store = MemoryLogStore();
    await store.open();
    final KvTransaction transaction = KvTransaction(store);
    await transaction.put(key(1), key(1));
    expect(await transaction.get(key(1)), key(1));
    expect(await store.get(key(1)), isNull);
    await store.close();
  });
}
