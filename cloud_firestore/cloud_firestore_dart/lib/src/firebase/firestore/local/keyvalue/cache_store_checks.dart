import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';

/// **Experimental.** One check of the contract of a [CacheStore], to run in the tests of a store:
///
/// ```dart
/// import 'package:cloud_firestore_dart/cache_store_testing.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
///     test(check.name, () => check.run(() => MyStore(newEmptyFile())));
///   }
/// }
/// ```
final class CacheStoreCheck {
  const CacheStoreCheck._(this.name, this._body);

  /// What the check verifies, as a test name.
  final String name;

  final Future<void> Function(CacheStore store) _body;

  /// Runs the check on a store that [newStore] creates over empty storage. The check opens the store, and closes it
  /// at the end. It throws a [StateError] that says what is wrong when the store breaks the contract.
  Future<void> run(CacheStore Function() newStore) async {
    final CacheStore store = newStore();
    await store.open();
    try {
      await _body(store);
    } finally {
      await store.close();
    }
  }

  @override
  String toString() => 'CacheStoreCheck($name)';
}

/// **Experimental.** The checks of the contract of a [CacheStore] (see [CacheStoreCheck]): reads, writes and deletes,
/// the byte order of the keys, range scans (bounds, reverse order, limit), reading the writes of a transaction,
/// commit, rollback when the body throws, isolation of concurrent transactions, keys and values kept byte for byte
/// (also empty values), and data that is still there after the store is closed and opened again.
final List<CacheStoreCheck> cacheStoreConformanceChecks =
    List<CacheStoreCheck>.unmodifiable(<CacheStoreCheck>[
      const CacheStoreCheck._('get, put and delete', _getPutDelete),
      const CacheStoreCheck._(
        'keys are ordered by their unsigned bytes',
        _keyOrder,
      ),
      const CacheStoreCheck._(
        'scan honours its bounds, the reverse order and the limit',
        _scanRanges,
      ),
      const CacheStoreCheck._(
        'a transaction reads its own writes',
        _readYourWrites,
      ),
      const CacheStoreCheck._('a committed transaction is kept', _commit),
      const CacheStoreCheck._(
        'a transaction whose body throws is rolled back',
        _rollback,
      ),
      const CacheStoreCheck._(
        'concurrent transactions do not see half of each other',
        _isolation,
      ),
      const CacheStoreCheck._(
        'keys and values are kept byte for byte, empty values included',
        _bytes,
      ),
      const CacheStoreCheck._('many keys are scanned in pages', _manyKeys),
      const CacheStoreCheck._(
        'the data is kept when the store is closed and opened again',
        _reopen,
      ),
    ]);

Uint8List _bytesOf(List<int> bytes) => Uint8List.fromList(bytes);

Uint8List _k(String key) => _bytesOf(key.codeUnits);

String _show(Uint8List? bytes) =>
    bytes == null ? 'null' : '[${bytes.join(', ')}]';

bool _equal(Uint8List? a, Uint8List? b) {
  if (a == null || b == null) {
    return a == null && b == null;
  }
  return compareCacheStoreKeys(a, b) == 0;
}

void _expectValue(Uint8List? actual, Uint8List? expected, String what) {
  if (!_equal(actual, expected)) {
    throw StateError(
      '$what: expected ${_show(expected)}, got ${_show(actual)}',
    );
  }
}

void _expectKeys(
  List<CacheStoreEntry> actual,
  List<Uint8List> expected,
  String what,
) {
  final List<String> got = <String>[
    for (final CacheStoreEntry entry in actual) _show(entry.key),
  ];
  final List<String> want = <String>[
    for (final Uint8List key in expected) _show(key),
  ];
  if (got.join(' ') != want.join(' ')) {
    throw StateError('$what: expected the keys $want, got $got');
  }
}

/// A range that holds every key the checks write.
final Uint8List _all = Uint8List(0);
final Uint8List _allEnd = _bytesOf(<int>[0xff, 0xff, 0xff, 0xff, 0xff]);

