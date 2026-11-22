// An update whose only key is the location itself (`update({'': v})`, a merge with a root
// write) shadows like a set: acknowledging the first of two keeps the second visible.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

void main() {
  test(
    'acknowledging the first of two root merges keeps the second visible',
    () async {
      final RepoHarness h = RepoHarness();
      h.listen('S', 'a');
      h.answer('a', 0);
      await settle();
      for (final int value in <int>[1, 2]) {
        h.repo.updateChildren(
          Path('a'),
          CompoundWrite.fromValue(<String, Object?>{'': value}),
          <String, Object?>{'': value},
          onComplete: h.completion('W$value'),
        );
      }
      await settle();
      h.server.respond(h.callsAt('merge', '/a').first);
      await settle();
      expect(h.log, <String>['S:V(0)', 'S:V(1)', 'S:V(2)', 'W1:ok']);
    },
  );

  test(
    'a root merge with a child key acknowledged under a later set',
    () async {
      final RepoHarness h = RepoHarness();
      h.listen('S', 'a');
      h.answer('a', 0);
      await settle();
      h.repo.updateChildren(
        Path('a'),
        CompoundWrite.fromValue(<String, Object?>{'': 1}),
        <String, Object?>{'': 1},
        onComplete: h.completion('W1'),
      );
      h.set('a/b', 2, name: 'W2');
      await settle();
      h.server.respond(h.callsAt('merge', '/a').single);
      await settle();
      expect(h.log, <String>['S:V(0)', 'S:V(1)', 'S:V({"b":2})', 'W1:ok']);
    },
  );
}
