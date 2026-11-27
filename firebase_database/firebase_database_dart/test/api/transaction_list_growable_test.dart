// The value a transaction handler receives is a mutable deep copy: lists at every depth are
// growable (add and remove work), maps at every depth take new keys. DataSnapshot.value stays
// unmodifiable.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// Runs [body] on a harness that is online and listens to `a`, answered with [cached].
void _withCached(String name, Object? cached, void Function(Harness h) body) {
  test(name, () {
    fakeTime((FakeTime time) {
      final Harness h = Harness(time);
      h.listenAnswered('S', h.ref('a').onValue, 'a', cached);
      h.log.clear();
      body(h);
    });
  });
}

/// Runs a transaction on `a` with [update], then the server acknowledges its one write.
void _runAndAck(Harness h, Object? Function(Object? value) update) {
  h.trackTransaction(
    'T',
    h.ref('a').runTransaction((Object? value) {
      try {
        return Transaction.success(update(value));
      } on Object catch (e) {
        h.log.add('H:threw ${e.runtimeType}');
        rethrow;
      }
    }),
  );
  h.settle();
  expect(
    <String>[...h.named('H'), ...h.named('T')],
    isEmpty,
    reason: 'the handler threw',
  );
  // One pending request only: the transaction's put.
  h.server.ackLastWrite();
  h.settle();
}

void main() {
  _withCached('a top-level list takes add and remove', <Object?>[1, 2], (
    Harness h,
  ) {
    _runAndAck(h, (Object? value) {
      final List<Object?> list = value! as List<Object?>;
      list
        ..add(3)
        ..removeAt(0);
      return list;
    });
    expect(h.named('T'), <String>['T:committed([2,3])']);
  });

  _withCached(
    'a list with a hole takes add',
    <String, Object?>{'0': 'x', '2': 'z'},
    (Harness h) {
      _runAndAck(h, (Object? value) {
        final List<Object?> list = value! as List<Object?>;
        expect(list, <Object?>['x', null, 'z']);
        list.add('w');
        return list;
      });
      expect(h.named('T'), <String>['T:committed([x,null,z,w])']);
    },
  );

  _withCached(
    'lists and maps several levels deep are growable and mutable',
    <String, Object?>{
      'l': <Object?>[
        1,
        <String, Object?>{
          'm': <Object?>[
            <Object?>[10, 20],
            30,
          ],
        },
      ],
      'n': <String, Object?>{
        'o': <String, Object?>{
          'p': <Object?>['q'],
        },
      },
    },
    (Harness h) {
      _runAndAck(h, (Object? value) {
        final Map<String, Object?> root = value! as Map<String, Object?>;
        final List<Object?> l = root['l']! as List<Object?>;
        final Map<String, Object?> lm = l[1]! as Map<String, Object?>;
        final List<Object?> m = lm['m']! as List<Object?>;
        (m[0]! as List<Object?>)
          ..add(21)
          ..remove(10);
        m.removeLast();
        lm['k'] = true;
        l.add(2);
        final Map<String, Object?> o =
            (root['n']! as Map<String, Object?>)['o']! as Map<String, Object?>;
        (o['p']! as List<Object?>).add('r');
        o['s'] = 1;
        root['t'] = <Object?>[];
        return root;
      });
      expect(h.named('T'), <String>[
        'T:committed({l:[1,{k:true,m:[[20,21]]},2],n:{o:{p:[q,r],s:1}}})',
      ]);
    },
  );

  _withCached('DataSnapshot.value lists stay unmodifiable', <Object?>[1, 2], (
    Harness h,
  ) {
    final List<Object?> snapshotValues = <Object?>[];
    final StreamSubscription<DatabaseEvent> s = h
        .ref('a')
        .onValue
        .listen((DatabaseEvent e) => snapshotValues.add(e.snapshot.value));
    h.settle();
    final List<Object?> list = snapshotValues.single! as List<Object?>;
    expect(() => list.add(3), throwsUnsupportedError);
    unawaited(s.cancel());
  });
}
