// An offline get() answered from the persisted cache: only data the cache knows is complete
// for the query answers (docs/database_decisions.md section 10, "if it has the data"), and a
// get never leaves its tracked query active.
import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// The tracked queries saved in [engine], by query.
Map<QuerySpec, TrackedQuery> tracked(InMemoryPersistenceStorageEngine engine) =>
    <QuerySpec, TrackedQuery>{
      for (final TrackedQuery q in engine.loadTrackedQueries()) q.querySpec: q,
    };

void main() {
  test(
    'offline get of a parent with only a child cached is unavailable',
    () async {
      final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
      final RepoHarness h = RepoHarness(persistence: managerOver(engine));
      final CallbackEventRegistration child = h.listen('S', 'a/b');
      h.answer('a/b', <String, Object?>{'x': 1});
      await settle();
      h.repo.removeEventCallback(child);
      await settle();
      h.log.clear();

      h.repo.interrupt();
      h.get('a');
      await settle();
      expect(h.log, <String>['G:E(unavailable)']);
    },
  );

  test(
    'offline get of a location cached complete and empty answers null',
    () async {
      final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
      final RepoHarness h = RepoHarness(persistence: managerOver(engine));
      final CallbackEventRegistration listener = h.listen('S', 'a');
      h.answer('a', null);
      await settle();
      h.repo.removeEventCallback(listener);
      await settle();
      h.log.clear();

      h.repo.interrupt();
      h.get('a');
      await settle();
      expect(h.log, <String>['G:=null']);
    },
  );

  test(
    'offline limited get from a complete cached parent applies the limit',
    () async {
      final RepoHarness h = RepoHarness(
        persistence: managerOver(
          persistedEngine(<String, Object?>{
            'l': <String, Object?>{'a': 1, 'b': 2, 'c': 3},
          }),
        ),
      );
      h.repo.interrupt();
      h.get('l', params: QueryParams.defaultParams.limitToFirst(1));
      await settle();
      expect(h.log, <String>['G:={"a":1}']);
    },
  );

  test('a get answered offline leaves its tracked query inactive', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(
      <String, Object?>{'a': 1},
    );
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.repo.interrupt();
    h.get('a');
    h.get('z');
    await settle();
    expect(h.log, <String>['G:=1', 'G:E(unavailable)']);
    expect(tracked(engine)[QuerySpec.defaultAt(Path('a'))]!.active, isFalse);
    expect(tracked(engine)[QuerySpec.defaultAt(Path('z'))]!.active, isFalse);
  });

  test('a write acknowledged after an offline get reaches the cache', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(
      <String, Object?>{
        'a': <String, Object?>{'x': 1},
      },
    );
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.repo.interrupt();
    h.get('a');
    await settle();
    h.repo.resume();
    await settle();
    h.set('a/x', 2, name: 'W');
    await settle();
    h.server.respond(h.callsAt('put', '/a/x').single);
    await settle();
    h.repo.interrupt();
    h.get('a');
    await settle();
    expect(h.log, <String>['G:={"x":1}', 'W:ok', 'G:={"x":2}']);
  });

  test('a refused get leaves its tracked query inactive', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.get('a');
    await settle();
    h.server.respond(h.openGets('/a').single, status: 'permission_denied');
    await settle();
    expect(h.log, <String>['G:E(permission-denied)']);
    expect(tracked(engine)[QuerySpec.defaultAt(Path('a'))]!.active, isFalse);
  });

  test('a get leaves a listener\'s tracked query active', () async {
    final InMemoryPersistenceStorageEngine engine = persistedEngine(const {});
    final RepoHarness h = RepoHarness(persistence: managerOver(engine));
    h.listen('S', 'a');
    await settle();
    h.repo.interrupt();
    h.get('a');
    await settle();
    expect(h.log, <String>['G:E(unavailable)']);
    expect(tracked(engine)[QuerySpec.defaultAt(Path('a'))]!.active, isTrue);
  });
}
