// Ports of Android's SqlPersistenceStorageEngineTest (E- ids of rtdb_storage_engine_design.md
// section 15) plus the SQLite engine's own cases. Each group names the mutation of lib/ that makes
// it fail.
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
// not exported by storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
// not exported by storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
// not exported by storage_engine.dart
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/node_codec.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_storage_engine.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

const int _mib = 1024 * 1024;

Node node(Object? json) => nodeFromJson(json);

Node leafOfSize(int size) => nodeFromJson('x' * size);

final Node sampleNode = node(<String, Object?>{
  'foo': <String, Object?>{'bar': true, 'baz': 'string'},
  'qux': 2,
  'quu': 1.2,
});

final QueryParams sampleParams = QueryParams.defaultParams
    .orderBy(PathIndex(Path('child')))
    .startAt(node('startVal'), ChildKey('startKey'))
    .endAt(node('endVal'), ChildKey('endKey'))
    .limitToLast(5);

final QuerySpec sampleQuery = QuerySpec.fromPathAndWireObject(
  Path('foo'),
  sampleParams.toWireObject(),
);

QuerySpec defaultAt(String path) => QuerySpec.defaultAt(Path(path));

Set<ChildKey> keys(List<String> names) => <ChildKey>{
  for (final String name in names) ChildKey(name),
};

/// The fields of a tracked query (its `==` belongs to another owner and may still be a stub).
List<Object?> fieldsOf(TrackedQuery q) => <Object?>[
  q.id,
  q.querySpec,
  q.lastUse,
  q.complete,
  q.active,
];

TrackedQuery tracked(
  int id,
  QuerySpec spec,
  int lastUse, {
  bool complete = false,
  bool active = false,
}) => TrackedQuery(
  id: id,
  querySpec: spec,
  lastUse: lastUse,
  complete: complete,
  active: active,
);

/// One engine over a store in a fresh directory, reopened on demand.
final class Harness {
  final StoreFixture fixture = StoreFixture();
  final List<String> warnings = <String>[];
  late SqliteConnection connection;
  late SqliteStorageEngine engine;

  Future<void> open() async {
    connection = await fixture.open();
    engine = SqliteStorageEngine(
      connection,
      logger: (DatabaseLogLevel level, String message) => warnings.add(message),
    );
  }

  Future<void> reopen() async {
    engine.close();
    await open();
  }

  void dispose() {
    engine.close();
    fixture.dispose();
  }

  void run(void Function() body) {
    engine.beginTransaction();
    try {
      body();
      engine.setTransactionSuccessful();
    } finally {
      engine.endTransaction();
    }
  }

