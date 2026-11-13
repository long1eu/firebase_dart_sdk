// Read-only transactions are transactions of the backend: started with the
// first read, every read carries their id, nothing is committed and they are
// released at the end.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction_runner.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Records what a transaction asks of the backend.
class _RecordingClient extends Fake implements TransactionClient {
  final List<String> calls = <String>[];
  int begun = 0;

  /// Errors thrown by the next lookups, in order.
  final List<FirestoreErrorCode> lookupErrors = <FirestoreErrorCode>[];
  bool rollbackFails = false;

  @override
  Future<Uint8List> beginReadOnlyTransaction({SnapshotVersion? readTime}) async {
    begun++;
    calls.add('begin${readTime == null ? '' : '@${readTime.timestamp.seconds}'}');
    return Uint8List.fromList(<int>[begun]);
  }

  @override
  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys,
      {Uint8List? transaction}) async {
    calls.add('lookup in $transaction');
    if (lookupErrors.isNotEmpty) {
      throw FirestoreError('lookup failed', lookupErrors.removeAt(0));
    }
    return <MaybeDocument>[doc('foo/bar', 7, map(<String>['a', 'b']))];
  }

  @override
  Future<List<Document>> runQuery(Query query, Uint8List transaction) async {
    calls.add('query in $transaction');
    return <Document>[doc('foo/bar', 7, map(<String>['a', 'b']))];
  }

  @override
  Future<Map<String, FieldValue>> runAggregateQuery(Query query,
      List<AggregateField> aggregateFields, Uint8List transaction) async {
    calls.add('aggregate in $transaction');
    return <String, FieldValue>{};
  }

  @override
  Future<void> rollback(Uint8List transaction) async {
    calls.add('rollback $transaction');
    if (rollbackFails) {
      throw FirestoreError('gone', FirestoreErrorCode.unavailable);
    }
  }

  @override
  Future<List<MutationResult>> commit(List<Mutation> mutations) async {
    calls.add('commit');
    return <MutationResult>[];
  }
}

