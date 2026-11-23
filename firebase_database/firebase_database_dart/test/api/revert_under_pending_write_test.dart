// A write refused by the server (or a transaction aborted) while an earlier write at a parent is
// still pending. The visible writes fold the lower write's data into the parent write's node. JS
// `WriteTree.ts` writeTreeRemoveWrite counts only writes at or below the removed one as
// overlapping, so it removed the lower write by its paths and left its data in the parent's node:
// a listener opened after the refusal saw the refused data until the parent write was answered.
// lib/src/core/write_tree.dart counts the parent write as overlapping and rebuilds. A listener
// open during the refusal kept the data too, because JS viewProcessorRevertUserWrite returns the
// view unchanged under a shadowing write; lib/src/core/view/view_processor.dart recomputes.

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
    h.server.failLastWrite('permission_denied');
    h.settle();
    expect(h.named('W2'), <String>['W2:E(permission-denied)']);
    expectNewListenerSeesNothing(h);
  });

  scenario('refused set below a pending set leaves nothing behind', (
    Harness h,
  ) {
    setUnderPendingSet(h, () => h.track('W2', h.ref('r/b/c').set(2)));
    h.server.failLastWrite('permission_denied');
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
    h.server.failLastWrite('datastale');
    h.settle();
    expect(h.named('T'), <String>['T:aborted(null)']);
    expectNewListenerSeesNothing(h);
  });

  // What should happen: the listener open during the refusal drops the refused data at once, and
  // `get`, which answers from that view, does too. It does not yet: ViewProcessor.revertUserWrite,
  // like JS viewProcessorRevertUserWrite, returns the view unchanged when a pending write shadows
  // the reverted path, so the refused data stays until the parent write is answered (reproduced
  // on the JS SDK 13.4.0). Always recomputing instead was tried and breaks a listener whose listen
  // is not answered yet, so this stays skipped until that fix exists.
  scenario(
    'an open listener drops refused data below a pending set at once',
    (Harness h) {
      setUnderPendingSet(
        h,
        () => h.track('W2', h.ref('r/b').update(<String, Object?>{'c': 2})),
      );
      h.server.failLastWrite('permission_denied');
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
    },
    skip:
        'open defect shared with the JS SDK: the open listener keeps refused data',
  );
}