Future<void> _getPutDelete(CacheStore store) async {
  await store.transaction((CacheStoreTransaction tx) async {
    _expectValue(await tx.get(_k('a')), null, 'get of a key never written');
    await tx.put(_k('a'), _k('1'));
    _expectValue(await tx.get(_k('a')), _k('1'), 'get after put');
    await tx.put(_k('a'), _k('2'));
    _expectValue(await tx.get(_k('a')), _k('2'), 'get after a second put');
    await tx.delete(_k('a'));
    _expectValue(await tx.get(_k('a')), null, 'get after delete');
    await tx.delete(_k('missing'));
    await tx.put(_k('b'), _k('3'));
  });
  await store.transaction((CacheStoreTransaction tx) async {
    _expectValue(
      await tx.get(_k('a')),
      null,
      'a deleted key, in the next transaction',
    );
    _expectValue(
      await tx.get(_k('b')),
      _k('3'),
      'a written key, in the next transaction',
    );
  }, readOnly: true);
}

Future<void> _keyOrder(CacheStore store) async {
  final List<Uint8List> sorted = <Uint8List>[
    _bytesOf(<int>[0x00]),
    _bytesOf(<int>[0x00, 0x00]),
    _bytesOf(<int>[0x00, 0x01]),
    _bytesOf(<int>[0x01]),
    _bytesOf(<int>[0x01, 0x00]),
    _bytesOf(<int>[0x01, 0xff, 0xff]),
    _bytesOf(<int>[0x02]),
    _bytesOf(<int>[0x7f]),
    _bytesOf(<int>[0x7f, 0xff]),
    _bytesOf(<int>[0x80]),
    _bytesOf(<int>[0x80, 0x00]),
    _bytesOf(<int>[0xc3, 0xa9]),
    _bytesOf(<int>[0xfe]),
    _bytesOf(<int>[0xff]),
    _bytesOf(<int>[0xff, 0x00]),
    _bytesOf(<int>[0xff, 0xff, 0xff]),
  ];
  final List<Uint8List> shuffled = sorted.toList()..shuffle(Random(7));
  await store.transaction((CacheStoreTransaction tx) async {
    for (final Uint8List key in shuffled) {
      await tx.put(key, key);
    }
  });
  await store.transaction((CacheStoreTransaction tx) async {
    final List<CacheStoreEntry> forward = await tx.scan(_all, _allEnd);
    _expectKeys(
      forward,
      sorted,
      'a scan of every key (bytes compare as unsigned, a prefix first)',
    );
    for (final CacheStoreEntry entry in forward) {
      _expectValue(entry.value, entry.key, 'the value of a scanned key');
    }
    _expectKeys(
      await tx.scan(_all, _allEnd, reverse: true),
      sorted.reversed.toList(),
      'a reverse scan of every key',
    );
  });
}

Future<void> _scanRanges(CacheStore store) async {
  Uint8List key(int byte, [List<int> rest = const <int>[]]) =>
      _bytesOf(<int>[byte, ...rest]);
  final List<Uint8List> keys = <Uint8List>[
    for (int i = 1; i <= 9; i++) key(i * 10),
    key(30, <int>[0]),
    key(30, <int>[0xff]),
  ];
  await store.transaction((CacheStoreTransaction tx) async {
    for (final Uint8List k in keys) {
      await tx.put(k, k);
    }
  });
  await store.transaction((CacheStoreTransaction tx) async {
    _expectKeys(
      await tx.scan(key(20), key(50)),
      <Uint8List>[
        key(20),
        key(30),
        key(30, <int>[0]),
        key(30, <int>[0xff]),
        key(40),
      ],
      'scan [20, 50): the start is included, the end is not',
    );
    _expectKeys(await tx.scan(key(20), key(50), reverse: true), <Uint8List>[
      key(40),
      key(30, <int>[0xff]),
      key(30, <int>[0]),
      key(30),
      key(20),
    ], 'reverse scan [20, 50)');
    _expectKeys(await tx.scan(key(20), key(50), limit: 2), <Uint8List>[
      key(20),
      key(30),
    ], 'scan [20, 50) limit 2');
    _expectKeys(
      await tx.scan(key(20), key(50), reverse: true, limit: 2),
      <Uint8List>[
        key(40),
        key(30, <int>[0xff]),
      ],
      'reverse scan [20, 50) limit 2: the largest keys',
    );
    _expectKeys(await tx.scan(key(30), key(31)), <Uint8List>[
      key(30),
      key(30, <int>[0]),
      key(30, <int>[0xff]),
    ], 'scan of the keys that start with 30');
    _expectKeys(
      await tx.scan(key(21), key(29)),
      <Uint8List>[],
      'scan of a range without keys',
    );
    _expectKeys(
      await tx.scan(key(50), key(50)),
      <Uint8List>[],
      'scan of an empty range',
    );
    _expectKeys(
      await tx.scan(key(25), key(35), limit: 0),
      <Uint8List>[],
      'scan with limit 0',
    );
    _expectKeys(await tx.scan(key(85), _allEnd), <Uint8List>[
      key(90),
    ], 'scan to the end');
  });
}

