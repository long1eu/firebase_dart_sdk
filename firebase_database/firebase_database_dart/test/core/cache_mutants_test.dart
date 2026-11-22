// Tests that kill mutants m08, m09, m11 and m12 of the test quality audit
// (rtdb/from_helper/reports/test_quality_audit.md): each pins behaviour no other test pinned.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

void main() {
  test(
    'm08 an acknowledged onDisconnect update applies locally on a drop',
    () async {
      final RepoHarness h = RepoHarness();
      h.listen('S', 'p');
      h.answer('p', <String, Object?>{'a': 1});
      h.repo.onDisconnectUpdate(
        Path('p'),
        <Path, Node>{Path('b'): nodeFromJson(2)},
        <String, Object?>{'b': 2},
        onComplete: h.completion('U'),
      );
      await settle();
      h.server.ackLastOnDisconnect();
      await settle();
      h.log.clear();

      h.server.disconnect();
      await settle();
      expect(h.log, <String>['S:V({"a":1,"b":2})']);
    },
  );

  test('m09 an update leaves a transaction on a sibling child running', () async {
    final RepoHarness h = RepoHarness();
    h.listen('S', 'a');
    h.answer('a', <String, Object?>{'c': 0});
    await settle();
    h.transaction(
      'a/c',
      (Object? value) => TransactionSuccess((value! as int) + 1),
    );
    await settle();
    h.repo.updateChildren(
      Path('a'),
      CompoundWrite.fromValue(<String, Object?>{'b': 5}),
      <String, Object?>{'b': 5},
      onComplete: h.completion('U'),
    );
    await settle();
    // The put is out: an abort would show on its `datastale` answer, which reruns instead.
    h.server.respond(h.callsAt('put', '/a/c').single, status: 'datastale');
    await settle();
    expect(h.log.where((String e) => e.startsWith('T:')), isEmpty);
    expect(h.callsAt('put', '/a/c'), hasLength(2));
  });

  test('m11 a listen hashes the server cache, not pending writes', () async {
    final RepoHarness h = RepoHarness();
    h.listen('S', 'a');
    h.answer('a', 1);
    await settle();
    h.set('a', 2);
    await settle();
    final String hash = h
        .server
        .activeListens[QuerySpec.defaultAt(Path('a')).toListenSpec()]!
        .hashProvider!
        .simpleHash();
    expect(hash, nodeFromJson(1).hash());
  });

  test('m12 a get of a kept-synced query keeps it synced', () async {
    final RepoHarness h = RepoHarness();
    final QuerySpec query = QuerySpec.defaultAt(Path('a'));
    h.repo.keepSynced(query, keep: true);
    await settle();
    h.get('a');
    await settle();
    h.server.respond(h.openGets('/a').single, data: 1);
    await settle();
    h.get('a', name: 'G2');
    await settle();
    expect(h.log, <String>['G:=1', 'G2:=1']);
    expect(h.server.callsOf('get'), hasLength(1));
  });
}
