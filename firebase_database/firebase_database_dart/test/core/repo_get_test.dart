// Repo.getValue: rows D46 to D54 of 14_api_contract.md section 4.4 (contract C25), the
// network-error and closed paths, and the REST-style answer of a filtered get. Time moves with
// FakeTime, so the 3 s wait costs nothing.
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// Runs [body] with a fresh [FakeTime].
void timedTest(String name, Future<void> Function(FakeTime time) body) {
  test(name, () {
    final FakeTime time = FakeTime();
    return time.run(() => body(time));
  });
}

void main() {
  timedTest('D46 get from an active view makes no request', (_) async {
    final RepoHarness h = RepoHarness();
    h.listen('S1', 'a');
    h.answer('a', 1);
    await settle();
    h.log.clear();

    h.set('a', 2);
    h.get('a');
    await settle();
    expect(h.log, <String>['S1:V(2)', 'G:=2']);
    expect(h.server.callsOf('get'), isEmpty);
  });

  timedTest('D47 no timer while connected', (FakeTime time) async {
    final RepoHarness h = RepoHarness(
      persistence: managerOver(persistedEngine(<String, Object?>{'a': 1})),
    );
    h.get('a');
    await time.elapse(const Duration(minutes: 1));
    expect(h.log, isEmpty);
    h.server.respond(h.openGets('/a').single, data: 7);
    await settle();
    expect(h.log, <String>['G:=7']);
  });

  timedTest('D48 the answer raises events on listeners it completes', (
    _,
  ) async {
    final RepoHarness h = RepoHarness();
    h.get('a');
    await settle();
    h.listen('S1', 'a/b');
    await settle();
    h.server.respond(h.openGets('/a').single, data: <String, Object?>{'b': 3});
    await settle();
    expect(h.log, <String>['S1:V(3)', 'G:={"b":3}']);
  });

  timedTest('D49 offline with no cache fails unavailable after 3 s', (
    FakeTime time,
  ) async {
    final RepoHarness h = RepoHarness();
    h.server.disconnect();
    await settle();

    h.get('a');
    await time.elapse(const Duration(milliseconds: 2999));
    h.log.add('t');
    await time.elapse(const Duration(milliseconds: 1));
    expect(h.log, <String>['t', 'G:E(unavailable)']);
  });

  timedTest('D50 offline with a persisted value answers it after 3 s', (
    FakeTime time,
  ) async {
    final RepoHarness h = RepoHarness(
      persistence: managerOver(persistedEngine(<String, Object?>{'a': 1})),
    );
    h.server.disconnect();
    await settle();

    h.get('a');
    await time.elapse(const Duration(seconds: 3));
    expect(h.log, <String>['G:=1']);
  });

  timedTest('D51 a connection during the wait stops it', (FakeTime time) async {
    final RepoHarness h = RepoHarness();
    h.server.disconnect();
    await settle();

    h.get('a');
    await time.elapse(const Duration(seconds: 1));
    h.server.connect();
    await time.elapse(const Duration(seconds: 10));
    expect(h.log, isEmpty);
    h.server.respond(h.openGets('/a').single, data: 4);
    await settle();
    expect(h.log, <String>['G:=4']);
  });

  timedTest('D52 a drop while the request is out starts the wait', (
    FakeTime time,
  ) async {
    final RepoHarness h = RepoHarness();
    h.get('a');
    await settle();
    h.server.disconnect();
    await time.elapse(const Duration(milliseconds: 2999));
    h.log.add('t');
    await time.elapse(const Duration(milliseconds: 1));
    expect(h.log, <String>['t', 'G:E(unavailable)']);
  });

  timedTest('D52 variant: a reconnect before the wait ends gets the answer', (
    FakeTime time,
  ) async {
    final RepoHarness h = RepoHarness();
    h.get('a');
    await settle();
    h.server.disconnect();
    await time.elapse(const Duration(seconds: 1));
    h.server.connect();
    await time.elapse(const Duration(seconds: 5));
    h.server.respond(h.openGets('/a').single, data: 4);
    await settle();
    expect(h.log, <String>['G:=4']);
  });

  timedTest('D53 a refusal never answers from the cache', (_) async {
    final RepoHarness h = RepoHarness(
      persistence: managerOver(persistedEngine(<String, Object?>{'a': 1})),
    );
    h.get('a');
    await settle();
    h.server.respond(
      h.openGets('/a').single,
      status: 'permission_denied',
      data: 'no',
    );
    await settle();
    expect(h.log, <String>['G:E(permission-denied)']);
  });

  timedTest('D54 after goOffline the get answers at once, no request', (
    _,
  ) async {
    final RepoHarness h = RepoHarness();
    h.repo.interrupt();
    h.get('a');
    await settle();
    expect(h.log, <String>['G:E(unavailable)']);
    expect(h.server.callsOf('get'), isEmpty);
  });

  timedTest('D54 variant: after goOffline a persisted value answers', (
    _,
  ) async {
    final RepoHarness h = RepoHarness(
      persistence: managerOver(persistedEngine(<String, Object?>{'a': 1})),
    );
    h.repo.interrupt();
    h.get('a');
    await settle();
    expect(h.log, <String>['G:=1']);
  });

  timedTest('a network error from the connection fails with network-error', (
    _,
  ) async {
    final RepoHarness h = RepoHarness();
    h.get('a');
    await settle();
    h.server.respond(h.openGets('/a').single, status: statusNetworkError);
    await settle();
    expect(h.log, <String>['G:E(network-error)']);
  });

  timedTest('a get open at close fails through the shutdown', (_) async {
    final RepoHarness h = RepoHarness();
    h.get('a');
    await settle();
    await h.repo.close();
    await settle();
    expect(h.log, <String>['G:E(database-closed)']);
  });

  timedTest('a filtered get answered with data only leaves the default query '
      'incomplete', (_) async {
    final PersistenceManager manager = managerOver(persistedEngine(const {}));
    final RepoHarness h = RepoHarness(persistence: manager);
    final QueryParams first = QueryParams.defaultParams.limitToFirst(1);
    h.get('l', params: first);
    await settle();
    // The REST client answers with the data and sends no data update.
    h.server.respond(h.openGets('/l').single, data: <String, Object?>{'a': 1});
    await settle();
    expect(h.log, <String>['G:={"a":1}']);

    final QuerySpec defaultQuery = QuerySpec.defaultAt(Path('l'));
    expect(h.repo.serverSyncTree.getServerValue(defaultQuery), isNull);
    expect(manager.serverCache(defaultQuery).fullyInitialized, isFalse);
    // So a get of the whole location still asks the server.
    h.get('l', name: 'D');
    await settle();
    expect(h.openGets('/l'), hasLength(1));
    // No listen was sent for the bracket, and no listen is left.
    expect(h.server.callsOf('listen'), isEmpty);
    expect(h.server.callsOf('unlisten'), isEmpty);
  });
}