void main() {
  final DocumentKey docKey = key('foo/bar');
  final Query foo = query('foo');
  late _RecordingClient client;

  setUp(() => client = _RecordingClient());

  TransactionRunner<String> runner(
    Future<String> Function(Transaction) updateFunction, {
    bool readOnly = true,
    int maxAttempts = 5,
  }) {
    return TransactionRunner<String>(
      createTransaction: () => Transaction(client, readOnly: readOnly),
      maxAttempts: maxAttempts,
      backoff: ExponentialBackoff(
          TaskScheduler('read-only'), TaskId.retryTransaction,
          initialDelay: const Duration(milliseconds: 1)),
      updateFunction: updateFunction,
    );
  }

  group('a read-only transaction', () {
    test('starts on the backend with its first read, once', () async {
      final Transaction tx = Transaction(client, readOnly: true);
      expect(client.calls, isEmpty);

      await Future.wait(<Future<void>>[
        tx.lookup(<DocumentKey>[docKey]),
        tx.runQuery(foo),
      ]);
      await tx.runAggregateQuery(foo, <AggregateField>[AggregateField.count()]);
      await tx.lookup(<DocumentKey>[docKey]);

      expect(client.begun, 1);
      expect(client.calls.first, 'begin');
      expect(client.calls.skip(1), <String>[
        'lookup in [1]',
        'query in [1]',
        'aggregate in [1]',
        'lookup in [1]',
      ]);
    });

    test('passes its read time when it starts', () async {
      final Transaction tx =
          Transaction(client, readOnly: true, readTime: version(5000000));
      await tx.lookup(<DocumentKey>[docKey]);
      expect(client.calls.first, 'begin@5');
    });

    test('commits nothing and is released when it ends', () async {
      final Transaction tx = Transaction(client, readOnly: true);
      await tx.lookup(<DocumentKey>[docKey]);
      await tx.commit();

      expect(client.calls, <String>['begin', 'lookup in [1]', 'rollback [1]']);
      expect(tx.committed, isTrue);
      // Releasing again does nothing.
      await tx.release();
      expect(client.calls, hasLength(3));
    });

    test('that read nothing does not talk to the backend', () async {
      final Transaction tx = Transaction(client, readOnly: true);
      await tx.commit();
      expect(client.calls, isEmpty);
      expect(tx.committed, isTrue);
    });

    test('ends normally when the release fails', () async {
      client.rollbackFails = true;
      final Transaction tx = Transaction(client, readOnly: true);
      await tx.lookup(<DocumentKey>[docKey]);
      await tx.commit();
      expect(client.calls.last, 'rollback [1]');
    });

    test('rejects writes', () async {
      final UserDataConverter converter =
          UserDataConverter(DatabaseId.forProject('project'));
      final Transaction tx = Transaction(client, readOnly: true);
      Matcher invalid = throwsA(isA<FirestoreError>().having(
          (FirestoreError e) => e.code,
          'code',
          FirestoreErrorCode.invalidArgument));

      expect(
          () => tx.set(
              docKey, converter.parseSetData(<String, Object?>{'a': 1})),
          invalid);
      expect(
          () => tx.update(
              docKey, converter.parseUpdateData(<String, Object?>{'a': 1})),
          invalid);
      expect(() => tx.delete(docKey), invalid);
      await tx.commit();
      expect(client.calls, isEmpty);
    });

    test('cannot be used after it ended', () async {
      final Transaction tx = Transaction(client, readOnly: true);
      await tx.commit();
      expect(tx.commit, throwsA(anything));
      expect(() => tx.lookup(<DocumentKey>[docKey]), throwsA(anything));
      expect(() => tx.runQuery(foo), throwsA(anything));
    });
  });

  group('a read-write transaction', () {
    test('reads without a backend transaction and cannot run queries',
        () async {
      final Transaction tx = Transaction(client);
      expect(tx.readOnly, isFalse);
      await tx.lookup(<DocumentKey>[docKey]);
      expect(client.calls, <String>['lookup in null']);

      Matcher invalid = throwsA(isA<FirestoreError>()
          .having((FirestoreError e) => e.code, 'code',
              FirestoreErrorCode.invalidArgument)
          .having((FirestoreError e) => e.message, 'message',
              contains('read-only transaction')));
      await expectLater(tx.runQuery(foo), invalid);
      await expectLater(
          tx.runAggregateQuery(
              foo, <AggregateField>[AggregateField.count()]),
          invalid);
      // Releasing is only for read-only transactions.
      await tx.release();
      expect(client.calls, hasLength(1));
    });
  });

  group('running a read-only transaction', () {
    test('releases the transaction and does not commit', () async {
      expect(
          await runner((Transaction tx) async {
            await tx.lookup(<DocumentKey>[docKey]);
            return 'done';
          }).run(),
          'done');
      expect(client.calls, <String>['begin', 'lookup in [1]', 'rollback [1]']);
    });

    test('is not retried for the errors of a conflict', () async {
      for (final FirestoreErrorCode code in <FirestoreErrorCode>[
        FirestoreErrorCode.aborted,
        FirestoreErrorCode.failedPrecondition,
        FirestoreErrorCode.alreadyExists,
      ]) {
        client = _RecordingClient()..lookupErrors.add(code);
        int attempts = 0;
        await expectLater(
            runner((Transaction tx) async {
              attempts++;
              await tx.lookup(<DocumentKey>[docKey]);
              return 'done';
            }).run(),
            throwsA(isA<FirestoreError>()
                .having((FirestoreError e) => e.code, 'code', code)));
        expect(attempts, 1, reason: '$code');
        // The failed attempt was released.
        expect(client.calls.last, 'rollback [1]');
      }
    });

    test('is retried when the connection fails, in a new transaction',
        () async {
      client.lookupErrors.add(FirestoreErrorCode.unavailable);
      int attempts = 0;
      expect(
          await runner((Transaction tx) async {
            attempts++;
            await tx.lookup(<DocumentKey>[docKey]);
            return 'done';
          }).run(),
          'done');
      expect(attempts, 2);
      expect(client.calls, <String>[
        'begin',
        'lookup in [1]',
        'rollback [1]',
        'begin',
        'lookup in [2]',
        'rollback [2]',
      ]);
    });

    test('is released when the callback throws', () async {
      await expectLater(
          runner((Transaction tx) async {
            await tx.lookup(<DocumentKey>[docKey]);
            throw StateError('callback failed');
          }).run(),
          throwsStateError);
      expect(client.calls.last, 'rollback [1]');
    });

    test('a read-write transaction is still retried for a conflict',
        () async {
      client.lookupErrors.add(FirestoreErrorCode.aborted);
      int attempts = 0;
      await runner((Transaction tx) async {
        attempts++;
        await tx.lookup(<DocumentKey>[docKey]);
        return 'done';
      }, readOnly: false)
          .run();
      expect(attempts, 2);
      expect(client.calls.where((String c) => c.startsWith('rollback')),
          isEmpty);
    });
  });
}
