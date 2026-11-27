// Contract of DefaultPersistenceManager.applyUserMergeToServerCache over a storage engine: an
// acked update with `.priority` entries is stored as the server applies it (CompoundWrite.apply).
//
// runPriorityMergePersistenceContract holds for every engine; the client's
// emptied_node_priority_persistence_test.dart runs it against InMemoryPersistenceStorageEngine and
// the SQLite package's emptied_node_priority_restart_test.dart against SqliteStorageEngine. No main
// here: other packages import this file.
//
// The engines differ only in hidden state. The in-memory engine stores client nodes, so a node
// emptied by a write below it keeps its priority and shows it again once refilled, as the server
// does. The SQLite engine clears the priority of an emptied node on purpose
// (ServerCacheRows._clearEmptiedNodes), so the refilled node has none ([keepsEmptiedPriority]).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

import '../core/repo_harness.dart';

/// A persistence manager over [engine].
PersistenceManager priorityContractManager(PersistenceStorageEngine engine) =>
    DefaultPersistenceManager(
      engine,
      CachePolicy.none,
      () => DateTime.utc(2026),
    );

/// Stores [value] at [path] in [engine] with a complete, inactive default tracked query there.
void seedCompleteCache(
  PersistenceStorageEngine engine,
  String path,
  Object? value,
) {
  engine.beginTransaction();
  try {
    engine
      ..overwriteServerCache(Path(path), nodeFromJson(value))
      ..saveTrackedQuery(
        TrackedQuery(
          id: 0,
          querySpec: QuerySpec.defaultAt(Path(path)),
          lastUse: 0,
          complete: true,
          active: false,
        ),
      );
    engine.setTransactionSuccessful();
  } finally {
    engine.endTransaction();
  }
}

/// Sequence (b) up to the listen at `x`: `x = {a: 1}` cached and complete with no default listen
/// at `x`; `update(x, {a: null, .priority: 7})` acked; a listen at `x/b` receives 1. Returns the
/// harness, still connected.
Future<RepoHarness> ackPriorityUpdateThenFillChild(
  PersistenceStorageEngine engine,
) async {
  seedCompleteCache(engine, 'x', <String, Object?>{'a': 1});
  final RepoHarness harness = RepoHarness(
    persistence: priorityContractManager(engine),
  );
  final Map<String, Object?> update = <String, Object?>{
    'a': null,
    '.priority': 7,
  };
  harness.repo.updateChildren(
    Path('x'),
    CompoundWrite.fromValue(update),
    update,
  );
  await settle();
  harness.server.respond(harness.server.callsOf('merge').single);
  await settle();
  harness.listen('B', 'x/b');
  await settle();
  harness.answer('x/b', 1);
  await settle();
  // First from the cache (x is complete and empty), then the server's answer.
  expect(harness.log, <String>['B:V(null)', 'B:V(1)']);
  return harness;
}

/// Listens at [path] on [harness]; the returned function gives the last value shown, in export
/// form (priority included).
Object? Function() listenExport(RepoHarness harness, String path) {
  bool seen = false;
  Object? shown;
  harness.listen(
    'L',
    path,
    after: (DataEvent e) {
      seen = true;
      shown = e.snapshot.toJson(exportFormat: true);
    },
  );
  return () {
    expect(seen, isTrue, reason: 'no event at $path');
    return shown;
  };
}

/// One merge shape: the cache at `x` before ([before], export JSON, null for nothing), the merge
/// at `x`, and where below `x` a later server write refills the result ([refill], null for none).
final class _Shape {
  const _Shape(this.name, this.before, this.merge, {this.refill = ''});

  final String name;
  final Object? before;
  final Map<String, Object?> merge;
  final String? refill;
}

