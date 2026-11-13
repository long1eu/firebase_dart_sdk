// disableNetwork/enableNetwork cycles, terminate and restart with pending writes, waitForPendingWrites and
// snapshotsInSync, under a bad network.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import 'chaos_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/chaos_lifecycle';

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

  group('network cycles', () {
    test('disableNetwork/enableNetwork mixed with writes and listens',
        () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('cycles');
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);
      await collection.doc('counter').set(<String, Object?>{'n': 0});
      final RecordingListener listener = RecordingListener(collection);
      await listener.synced();

      // Writes are issued while offline and while online; the network is only toggled when no write is in flight
      // (so that no acknowledgement is lost and every increment must count exactly once).
      final List<Future<void>> writes = <Future<void>>[];
      int expected = 0;
      for (int round = 0; round < 6; round++) {
        await db.disableNetwork();
        for (int i = 0; i < 3; i++) {
          writes.add(collection
              .doc('counter')
              .update(<String, Object?>{'n': FieldValue.increment(1)}));
          expected++;
        }
        writes.add(
            collection.doc('r$round').set(<String, Object?>{'round': round}));
        if (round.isOdd) {
          writes.add(collection.doc('r${round - 1}').delete());
        }
        // A listener started while offline.
        final RecordingListener offline =
            RecordingListener(collection.where('round', isEqualTo: round));
        await eventually(() => offline.events.isNotEmpty,
            reason: 'a snapshot while offline');
        expect(offline.last.metadata.isFromCache, isTrue);
        expect(offline.last.docs.single.metadata.hasPendingWrites, isTrue);
        // The oracle changes something the client cannot see yet.
        await env.oracle
            .collection(name)
            .doc('oracle')
            .set(<String, Object?>{'round': -round});

        await db.enableNetwork();
        writes.add(collection
            .doc('counter')
            .update(<String, Object?>{'n': FieldValue.increment(1)}));
        expected++;
        await db.waitForPendingWrites().timeout(const Duration(seconds: 10));
        await eventually(
            () =>
                !offline.last.metadata.isFromCache &&
                !offline.last.metadata.hasPendingWrites,
            reason: 'the offline listener to get in sync',
            describe: offline.describe);
        await offline.cancel();
      }
      await Future.wait(writes).timeout(const Duration(seconds: 10));

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      expect(server['counter'], <String, Object?>{'n': expected});
      expect(
          server.keys.toSet(), <String>{'counter', 'oracle', 'r1', 'r3', 'r5'});
      await listener.settlesOn(server.keys.toList()..sort(), server);
      await listener.cancel();
    });

    test('disableNetwork with writes in flight loses no write', () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('inflight');
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);
      await collection
          .doc('log')
          .set(<String, Object?>{'seq': <Object?>[], 'count': 0});

      // The network is disabled right after the writes are issued, so some of them are on their way.
      env.proxy.delay = const Duration(milliseconds: 5);
      final List<Future<void>> writes = <Future<void>>[];
      int index = 0;
      int acknowledged = 0;
      // The increments that the backend applied more than once so far, as far as the test can tell: after each
      // disableNetwork, what the backend counted minus what was acknowledged to the caller. Those writes are still
      // in the queue and are sent again.
      int resent = 0;
      for (int round = 0; round < 6; round++) {
        for (int i = 0; i < 4; i++) {
          final int value = index++;
          writes.add(collection.doc('log').update(<String, Object?>{
            'seq': FieldValue.arrayUnion(<Object?>[value]),
            'count': FieldValue.increment(1),
            'last': value,
          }).then((_) => acknowledged++));
        }
        await pause(round * 4);
        await db.disableNetwork();
        // What the backend had already received is applied by now, and no acknowledgement arrives any more.
        await pause(400);
        final int landed =
            (await env.serverDocs(name))['log']!['count']! as int;
        resent = landed - acknowledged;
        expect(resent, greaterThanOrEqualTo(0));
        await db.enableNetwork();
        // Let the queue drain, so that each round starts from a quiet state.
        await db.waitForPendingWrites().timeout(const Duration(seconds: 10));
      }
      env.proxy.delay = Duration.zero;
      await Future.wait(writes).timeout(const Duration(seconds: 20));

      final Map<String, Object?> log = (await env.serverDocs(name))['log']!;
      expect(log['seq'], <Object?>[for (int i = 0; i < index; i++) i]);
      expect(log['last'], index - 1);
      // An increment is counted again when the acknowledgement of its write did not arrive before the network was
      // disabled (see reviews/chaos_findings.md, F1), and only then: the excess is exactly the number of writes the
      // backend had applied without the caller being told.
      final int count = log['count']! as int;
      // ignore: avoid_print
      print('disableNetwork with writes in flight: count=$count ($index), '
          '$resent applied without an acknowledgement');
      expect(count, index + resent);
      final DocumentSnapshot<Map<String, Object?>> cached =
          await collection.doc('log').get(Source.server);
      expect(cached.data, log);
    });
  }, skip: chaosSkipReason);

  group('terminate and restart', () {
    Map<String, Map<String, Object?>> expectedDocs(int writes) =>
        <String, Map<String, Object?>>{
          'log': <String, Object?>{
            'seq': <Object?>[for (int i = 0; i < writes; i++) i],
            'count': writes,
            'last': writes - 1,
          },
          'kept': <String, Object?>{'v': 2},
        };

    // The number of increments (issued by [issue]) that were acknowledged to the caller.
    int acknowledgedIncrements = 0;

    void issue(
        CollectionReference<Map<String, Object?>> collection, int writes) {
      void ignore(Future<void> future) {
        // The futures of a terminated instance never complete (or fail): nobody waits for them.
        unawaited(future.catchError((Object _) {}));
      }

      ignore(collection
          .doc('log')
          .set(<String, Object?>{'seq': <Object?>[], 'count': 0, 'last': -1}));
      for (int i = 0; i < writes; i++) {
        ignore(collection.doc('log').update(<String, Object?>{
          'seq': FieldValue.arrayUnion(<Object?>[i]),
          'count': FieldValue.increment(1),
          'last': i,
        }).then((_) => acknowledgedIncrements++));
      }
      ignore(collection.doc('kept').set(<String, Object?>{'v': 1}));
      ignore(collection.doc('dropped').set(<String, Object?>{'v': 1}));
      ignore(collection.doc('kept').update(<String, Object?>{'v': 2}));
      ignore(collection.doc('dropped').delete());
    }

    test('pending writes queued offline are sent exactly once after a restart',
        () async {
      final String dbName = env.newDatabaseName();
      final String name = uniqueName('restart');
      Firestore db = await env.newClient(fixedDbName: dbName);
      await db.collection(name).doc('warmup').set(<String, Object?>{});
      await db.collection(name).doc('warmup').delete();

      env.proxy.disconnect();
      issue(db.collection(name), 12);
      await pause(300);
      await db.terminate();
      expect(await env.serverDocs(name), isEmpty);

      // Restart while still offline: the writes are in the cache, as pending writes.
      db = await env.newClient(fixedDbName: dbName);
      final QuerySnapshot<Map<String, Object?>> cached =
          await db.collection(name).get(Source.cache);
      expect(docsById(cached), expectedDocs(12));
      expect(cached.metadata.hasPendingWrites, isTrue);
      await pause(300);
      await db.terminate();

      // Restart with a network: they are sent, once.
      env.proxy.restore();
      db = await env.newClient(fixedDbName: dbName);
      await db.waitForPendingWrites().timeout(const Duration(seconds: 15));
      expect(await env.serverDocs(name), expectedDocs(12));
      final QuerySnapshot<Map<String, Object?>> after =
          await db.collection(name).get(Source.cache);
      expect(docsById(after), expectedDocs(12));
      expect(after.metadata.hasPendingWrites, isFalse);

      // And not again by yet another restart.
      await db.terminate();
      db = await env.newClient(fixedDbName: dbName);
      await db.waitForPendingWrites().timeout(const Duration(seconds: 15));
      await db.collection(name).doc('kept').get(Source.server);
      expect(await env.serverDocs(name), expectedDocs(12));
    });

    test('terminate with writes held back by the network sends them once',
        () async {
      final String dbName = env.newDatabaseName();
      final String name = uniqueName('inflight-restart');
      Firestore db = await env.newClient(fixedDbName: dbName);
      await db.collection(name).doc('warmup').set(<String, Object?>{});
      await db.collection(name).doc('warmup').delete();

      // The requests leave the client but never reach the backend.
      env.proxy.mode = ChaosMode.stallUp;
      issue(db.collection(name), 12);
      await pause(200);
      await db.terminate();
      env.proxy.cut();
      env.proxy.restore();
      expect(await env.serverDocs(name), isEmpty);

      db = await env.newClient(fixedDbName: dbName);
      await db.waitForPendingWrites().timeout(const Duration(seconds: 15));
      expect(await env.serverDocs(name), expectedDocs(12));
    });

    test('terminate in the middle of the writes loses none of them', () async {
      final String dbName = env.newDatabaseName();
      final String name = uniqueName('midflight-restart');
      Firestore db = await env.newClient(fixedDbName: dbName);
      await db.collection(name).doc('warmup').set(<String, Object?>{});
      await db.collection(name).doc('warmup').delete();

      // Terminate while the writes are being sent and acknowledged.
      env.proxy.delay = const Duration(milliseconds: 5);
      issue(db.collection(name), 30);
      await eventually(
          () async =>
              ((await env.serverDocs(name))['log']?['count'] as int? ?? 0) >= 3,
          reason: 'some writes to land');
      await db.terminate();
      final int acknowledged = acknowledgedIncrements;
      env.proxy.delay = Duration.zero;
      // What the backend had already received is applied by now.
      await pause(500);
      final int landed = (await env.serverDocs(name))['log']!['count']! as int;

      db = await env.newClient(fixedDbName: dbName);
      await db.waitForPendingWrites().timeout(const Duration(seconds: 15));
      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      final int count = server['log']!['count']! as int;
      // ignore: avoid_print
      print('terminate in the middle: $landed landed and $acknowledged were '
          'acknowledged before, count=$count (30)');
      // Everything idempotent is exact. A write that the backend applied but whose acknowledgement was not
      // processed before terminate is sent again (F1), so the increment is at least once. A write that was
      // acknowledged to the caller is never sent again.
      expect(count, inInclusiveRange(30, 30 + landed - acknowledged));
      server['log']!['count'] = 30;
      expect(server, expectedDocs(30));
    });
  }, skip: chaosSkipReason);

  group('waitForPendingWrites and snapshotsInSync', () {
    test('waitForPendingWrites completes only when the writes landed',
        () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('wait');
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);
      await collection.doc('warmup').set(<String, Object?>{});

      env.proxy.disconnect();
      final List<Future<void>> writes = <Future<void>>[
        for (int i = 0; i < 5; i++)
          collection.doc('d$i').set(<String, Object?>{'i': i}),
      ];
      bool waited = false;
      final Future<void> wait =
          db.waitForPendingWrites().then((_) => waited = true);
      await pause(1500);
      expect(waited, isFalse,
          reason: 'waitForPendingWrites completed while offline');
      expect((await env.serverDocs(name)).keys, <String>['warmup']);

      // The connection comes back, but it is cut again while the writes go through.
      env.proxy.restore();
      await env.proxy
          .cutOnNext(ChaosDirection.down, minBytes: 30)
          .timeout(const Duration(seconds: 15));
      expect(env.proxy.cuts, greaterThanOrEqualTo(1));
      // A write issued after waitForPendingWrites was called is not waited for.
      env.proxy.disconnect();
      final Future<void> late =
          collection.doc('late').set(<String, Object?>{'late': true});
      await pause(200);
      env.proxy.restore();

      await wait.timeout(const Duration(seconds: 20));
      // When it completes, the writes issued before it are on the backend.
      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      for (int i = 0; i < 5; i++) {
        expect(server['d$i'], <String, Object?>{'i': i});
      }
      await Future.wait(writes).timeout(const Duration(seconds: 10));
      await late.timeout(const Duration(seconds: 15));
    });

    test('snapshotsInSync only fires when the listeners agree', () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('insync');
      final CollectionReference<Map<String, Object?>> writer =
          env.oracle.collection(name);
      for (int i = 0; i < 4; i++) {
        await writer.doc('d$i').set(<String, Object?>{'n': i, 'big': i >= 2});
      }

      final RecordingListener all = RecordingListener(db.collection(name));
      final RecordingListener big =
          RecordingListener(db.collection(name).where('big', isEqualTo: true));
      await all.synced();
      await big.synced();

      // At every in-sync event, what the two listeners last showed must be the same state: the documents of the
      // filtered query are exactly the ones of the full query that match.
      final List<String> disagreements = <String>[];
      int inSyncEvents = 0;
      final StreamSubscription<void> inSync = db.snapshotsInSync.listen((_) {
        inSyncEvents++;
        if (all.events.isEmpty || big.events.isEmpty) {
          return;
        }
        final List<String> fromAll = all.last.docs
            .where((QueryDocumentSnapshot<Map<String, Object?>> d) =>
                d.data['big'] == true)
            .map((QueryDocumentSnapshot<Map<String, Object?>> d) =>
                '${d.id}=${d.data['n']}')
            .toList();
        final List<String> fromBig = big.last.docs
            .map((QueryDocumentSnapshot<Map<String, Object?>> d) =>
                '${d.id}=${d.data['n']}')
            .toList();
        if (fromAll.join(',') != fromBig.join(',')) {
          disagreements.add('in-sync event $inSyncEvents: all has $fromAll, '
              'big has $fromBig');
        }
      });

      // Local writes and remote writes that move documents in and out of the filtered query, with cuts.
      final CollectionReference<Map<String, Object?>> local =
          db.collection(name);
      final List<Future<void>> writes = <Future<void>>[];
      for (int round = 0; round < 8; round++) {
        if (round % 3 == 1) {
          env.proxy.disconnect();
        } else if (round % 3 == 2) {
          env.proxy.cut();
        }
        writes.add(local.doc('d${round % 4}').update(<String, Object?>{
          'big': round.isEven,
          'n': FieldValue.increment(10),
        }));
        await writer.doc('o$round').set(<String, Object?>{
          'n': round,
          'big': round.isOdd,
        });
        await writer.doc('d${(round + 2) % 4}').set(
            <String, Object?>{'big': round % 4 < 2}, SetOptions.mergeAllFields);
        await pause(200);
        env.proxy.restore();
        await pause(200);
      }
      await Future.wait(writes).timeout(const Duration(seconds: 20));

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      await all.settlesOn(server.keys.toList()..sort(), server);
      await big.settlesOn(
          server.keys.where((String id) => server[id]!['big'] == true).toList()
            ..sort(),
          server);
      expect(inSyncEvents, greaterThan(8));
      expect(disagreements, isEmpty);
      await inSync.cancel();
      await all.cancel();
      await big.cancel();
    });
  }, skip: chaosSkipReason);
}
