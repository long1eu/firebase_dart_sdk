// Server pushes reach the persistent cache only under a query the tree holds
// (docs/database_decisions.md section 6: "server data is applied and written to the cache only
// under an active or tracked query").
import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// The whole server cache of [engine] as JSON.
String stored(InMemoryPersistenceStorageEngine engine) {
  engine.disableTransactionCheck = true;
  try {
    return json(engine.serverCache(Path.empty));
  } finally {
    engine.disableTransactionCheck = false;
  }
}

void main() {
  test('a push and a merge to unlistened paths are not stored', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.server.deliverDataUpdate('u', <String, Object?>{'x': 1});
    h.server.deliverDataUpdate('v', <String, Object?>{'y': 2}, isMerge: true);
    await settle();
    expect(stored(engine), 'null');

    h.repo.interrupt();
    h.listen('S', 'u');
    h.listen('T', 'v/y');
    h.get('v');
    await settle();
    expect(h.log, <String>['G:E(unavailable)']);
  });

  test('a push above a listen stores only the listened part', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.listen('S', 'a/b');
    await settle();
    h.server.deliverDataUpdate('a', <String, Object?>{'b': 1, 'c': 2});
    h.server.deliverDataUpdate('a', <String, Object?>{
      'b': 3,
      'd': 4,
    }, isMerge: true);
    await settle();
    expect(h.log, <String>['S:V(1)', 'S:V(3)']);
    expect(stored(engine), '{"a":{"b":3}}');
  });

  test('a push after the unlisten is not stored', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.repo.removeEventCallback(h.listen('S', 'a'));
    await settle();
    h.server.deliverDataUpdate('a', <String, Object?>{'x': 1});
    await settle();
    expect(stored(engine), 'null');
    expect(h.log, isEmpty);
  });

  test(
    'an unlistened push leaves an inactive tracked query\'s data alone',
    () async {
      final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
      final RepoHarness h = RepoHarness(persistence: managerOver(engine));
      final CallbackEventRegistration listener = h.listen('S', 'a');
      h.answer('a', <String, Object?>{'x': 1, 'y': 2});
      await settle();
      h.repo.removeEventCallback(listener);
      await settle();
      h.log.clear();

      h.server.deliverDataUpdate('a', <String, Object?>{'x': 9});
      h.server.deliverDataUpdate('a', <String, Object?>{'z': 3}, isMerge: true);
      await settle();
      expect(stored(engine), '{"a":{"x":1,"y":2}}');
      h.repo.interrupt();
      h.get('a');
      await settle();
      expect(h.log, <String>['G:={"x":1,"y":2}']);
    },
  );

  test('a push under a keepSynced query is stored', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.repo.keepSynced(QuerySpec.defaultAt(Path('k')), keep: true);
    await settle();
    h.server.deliverDataUpdate('k/z', 1);
    await settle();
    expect(stored(engine), '{"k":{"z":1}}');
  });

  test('a push at and below a listen is stored', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.listen('S', 'a');
    await settle();
    h.server.deliverDataUpdate('a', <String, Object?>{'b': 1});
    h.server.deliverDataUpdate('a/c', 2);
    h.server.deliverDataUpdate('a', <String, Object?>{'d': 3}, isMerge: true);
    await settle();
    expect(stored(engine), '{"a":{"b":1,"c":2,"d":3}}');
  });
}
