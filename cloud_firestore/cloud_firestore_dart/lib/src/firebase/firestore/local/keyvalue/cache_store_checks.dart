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
/// the byte order of the keys, range scans (bounds, reverse order, limit), writes of puts and deletes together, reads
/// that run at the same time, keys and values kept byte for byte (also empty values), large writes, and data that is
/// still there after the store is closed and opened again.
final List<CacheStoreCheck> cacheStoreConformanceChecks =
    List<CacheStoreCheck>.unmodifiable(<CacheStoreCheck>[
      const CacheStoreCheck._('get, write and delete', _getWriteDelete),
      const CacheStoreCheck._(
        'keys are ordered by their unsigned bytes',
        _keyOrder,
      ),
      const CacheStoreCheck._(
        'scan honours its bounds, the reverse order and the limit',
        _scanRanges,
      ),
      const CacheStoreCheck._(
        'a write applies its puts and deletes together',
        _mixedWrite,
      ),
      const CacheStoreCheck._(
        'reads can run at the same time',
        _concurrentReads,
      ),
      const CacheStoreCheck._(
        'keys and values are kept byte for byte, empty values included',
        _bytes,
      ),
      const CacheStoreCheck._(
        'a write of many keys is kept and scanned in pages',
        _manyKeys,
      ),
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

Future<void> _put(CacheStore store, Uint8List key, Uint8List value) => store
    .write(<CacheStoreEntry>[CacheStoreEntry(key, value)], const <Uint8List>[]);

Future<void> _putAll(CacheStore store, Iterable<Uint8List> keys) =>
    store.write(<CacheStoreEntry>[
      for (final Uint8List key in keys) CacheStoreEntry(key, key),
    ], const <Uint8List>[]);

Future<void> _getWriteDelete(CacheStore store) async {
  _expectValue(await store.get(_k('a')), null, 'get of a key never written');
  await _put(store, _k('a'), _k('1'));
  _expectValue(await store.get(_k('a')), _k('1'), 'get after a put');
  await _put(store, _k('a'), _k('2'));
  _expectValue(await store.get(_k('a')), _k('2'), 'get after a second put');
  await store.write(const <CacheStoreEntry>[], <Uint8List>[_k('a')]);
  _expectValue(await store.get(_k('a')), null, 'get after a delete');
  await store.write(const <CacheStoreEntry>[], <Uint8List>[_k('missing')]);
  _expectValue(
    await store.get(_k('missing')),
    null,
    'get after the delete of a key that did not exist',
  );
  await store.write(const <CacheStoreEntry>[], const <Uint8List>[]);
  _expectKeys(
    await store.scan(_all, _allEnd),
    <Uint8List>[],
    'scan after the last key was deleted',
  );
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
  await _putAll(store, sorted.toList()..shuffle(Random(7)));
  final List<CacheStoreEntry> forward = await store.scan(_all, _allEnd);
  _expectKeys(
    forward,
    sorted,
    'a scan of every key (bytes compare as unsigned, a prefix first)',
  );
  for (final CacheStoreEntry entry in forward) {
    _expectValue(entry.value, entry.key, 'the value of a scanned key');
  }
  _expectKeys(
    await store.scan(_all, _allEnd, reverse: true),
    sorted.reversed.toList(),
    'a reverse scan of every key',
  );
}

Future<void> _scanRanges(CacheStore store) async {
  Uint8List key(int byte, [List<int> rest = const <int>[]]) =>
      _bytesOf(<int>[byte, ...rest]);
  await _putAll(store, <Uint8List>[
    for (int i = 1; i <= 9; i++) key(i * 10),
    key(30, <int>[0]),
    key(30, <int>[0xff]),
  ]);
  _expectKeys(
    await store.scan(key(20), key(50)),
    <Uint8List>[
      key(20),
      key(30),
      key(30, <int>[0]),
      key(30, <int>[0xff]),
      key(40),
    ],
    'scan [20, 50): the start is included, the end is not',
  );
  _expectKeys(await store.scan(key(20), key(50), reverse: true), <Uint8List>[
    key(40),
    key(30, <int>[0xff]),
    key(30, <int>[0]),
    key(30),
    key(20),
  ], 'reverse scan [20, 50)');
  _expectKeys(await store.scan(key(20), key(50), limit: 2), <Uint8List>[
    key(20),
    key(30),
  ], 'scan [20, 50) limit 2');
  _expectKeys(
    await store.scan(key(20), key(50), reverse: true, limit: 2),
    <Uint8List>[
      key(40),
      key(30, <int>[0xff]),
    ],
    'reverse scan [20, 50) limit 2: the largest keys',
  );
  _expectKeys(await store.scan(key(30), key(31)), <Uint8List>[
    key(30),
    key(30, <int>[0]),
    key(30, <int>[0xff]),
  ], 'scan of the keys that start with 30');
  _expectKeys(
    await store.scan(key(21), key(29)),
    <Uint8List>[],
    'scan of a range without keys',
  );
  _expectKeys(
    await store.scan(key(50), key(50)),
    <Uint8List>[],
    'scan of an empty range',
  );
  _expectKeys(
    await store.scan(key(25), key(35), limit: 0),
    <Uint8List>[],
    'scan with limit 0',
  );
  _expectKeys(await store.scan(key(85), _allEnd), <Uint8List>[
    key(90),
  ], 'scan to the end');
}

Future<void> _mixedWrite(CacheStore store) async {
  await store.write(<CacheStoreEntry>[
    CacheStoreEntry(_k('a'), _k('old')),
    CacheStoreEntry(_k('c'), _k('old')),
    CacheStoreEntry(_k('d'), _k('old')),
  ], const <Uint8List>[]);
  await store.write(
    <CacheStoreEntry>[
      CacheStoreEntry(_k('b'), _k('new')),
      CacheStoreEntry(_k('a'), _k('changed')),
    ],
    <Uint8List>[_k('c'), _k('missing')],
  );
  _expectValue(await store.get(_k('a')), _k('changed'), 'a changed key');
  _expectValue(await store.get(_k('b')), _k('new'), 'a new key');
  _expectValue(await store.get(_k('c')), null, 'a deleted key');
  _expectValue(await store.get(_k('d')), _k('old'), 'a key the write left');
  final List<CacheStoreEntry> entries = await store.scan(_all, _allEnd);
  _expectKeys(entries, <Uint8List>[
    _k('a'),
    _k('b'),
    _k('d'),
  ], 'scan after a write of puts and deletes');
  _expectValue(entries.first.value, _k('changed'), 'the scanned changed value');
}

Future<void> _concurrentReads(CacheStore store) async {
  final List<Uint8List> keys = <Uint8List>[
    for (int i = 0; i < 20; i++) _bytesOf(<int>[0x30, i]),
  ];
  await _putAll(store, keys);
  final List<Future<Object?>> reads = <Future<Object?>>[
    for (final Uint8List key in keys) store.get(key),
    for (int i = 0; i < 20; i++)
      store.scan(keys[i], _allEnd, reverse: i.isOdd, limit: 5),
  ];
  final List<Object?> results = await Future.wait(reads);
  for (int i = 0; i < 20; i++) {
    _expectValue(results[i] as Uint8List?, keys[i], 'a get among other reads');
    final List<Uint8List> expected = i.isOdd
        ? keys.skip(i).toList().reversed.take(5).toList()
        : keys.skip(i).take(5).toList();
    _expectKeys(
      results[20 + i]! as List<CacheStoreEntry>,
      expected,
      'a scan among other reads',
    );
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
  await store.write(<CacheStoreEntry>[
    for (final (Uint8List key, Uint8List value) in written.values)
      CacheStoreEntry(key, value),
  ], const <Uint8List>[]);
  for (final MapEntry<String, (Uint8List, Uint8List)> entry
      in written.entries) {
    final (Uint8List key, Uint8List value) = entry.value;
    final Uint8List? read = await store.get(key);
    if (read == null || !_equal(read, value)) {
      throw StateError(
        '${entry.key}: the value read back differs (${read == null ? 'null' : '${read.length} bytes'} instead of '
        '${value.length} bytes)',
      );
    }
  }
  final List<CacheStoreEntry> scanned = await store.scan(
    _k('empty'),
    _k('empty\u0000'),
  );
  if (scanned.length != 1 || scanned.single.value.isNotEmpty) {
    throw StateError(
      'an empty value must be scanned as an empty array, got $scanned',
    );
  }
}

Future<void> _manyKeys(CacheStore store) async {
  const int count = 3000;
  Uint8List key(int i) => _bytesOf(<int>[0x40, i ~/ 256, i % 256]);
  await store.write(<CacheStoreEntry>[
    for (int i = count - 1; i >= 0; i--)
      CacheStoreEntry(key(i), _bytesOf(<int>[i % 256])),
  ], const <Uint8List>[]);
  int next = 0;
  Uint8List start = _bytesOf(<int>[0x40]);
  final Uint8List end = _bytesOf(<int>[0x41]);
  while (true) {
    final List<CacheStoreEntry> page = await store.scan(start, end, limit: 500);
    for (final CacheStoreEntry entry in page) {
      _expectValue(
        entry.key,
        key(next),
        'key ${next + 1} of $count, scanned in pages of 500',
      );
      _expectValue(entry.value, _bytesOf(<int>[next % 256]), 'its value');
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
  await store.write(const <CacheStoreEntry>[], <Uint8List>[
    for (int i = 0; i < count; i += 2) key(i),
  ]);
  final List<CacheStoreEntry> left = await store.scan(
    _bytesOf(<int>[0x40]),
    end,
  );
  if (left.length != count ~/ 2) {
    throw StateError(
      '${left.length} keys left after deleting half of $count in one write, not ${count ~/ 2}',
    );
  }
}

Future<void> _reopen(CacheStore store) async {
  await store.write(<CacheStoreEntry>[
    CacheStoreEntry(_k('a'), _k('1')),
    CacheStoreEntry(_k('b'), _k('2')),
    CacheStoreEntry(_k('c'), Uint8List(0)),
  ], const <Uint8List>[]);
  await store.write(const <CacheStoreEntry>[], <Uint8List>[_k('b')]);
  await store.close();
  await store.open();
  _expectKeys(await store.scan(_all, _allEnd), <Uint8List>[
    _k('a'),
    _k('c'),
  ], 'the keys after close and open');
  _expectValue(
    await store.get(_k('a')),
    _k('1'),
    'a value after close and open',
  );
  _expectValue(
    await store.get(_k('c')),
    Uint8List(0),
    'an empty value after close and open',
  );
}