Future<void> _readYourWrites(CacheStore store) async {
  await store.transaction((CacheStoreTransaction tx) async {
    await tx.put(_k('a'), _k('old'));
    await tx.put(_k('c'), _k('old'));
  });
  await store.transaction((CacheStoreTransaction tx) async {
    await tx.put(_k('b'), _k('new'));
    await tx.put(_k('a'), _k('changed'));
    await tx.delete(_k('c'));
    _expectValue(
      await tx.get(_k('b')),
      _k('new'),
      'get of a key this transaction wrote',
    );
    _expectValue(
      await tx.get(_k('a')),
      _k('changed'),
      'get of a key this transaction changed',
    );
    _expectValue(
      await tx.get(_k('c')),
      null,
      'get of a key this transaction deleted',
    );
    final List<CacheStoreEntry> entries = await tx.scan(_all, _allEnd);
    _expectKeys(entries, <Uint8List>[
      _k('a'),
      _k('b'),
    ], 'scan inside the transaction');
    _expectValue(
      entries.first.value,
      _k('changed'),
      'scanned value of a key this transaction changed',
    );
    _expectKeys(
      await tx.scan(_all, _allEnd, reverse: true, limit: 1),
      <Uint8List>[_k('b')],
      'reverse scan inside the transaction',
    );
  });
}

Future<void> _commit(CacheStore store) async {
  final String result = await store.transaction((
    CacheStoreTransaction tx,
  ) async {
    await tx.put(_k('a'), _k('1'));
    return 'result';
  });
  if (result != 'result') {
    throw StateError(
      'transaction returned "$result", not what its body returned',
    );
  }
  await store.transaction((CacheStoreTransaction tx) async {
    _expectValue(
      await tx.get(_k('a')),
      _k('1'),
      'a key committed by the previous transaction',
    );
  }, readOnly: true);
}

Future<void> _rollback(CacheStore store) async {
  await store.transaction((CacheStoreTransaction tx) async {
    await tx.put(_k('kept'), _k('1'));
    await tx.put(_k('deleted'), _k('2'));
  });
  final Exception error = Exception('the body failed');
  Object? thrown;
  try {
    await store.transaction<void>((CacheStoreTransaction tx) async {
      await tx.put(_k('new'), _k('x'));
      await tx.put(_k('kept'), _k('changed'));
      await tx.delete(_k('deleted'));
      throw error;
    });
  } catch (e) {
    thrown = e;
  }
  if (!identical(thrown, error)) {
    throw StateError(
      'transaction threw $thrown instead of the error of its body',
    );
  }
  await store.transaction((CacheStoreTransaction tx) async {
    _expectValue(
      await tx.get(_k('new')),
      null,
      'a key put by a rolled back transaction',
    );
    _expectValue(
      await tx.get(_k('kept')),
      _k('1'),
      'a key changed by a rolled back transaction',
    );
    _expectValue(
      await tx.get(_k('deleted')),
      _k('2'),
      'a key deleted by a rolled back transaction',
    );
    _expectKeys(await tx.scan(_all, _allEnd), <Uint8List>[
      _k('deleted'),
      _k('kept'),
    ], 'scan after a rollback');
  });
  // The store still works after a rollback.
  await store.transaction(
    (CacheStoreTransaction tx) => tx.put(_k('after'), _k('3')),
  );
  await store.transaction((CacheStoreTransaction tx) async {
    _expectValue(
      await tx.get(_k('after')),
      _k('3'),
      'a key written after a rollback',
    );
  });
}

Future<void> _isolation(CacheStore store) async {
  for (final bool readOnly in <bool>[false, true]) {
    final Uint8List first = _k('first$readOnly');
    final Uint8List second = _k('second$readOnly');
    final Completer<void> firstWritten = Completer<void>();
    final Future<void> writer = store.transaction((
      CacheStoreTransaction tx,
    ) async {
      await tx.put(first, _k('1'));
      firstWritten.complete();
      // Long enough for the reader to start: it must wait for this transaction or not see its writes.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tx.put(second, _k('2'));
    });
    await firstWritten.future;
    final List<Uint8List?> seen = await store.transaction((
      CacheStoreTransaction tx,
    ) async {
      return <Uint8List?>[await tx.get(first), await tx.get(second)];
    }, readOnly: readOnly);
    await writer;
    if ((seen[0] == null) != (seen[1] == null)) {
      throw StateError(
        'a ${readOnly ? 'read-only' : 'read-write'} transaction that ran during another one saw '
        '${seen[0] == null ? 'only its second write' : 'only its first write'}',
      );
    }
  }
}

