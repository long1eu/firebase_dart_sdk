// Three tests the parity audit of 2026-11-28 named as missing, through the public API on the
// FakeDatabaseServer: remove() of a node's last child keeps the node's priority (write.remove,
// next to the set and update forms in test/core/priority_merge_test.dart); a write whose path is
// longer than 768 bytes throws at the public call (set, update, push().set; the value form is in
// validation_test.dart); startAfter and endBefore, with the wire form they send.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  void scenario(String name, void Function(Harness h) body) {
    test(name, () {
      fakeTime((FakeTime time) => body(Harness(time)));
    });
  }

  group('remove() of the last child', () {
    // The writes are not acknowledged: the local view is what this client shows, and the
    // FakeDatabaseServer does not model a node emptied and refilled (production keeps the priority,
    // verification kit check 22).
    scenario('keeps the priority of its parent when another child is added', (
      Harness h,
    ) {
      final List<String> seen = <String>[];
      h
          .ref('x')
          .onValue
          .listen(
            (DatabaseEvent e) =>
                seen.add('${bare(e.snapshot.value)} p=${e.snapshot.priority}'),
          );
      h.settle();
      h.server.answerListen('x', <String, Object?>{'a': 1, '.priority': 5});
      h.settle();

      h.ref('x/a').remove();
      h.settle();
      h.ref('x/b').set(2);
      h.settle();

      expect(seen, <String>['{a:1} p=5', 'null p=null', '{b:2} p=5']);
      expect(
        h.server.requests,
        containsAllInOrder(<String>['p /x/a', 'p /x/b']),
      );
    });
  });

  group('a write path longer than 768 bytes', () {
    // The byte count is the JS one: one byte per segment for its '/', plus each segment in UTF-8.
    String twoSegments(int first, int second) =>
        '${'a' * first}/${'b' * second}';

    scenario('set: 768 bytes is accepted, 769 throws', (Harness h) {
      expect(() => h.ref(twoSegments(383, 383)).set(1), returnsNormally);
      expect(() => h.ref(twoSegments(384, 383)).set(1), throwsArgumentError);
    });

    scenario('set: bytes are counted in UTF-8, not in characters', (Harness h) {
      // 'é' is two bytes: 383 of them and one 'a' make 1 + 767 = 768 bytes, 384 make 769.
      expect(() => h.ref('${'é' * 383}a').set(1), returnsNormally);
      expect(() => h.ref('é' * 384).set(1), throwsArgumentError);
    });

    scenario('update: the location and the key together', (Harness h) {
      expect(
        () => h.ref('a' * 383).update(<String, Object?>{'b' * 383: 1}),
        returnsNormally,
      );
      expect(
        () => h.ref('a' * 383).update(<String, Object?>{'b' * 384: 1}),
        throwsArgumentError,
      );
    });

    scenario('push().set: the location and the 20-character push id', (
      Harness h,
    ) {
      expect(() => h.ref('a' * 746).push().set(1), returnsNormally);
      expect(() => h.ref('a' * 747).push().set(1), throwsArgumentError);
    });

    scenario('a refused write sends nothing', (Harness h) {
      expect(() => h.ref(twoSegments(384, 383)).set(1), throwsArgumentError);
      expect(
        () => h.ref('a' * 383).update(<String, Object?>{'b' * 384: 1}),
        throwsArgumentError,
      );
      expect(() => h.ref('a' * 747).push().set(1), throwsArgumentError);
      h.settle();
      expect(
        h.server.requests.where(
          (String r) => r.startsWith('p ') || r.startsWith('m '),
        ),
        isEmpty,
      );
    });
  });

  group('startAfter and endBefore', () {
    final Map<String, Object?> scores = <String, Object?>{
      'a': <String, Object?>{'age': 29},
      'b': <String, Object?>{'age': 30},
      'c': <String, Object?>{'age': 31},
    };

    scenario('startAfter on a child index: sn [MAX_NAME], sin false', (
      Harness h,
    ) {
      h.listen('S1', h.ref('s').orderByChild('age').startAfter(30).onValue);
      h.settle();
      expect(h.server.requests, <String>[
        'q /s {"i":"age","sin":false,"sn":"[MAX_NAME]","sp":30}',
      ]);
      h.server.answerListen('s', scores);
      h.settle();
      expect(h.log, <String>['S1:V({c:{age:31}})']);
    });

    scenario('endBefore on a child index: en [MIN_NAME], ein false', (
      Harness h,
    ) {
      h.listen('S1', h.ref('s').orderByChild('age').endBefore(30).onValue);
      h.settle();
      expect(h.server.requests, <String>[
        'q /s {"ein":false,"en":"[MIN_NAME]","ep":30,"i":"age"}',
      ]);
      h.server.answerListen('s', scores);
      h.settle();
      expect(h.log, <String>['S1:V({a:{age:29}})']);
    });

    scenario('on the key index: no name, the bound alone', (Harness h) {
      h.listen(
        'S1',
        h.ref('s').orderByKey().startAfter('a').endBefore('c').onValue,
      );
      h.settle();
      expect(h.server.requests, <String>[
        'q /s {"ein":false,"ep":"c","i":".key","sin":false,"sp":"a"}',
      ]);
      h.server.answerListen('s', scores);
      h.settle();
      expect(h.log, <String>['S1:V({b:{age:30}})']);
    });

    scenario('with a key: the key is the name', (Harness h) {
      h.listen(
        'S1',
        h.ref('s').orderByChild('age').startAfter(30, key: 'b').onValue,
      );
      h.settle();
      expect(h.server.requests, <String>[
        'q /s {"i":"age","sin":false,"sn":"b","sp":30}',
      ]);
      h.server.answerListen('s', scores);
      h.settle();
      expect(h.log, <String>['S1:V({c:{age:31}})']);
    });
  });
}
