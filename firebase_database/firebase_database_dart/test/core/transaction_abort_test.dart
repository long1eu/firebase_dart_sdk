// Transactions aborted while they wait: a second abort of a sent transaction (review H1) and a
// handler that writes to its own path (review M1). Driven through FakeServerActions.
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// A Repo with `S1` on `c`, answered [value], log cleared.
Future<RepoHarness> _withCounter([Object? value = 0]) async {
  final RepoHarness h = RepoHarness();
  h.listen('S1', 'c');
  h.answer('c', value);
  await settle();
  h.log.clear();
  return h;
}

TransactionOutcome _increment(Object? value) =>
    TransactionSuccess((value! as int) + 1);

/// Pushes [value] at [path] as the server stores it, then acknowledges [call].
void _ackWith(RepoHarness h, ServerCall call, String path, Object? value) {
  h.server.deliverDataUpdate(path, value);
  h.server.respond(call);
}

void _expectClean(RepoHarness h) {
  expect(h.repo.debugPendingWriteIds, isEmpty, reason: 'pending writes');
  expect(h.repo.debugTransactionQueueEmpty, isTrue, reason: 'queue');
}

void main() {
  group('a sent transaction aborted twice still completes (H1)', () {
    test('two sets, then datastale: overridden-by-set, the sets win', () async {
      final RepoHarness h = await _withCounter();
      h.transaction('c', _increment);
      await settle();
      h
        ..set('c', 10, name: 'F1')
        ..set('c', 11, name: 'F2');
      await settle();
      final List<ServerCall> puts = h.server.callsOf('put');
      h.server.respond(puts[0], status: 'datastale');
      await settle();
      _ackWith(h, puts[1], 'c', 10);
      _ackWith(h, puts[2], 'c', 11);
      await settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'S1:V(10)',
        'S1:V(11)',
        'T:E(overridden-by-set)',
        'F1:ok',
        'F2:ok',
      ]);
      _expectClean(h);
    });

    test('a set, then purge: write-canceled, nothing left', () async {
      final RepoHarness h = await _withCounter();
      h.transaction('c', _increment);
      await settle();
      h.set('c', 10, name: 'F');
      h.repo.purgeOutstandingWrites();
      await settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'S1:V(10)',
        'S1:V(0)',
        'T:E(write-canceled)',
        'F:E(write-canceled)',
      ]);
      _expectClean(h);
    });
  });

  group('a handler that writes to its own path (M1)', () {
    test('on its second run: overridden-by-set, the set wins', () async {
      final RepoHarness h = await _withCounter();
      int runs = 0;
      h.transaction('c', (Object? v) {
        if (++runs == 2) {
          h.set('c', 50, name: 'F');
        }
        return _increment(v);
      });
      await settle();
      h.server
        ..deliverDataUpdate('c', 5)
        ..failLastWrite('datastale');
      await settle();
      h.server.ackLastWrite();
      await settle();
      expect(runs, 2);
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'H(5)',
        'S1:V(50)',
        'T:E(overridden-by-set)',
        'F:ok',
      ]);
      expect(h.server.callsOf('put').last.data, 50);
      _expectClean(h);
    });

    test('on its first run: overridden-by-set, only the set is sent', () async {
      final RepoHarness h = await _withCounter();
      h.transaction('c', (Object? v) {
        h.set('c', 50, name: 'F');
        return _increment(v);
      });
      await settle();
      h.server.ackLastWrite();
      await settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(50)',
        'T:E(overridden-by-set)',
        'F:ok',
      ]);
      expect(h.server.callsOf('put').map((ServerCall c) => c.hash), <String?>[
        null,
      ]);
      _expectClean(h);
    });

    test('a write elsewhere does not abort it', () async {
      final RepoHarness h = await _withCounter();
      h.transaction('c', (Object? v) {
        h.set('d', 1);
        return _increment(v);
      });
      await settle();
      final ServerCall put = h.server
          .callsOf('put')
          .firstWhere((ServerCall c) => c.hash != null);
      expect(put.data, 1);
    });
  });
}
