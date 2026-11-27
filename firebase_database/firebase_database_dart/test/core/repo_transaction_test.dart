// Repo transactions: rows D24 and D34 to D41 of 14_api_contract.md section 4.4, retries, the
// abort on an overlapping set, and the queue tree. Driven through FakeServerActions.
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// A Repo with `S1` on `c`, answered [value], log cleared.
Future<RepoHarness> withCounter([Object? value = 0]) async {
  final RepoHarness h = RepoHarness();
  h.listen('S1', 'c');
  h.answer('c', value);
  await settle();
  h.log.clear();
  return h;
}

TransactionOutcome increment(Object? value) =>
    TransactionSuccess((value! as int) + 1);

void main() {
  test('D24 purgeOutstandingWrites cancels writes and transactions', () async {
    final RepoHarness h = RepoHarness();
    h.listen('S1', 'a');
    h.answer('a', 1);
    h.listen('S2', 'c');
    h.answer('c', 0);
    await settle();
    h.log.clear();

    h.set('a', 2, name: 'F');
    h.transaction('c', (_) => const TransactionSuccess(7));
    await settle();
    h.repo.purgeOutstandingWrites();
    await settle();

    List<String> named(String prefix) =>
        h.log.where((String e) => e.startsWith(prefix)).toList();
    expect(named('S1:'), <String>['S1:V(2)', 'S1:V(1)']);
    expect(named('S2:'), <String>['S2:V(7)', 'S2:V(0)']);
    expect(named('F:'), <String>['F:E(write-canceled)']);
    expect(named('T:'), <String>['T:E(write-canceled)']);
  });

  test('D34 the first run happens inside the call', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', increment);
    h.log.add('returned');
    await settle();
    h.server.ackLastWrite();
    await settle();
    expect(h.log, <String>['H(0)', 'returned', 'S1:V(1)', 'T:committed(1)']);
    final ServerCall put = h.server.callsOf('put').single;
    expect(put.path, '/c');
    expect(put.data, 1);
    expect(put.hash, isNotNull);
  });

  test('D35 rerun after data-stale', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', increment);
    await settle();
    h.server
      ..deliverDataUpdate('c', 5)
      ..failLastWrite('datastale');
    await settle();
    h.server.ackLastWrite();
    await settle();
    expect(h.log, <String>[
      'H(0)',
      'S1:V(1)',
      'H(5)',
      'S1:V(6)',
      'T:committed(6)',
    ]);
  });

  test('D36 a rerun that aborts reverts', () async {
    final RepoHarness h = await withCounter();
    h.transaction(
      'c',
      (Object? v) =>
          v == 5 ? TransactionOutcome.abort : const TransactionSuccess(1),
    );
    await settle();
    h.server
      ..deliverDataUpdate('c', 5)
      ..failLastWrite('datastale');
    await settle();
    expect(h.log, <String>[
      'H(0)',
      'S1:V(1)',
      'H(5)',
      'S1:V(5)',
      'T:aborted(5)',
    ]);
  });

  test('D37 abort on the first run sends nothing', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', (_) => TransactionOutcome.abort);
    await settle();
    expect(h.log, <String>['H(0)', 'T:aborted(0)']);
    expect(h.server.callsOf('put'), isEmpty);
  });

  test('D38 a throwing handler aborts with user-code-exception', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', (_) => throw StateError('boom'));
    await settle();
    // The public layer keeps the thrown object itself and fails with it.
    expect(h.log, <String>['H(0)', 'T:E(user-code-exception)']);
    expect(h.server.callsOf('put'), isEmpty);
  });

  test(
    'D39 applyLocally false raises no local event before the answer',
    () async {
      final RepoHarness h = await withCounter();
      h.transaction(
        'c',
        (_) => const TransactionSuccess(1),
        applyLocally: false,
      );
      await settle();
      h.server.ackLastWrite();
      await settle();
      expect(h.log, <String>['H(0)', 'S1:V(1)', 'T:committed(1)']);
    },
  );

  test('D40 a sent transaction fails when the connection drops', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', (_) => const TransactionSuccess(1));
    await settle();
    h.server.disconnect();
    await settle();
    expect(h.log, <String>['H(0)', 'S1:V(1)', 'S1:V(0)', 'T:E(disconnected)']);
  });

  test('D41 the handler gets a mutable copy', () async {
    final RepoHarness h = await withCounter(<String, Object?>{'n': 1});
    h.transaction('c', (Object? v) {
      (v! as Map<String, Object?>)['n'] = 2;
      return TransactionSuccess(v);
    });
    await settle();
    h.server.ackLastWrite();
    await settle();
    expect(h.log, <String>[
      'H({"n":1})',
      'S1:V({"n":2})',
      'T:committed({"n":2})',
    ]);
  });

  test('more than 25 runs fail with max-retries', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', increment);
    await settle();
    for (int i = 0; i < maxTransactionRetries; i++) {
      h.server.failLastWrite('datastale');
      await settle();
    }
    expect(h.log.last, 'T:E(max-retries)');
    expect(h.server.callsOf('put'), hasLength(maxTransactionRetries));
    expect(h.log.where((String e) => e.startsWith('H(')), hasLength(25));
  });

  test(
    'a set over a sent transaction aborts it with overridden-by-set',
    () async {
      final RepoHarness h = await withCounter();
      h.transaction('c', increment);
      await settle();
      h.set('c', 10, name: 'F');
      await settle();
      final ServerCall transactionPut = h.server.callsOf('put').first;
      h.server.respond(transactionPut, status: 'datastale');
      await settle();
      expect(h.log, <String>[
        'H(0)',
        'S1:V(1)',
        'S1:V(10)',
        'T:E(overridden-by-set)',
      ]);
    },
  );

  test('a set aborts a queued transaction at once', () async {
    final RepoHarness h = await withCounter(<String, Object?>{'x': 0});
    // The first transaction is sent; the second waits behind it (same queue).
    h.transaction('c/x', increment);
    await settle();
    h.transaction(
      'c',
      (_) => const TransactionSuccess(<String, Object?>{'x': 5}),
    );
    await settle();
    h.log.clear();

    h.set('c', 9);
    await settle();
    expect(h.log, contains('T:E(overridden-by-set)'));
    expect(h.server.callsOf('put').map((ServerCall c) => c.path), <String>[
      '/c/x',
      '/c',
    ]);
  });

  test(
    'a queue waits for its sent transaction, then goes out in order',
    () async {
      final RepoHarness h = await withCounter(<String, Object?>{'x': 0});
      h.transaction('c/x', increment);
      await settle();
      h.transaction(
        'c',
        (Object? v) => TransactionSuccess(<String, Object?>{
          'x': ((v! as Map<String, Object?>)['x']! as int) * 10,
        }),
      );
      await settle();
      expect(h.server.callsOf('put').map((ServerCall c) => c.path), <String>[
        '/c/x',
      ]);

      h.server.ackLastWrite();
      await settle();
      expect(h.server.callsOf('put').map((ServerCall c) => c.path), <String>[
        '/c/x',
        '/c',
      ]);
      expect(h.server.callsOf('put').last.data, <String, Object?>{'x': 10});
      h.server.ackLastWrite();
      await settle();
      expect(h.log.where((String e) => e.startsWith('T:')), <String>[
        'T:committed(1)',
        'T:committed({"x":10})',
      ]);
    },
  );

  test('the transaction result is normalised (C12)', () async {
    final RepoHarness h = await withCounter();
    h.transaction('c', (_) => const TransactionSuccess(-0.0));
    await settle();
    final Object? data = h.server.callsOf('put').single.data;
    expect(data, isA<int>());
    expect(data, 0);
  });

  test('a hijacked hash is sent as badhash', () async {
    final RepoHarness h = await withCounter();
    h.repo.setHijackHash(true);
    h.transaction('c', increment);
    await settle();
    expect(h.server.callsOf('put').single.hash, 'badhash');
  });

  test('transactions are watched: the server data arrives first', () async {
    final RepoHarness h = RepoHarness();
    h.transaction(
      'w',
      (Object? v) => TransactionSuccess(((v as int?) ?? 0) + 1),
    );
    await settle();
    expect(h.server.callsOf('listen').single.spec!.path, '/w');
    // Run on the empty local value, then rerun on the server's value.
    h.answer('w', 41);
    await settle();
    expect(h.log, <String>['H(null)']);
    h.server.failLastWrite('datastale');
    await settle();
    h.server.ackLastWrite();
    await settle();
    expect(h.log, <String>['H(null)', 'H(41)', 'T:committed(42)']);
    await settle();
    expect(h.callsAt('unlisten', '/w'), hasLength(1));
  });

  test(
    'with persistence on, a transaction write is not stored and one info line says so',
    () async {
      final InMemoryPersistenceStorageEngine engine =
          InMemoryPersistenceStorageEngine();
      final RepoHarness h = RepoHarness(persistence: managerOver(engine));
      h.listen('S1', 'c');
      h.answer('c', 0);
      await settle();

      h.transaction('c', increment);
      await settle();
      expect(h.server.callsOf('put').single.path, '/c');
      expect(engine.loadUserWrites(), isEmpty);

      // A plain set on the same Repo is stored: the engine records user writes.
      h.set('d', 1);
      expect(
        engine.loadUserWrites().map((UserWriteRecord w) => w.path.toString()),
        <String>['/d'],
      );

      // A second transaction logs nothing more; the line is written when the call is made.
      h.transaction('c', increment);
      await settle();
      expect(
        h.logs.where(
          (String l) => l.contains('runTransaction() usage detected'),
        ),
        <String>[
          'info: runTransaction() usage detected while persistence is enabled. Please be aware that '
              'transactions *will not* be persisted across database restarts.',
        ],
      );
    },
  );
}
