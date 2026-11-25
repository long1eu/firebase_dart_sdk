// The priority a node keeps when a write below it empties it survives a restart in the
// in-memory engine: the server cache holds client nodes, so the hidden state is stored as is,
// and a restarted client sends the server's hash for the listen and refills the node with the
// priority while offline.
//
// The SQLite engine stores export JSON (`Node.toJson(exportFormat: true)`, read back with the
// public `nodeFromJson`) and clears the priority of an emptied node on purpose
// (`ServerCacheRows._clearEmptiedNodes`), so there the kept priority does not survive a restart:
// the restarted client hashes the node as empty and the server sends it again.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import '../repo_harness.dart';

/// The JS hash of `{m: 1, n: {".priority": 5}}`: sha1(':m:' + sha1('number:3ff0000000000000') +
/// ':n:' + sha1('priority:number:4014000000000000:')).
const String _serverHash = 'XzWOy74sb2cqzi7dorD7AhCCaFY=';

void main() {
  test('in memory: the kept priority survives a restart', () async {
    final InMemoryPersistenceStorageEngine engine =
        InMemoryPersistenceStorageEngine();
    final RepoHarness first = RepoHarness(persistence: managerOver(engine));
    first.listen('L', 'p');
    first.answer('p', <String, Object?>{
      'm': 1,
      'n': <String, Object?>{'a': 1, '.priority': 5},
    });
    await settle();
    // Another client removes n/a; the server forwards the write as written.
    first.server.deliverDataUpdate('p/n/a', null);
    await settle();
    final Node stored = engine.serverCache(Path('p'));
    expect(stored.toJson(exportFormat: true), <String, Object?>{'m': 1});
    expect((stored as ChildrenNode).toServerJson(), <String, Object?>{
      'm': 1,
      'n': <String, Object?>{'.priority': 5},
    });
    expect(stored.hash(), _serverHash);

    // A new client over the same engine, offline.
    final RepoHarness second = RepoHarness(
      persistence: managerOver(engine),
      connected: false,
    );
    second.listen('L', 'p');
    await settle();
    expect(second.log, <String>['L:V({"m":1})']);
    second.server.connect();
    await settle();
    final ServerCall listen = second.server.callsOf('listen').single;
    expect(listen.hashProvider!.simpleHash(), _serverHash);
    second.set('p/n/b', 1);
    await settle();
    expect(second.log.last, 'L:V({"m":1,"n":{"b":1}})');
    final Node shown = second.repo.serverSyncTree.calcCompleteEventCache(
      Path('p/n'),
    )!;
    expect(shown.priority.value, 5);
  });
}
