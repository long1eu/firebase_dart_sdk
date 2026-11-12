// Listeners under a bad network: after the network is back, the last snapshot is the state of the backend.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import 'chaos_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/chaos_listeners';

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

  group('listeners', () {
    test('across repeated cuts end with the state of the backend', () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('listen');
      final CollectionReference<Map<String, Object?>> writer =
          env.oracle.collection(name);
      for (int i = 0; i < 5; i++) {
        await writer
            .doc('d$i')
            .set(<String, Object?>{'n': i, 'even': i.isEven});
      }

      final RecordingListener all =
          RecordingListener(db.collection(name).orderBy('n'));
      final RecordingListener even = RecordingListener(db
          .collection(name)
          .where('even', isEqualTo: true)
          .orderBy('n', Direction.descending)
          .limit(3));
      await all.synced();

      // The oracle keeps changing the collection while the connection of the client is cut again and again, at
      // different moments: dropped, refused for a while, cut when data flows down, stalled then dropped.
      int next = 5;
      Future<void> churn(int round) async {
        await writer.doc('d${next++}').set(<String, Object?>{
          'n': 100 - round,
          'even': round.isEven,
        });
        await writer.doc('d${round % 5}').set(<String, Object?>{
          'n': FieldValue.increment(1000),
          'even': round.isOdd,
        }, SetOptions.mergeAllFields);
        if (round % 3 == 0) {
          await writer.doc('d${next - 2}').delete();
        }
      }

      for (int round = 0; round < 8; round++) {
        switch (round % 4) {
          case 0:
            env.proxy.cut();
            break;
          case 1:
            env.proxy.disconnect();
            break;
          case 2:
            unawaited(env.proxy.cutOnNext(ChaosDirection.down, minBytes: 30));
            break;
          case 3:
            env.proxy.mode = ChaosMode.stall;
            break;
        }
        await churn(round);
        await pause(250);
        if (round % 4 == 3) {
          env.proxy.cut();
        }
        env.proxy.restore();
        await churn(round + 100);
        await pause(150);
      }
      env.proxy.restore();

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      final List<String> expectedAll = server.keys.toList()
        ..sort((String a, String b) {
          final int byN =
              (server[a]!['n']! as int).compareTo(server[b]!['n']! as int);
          return byN != 0 ? byN : a.compareTo(b);
        });
      final List<String> expectedEven = expectedAll.reversed
          .where((String id) => server[id]!['even'] == true)
          .take(3)
          .toList();

      await all.settlesOn(expectedAll, server);
      await even.settlesOn(expectedEven, server);
      expect(env.proxy.cuts, greaterThanOrEqualTo(2));
      await all.cancel();
      await even.cancel();
    });

    test('report pending writes and the cache state across an outage',
        () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('metadata');
      await env.oracle.collection(name).doc('a').set(<String, Object?>{'v': 0});

      final RecordingListener listener = RecordingListener(db.collection(name));
      await listener.synced();
      expect(listener.last.metadata.hasPendingWrites, isFalse);

      env.proxy.disconnect();
      final Future<void> write =
          db.collection(name).doc('a').update(<String, Object?>{'v': 1});
      final Future<void> create =
          db.collection(name).doc('b').set(<String, Object?>{'v': 2});

      // The local writes show up at once, flagged as pending, on both documents.
      await eventually(
          () =>
              listener.last.docs.length == 2 &&
              listener.last.metadata.hasPendingWrites,
          reason: 'the pending writes');
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in listener.last.docs) {
        expect(doc.metadata.hasPendingWrites, isTrue, reason: doc.id);
      }
      expect(listener.last.docs.first.data, <String, Object?>{'v': 1});

      // A change made elsewhere during the outage.
      await env.oracle.collection(name).doc('c').set(<String, Object?>{'v': 3});
      // Once the client gives up on the connection the snapshots are from cache.
      await eventually(() => listener.last.metadata.isFromCache,
          timeout: const Duration(seconds: 15),
          reason: 'a snapshot from cache while offline');
      expect(listener.last.metadata.hasPendingWrites, isTrue);
      expect(listener.last.docs.length, 2);

      env.proxy.restore();
      await write.timeout(const Duration(seconds: 15));
      await create.timeout(const Duration(seconds: 15));
      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      expect(server, <String, Map<String, Object?>>{
        'a': <String, Object?>{'v': 1},
        'b': <String, Object?>{'v': 2},
        'c': <String, Object?>{'v': 3},
      });
      await listener.settlesOn(<String>['a', 'b', 'c'], server);
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in listener.last.docs) {
        expect(doc.metadata.hasPendingWrites, isFalse, reason: doc.id);
        expect(doc.metadata.isFromCache, isFalse, reason: doc.id);
      }
      await listener.cancel();
    });

    test('resolve limbo documents while the connection is cut', () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('limbo');
      final CollectionReference<Map<String, Object?>> writer =
          env.oracle.collection(name);
      for (final String id in <String>['a', 'b', 'c', 'd']) {
        await writer.doc(id).set(<String, Object?>{'match': true});
      }

      // Fill the cache, then stop listening: the client does not see what changes next.
      final RecordingListener warmup = RecordingListener(db.collection(name));
      await warmup.synced();
      await warmup.cancel();
      await writer.doc('b').update(<String, Object?>{'match': false});
      await writer.doc('c').delete();
      await writer.doc('e').set(<String, Object?>{'match': true});

      // The cache says a, b, c and d match; the backend says a, d and e. b and c are in limbo until the client
      // looks them up. The connection is cut while that happens, twice.
      final Future<void> firstCut =
          env.proxy.cutOnNext(ChaosDirection.down, minBytes: 30);
      final RecordingListener listener = RecordingListener(
          db.collection(name).where('match', isEqualTo: true));
      await firstCut.timeout(const Duration(seconds: 10));
      // (The second cut is given up if the listener already got everything.)
      await env.proxy.cutOnNext(ChaosDirection.down, minBytes: 30).timeout(
          const Duration(seconds: 3),
          onTimeout: () => env.proxy.cutWhen = null);

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      await listener.settlesOn(<String>['a', 'd', 'e'], server);
      await listener.cancel();
    });

    test('catch up with deletes and updates after a long outage', () async {
      final Firestore db = await env.newClient();
      final String name = uniqueName('outage');
      final CollectionReference<Map<String, Object?>> writer =
          env.oracle.collection(name);
      for (int i = 0; i < 20; i++) {
        await writer
            .doc('d${i.toString().padLeft(2, '0')}')
            .set(<String, Object?>{'n': i});
      }
      final RecordingListener all = RecordingListener(db.collection(name));
      final RecordingListener some = RecordingListener(
          db.collection(name).where('n', isLessThan: 10).limit(5));
      await all.synced();
      await some.synced();

      env.proxy.disconnect();
      for (int i = 0; i < 20; i += 2) {
        await writer.doc('d${i.toString().padLeft(2, '0')}').delete();
      }
      for (int i = 1; i < 20; i += 4) {
        await writer
            .doc('d${i.toString().padLeft(2, '0')}')
            .update(<String, Object?>{'n': -i});
      }
      await writer.doc('new').set(<String, Object?>{'n': 3});
      await pause(500);
      env.proxy.restore();

      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(name);
      await all.settlesOn(server.keys.toList()..sort(), server);
      final List<String> expectedSome = (server.keys
              .where((String id) => (server[id]!['n']! as int) < 10)
              .toList()
            ..sort((String a, String b) {
              final int byN =
                  (server[a]!['n']! as int).compareTo(server[b]!['n']! as int);
              return byN != 0 ? byN : a.compareTo(b);
            }))
          .take(5)
          .toList();
      await some.settlesOn(expectedSome, server);
      await all.cancel();
      await some.cancel();
    });
  }, skip: chaosSkipReason);
}
