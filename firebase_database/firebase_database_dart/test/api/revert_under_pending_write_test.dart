// A write refused by the server (or a transaction aborted) while an earlier write at a parent is
// still pending. The visible writes fold the lower write's data into the parent write's node. JS
// `WriteTree.ts` writeTreeRemoveWrite counts only writes at or below the removed one as
// overlapping, so it removed the lower write by its paths and left its data in the parent's node:
// a listener opened after the refusal saw the refused data until the parent write was answered.
// lib/src/core/write_tree.dart counts the parent write as overlapping and rebuilds. A listener
// open during the refusal kept the data too, because JS viewProcessorRevertUserWrite returns the
// view unchanged under a shadowing write; lib/src/core/view/view_processor.dart takes what the
// write tree holds instead.
//
// The fake server refuses the last write while the earlier one is pending, which a server
// answering in order does not do: the first four tests pass `outOfOrder: true` for that. They test
// the write tree's rebuild, not the server. Through the public API the same state comes from a
// queued transaction aborted while an ancestor transaction is in flight (last test, in order).

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  void scenario(String name, void Function(Harness h) body, {String? skip}) {
    test(name, () {
      fakeTime((FakeTime time) => body(Harness(time)));
    }, skip: skip);
  }

  /// Listens at `r`, sets `r` to `{a: 1}` (left pending), then runs [lower], a write below it that
  /// the test makes the server refuse.
  void setUnderPendingSet(Harness h, void Function() lower) {
    h.listenAnswered('S', h.ref('r').onValue, 'r', null);
    h.track('W1', h.ref('r').set(<String, Object?>{'a': 1}));
    lower();
    h.settle();
  }

  /// A listener opened at `r/b` after the refusal: it must not see the refused data.
  void expectNewListenerSeesNothing(Harness h) {
    h.log.clear();
    h.listen('N', h.ref('r/b').onValue);
    h.settle();
    expect(h.named('N'), <String>['N:V(null)']);

    h.server.ackLastWrite();
    h.settle();
    expect(h.named('N'), <String>['N:V(null)']);
    expect(h.named('W1'), <String>['W1:ok']);
  }

  scenario('refused update below a pending set leaves nothing behind', (
    Harness h,
  ) {
    setUnderPendingSet(
      h,
      () => h.track('W2', h.ref('r/b').update(<String, Object?>{'c': 2})),
    );
    // Out of order on purpose: the state under test, not a server answer (see the top).
    h.server.failLastWrite('permission_denied', outOfOrder: true);
    h.settle();
    expect(h.named('W2'), <String>['W2:E(permission-denied)']);
    expectNewListenerSeesNothing(h);
  });

  scenario('refused set below a pending set leaves nothing behind', (
    Harness h,
  ) {
    setUnderPendingSet(h, () => h.track('W2', h.ref('r/b/c').set(2)));
    // Out of order on purpose: the state under test, not a server answer (see the top).
    h.server.failLastWrite('permission_denied', outOfOrder: true);
    h.settle();
    expect(h.named('W2'), <String>['W2:E(permission-denied)']);
    expectNewListenerSeesNothing(h);
  });

  scenario('aborted transaction below a pending set leaves nothing behind', (
    Harness h,
  ) {
    int runs = 0;
    setUnderPendingSet(
      h,
      () => h.trackTransaction(
        'T',
        h
            .ref('r/b')
            .runTransaction(
              h.handler(
                (Object? value) => ++runs == 1
                    ? Transaction.success(const <String, Object?>{'c': 2})
                    : Transaction.abort(),
              ),
            ),
      ),
    );
    // Out of order on purpose: the state under test, not a server answer (see the top).
    h.server.failLastWrite('datastale', outOfOrder: true);
    h.settle();
    expect(h.named('T'), <String>['T:aborted(null)']);
    expectNewListenerSeesNothing(h);
  });

  // The listener open during the refusal drops the refused data at once, and `get`, which
  // answers from that view, does too. JS viewProcessorRevertUserWrite returns the view unchanged
  // when a pending write shadows the reverted path and keeps the refused data until the parent
  // write is answered (reproduced on the JS SDK 13.4.0).
  scenario('an open listener drops refused data below a pending set at once', (
    Harness h,
  ) {
    setUnderPendingSet(
      h,
      () => h.track('W2', h.ref('r/b').update(<String, Object?>{'c': 2})),
    );
    // Out of order on purpose: the state under test, not a server answer (see the top).
    h.server.failLastWrite('permission_denied', outOfOrder: true);
    h.settle();
    expect(h.named('S'), <String>[
      'S:V(null)',
      'S:V({a:1})',
      'S:V({a:1,b:{c:2}})',
      'S:V({a:1})',
    ]);
    h.trackValue('G', h.ref('r').get());
    h.settle();
    expect(h.named('G'), <String>['G:={a:1}']);
  });

  // A transaction waits while a transaction above it is in flight, and that one's write shadows
  // it. A set below the waiting transaction aborts it at once: its data must leave the listener
  // then, not when the transaction above is answered. Measured on the emulator before the fix:
  // the aborted data stayed until the first transaction committed.
  scenario(
    'a queued transaction aborted under an ancestor transaction in flight '
    'leaves the listener at once',
    (Harness h) {
      h.listenAnswered('S', h.ref('r').onValue, 'r', <String, Object?>{'x': 0});
      h.trackTransaction(
        'T1',
        h
            .ref('r')
            .runTransaction(
              (Object? value) =>
                  Transaction.success(const <String, Object?>{'x': 1}),
            ),
      );
      h.trackTransaction(
        'T2',
        h
            .ref('r/b')
            .runTransaction(
              (Object? value) =>
                  Transaction.success(const <String, Object?>{'c': 1}),
            ),
      );
      h.track('W', h.ref('r/b/z').set(5));
      h.settle();
      expect(h.named('T2'), <String>['T2:E(overridden-by-set)']);
      expect(h.named('S').last, 'S:V({b:{z:5},x:1})');
      h.trackValue('G', h.ref('r').get());
      h.settle();
      expect(h.named('G'), <String>['G:={b:{z:5},x:1}']);
    },
  );
}
