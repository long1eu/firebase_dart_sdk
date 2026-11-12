// Transactions under a bad network: no lost update, and no double apply unless the answer to the commit is lost.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import 'chaos_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/chaos_transactions';

  late ChaosEnv env;

  setUp(() async {
    if (chaosSkipReason == null) {
      env = await ChaosEnv.start();
    }
  });

  tearDown(() async {
    if (chaosSkipReason == null) {
      await env.close();
    }
  });

  /// Runs [count] read-modify-write transactions one after the other: each one reads the counter document, adds one
  /// to `n`, appends its index to `log` and creates a marker document. [chaos] is called in the first attempt of
  /// each transaction, before the lookup (`beforeLookup` true) and after it, just before the commit.
  ///
  /// Returns the number of attempts of each transaction; a transaction that failed has a negative number.
  Future<List<int>> runTransactions(
    Firestore db,
    CollectionReference<Map<String, Object?>> collection,
    int count,
    FutureOr<void> Function(int index, {required bool beforeLookup}) chaos,
  ) async {
    final DocumentReference<Map<String, Object?>> counter =
        collection.doc('counter');
    final List<int> attempts = <int>[];
    for (int i = 0; i < count; i++) {
      int attempt = 0;
      try {
        await db.runTransaction<void>((Transaction transaction) async {
          attempt++;
          if (attempt == 1) {
            await chaos(i, beforeLookup: true);
          }
          final DocumentSnapshot<Map<String, Object?>> snapshot =
              await transaction.get(counter);
          final Map<String, Object?> data = snapshot.data!;
          if (attempt == 1) {
            await chaos(i, beforeLookup: false);
          }
          transaction
            ..update(counter, <String, Object?>{
              'n': (data['n']! as int) + 1,
              'log': <Object?>[...data['log']! as List<Object?>, i],
            })
            ..set(collection.doc('marker$i'), <String, Object?>{'i': i});
        }).timeout(const Duration(seconds: 20));
        attempts.add(attempt);
      } on FirestoreError catch (e) {
        // ignore: avoid_print
        print('transaction $i failed after $attempt attempts: ${e.code}');
        attempts.add(-attempt);
      }
    }
    return attempts;
  }

  Future<CollectionReference<Map<String, Object?>>> prepare(
      Firestore db) async {
    final String name = uniqueName('tx');
    await env.oracle
        .collection(name)
        .doc('counter')
        .set(<String, Object?>{'n': 0, 'log': <Object?>[]});
    // Open the connection.
    await db.collection(name).doc('counter').get(Source.server);
    return db.collection(name);
  }

  Future<void> expectExactlyOnce(
      CollectionReference<Map<String, Object?>> collection, int count) async {
    final Map<String, Map<String, Object?>> server =
        await env.serverDocs(collection.path);
    expect(server['counter'], <String, Object?>{
      'n': count,
      'log': <Object?>[for (int i = 0; i < count; i++) i],
    });
    expect(server.keys.toSet(), <String>{
      'counter',
      for (int i = 0; i < count; i++) 'marker$i',
    });
  }

  group('transactions', () {
    test('retry a lookup whose request or response is lost', () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);

      final List<int> attempts = await runTransactions(db, collection, 6,
          (int i, {required bool beforeLookup}) {
        if (!beforeLookup) {
          return;
        }
        switch (i % 3) {
          case 0:
            // The connection is gone before the lookup.
            env.proxy.cut();
            break;
          case 1:
            // The request of the lookup is lost.
            unawaited(env.proxy.cutOnNext(ChaosDirection.up, minBytes: 60));
            break;
          case 2:
            // The response of the lookup is lost.
            unawaited(env.proxy.cutOnNext(ChaosDirection.down, minBytes: 30));
            break;
        }
      });

      expect(attempts, everyElement(greaterThan(0)),
          reason: 'every transaction succeeds');
      expect(attempts.where((int a) => a > 1), isNotEmpty,
          reason: 'some lookups were retried: $attempts');
      expect(env.proxy.cuts, greaterThanOrEqualTo(2));
      await expectExactlyOnce(collection, 6);
    });

    test('retry a commit whose request is lost, exactly once', () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);

      final List<int> attempts = await runTransactions(db, collection, 5,
          (int i, {required bool beforeLookup}) async {
        if (beforeLookup) {
          return;
        }
        // Hold back what the client sends from now on (the commit) and drop the connection: the backend never
        // sees the commit.
        env.proxy.mode = ChaosMode.stallUp;
        unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
          env.proxy.cut();
          env.proxy.mode = ChaosMode.forward;
        }));
      });

      expect(attempts, everyElement(greaterThan(1)),
          reason: 'every transaction is retried and succeeds: $attempts');
      await expectExactlyOnce(collection, 5);
    });

    test('a commit whose response is lost is never lost, and reported',
        () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);

      const int count = 5;
      final List<int> attempts = await runTransactions(db, collection, count,
          (int i, {required bool beforeLookup}) async {
        if (beforeLookup) {
          return;
        }
        // The backend receives and applies the commit, but its answer never arrives.
        env.proxy.mode = ChaosMode.stallDown;
        unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
          env.proxy.cut();
          env.proxy.mode = ChaosMode.forward;
        }));
      });

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(collection.path);
      final List<Object?> log = server['counter']!['log']! as List<Object?>;
      final int n = server['counter']!['n']! as int;
      // ignore: avoid_print
      print('lost commit responses: attempts=$attempts n=$n log=$log');

      // No lost update: the counter and the log always move together, every transaction is there, in order.
      expect(n, log.length);
      expect(log.toSet(), <Object?>{for (int i = 0; i < count; i++) i});
      expect(log, List<Object?>.of(log)..sort(),
          reason: 'the transactions are applied in order');
      expect(server.keys.toSet(), <String>{
        'counter',
        for (int i = 0; i < count; i++) 'marker$i',
      });
      // The client cannot know that the commit was applied: it gets UNAVAILABLE, which is retried (as in the other
      // SDKs), and the body runs again on top of its own first commit. So a transaction whose commit answer is
      // lost is applied at most twice here (once per lost answer), never more. See reviews/chaos_findings.md (F2).
      for (int i = 0; i < count; i++) {
        final int applied = log.where((Object? e) => e == i).length;
        expect(applied, inInclusiveRange(1, 2), reason: 'transaction $i');
      }
    });

    test('concurrent transactions of two clients under cuts lose no update',
        () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      final DocumentReference<Map<String, Object?>> counter =
          collection.doc('counter');
      final DocumentReference<Map<String, Object?>> oracleCounter =
          env.oracle.doc(counter.path);

      // The oracle increments 15 times without any trouble, while the client under test does 6 transactions whose
      // lookups are disturbed (requests lost, never an answer to a commit).
      int clientDone = 0;
      Future<void> clientTransactions() async {
        for (int i = 0; i < 6; i++) {
          bool first = true;
          await db.runTransaction<void>((Transaction transaction) async {
            if (first) {
              first = false;
              env.proxy.cut();
            }
            final DocumentSnapshot<Map<String, Object?>> snapshot =
                await transaction.get(counter);
            transaction.update(counter,
                <String, Object?>{'n': (snapshot.data!['n']! as int) + 1});
          }, options: TransactionOptions(maxAttempts: 20)).timeout(
              const Duration(seconds: 25));
          clientDone++;
        }
      }

      Future<void> oracleTransactions() async {
        for (int i = 0; i < 15; i++) {
          await env.oracle.runTransaction<void>(
              (Transaction transaction) async {
            final DocumentSnapshot<Map<String, Object?>> snapshot =
                await transaction.get(oracleCounter);
            transaction.update(oracleCounter,
                <String, Object?>{'n': (snapshot.data!['n']! as int) + 1});
          }, options: TransactionOptions(maxAttempts: 20));
          await pause(20);
        }
      }

      await Future.wait(<Future<void>>[
        clientTransactions(),
        oracleTransactions(),
      ]);
      expect(clientDone, 6);
      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(collection.path);
      expect(server['counter']!['n'], 21);
    });
  }, skip: chaosSkipReason);
}
