// Gaps the test quality audit listed (rtdb/from_helper/reports/test_quality_audit.md): mutation
// m18 (`.info/authenticated` after an auth failure), transaction priority (D3) and a transaction
// refused by the server (D4). Driven through FakeServerActions.
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// A Repo with `S1` on `c`, answered [value], log cleared.
Future<RepoHarness> _withCounter(Object? value) async {
  final RepoHarness h = RepoHarness();
  h.listen('S1', 'c');
  h.answer('c', value);
  await settle();
  h.log.clear();
  return h;
}

void main() {
  test('m18: .info/authenticated is false after an auth failure', () async {
    final RepoHarness h = RepoHarness();
    h.listen('I', '.info/authenticated');
    h.server.deliverAuthStatus('ok');
    await settle();
    h.server.deliverAuthStatus('invalid_token', explanation: 'revoked');
    await settle();
    expect(h.log.last, 'I:V(false)');
    expect(h.log, contains('I:V(true)'));
  });

  group('transaction priority (D3)', () {
    test('a .priority in the result is written and sent', () async {
      final RepoHarness h = await _withCounter(1);
      h.transaction(
        'c',
        (_) => const TransactionSuccess(<String, Object?>{
          '.value': 2,
          '.priority': 'p5',
        }),
      );
      await settle();
      expect(h.server.callsOf('put').single.data, <String, Object?>{
        '.value': 2,
        '.priority': 'p5',
      });
      h.server.ackLastWrite();
      await settle();
      expect(h.log.last, 'T:committed(2)');
      expect(h.server.dataAt('c'), <String, Object?>{
        '.value': 2,
        '.priority': 'p5',
      });
    });

    test('a rerun keeps the priority the server sent', () async {
      final RepoHarness h = await _withCounter(<String, Object?>{
        '.value': 1,
        '.priority': 'p7',
      });
      h.transaction('c', (Object? v) => TransactionSuccess((v! as int) + 1));
      await settle();
      h.server
        ..deliverDataUpdate('c', <String, Object?>{
          '.value': 5,
          '.priority': 'p9',
        })
        ..failLastWrite('datastale');
      await settle();
      expect(h.server.callsOf('put').last.data, <String, Object?>{
        '.value': 6,
        '.priority': 'p9',
      });
      h.server.ackLastWrite();
      await settle();
      expect(h.log, <String>[
        'H(1)',
        'S1:V(2)',
        'H(5)',
        'S1:V(6)',
        'T:committed(6)',
      ]);
      expect(h.repo.debugPendingWriteIds, isEmpty);
    });
  });

  test('D4: a transaction the server refuses fails and reverts', () async {
    final RepoHarness h = await _withCounter(0);
    h.transaction('c', (_) => const TransactionSuccess(1));
    await settle();
    h.server.failLastWrite('permission_denied', reason: 'no');
    await settle();
    expect(h.log, <String>[
      'H(0)',
      'S1:V(1)',
      'S1:V(0)',
      'T:E(permission-denied)',
    ]);
    expect(h.repo.debugPendingWriteIds, isEmpty);
    expect(h.repo.debugTransactionQueueEmpty, isTrue);
    expect(h.server.callsOf('put'), hasLength(1), reason: 'not retried');
  });
}