  /// The value of [sql] read through a second connection, as another process would see the file.
  Object? rawScalar(String sql) {
    final sqlite.Database db = fixture.raw();
    try {
      return StoreFixture.scalar(db, sql);
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  void rawExecute(String sql, [List<Object?> parameters = const <Object?>[]]) {
    final sqlite.Database db = fixture.raw();
    try {
      db.execute(sql, parameters);
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  /// The full `SUM` the size counter must equal.
  int fullSum() =>
      rawScalar(
            'SELECT coalesce(sum(length(CAST(path AS BLOB)) + length(value)), 0) '
            'FROM server_cache',
          )!
          as int;

  void overwrite(String path, Node value) =>
      run(() => engine.overwriteServerCache(Path(path), value));

  void mergeWrite(String path, CompoundWrite merge) =>
      run(() => engine.mergeIntoServerCacheWrite(Path(path), merge));

  void saveOverwrite(String path, Node value, int id) =>
      run(() => engine.saveUserOverwrite(Path(path), value, id));

  void saveMerge(String path, CompoundWrite merge, int id) =>
      run(() => engine.saveUserMerge(Path(path), merge, id));

  void saveQuery(TrackedQuery query) =>
      run(() => engine.saveTrackedQuery(query));

  void saveKeys(int id, Set<ChildKey> keys) =>
      run(() => engine.saveTrackedQueryKeys(id, keys));

  Node cache(String path) => engine.serverCache(Path(path));
}

void expectOverwrite(UserWriteRecord record, int id, String path, Node value) {
  expect(record.writeId, id);
  expect(record.path, Path(path));
  expect(record.isOverwrite, isTrue);
  expect(record.overwrite, value);
  expect(record.visible, isTrue);
}

void expectMerge(UserWriteRecord record, int id, String path, CompoundWrite m) {
  expect(record.writeId, id);
  expect(record.path, Path(path));
  expect(record.isMerge, isTrue);
  expect(record.merge, m);
}

void main() {
  late Harness h;

  setUp(() async {
    h = Harness();
    await h.open();
  });
  tearDown(() => h.dispose());

  // Mutation: in UserWriteRows.load, drop `ORDER BY id` and select `ORDER BY path DESC` (E-W8), or
  // write 'INSERT INTO' instead of 'INSERT OR REPLACE INTO' in UserWriteRows._save (E-W3, E-W7:
  // the constraint fails an assertion).
  group('user writes', () {
    test('E-W1 user write is persisted', () async {
      h.saveOverwrite('foo/bar', sampleNode, 1);
      await h.reopen();
      final List<UserWriteRecord> writes = h.engine.loadUserWrites();
      expect(writes, hasLength(1));
      expectOverwrite(writes.single, 1, 'foo/bar', sampleNode);
    });

    test('E-W2 user merge is persisted', () async {
      final CompoundWrite merge = CompoundWrite.fromValue(<String, Object?>{
        'foo': <String, Object?>{'bar': 1, 'baz': 'string'},
        'quu': true,
      });
      h.saveMerge('foo/bar', merge, 1);
      await h.reopen();
      expectMerge(h.engine.loadUserWrites().single, 1, 'foo/bar', merge);
    });

    test('E-W3 same write id overwrites the old write', () {
      h.saveOverwrite('foo/bar', node('first'), 1);
      h.saveOverwrite('other/path', node('second'), 1);
      expectOverwrite(
        h.engine.loadUserWrites().single,
        1,
        'other/path',
        node('second'),
      );
    });

    test('E-W4 huge writes round-trip in one row', () {
      final Node tenMeg = leafOfSize(10 * _mib);
      final CompoundWrite merge = CompoundWrite.empty.addWrite(
        Path('update'),
        tenMeg,
      );
      h.saveOverwrite('foo/bar', tenMeg, 1);
      h.saveMerge('foo/baz', merge, 2);
      final List<UserWriteRecord> writes = h.engine.loadUserWrites();
      expect(writes, hasLength(2));
      expectOverwrite(writes[0], 1, 'foo/bar', tenMeg);
      expectMerge(writes[1], 2, 'foo/baz', merge);
      expect(h.rawScalar('SELECT count(*) FROM user_writes'), 2);
    });

    test('E-W5 huge writes can be deleted', () {
      h.saveOverwrite('foo/bar', leafOfSize(10 * _mib), 1);
      h.run(() => h.engine.removeUserWrite(1));
      expect(h.engine.loadUserWrites(), isEmpty);
    });

    test('E-W6 huge and small writes interleaved', () {
      final Node tenMeg = leafOfSize(10 * _mib);
      final Node tenMegPlusOne = leafOfSize(10 * _mib + 1);
      h.saveOverwrite('foo/1', node('node-1'), 1);
      h.saveOverwrite('foo/2', tenMeg, 2);
      h.saveOverwrite('foo/3', node('node-3'), 3);
      h.saveOverwrite('foo/4', tenMegPlusOne, 4);
      final List<UserWriteRecord> writes = h.engine.loadUserWrites();
      expect(writes, hasLength(4));
      expectOverwrite(writes[0], 1, 'foo/1', node('node-1'));
      expectOverwrite(writes[1], 2, 'foo/2', tenMeg);
      expectOverwrite(writes[2], 3, 'foo/3', node('node-3'));
      expectOverwrite(writes[3], 4, 'foo/4', tenMegPlusOne);
    });

    test('E-W7 same id overwrites a huge write', () {
      h.saveOverwrite('foo/bar', leafOfSize(10 * _mib), 1);
      h.saveOverwrite('other/path', node('second'), 1);
      expectOverwrite(
        h.engine.loadUserWrites().single,
        1,
        'other/path',
        node('second'),
      );
    });

    test('E-W8 writes are returned in id order', () {
      const int count = 20;
      for (int i = count - 1; i >= 0; i--) {
        h.saveOverwrite('foo/$i', node(i), i);
      }
      final List<UserWriteRecord> writes = h.engine.loadUserWrites();
      expect(writes, hasLength(count));
      for (int i = 0; i < count; i++) {
        expectOverwrite(writes[i], i, 'foo/$i', node(i));
      }
    });

    test('E-W9 removeAllUserWrites', () {
      h.saveOverwrite('foo/1', node('node-1'), 1);
      h.saveOverwrite('foo/2', leafOfSize(10 * _mib), 2);
      h.saveMerge(
        'foo/baz',
        CompoundWrite.empty.addWrite(Path('update'), leafOfSize(_mib)),
        3,
      );
      h.run(h.engine.removeAllUserWrites);
      expect(h.engine.loadUserWrites(), isEmpty);
    });

    test('E-A2 writes come back in id order after a reopen', () async {
      h.saveOverwrite('c', node('c'), 3);
      h.saveOverwrite('a', node('a'), 1);
      h.saveMerge('b', CompoundWrite.fromValue(<String, Object?>{'x': 1}), 2);
      await h.reopen();
      expect(
        h.engine.loadUserWrites().map((UserWriteRecord w) => w.writeId),
        <int>[1, 2, 3],
      );
    });
  });

  // Mutation: in ServerCacheRows.load, take the ancestor branch for every row
  // (`node = rowNode.getChild(...)` without the `rowPath.contains(path)` test) or swap the range
  // end from `0` to `/` in PathKey.rangeEnd (E-C16, E-N3: nothing below is loaded).
  group('server cache', () {
    test('E-C1 cache saved is returned', () {
      h.overwrite('foo', sampleNode);
      expect(h.cache('foo'), sampleNode);
    });

    test('E-C2 cache saved is returned at the root', () {
      h.overwrite('', sampleNode);
      expect(h.cache(''), sampleNode);
    });

    test('E-C3 later writes overwrite older writes', () {
      h.overwrite('foo', sampleNode);
      h.overwrite('foo/bar', node('later-bar'));
      h.overwrite('unaffected', node('unaffected'));
      h.overwrite('foo/later-qux', node('later-qux'));
      h.overwrite('foo/bar', node('latest-bar'));
      final Node expected = sampleNode
          .updateChild(Path('bar'), node('latest-bar'))
          .updateChild(Path('later-qux'), node('later-qux'));
      expect(h.cache('foo'), expected);
    });

    test('E-C4 later writes overwrite older deeper writes', () {
      h.overwrite('foo', sampleNode);
      h.overwrite('foo/bar', node('later-bar'));
      h.overwrite('unaffected', node('unaffected'));
      h.overwrite('foo/later-qux', node('later-qux'));
      h.overwrite('foo/bar', node('latest-bar'));
      h.overwrite('foo', node('latest-foo'));
      expect(h.cache('foo'), node('latest-foo'));
    });

    test('E-C5 later writes do not affect an unaffected path', () {
      h.overwrite('foo', sampleNode);
      h.overwrite('unaffected', node('unaffected'));
      h.overwrite('foo', node('latest-foo'));
      expect(h.cache('unaffected'), node('unaffected'));
    });

    test('E-C6 merge on an empty cache gives results', () {
      h.mergeWrite(
        'foo',
        CompoundWrite.fromValue(<String, Object?>{
          'foo': 'foo-value',
          'bar': 'bar-value',
        }),
      );
      expect(
        h.cache('foo'),
        node(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
      );
    });

    test('E-C7 merge partly overwriting a previous write', () {
      h.overwrite(
        'foo',
        node(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
      );
      h.mergeWrite(
        'foo',
        CompoundWrite.fromValue(<String, Object?>{
          'foo': 'new-foo-value',
          'baz': 'baz-value',
        }),
      );
      expect(
        h.cache('foo'),
        node(<String, Object?>{
          'foo': 'new-foo-value',
          'bar': 'bar-value',
          'baz': 'baz-value',
        }),
      );
    });

    test('E-C8 merge partly overwriting a previous merge', () {
      h.mergeWrite(
        'foo',
        CompoundWrite.fromValue(<String, Object?>{
          'foo': 'foo-value',
          'bar': 'bar-value',
        }),
      );
      h.mergeWrite(
        'foo',
        CompoundWrite.fromValue(<String, Object?>{
          'foo': 'new-foo-value',
          'baz': 'baz-value',
        }),
      );
      expect(
        h.cache('foo'),
        node(<String, Object?>{
          'foo': 'new-foo-value',
          'bar': 'bar-value',
          'baz': 'baz-value',
        }),
      );
    });

    test('E-C9 overwrite removes previous merges', () {
      h.overwrite(
        'foo',
        node(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
      );
      h.mergeWrite(
        'foo',
        CompoundWrite.fromValue(<String, Object?>{
          'foo': 'new-foo-value',
          'baz': 'baz-value',
        }),
      );
      final Node replacing = node(<String, Object?>{
        'qux': 'qux-value',
        'quu': 'quu-value',
      });
      h.overwrite('foo', replacing);
      expect(h.cache('foo'), replacing);
    });

    test('E-C10 empty overwrite deletes a node from a higher write', () {
      h.overwrite(
        'foo',
        node(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
      );
      h.overwrite('foo/bar', node(null));
      expect(h.cache('foo'), node(<String, Object?>{'foo': 'foo-value'}));
    });

    test('E-C11 deeper read from a higher set', () {
      h.overwrite(
        'foo',
        node(<String, Object?>{'foo': 'foo-value', 'bar': 'bar-value'}),
      );
      expect(h.cache('foo/bar'), node('bar-value'));
    });

    // Mutation: in ServerCacheRows._saveNested, raise splitThreshold to 1 << 40 (one row per
    // write) or double it (a row holds a node of more than 16 KiB), or halve it (no row holds a
    // node of more than 8 KiB).
    test('E-C12 huge node is split at 16 KiB and reads back whole', () {
      final Map<String, Object?> outer = <String, Object?>{};
      for (int i = 0; i < 100; i++) {
        final Map<String, Object?> inner = <String, Object?>{};
        for (int j = 0; j < i; j++) {
          inner['inner-$j'] = <String, Object?>{
            for (int k = 0; k < j; k++) 'key-$k': 'leaf-$k',
          };
        }
        outer['outer-$i'] = inner;
      }
      final Node value = node(outer);
      h.overwrite('foo', value);
      expect(h.cache('foo'), value);
      // Every row holds a node of at most 16 KiB (estimated JSON), and some row one of more
      // than 8 KiB: the split is at the threshold, not below it.
      int largest = 0;
      final sqlite.Database db = h.fixture.raw();
      try {
        for (final sqlite.Row row in db.select(
          'SELECT value FROM server_cache',
        )) {
          final Node stored = NodeCodec.decodeNode(row['value'] as Uint8List);
          largest = max(largest, estimateSerializedNodeSize(stored));
        }
      } finally {
        StoreFixture.closeRaw(db);
      }
      expect(largest, lessThanOrEqualTo(16 * 1024));
      expect(largest, greaterThan(8 * 1024));
    });

    test('E-C13 many large leaf nodes', () {
      final Node oneMeg = leafOfSize(_mib);
      Node outer = ChildrenNode.empty;
      for (int i = 0; i < 30; i++) {
        outer = outer.updateImmediateChild(ChildKey('key-$i'), oneMeg);
      }
      h.overwrite('foo', outer);
      expect(h.cache('foo'), outer);
    });

    test('E-C14 deep overwrite with a nested large node', () {
      final Node first = node(<String, Object?>{
        'a': <String, Object?>{'aa': 1},
      });
      final Node newA = ChildrenNode.empty.updateChild(
        Path('ab'),
        leafOfSize(_mib),
      );
      h.overwrite('', first);
      h.overwrite('a', newA);
      expect(h.cache(''), first.updateChild(Path('a'), newA));
    });

    test('E-C15 priority', () {
      h.overwrite('foo/bar', node('bar-value'));
      h.overwrite('foo/.priority', node('prio-value'));
      expect(
        h.cache('foo'),
        node(<String, Object?>{'bar': 'bar-value', '.priority': 'prio-value'}),
      );
    });

    test('E-C16 similar siblings are not loaded', () {
      h.overwrite('foo/123', node('value'));
      h.overwrite('foo/1230', node('sibling-value'));
      expect(h.cache('foo/123'), node('value'));
    });

    // Ignored upstream ("a rare edge case around priorities"). Mutation: return early at the top
    // of ServerCacheRows._clearEmptiedNodes: the priority comes back with baz.
    test('E-C17 a priority is cleared when its node empties', () {
      h.overwrite('foo', node(<String, Object?>{'bar': 'bar-value'}));
      h.overwrite('foo/.priority', node('prio-value'));
      h.overwrite('foo/bar', node(null));
      h.overwrite('foo/baz', node('baz-value'));
      expect(h.cache('foo'), node(<String, Object?>{'baz': 'baz-value'}));
    });

    test(
      'E-C17b a split node with a priority loses it when emptied by a merge',
      () {
        final Map<String, Object?> big = <String, Object?>{
          for (int i = 0; i < 40; i++) 'c$i': 'v' * 1024,
          '.priority': 7,
        };
        h.overwrite('foo', node(big));
        expect(h.cache('foo').priority, node(7));
        h.mergeWrite(
          'foo',
          CompoundWrite.fromValue(<String, Object?>{
            for (int i = 0; i < 40; i++) 'c$i': null,
          }),
        );
        h.overwrite('foo/new', node('n'));
        expect(h.cache('foo'), node(<String, Object?>{'new': 'n'}));
      },
    );

    // Review L1. Mutation: in ServerCacheRows._hasPriority, return false after the `.priority` row
    // check (the priority inside the /a/ row comes back with b).
    test(
      'a priority inside an ancestor row is cleared when its node empties',
      () {
        h.overwrite('a', node(<String, Object?>{'z': 1, '.priority': 5}));
        h.overwrite('a/z', node(null));
        expect(h.cache('a').isEmpty, isTrue);
        h.overwrite('a/b', node(2));
        final Node a = h.cache('a');
        expect(a, node(<String, Object?>{'b': 2}));
        expect(a.priority.isEmpty, isTrue);
        expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
      },
    );

    test('a node that keeps data keeps its priority after a deletion', () {
      h.overwrite('a', node(<String, Object?>{'y': 1, 'z': 1, '.priority': 5}));
      h.overwrite('a/z', node(null));
      expect(h.cache('a').priority, node(5));
    });

    test('E-C18 huge leaf node', () {
      final Node tenMeg = leafOfSize(10 * _mib);
      h.overwrite('foo', tenMeg);
      expect(h.cache('foo'), tenMeg);
    });

    test('E-C19 huge leaf node siblings', () {
      final Node tenMeg = leafOfSize(10 * _mib);
      final Node tenMegPlusOne = leafOfSize(10 * _mib + 1);
      h.overwrite('foo/one', tenMeg);
      h.overwrite('foo/two', tenMegPlusOne);
      final Node value = h.cache('foo');
      expect(value.getChild(Path('one')), tenMeg);
      expect(value.getChild(Path('two')), tenMegPlusOne);
    });

    test('E-C20 huge leaf node, then a tiny leaf node', () {
      h.overwrite('foo', leafOfSize(10 * _mib));
      final Node tiny = leafOfSize(1024);
      h.overwrite('foo', tiny);
      expect(h.cache('foo'), tiny);
    });

    test('E-C21 huge leaf node, then a smaller leaf node', () {
      h.overwrite('foo', leafOfSize(10 * _mib));
      final Node fiveMeg = leafOfSize(5 * _mib);
      h.overwrite('foo', fiveMeg);
      expect(h.cache('foo'), fiveMeg);
    });

    test('E-C22 huge leaf node, then a deeper set', () {
      h.overwrite('foo', leafOfSize(10 * _mib));
      h.overwrite('foo/deep', node('deep-value'));
      expect(h.cache('foo'), node(<String, Object?>{'deep': 'deep-value'}));
    });

    test('mergeIntoServerCache with a node replaces only its children', () {
      h.overwrite('a', node(<String, Object?>{'b': 1, 'c': 2}));
      h.run(
        () => h.engine.mergeIntoServerCache(
          Path('a'),
          node(<String, Object?>{
            'c': <String, Object?>{'x': 3},
            'd': 4,
          }),
        ),
      );
      expect(
        h.cache('a'),
        node(<String, Object?>{
          'b': 1,
          'c': <String, Object?>{'x': 3},
          'd': 4,
        }),
      );
    });

    test('E-N1 unusual keys round-trip and range scans stay exact', () {
      const List<String> names = <String>[
        'a',
        'a-b',
        'a b',
        'a!',
        'a,b',
        'ü',
        '日本',
        '😀',
        'a😀',
      ];
      for (final String name in names) {
        h.overwrite('k/$name', node(<String, Object?>{'v': name}));
        h.overwrite('k/$name/child', node('child of $name'));
      }
      for (final String name in names) {
        expect(
          h.cache('k/$name'),
          node(<String, Object?>{'v': name, 'child': 'child of $name'}),
          reason: name,
        );
      }
      expect(h.cache('k').numChildren, names.length);
    });

    test('E-N3 sibling /a-b/ is not loaded with /a/', () {
      h.overwrite('a', node('a'));
      h.overwrite('a-b', node('a-b'));
      h.overwrite('a/b', node('a/b'));
      expect(h.cache('a'), node(<String, Object?>{'b': 'a/b'}));
      expect(h.cache('a-b'), node('a-b'));
    });

    test(
      'E-N2 numbers keep their type through the server cache and writes',
      () async {
        final Map<String, Object?> json = <String, Object?>{
          'big': 9007199254740993,
          'one': 1.0,
          'zero': -0.0,
        };
        h.overwrite('n', node(json));
        h.saveOverwrite('w', node(json), 1);
        await h.reopen();
        for (final Node stored in <Node>[
          h.cache('n'),
          h.engine.loadUserWrites().single.overwrite!,
        ]) {
          final Map<String, Object?> back =
              stored.toJson(exportFormat: true)! as Map<String, Object?>;
          expect(back['big'], allOf(isA<int>(), 9007199254740993));
          expect(back['one'], isA<double>());
          expect((back['zero']! as double).isNegative, isTrue);
        }
      },
    );
  });

  // Mutation: in ServerCacheRows._saveRow, drop `size += ...` (E-S1..S4 fail), or in
  // SqliteStorageEngine.endTransaction drop `_serverCache.size = _sizeAtBegin;` (E-S4's rollback
  // case fails).
  group('size', () {
    test('E-S1 size of nodes', () {
      final int sampleSize = estimateSerializedNodeSize(sampleNode);
      h.overwrite('foo', sampleNode);
      final int expected = sampleSize + 4;
      // Android's bound, then the exact count of this engine.
      expect(
        (h.engine.serverCacheEstimatedSizeInBytes() - expected).abs(),
        lessThan(20),
      );
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    });

    test('E-S2 size accounts for paths (bytes)', () {
      final int sampleSize = estimateSerializedNodeSize(sampleNode);
      const String path =
          'super/duper/long/mega/deep/but/also/super/insightful/'
          'but/not/quite/max/path/depth/length';
      h.overwrite(path, sampleNode);
      expect(
        (h.engine.serverCacheEstimatedSizeInBytes() -
                (sampleSize + path.length))
            .abs(),
        lessThan(20),
      );
      h.overwrite('ü/日本', node(1));
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    });

    test('E-S3 size for hundreds of nodes', () {
      final int sampleSize = estimateSerializedNodeSize(sampleNode);
      int expected = 0;
      const int count = 200;
      h.run(() {
        for (int i = 0; i < count; i++) {
          final String path = 'super/duper/long/path/$i';
          h.engine.overwriteServerCache(Path(path), sampleNode);
          expected += sampleSize + path.length;
        }
      });
      expect(
        (h.engine.serverCacheEstimatedSizeInBytes() - expected).abs(),
        lessThan(20 * count),
      );
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    });

    test('a transaction refused as busy leaves the counter equal to the rows', () {
      // Fails without the `!_connection.commit()` branch of SqliteStorageEngine.endTransaction
      // (sqlite_storage_engine.dart:89-91): the refused write is still counted.
      h.overwrite('a', sampleNode);
      final sqlite.Database other = h.fixture.raw();
      try {
        other.execute('BEGIN IMMEDIATE');
        h.overwrite('b', sampleNode);
        other.execute('ROLLBACK');
      } finally {
        StoreFixture.closeRaw(other);
      }

      expect(h.connection.isDurable, isTrue);
      expect(h.cache('b').isEmpty, isTrue);
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());

      h.overwrite('b', sampleNode);
      expect(h.cache('b'), sampleNode);
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    });

    test(
      'E-S4 the counter equals the full SUM after random operations and a rollback',
      () async {
        final Random random = Random(42);
        const List<String> names = <String>['a', 'b', 'c', 'd'];
        String randomPath() => <String>[
          for (int i = 0; i <= random.nextInt(3); i++)
            names[random.nextInt(names.length)],
        ].join('/');
        Node randomNode() {
          switch (random.nextInt(5)) {
            case 0:
              return ChildrenNode.empty;
            case 1:
              return node(<String, Object?>{
                for (int i = 0; i < 30; i++) 'k$i': 'v' * 1024,
              });
            default:
              return node(<String, Object?>{
                names[random.nextInt(names.length)]: random.nextInt(1000),
                'x': 'y' * random.nextInt(50),
              });
          }
        }

        void randomOperation() {
          final Path path = Path(randomPath());
          switch (random.nextInt(3)) {
            case 0:
              h.engine.overwriteServerCache(path, randomNode());
            case 1:
              h.engine.mergeIntoServerCache(path, randomNode());
            default:
              h.engine.mergeIntoServerCacheWrite(
                path,
                CompoundWrite.empty
                    .addWrite(Path(randomPath()), randomNode())
                    .addWrite(Path(randomPath()), randomNode()),
              );
          }
        }

        for (int batch = 0; batch < 100; batch++) {
          h.run(() {
            for (int i = 0; i < 100; i++) {
              randomOperation();
            }
          });
        }
        expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());

        final int before = h.engine.serverCacheEstimatedSizeInBytes();
        h.engine.beginTransaction();
        for (int i = 0; i < 50; i++) {
          randomOperation();
        }
        h.engine.endTransaction();
        expect(h.engine.serverCacheEstimatedSizeInBytes(), before);
        expect(h.fullSum(), before);

        await h.reopen();
        expect(h.engine.serverCacheEstimatedSizeInBytes(), before);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  // Mutation: in TrackedQueryRows.resetPreviouslyActive, drop `WHERE active = 1` (E-Q4: inactive
  // queries get the new lastUse), or drop the tracked_keys delete in TrackedQueryRows.delete
  // (E-K5).
  group('tracked queries', () {
    test('E-Q1 save and load tracked queries', () async {
      final List<TrackedQuery> queries = <TrackedQuery>[
        tracked(1, sampleQuery, 100),
        tracked(2, defaultAt('a'), 200, complete: true),
        tracked(3, defaultAt('b'), 300),
        tracked(4, defaultAt('foo'), 400),
      ];
      for (final TrackedQuery query in queries.reversed) {
        h.saveQuery(query);
      }
      await h.reopen();
      expect(
        h.engine.loadTrackedQueries().map(fieldsOf),
        queries.map(fieldsOf),
      );
    });

    test('E-Q2 overwrite tracked query by id', () {
      h.saveQuery(tracked(1, sampleQuery, 100));
      final TrackedQuery replaced = tracked(
        1,
        defaultAt('foo'),
        200,
        complete: true,
        active: true,
      );
      h.saveQuery(replaced);
      expect(h.engine.loadTrackedQueries().map(fieldsOf), <List<Object?>>[
        fieldsOf(replaced),
      ]);
    });

    test('E-Q3 delete tracked query', () {
      final TrackedQuery query1 = tracked(1, defaultAt('a'), 200);
      final TrackedQuery query2 = tracked(
        2,
        defaultAt('b'),
        300,
        complete: true,
      );
      final TrackedQuery query3 = tracked(3, defaultAt('c'), 400, active: true);
      h
        ..saveQuery(query1)
        ..saveQuery(query2)
        ..saveQuery(query3)
        ..run(() => h.engine.deleteTrackedQuery(2));
      expect(h.engine.loadTrackedQueries().map(fieldsOf), <List<Object?>>[
        fieldsOf(query1),
        fieldsOf(query3),
      ]);
    });

    test('E-Q4 reset previously active tracked queries', () {
      final TrackedQuery inactive1 = tracked(1, defaultAt('a'), 200);
      final TrackedQuery active1 = tracked(
        2,
        defaultAt('b'),
        300,
        active: true,
      );
      final TrackedQuery inactive2 = tracked(3, defaultAt('c'), 400);
      final TrackedQuery active2 = tracked(
        4,
        defaultAt('d'),
        500,
        active: true,
      );
      for (final TrackedQuery q in <TrackedQuery>[
        inactive1,
        active1,
        inactive2,
        active2,
      ]) {
        h.saveQuery(q);
      }
      h.run(() => h.engine.resetPreviouslyActiveTrackedQueries(234));
      expect(h.engine.loadTrackedQueries().map(fieldsOf), <List<Object?>>[
        fieldsOf(inactive1),
        fieldsOf(tracked(2, defaultAt('b'), 234)),
        fieldsOf(inactive2),
        fieldsOf(tracked(4, defaultAt('d'), 234)),
      ]);
    });

    test('reset outside a transaction runs as its own transaction', () async {
      h.saveQuery(tracked(1, defaultAt('a'), 100, active: true));
      h.engine.resetPreviouslyActiveTrackedQueries(300);
      expect(h.connection.inTransaction, isFalse);
      await h.reopen();
      expect(fieldsOf(h.engine.loadTrackedQueries().single), <Object?>[
        1,
        defaultAt('a'),
        300,
        false,
        false,
      ]);
    });

    test('a second id for the same query replaces the first with its keys', () {
      h.saveQuery(tracked(1, defaultAt('a'), 100));
      h.saveKeys(1, keys(<String>['x']));
      h.saveQuery(tracked(2, defaultAt('a'), 200));
      expect(h.engine.loadTrackedQueries().map((TrackedQuery q) => q.id), <int>[
        2,
      ]);
      expect(h.engine.loadTrackedQueryKeys(<int>{1}), isEmpty);
    });

    test('E-K1 save and load tracked query keys', () {
      final Set<ChildKey> saved = keys(<String>['foo', '☁', '10']);
      h.saveKeys(1, saved);
      h.saveKeys(2, keys(<String>['not', 'included']));
      expect(h.engine.loadTrackedQueryKeys(<int>{1}), saved);
    });

    test('E-K2 save overwrites tracked query keys', () {
      h.saveKeys(1, keys(<String>['a', 'b', 'c']));
      h.saveKeys(1, keys(<String>['c', 'd', 'e']));
      expect(
        h.engine.loadTrackedQueryKeys(<int>{1}),
        keys(<String>['c', 'd', 'e']),
      );
    });

    test('E-K3 load tracked query keys by set', () {
      h.saveKeys(1, keys(<String>['a', 'b', 'c']));
      h.saveKeys(2, keys(<String>['c', 'd', 'e']));
      h.saveKeys(3, keys(<String>['not', 'included']));
      expect(
        h.engine.loadTrackedQueryKeys(<int>{1, 2}),
        keys(<String>['a', 'b', 'c', 'd', 'e']),
      );
      expect(h.engine.loadTrackedQueryKeys(<int>{}), isEmpty);
    });

    test('loading keys of more ids than one statement binds', () {
      h.run(() {
        for (int id = 0; id < 1200; id++) {
          h.engine.saveTrackedQueryKeys(id, keys(<String>['k$id']));
        }
      });
      expect(
        h.engine.loadTrackedQueryKeys(<int>{for (int i = 0; i < 1200; i++) i}),
        hasLength(1200),
      );
    });

    test('E-K4 update tracked query keys', () {
      h.saveKeys(1, keys(<String>['a', 'b', 'c']));
      h.run(
        () => h.engine.updateTrackedQueryKeys(
          1,
          keys(<String>['d', 'e']),
          keys(<String>['a', 'b', 'not-stored']),
        ),
      );
      expect(
        h.engine.loadTrackedQueryKeys(<int>{1}),
        keys(<String>['c', 'd', 'e']),
      );
    });

    test('E-K5 deleting a tracked query removes its keys', () {
      final TrackedQuery query1 = tracked(1, defaultAt('a'), 200, active: true);
      final TrackedQuery query2 = tracked(2, defaultAt('b'), 300, active: true);
      h
        ..saveQuery(query1)
        ..saveQuery(query2)
        ..saveKeys(1, keys(<String>['a', 'b']))
        ..saveKeys(2, keys(<String>['b', 'c']))
        ..run(() => h.engine.deleteTrackedQuery(1));
      expect(h.engine.loadTrackedQueries().map(fieldsOf), <List<Object?>>[
        fieldsOf(query2),
      ]);
      expect(h.engine.loadTrackedQueryKeys(<int>{1}), isEmpty);
      expect(h.engine.loadTrackedQueryKeys(<int>{2}), keys(<String>['b', 'c']));
    });
  });

  // Mutation: in SqliteStorageEngine._requireTransaction, drop the throw (the calls with nothing
  // to write then pass silently).
  group('transactions', () {
    test('E-T1 every mutation outside a transaction is a StateError', () {
      final PruneForest forest = PruneForest.fromTree(
        ImmutableTree<bool>.empty(),
      );
      final Map<String, void Function()> mutations = <String, void Function()>{
        'saveUserOverwrite': () =>
            h.engine.saveUserOverwrite(Path('a'), node(1), 1),
        'saveUserMerge': () =>
            h.engine.saveUserMerge(Path('a'), CompoundWrite.empty, 1),
        'removeUserWrite': () => h.engine.removeUserWrite(1),
        'removeAllUserWrites': h.engine.removeAllUserWrites,
        'overwriteServerCache': () =>
            h.engine.overwriteServerCache(Path('a'), node(1)),
        'mergeIntoServerCache': () =>
            h.engine.mergeIntoServerCache(Path('a'), ChildrenNode.empty),
        'mergeIntoServerCacheWrite': () =>
            h.engine.mergeIntoServerCacheWrite(Path('a'), CompoundWrite.empty),
        'saveTrackedQuery': () =>
            h.engine.saveTrackedQuery(tracked(1, defaultAt('a'), 1)),
        'deleteTrackedQuery': () => h.engine.deleteTrackedQuery(1),
        'saveTrackedQueryKeys': () =>
            h.engine.saveTrackedQueryKeys(1, <ChildKey>{}),
        'updateTrackedQueryKeys': () =>
            h.engine.updateTrackedQueryKeys(1, <ChildKey>{}, <ChildKey>{}),
        'pruneCache': () => h.engine.pruneCache(Path.empty, forest),
        'setTransactionSuccessful': h.engine.setTransactionSuccessful,
        'endTransaction': h.engine.endTransaction,
      };
      for (final MapEntry<String, void Function()> mutation
          in mutations.entries) {
        expect(mutation.value, throwsStateError, reason: mutation.key);
      }
    });

    test(
      'a nested beginTransaction is a StateError and keeps the outer one',
      () {
        h.engine.beginTransaction();
        expect(h.engine.beginTransaction, throwsStateError);
        h.engine.saveUserOverwrite(Path('a'), node(1), 1);
        h.engine.setTransactionSuccessful();
        h.engine.endTransaction();
        expect(h.engine.loadUserWrites(), hasLength(1));
      },
    );

    // Mutation: in SqliteStorageEngine.endTransaction, always call `_connection.commit()`.
    test(
      'E-A1 an ack is atomic: not marked successful, both halves roll back',
      () {
        h.saveOverwrite('a', node('pending'), 1);
        h.engine.beginTransaction();
        h.engine.removeUserWrite(1);
        h.engine.overwriteServerCache(Path('a'), node('pending'));
        h.engine.endTransaction();
        expect(h.engine.loadUserWrites().single.writeId, 1);
        expect(h.cache('a').isEmpty, isTrue);
      },
    );

    test(
      'E-A1 an ack is atomic: a close in the middle undoes both halves',
      () async {
        h.saveOverwrite('a', node('pending'), 1);
        h.engine.beginTransaction();
        h.engine.removeUserWrite(1);
        h.engine.overwriteServerCache(Path('a'), node('pending'));
        await h.reopen();
        expect(h.engine.loadUserWrites().single.writeId, 1);
        expect(h.cache('a').isEmpty, isTrue);
      },
    );
  });

  // What the client's persistence managers assume of an engine (commit 4ded0c9e).
  // Mutation: in SqliteStorageEngine.endTransaction, skip `_connection.rollback()` when
  // `_successful` is false (the next beginTransaction is a StateError); or in
  // SqliteStorageEngine.resetPreviouslyActiveTrackedQueries, always open a transaction (the call
  // inside one throws).
  group('manager assumptions', () {
    test('a body that throws ends rolled back and the engine stays usable', () {
      expect(
        () => h.run(() {
          h.engine.saveUserOverwrite(Path('a'), node(1), 1);
          throw const FormatException('body failed');
        }),
        throwsFormatException,
      );
      expect(h.engine.loadUserWrites(), isEmpty);
      h.saveOverwrite('b', node(2), 2);
      expect(h.engine.loadUserWrites().single.writeId, 2);
      expect(h.engine.isDurable, isTrue);
    });

    test('reset inside a transaction joins it; outside it is its own', () {
      h.saveQuery(tracked(1, defaultAt('a'), 100, active: true));
      h.run(() => h.engine.resetPreviouslyActiveTrackedQueries(200));
      expect(fieldsOf(h.engine.loadTrackedQueries().single), <Object?>[
        1,
        defaultAt('a'),
        200,
        false,
        false,
      ]);

      h.saveQuery(tracked(1, defaultAt('a'), 100, active: true));
      h.engine.beginTransaction();
      h.engine.resetPreviouslyActiveTrackedQueries(300);
      h.engine.endTransaction();
      expect(h.engine.loadTrackedQueries().single.active, isTrue);

      h.engine.resetPreviouslyActiveTrackedQueries(400);
      expect(h.connection.inTransaction, isFalse);
      expect(h.engine.loadTrackedQueries().single.lastUse, 400);
    });

    test('lastUse round-trips exactly as an int, ordered by id', () async {
      const int lastUse = 1767225600123;
      h.saveQuery(tracked(9, defaultAt('z'), lastUse + 1));
      h.saveQuery(tracked(3, defaultAt('y'), lastUse));
      await h.reopen();
      final List<TrackedQuery> loaded = h.engine.loadTrackedQueries();
      expect(loaded.map((TrackedQuery q) => q.id), <int>[3, 9]);
      expect(loaded.map((TrackedQuery q) => q.lastUse), <int>[
        lastUse,
        lastUse + 1,
      ]);
    });

    test('ids that are not stored never throw', () {
      h.run(() {
        h.engine.removeUserWrite(42);
        h.engine.deleteTrackedQuery(42);
        h.engine.saveTrackedQueryKeys(42, keys(<String>['a']));
        h.engine.updateTrackedQueryKeys(
          43,
          keys(<String>['b']),
          keys(<String>['not-stored']),
        );
      });
      expect(h.engine.loadTrackedQueryKeys(<int>{44}), isEmpty);
      expect(
        h.engine.loadTrackedQueryKeys(<int>{42, 43}),
        keys(<String>['a', 'b']),
      );
    });
  });

  // Mutation: in UserWriteRows._decode or ServerCacheRows._decode, drop the `on FormatException`
  // clause: the exception reaches the caller.
  group('stored data that does not decode', () {
    test('E-R2 an undecodable write row is skipped with a warning', () {
      h.saveOverwrite('a', node('good'), 1);
      h.rawExecute(
        "INSERT INTO user_writes (id, path, type, value) VALUES (2, '/b/', 'o', x'7b7b')",
      );
      h.rawExecute(
        "INSERT INTO user_writes (id, path, type, value) VALUES (3, '/c/', 'm', ?)",
        <Object?>[Uint8List.fromList('"not a map"'.codeUnits)],
      );
      final List<UserWriteRecord> writes = h.engine.loadUserWrites();
      expect(writes.map((UserWriteRecord w) => w.writeId), <int>[1]);
      expect(h.warnings.single, contains('2 stored write(s)'));
      expect(h.warnings.single, isNot(contains('/b/')));
    });

    test('E-V4 an undecodable server cache row is skipped with a warning', () {
      h.overwrite('c/d', node('d-value'));
      h.rawExecute(
        "INSERT INTO server_cache (path, value) VALUES ('/c/', x'7b7b')",
      );
      // The subtree of the unreadable row reads as absent, rows below it included; a row at or
      // above the path asked for that decodes (written later, as it is deeper) still counts.
      expect(h.cache('c').isEmpty, isTrue);
      expect(h.warnings.single, contains('could not be read'));
      expect(h.cache('c/d'), node('d-value'));
    });

    // Mutation: in ServerCacheRows.load, drop `node = ChildrenNode.empty;` in the unreadable
    // ancestor branch ('big/gone' reads the stale root row), or drop the `node.updateChild(...,
    // ChildrenNode.empty)` of the unreadable descendant branch (the root shows the stale 'big').
    test(
      'an unreadable split marker never lets an ancestor row show through',
      () {
        h.overwrite(
          '',
          node(<String, Object?>{
            'other': 1,
            'big': <String, Object?>{'c1': 'stale', 'gone': 'stale'},
          }),
        );
        final Map<String, Object?> fresh = <String, Object?>{
          for (int i = 0; i < 40; i++) 'c$i': 'v' * 1024,
        };
        h.overwrite('big', node(fresh));
        expect(h.cache('big'), node(fresh));
        h.rawExecute(
          "UPDATE server_cache SET value = x'7b7b' WHERE path = '/big/'",
        );

        expect(h.cache(''), node(<String, Object?>{'other': 1}));
        expect(h.cache('big').isEmpty, isTrue);
        expect(h.cache('big/gone').isEmpty, isTrue);
        expect(h.cache('big/c1'), node('v' * 1024));
        expect(h.warnings, hasLength(4));
        expect(h.warnings, everyElement(isNot(contains('stale'))));
      },
    );

    // Mutation: in ServerCacheRows._estimatedSize, drop the `on ArgumentError` clause.
    test(
      'an unresolved server value in the server cache is stored, not thrown',
      () {
        final Node withServerValue = node(<String, Object?>{
          't': <String, Object?>{'.sv': 'timestamp'},
          'x': 1,
        });
        h.overwrite('s', withServerValue);
        expect(
          h.cache('s').toJson(exportFormat: true),
          withServerValue.toJson(exportFormat: true),
        );
        expect(h.warnings.single, contains('unresolved server value'));
        expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
      },
    );

    test('a 100 000-deep cached value is skipped, no stack overflow', () {
      h.overwrite('ok', node('fine'));
      h.rawExecute(
        "INSERT INTO server_cache (path, value) VALUES ('/deep/', ?)",
        <Object?>[Uint8List.fromList(('[' * 100000 + ']' * 100000).codeUnits)],
      );
      expect(h.cache('deep').isEmpty, isTrue);
      expect(h.cache('ok'), node('fine'));
      expect(h.warnings, hasLength(1));
    });

    test('an undecodable tracked query row is skipped with a warning', () {
      h.saveQuery(tracked(1, defaultAt('a'), 1));
      h.rawExecute(
        'INSERT INTO tracked_queries '
        "(id, path, query_params, last_use_ms, complete, active) VALUES (2, '/b/', '{', 1, 0, 0)",
      );
      expect(h.engine.loadTrackedQueries().map((TrackedQuery q) => q.id), <int>[
        1,
      ]);
      expect(h.warnings.single, contains('tracked queries'));
    });

    // Review M4. Mutation: in TrackedQueryRows._decode, catch `on FormatException` only instead of
    // `on Object`: QueryParams.fromWireObject's UnsupportedError reaches loadTrackedQueries.
    test('a limit of 1e999 (infinity) is a cache miss, not an exception', () {
      h.rawExecute(
        'INSERT INTO tracked_queries '
        '(id, path, query_params, last_use_ms, complete, active) '
        "VALUES (1, '/a/', '{\"l\":1e999}', 0, 0, 0)",
      );
      expect(h.engine.loadTrackedQueries(), isEmpty);
      expect(h.warnings.single, contains('tracked queries'));
    });
  });

  // Mutation: in ServerCacheRows.prune, delete `_collectResaves(...)` (kept data inside a pruned
  // row is lost), or delete `size = measureAll();` (the counter keeps the re-saved rows twice).
  // These cases need PruneForest, which another owner is filling.
  group('prune', () {
    test('prunes, keeps, re-saves kept parts and recounts the size', () {
      h.overwrite(
        'a',
        node(<String, Object?>{
          'x': 'xx',
          'keep': <String, Object?>{'k': 'kv'},
          'y': 'yy',
        }),
      );
      h.overwrite('b', node('b-value'));
      final PruneForest forest = PruneForest()
          .prune(Path('a'))
          .keep(Path('a/keep'));
      h.run(() => h.engine.pruneCache(Path.empty, forest));
      expect(
        h.cache('a'),
        node(<String, Object?>{
          'keep': <String, Object?>{'k': 'kv'},
        }),
      );
      expect(h.cache('b'), node('b-value'));
      expect(h.warnings.single, contains('neither pruned nor kept'));
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    });

    test('a kept row inside a split node stays without a re-save', () {
      h.overwrite(
        'c',
        node(<String, Object?>{for (int i = 0; i < 40; i++) 'c$i': 'v' * 1024}),
      );
      final PruneForest forest = PruneForest()
          .prune(Path('c'))
          .keep(Path('c/c1'));
      h.run(() => h.engine.pruneCache(Path.empty, forest));
      expect(h.cache('c'), node(<String, Object?>{'c1': 'v' * 1024}));
      expect(h.rawScalar('SELECT count(*) FROM server_cache'), 1);
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    });

    test('data above the prune root is left alone with a warning', () {
      h.overwrite(
        'p',
        node(<String, Object?>{
          'q': <String, Object?>{'r': 1},
        }),
      );
      final PruneForest forest = PruneForest().prune(Path.empty);
      h.run(() => h.engine.pruneCache(Path('p/q'), forest));
      expect(
        h.cache('p'),
        node(<String, Object?>{
          'q': <String, Object?>{'r': 1},
        }),
      );
      expect(h.warnings.single, contains('above its root'));
    });

    test('E-S5 prune then incremental vacuum shrinks the file', () {
      h.overwrite(
        'big',
        node(<String, Object?>{
          for (int i = 0; i < 200; i++) 'c$i': 'v' * 10240,
        }),
      );
      final int pagesBefore = h.rawScalar('PRAGMA page_count')! as int;
      h.run(
        () => h.engine.pruneCache(Path.empty, PruneForest().prune(Path('big'))),
      );
      expect(h.cache('big').isEmpty, isTrue);
      expect(
        h.rawScalar('PRAGMA page_count')! as int,
        lessThan(pagesBefore ~/ 2),
      );
      expect(h.engine.serverCacheEstimatedSizeInBytes(), 0);
    });

    test('a forest that prunes nothing changes nothing', () {
      h.overwrite('a', node(1));
      h.run(() => h.engine.pruneCache(Path.empty, PruneForest()));
      expect(h.cache('a'), node(1));
    });
  });

  // Mutation: in SqliteStorageEngine.serverCacheEstimatedSizeInBytes, return the counter whatever
  // the state (the degraded case expects 0).
  group('stores that are not durable', () {
    void expectEmptyAndQuiet() {
      expect(h.engine.isDurable, isFalse);
      expect(h.cache('').isEmpty, isTrue);
      expect(h.cache('a').isEmpty, isTrue);
      expect(h.engine.loadUserWrites(), isEmpty);
      expect(h.engine.loadTrackedQueries(), isEmpty);
      expect(h.engine.loadTrackedQueryKeys(<int>{1}), isEmpty);
      expect(h.engine.serverCacheEstimatedSizeInBytes(), 0);
      h.run(() {
        h.engine.overwriteServerCache(Path('a'), node(1));
        h.engine.saveUserOverwrite(Path('a'), node(1), 9);
        h.engine.saveTrackedQuery(tracked(1, defaultAt('a'), 1));
        h.engine.updateTrackedQueryKeys(1, keys(<String>['k']), <ChildKey>{});
        h.engine.pruneCache(
          Path.empty,
          PruneForest.fromTree(ImmutableTree<bool>.empty()),
        );
      });
      h.engine.resetPreviouslyActiveTrackedQueries(5);
      expect(h.cache('a').isEmpty, isTrue);
      expect(h.engine.loadUserWrites(), isEmpty);
    }

    void seed() {
      h.overwrite('a', node(<String, Object?>{'b': 1}));
      h.saveOverwrite('w', node(1), 1);
      h.saveQuery(tracked(1, defaultAt('a'), 1, active: true));
      h.saveKeys(1, keys(<String>['b']));
    }

    test('degraded (disk full): empty reads, no exception', () {
      seed();
      final sqlite.Database db = h.connection.debugDatabase!;
      final int pages = StoreFixture.scalar(db, 'PRAGMA page_count')! as int;
      db.select('PRAGMA max_page_count = $pages');
      h.overwrite('big', leafOfSize(_mib));
      expect(h.connection.state, StoreState.degraded);
      expectEmptyAndQuiet();
    });

    test('fenced (lease taken): empty reads, no exception', () {
      seed();
      h.rawExecute(
        "UPDATE lease SET owner_id = 'intruder', epoch = epoch + 1 WHERE id = 0",
      );
      h.overwrite('x', node(1));
      expect(h.connection.state, StoreState.fenced);
      expectEmptyAndQuiet();
      expect(
        h.rawScalar("SELECT count(*) FROM server_cache WHERE path = '/x/'"),
        0,
      );
    });

    test(
      'closed: empty reads; mutations outside a transaction still throw',
      () {
        h.engine.close();
        expect(h.engine.isDurable, isFalse);
        expect(h.cache('a').isEmpty, isTrue);
        expect(() => h.engine.removeUserWrite(1), throwsStateError);
      },
    );

    // Review L9. Mutation: in SqliteStorageEngine.endTransaction, drop the
    // `if (_connection.inTransaction)` test (rollback() then throws StateError).
    test(
      'a close inside a transaction: later calls of that transaction are quiet',
      () async {
        h.engine.beginTransaction();
        h.engine.saveUserOverwrite(Path('a'), node(1), 1);
        h.engine.close();
        h.engine.saveUserOverwrite(Path('b'), node(2), 2);
        h.engine.resetPreviouslyActiveTrackedQueries(5);
        h.engine.setTransactionSuccessful();
        h.engine.endTransaction();
        expect(h.engine.beginTransaction, returnsNormally);
        h.engine.endTransaction();
        await h.open();
        expect(h.engine.loadUserWrites(), isEmpty);
      },
    );
  });

  // Mutation: in ServerCacheRows._saveNested, raise splitThreshold to 1 << 40: the whole 50 MiB
  // node lands in one row and the max(length) expectation fails.
  test(
    'a 50 MiB node is split into small rows and a small child loads cold',
    () async {
      final String tenKiB = 'x' * 10240;
      final Map<String, Object?> json = <String, Object?>{
        for (int g = 0; g < 50; g++)
          'g$g': <String, Object?>{for (int c = 0; c < 100; c++) 'c$c': tenKiB},
      };
      h.overwrite('big', node(json));
      expect(h.rawScalar('SELECT count(*) FROM server_cache'), 5000 + 50 + 1);
      expect(
        h.rawScalar('SELECT max(length(value)) FROM server_cache')! as int,
        lessThan(16 * 1024),
      );
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
      expect(h.fullSum(), greaterThan(50 * 1000 * 1000));

      await h.reopen();
      expect(h.cache('big/g7/c42'), node(tenKiB));
      final Node group = h.cache('big/g7');
      expect(group.numChildren, 100);
      expect(h.engine.serverCacheEstimatedSizeInBytes(), h.fullSum());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