const List<_Shape> _shapes = <_Shape>[
  _Shape('{b: 1, .priority: 7} on an empty x', null, <String, Object?>{
    'b': 1,
    '.priority': 7,
  }),
  _Shape(
    '{a: null, .priority: 7} on x = {a: 1}',
    <String, Object?>{'a': 1},
    <String, Object?>{'a': null, '.priority': 7},
  ),
  _Shape(
    '{a: null, .priority: 7} on x = {a: 1} with priority 3',
    <String, Object?>{'a': 1, '.priority': 3},
    <String, Object?>{'a': null, '.priority': 7},
  ),
  _Shape(
    '{a: null, .priority: null} on x = {a: 1}',
    <String, Object?>{'a': 1},
    <String, Object?>{'a': null, '.priority': null},
  ),
  _Shape(
    '{a: null, .priority: null} on x = {a: 1} with priority 3',
    <String, Object?>{'a': 1, '.priority': 3},
    <String, Object?>{'a': null, '.priority': null},
  ),
  _Shape(
    'nested owner {c/a: null, c/.priority: 7}',
    <String, Object?>{
      'c': <String, Object?>{'a': 1},
      'd': 1,
    },
    <String, Object?>{'c/a': null, 'c/.priority': 7},
    refill: 'c',
  ),
  _Shape('priority on a leaf x', 'hello', <String, Object?>{
    '.priority': 7,
  }, refill: null),
  _Shape(
    '{a: null, .priority: 7} on a node that stays non-empty',
    <String, Object?>{'a': 1, 'b': 2},
    <String, Object?>{'a': null, '.priority': 7},
  ),
  _Shape(
    'nested {c/.priority: 7} on an existing c',
    <String, Object?>{
      'c': <String, Object?>{'a': 1},
    },
    <String, Object?>{'c/.priority': 7},
    refill: 'c',
  ),
];

/// The contract; [keepsEmptiedPriority] says whether the engine keeps the priority of a node
/// emptied by a write below it (hidden state, shown again once the node is refilled).
void runPriorityMergePersistenceContract(
  PersistenceStorageEngine Function() open, {
  required bool keepsEmptiedPriority,
}) {
  late PersistenceStorageEngine engine;

  setUp(() => engine = open());

  void inTransaction(void Function() body) {
    engine.beginTransaction();
    try {
      body();
      engine.setTransactionSuccessful();
    } finally {
      engine.endTransaction();
    }
  }

  group('an acked merge is stored as CompoundWrite.apply gives it:', () {
    for (final _Shape shape in _shapes) {
      test(shape.name, () {
        final Node before = nodeFromJson(shape.before);
        if (shape.before != null) {
          inTransaction(() => engine.overwriteServerCache(Path('x'), before));
        }
        final CompoundWrite merge = CompoundWrite.fromValue(shape.merge);
        final Node model = merge.apply(before);
        final PersistenceManager manager = priorityContractManager(engine);
        manager.runInTransaction(
          () => manager.applyUserMergeToServerCache(Path('x'), merge),
        );
        expect(
          engine.serverCache(Path('x')).toJson(exportFormat: true),
          model.toJson(exportFormat: true),
          reason: 'read right after the ack',
        );

        final String? refill = shape.refill;
        if (refill == null) {
          return;
        }
        // A later server write below the owner fills it again: hidden state shows here.
        final Path filled = Path(refill.isEmpty ? 'zz' : '$refill/zz');
        inTransaction(
          () => engine.overwriteServerCache(
            Path('x').childPath(filled),
            nodeFromJson(1),
          ),
        );
        final Node base = keepsEmptiedPriority
            ? model
            : nodeFromJson(model.toJson(exportFormat: true));
        expect(
          engine.serverCache(Path('x')).toJson(exportFormat: true),
          base.updateChild(filled, nodeFromJson(1)).toJson(exportFormat: true),
          reason: 'read after x/$refill/zz is written',
        );
      });
    }
  });

  test("an acked update is stored in the server's order", () async {
    // x {a: 1} is cached with no active listen, so the ack writes the update into the server
    // cache by hand. The server applies {a: null, .priority: 7} in two passes: a goes, x is
    // gone, and the priority lands on nothing.
    seedCompleteCache(engine, 'x', <String, Object?>{'a': 1});
    final RepoHarness first = RepoHarness(
      persistence: priorityContractManager(engine),
    );
    final Map<String, Object?> update = <String, Object?>{
      'a': null,
      '.priority': 7,
    };
    first.repo.updateChildren(
      Path('x'),
      CompoundWrite.fromValue(update),
      update,
    );
    await settle();
    first.server.respond(first.server.callsOf('merge').single);
    await settle();
    expect(engine.serverCache(Path('x')).hash(), '');

    // The reader: a restarted client, offline, writes below x; the server would hold x {b: 1}
    // with no priority.
    final RepoHarness second = RepoHarness(
      persistence: priorityContractManager(engine),
      connected: false,
    );
    final Object? Function() shown = listenExport(second, 'x');
    await settle();
    second.set('x/b', 1);
    await settle();
    expect(shown(), <String, Object?>{'b': 1});
  });

  test('a priority acked on an emptied node does not come back when the server '
      'fills it', () async {
    final RepoHarness harness = await ackPriorityUpdateThenFillChild(engine);
    final Object? Function() shown = listenExport(harness, 'x');
    await settle();
    expect(shown(), <String, Object?>{'b': 1});
  });
}