Future<void> _bytes(CacheStore store) async {
  final Random random = Random(42);
  final Map<String, (Uint8List, Uint8List)>
  written = <String, (Uint8List, Uint8List)>{
    'empty value': (_k('empty'), Uint8List(0)),
    'zero bytes': (_bytesOf(<int>[0, 0, 0]), _bytesOf(<int>[0, 0])),
    'all byte values': (
      _bytesOf(<int>[0x10, for (int i = 0; i < 256; i++) i]),
      _bytesOf(<int>[for (int i = 255; i >= 0; i--) i]),
    ),
    'a value of 256 KB': (
      _k('large'),
      _bytesOf(<int>[for (int i = 0; i < 256 * 1024; i++) random.nextInt(256)]),
    ),
    'a key of 1 KB': (
      _bytesOf(<int>[0x20, for (int i = 0; i < 1024; i++) random.nextInt(256)]),
      _k('v'),
    ),
  };
  await store.transaction((CacheStoreTransaction tx) async {
    for (final (Uint8List key, Uint8List value) in written.values) {
      await tx.put(key, value);
    }
  });
  await store.transaction((CacheStoreTransaction tx) async {
    for (final MapEntry<String, (Uint8List, Uint8List)> entry
        in written.entries) {
      final (Uint8List key, Uint8List value) = entry.value;
      final Uint8List? read = await tx.get(key);
      if (read == null || !_equal(read, value)) {
        throw StateError(
          '${entry.key}: the value read back differs (${read == null ? 'null' : '${read.length} bytes'} instead of '
          '${value.length} bytes)',
        );
      }
    }
    final List<CacheStoreEntry> scanned = await tx.scan(
      _k('empty'),
      _k('empty\u0000'),
    );
    if (scanned.length != 1 || scanned.single.value.isNotEmpty) {
      throw StateError(
        'an empty value must be scanned as an empty array, got $scanned',
      );
    }
  });
}

Future<void> _manyKeys(CacheStore store) async {
  const int count = 3000;
  Uint8List key(int i) => _bytesOf(<int>[0x40, i ~/ 256, i % 256]);
  await store.transaction((CacheStoreTransaction tx) async {
    for (int i = count - 1; i >= 0; i--) {
      await tx.put(key(i), _bytesOf(<int>[i % 256]));
    }
  });
  await store.transaction((CacheStoreTransaction tx) async {
    int next = 0;
    Uint8List start = _bytesOf(<int>[0x40]);
    final Uint8List end = _bytesOf(<int>[0x41]);
    while (true) {
      final List<CacheStoreEntry> page = await tx.scan(start, end, limit: 500);
      for (final CacheStoreEntry entry in page) {
        _expectValue(
          entry.key,
          key(next),
          'key ${next + 1} of $count, scanned in pages of 500',
        );
        next++;
      }
      if (page.length < 500) {
        break;
      }
      start = _bytesOf(<int>[...page.last.key, 0]);
    }
    if (next != count) {
      throw StateError('scanned $next keys in pages, not $count');
    }
  });
}

Future<void> _reopen(CacheStore store) async {
  await store.transaction((CacheStoreTransaction tx) async {
    await tx.put(_k('a'), _k('1'));
    await tx.put(_k('b'), _k('2'));
    await tx.put(_k('c'), Uint8List(0));
  });
  await store.transaction((CacheStoreTransaction tx) => tx.delete(_k('b')));
  await store.close();
  await store.open();
  await store.transaction((CacheStoreTransaction tx) async {
    _expectKeys(await tx.scan(_all, _allEnd), <Uint8List>[
      _k('a'),
      _k('c'),
    ], 'the keys after close and open');
    _expectValue(
      await tx.get(_k('a')),
      _k('1'),
      'a value after close and open',
    );
    _expectValue(
      await tx.get(_k('c')),
      Uint8List(0),
      'an empty value after close and open',
    );
  });
}
