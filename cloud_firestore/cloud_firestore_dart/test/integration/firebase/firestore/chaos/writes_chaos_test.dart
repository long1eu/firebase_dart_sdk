// Writes under a bad network: every write lands exactly once and in order.
//
// The client under test reaches the emulator through a proxy that the test cuts; a second client that talks to the
// emulator directly is the oracle.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import 'chaos_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/chaos_writes';

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

  /// Issues the writes of the scenario on [collection] and returns their futures. The expected result is
  /// [expectedDocs].
  List<Future<void>> issueWrites(
      Firestore db, CollectionReference<Map<String, Object?>> collection) {
    final DocumentReference<Map<String, Object?>> a = collection.doc('a');
    final DocumentReference<Map<String, Object?>> b = collection.doc('b');
    final DocumentReference<Map<String, Object?>> log = collection.doc('log');
    final List<Future<void>> writes = <Future<void>>[
      a.set(<String, Object?>{'n': 0, 'list': <Object?>[], 'tag': 'first'}),
      for (int i = 0; i < 5; i++)
        a.update(<String, Object?>{'n': FieldValue.increment(1)}),
      a.update(<String, Object?>{
        'list': FieldValue.arrayUnion(<Object?>[1, 2])
      }),
      a.update(<String, Object?>{
        'list': FieldValue.arrayUnion(<Object?>[2, 3])
      }),
      a.update(<String, Object?>{
        'list': FieldValue.arrayRemove(<Object?>[1])
      }),
      a.update(<String, Object?>{'tag': 'second'}),
      // Set, delete and set again: the last one wins.
      b.set(<String, Object?>{'v': 1}),
      b.delete(),
      b.set(<String, Object?>{'v': 2}),
      // A document that existed before is deleted, another one is created and deleted.
      collection.doc('existing').delete(),
      collection.doc('transient').set(<String, Object?>{'v': 1}),
      collection.doc('transient').delete(),
      // The order of the writes: each one appends its index.
      log.set(<String, Object?>{'seq': <Object?>[], 'last': -1}),
      for (int i = 0; i < 20; i++)
        log.update(<String, Object?>{
          'seq': FieldValue.arrayUnion(<Object?>[i]),
          'last': i,
          'count': FieldValue.increment(1),
        }),
      // Batches are atomic and counted once.
      (db.batch()
            ..set(collection.doc('batch1'), <String, Object?>{'v': 1})
            ..update(a, <String, Object?>{'n': FieldValue.increment(10)})
            ..delete(collection.doc('existing2')))
          .commit(),
      (db.batch()
            ..set(collection.doc('batch2'), <String, Object?>{'v': 2})
            ..update(a, <String, Object?>{'n': FieldValue.increment(100)})
            ..update(collection.doc('batch1'),
                <String, Object?>{'v': FieldValue.increment(1)}))
          .commit(),
    ];
    return writes;
  }

  final Map<String, Map<String, Object?>> expectedDocs =
      <String, Map<String, Object?>>{
    'a': <String, Object?>{
      'n': 115,
      'list': <Object?>[2, 3],
      'tag': 'second',
    },
    'b': <String, Object?>{'v': 2},
    'log': <String, Object?>{
      'seq': <Object?>[for (int i = 0; i < 20; i++) i],
      'last': 19,
      'count': 20,
    },
    'batch1': <String, Object?>{'v': 2},
    'batch2': <String, Object?>{'v': 2},
  };

  Future<CollectionReference<Map<String, Object?>>> prepare(
      Firestore db) async {
    final String name = uniqueName('writes');
    await env.oracle.collection(name).doc('existing').set(<String, Object?>{});
    await env.oracle.collection(name).doc('existing2').set(<String, Object?>{});
    return db.collection(name);
  }

  Future<void> expectLanded(Firestore db,
      CollectionReference<Map<String, Object?>> collection) async {
    expect(await env.serverDocs(collection.path), expectedDocs,
        reason: 'the backend');
    // The cache of the client agrees, without pending writes.
    final QuerySnapshot<Map<String, Object?>> cached =
        await collection.get(Source.cache);
    expect(docsById(cached), expectedDocs, reason: 'the cache of the client');
    expect(cached.metadata.hasPendingWrites, isFalse);
  }

  group('writes', () {
    test('queued while the connection is cut land exactly once and in order',
        () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      // Open the write stream first, then lose the network.
      await collection.doc('warmup').set(<String, Object?>{});
      await collection.doc('warmup').delete();

      env.proxy.disconnect();
      final List<Future<void>> writes = issueWrites(db, collection);
      // The writes are visible locally right away, as pending writes.
      final QuerySnapshot<Map<String, Object?>> pending =
          await collection.get(Source.cache);
      expect(docsById(pending), expectedDocs);
      expect(pending.metadata.hasPendingWrites, isTrue);

      await pause(1500);
      env.proxy.restore();
      await Future.wait(writes).timeout(const Duration(seconds: 20));
      await expectLanded(db, collection);
    });

    test('issued before the first connection land exactly once', () async {
      env.proxy.disconnect();
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      final List<Future<void>> writes = issueWrites(db, collection);
      await pause(1000);
      env.proxy.restore();
      await Future.wait(writes).timeout(const Duration(seconds: 20));
      await expectLanded(db, collection);
    });

    test('survive cuts in the middle of the write stream that lose requests',
        () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      await collection.doc('warmup').set(<String, Object?>{});
      await collection.doc('warmup').delete();

      // Slow the traffic down so that the cuts fall in the middle of the writes. Before each cut the requests are
      // held back for a moment while the answers still arrive: only requests are lost, never an acknowledgement.
      env.proxy.delay = const Duration(milliseconds: 10);
      final List<Future<void>> writes = issueWrites(db, collection);
      int cuts = 0;
      for (final int bytes in <int>[400, 1500, 3000]) {
        final int start = env.proxy.bytesUp;
        await eventually(() => env.proxy.bytesUp - start >= bytes,
                reason: 'more requests')
            .timeout(const Duration(seconds: 5), onTimeout: () {});
        env.proxy.mode = ChaosMode.stallUp;
        await env.proxy.backendQuiet();
        if (env.proxy.openConnections > 0) {
          cuts++;
        }
        env.proxy.cut();
        env.proxy.mode = ChaosMode.forward;
      }
      env.proxy.delay = Duration.zero;

      await Future.wait(writes).timeout(const Duration(seconds: 25));
      expect(cuts, greaterThanOrEqualTo(1));
      // The premise of this test: every answer of the backend reached the client before the cuts. A write whose
      // acknowledgement is lost is sent again and applied twice (F1, the test below), so exactly-once is only
      // expected without lost answers.
      expect(env.proxy.answerBytesLostByCuts, 0,
          reason: 'a cut lost answers of the backend');
      await expectLanded(db, collection);
    });

    test('survive cuts that lose acknowledgements (at least once)', () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      await collection.doc('warmup').set(<String, Object?>{});
      await collection.doc('warmup').delete();

      // The acknowledgement of a write the backend applied is lost, and the client sends the write again on the
      // next stream.
      final List<Future<void>> writes = issueWrites(db, collection);
      // Twice, while the writes go through: the answers of the backend are held back for a moment and the
      // connection is dropped, so the backend applied writes whose acknowledgement never arrives.
      env.proxy.delay = const Duration(milliseconds: 5);
      int lostBytes = 0;
      for (int round = 0; round < 2; round++) {
        // Wait until acknowledgements are coming back (the stream is open and writes are in flight).
        final int start = env.proxy.bytesDown;
        await eventually(() => env.proxy.bytesDown - start >= 150,
                reason: 'more answers')
            .timeout(const Duration(seconds: 3), onTimeout: () {});
        env.proxy.mode = ChaosMode.stallDown;
        // The backend answers what it applies; those answers are held back and then lost.
        final int held = env.proxy.bytesDown;
        await env.proxy.backendQuiet(quiet: const Duration(milliseconds: 300));
        lostBytes += env.proxy.bytesDown - held;
        env.proxy.cut();
        env.proxy.mode = ChaosMode.forward;
      }
      env.proxy.delay = Duration.zero;
      final int cuts = env.proxy.cuts;

      await Future.wait(writes).timeout(const Duration(seconds: 15));
      expect(cuts, greaterThanOrEqualTo(1));

      // Everything that is idempotent is exact: order, last write wins, array transforms, deletes, batches.
      // A write whose acknowledgement was lost is applied again by the emulator (the WriteStream protocol has no
      // write id; the SDKs rely on the backend), so a numeric increment can be counted once more per cut. See
      // reviews/chaos_findings.md (F1).
      final Map<String, Map<String, Object?>> server =
          await env.serverDocs(collection.path);
      // The cache is an estimate until the documents are read from the backend again; then it agrees. (Before the
      // F1b fix it was regularly behind here for the re-sent writes that changed nothing on the backend.)
      final Map<String, Map<String, Object?>> staleCache =
          docsById(await collection.get(Source.cache));
      await collection.get(Source.server);
      final QuerySnapshot<Map<String, Object?>> cached =
          await collection.get(Source.cache);
      expect(docsById(cached), server,
          reason: 'the cache agrees with the backend');
      expect(cached.metadata.hasPendingWrites, isFalse);
      expect(server.keys.toSet(), expectedDocs.keys.toSet());
      if (staleCache.toString() != server.toString()) {
        // ignore: avoid_print
        print('lost acknowledgements: the cache was behind before the server '
            'read: ${staleCache['a']} instead of ${server['a']}');
      }

      final int count = server['log']!['count']! as int;
      // A cut can lose the acknowledgements of all the writes in flight (up to 10 are sent ahead).
      expect(count, inInclusiveRange(20, 20 + 10 * cuts));
      final int n = server['a']!['n']! as int;
      expect(n, greaterThanOrEqualTo(115));
      // Each resent write adds 1, 10 or 100 once more.
      expect(n - 115, lessThanOrEqualTo(115 * cuts));
      final int batch1 = server['batch1']!['v']! as int;
      expect(batch1, inInclusiveRange(2, 2 + cuts));
      // ignore: avoid_print
      print('lost acknowledgements: $cuts cuts, $lostBytes bytes of answers '
          'lost, count=$count (20), n=$n (115), batch1.v=$batch1 (2)');

      server['log']!['count'] = 20;
      server['a']!['n'] = 115;
      server['batch1']!['v'] = 2;
      expect(server, expectedDocs);
    });

    test(
        'after a lost acknowledgement the cache has the re-sent write that '
        'changed nothing (F1b)', () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(uniqueName('stale'));
      final DocumentReference<Map<String, Object?>> doc = collection.doc('a');
      await doc.set(<String, Object?>{'n': 0, 'tag': 'first'});

      // Two writes reach the backend and are applied; their acknowledgements are lost.
      env.proxy.mode = ChaosMode.stallDown;
      final List<Future<void>> writes = <Future<void>>[
        doc.update(<String, Object?>{'n': FieldValue.increment(1)}),
        doc.update(<String, Object?>{'tag': 'second'}),
      ];
      await eventually(
          () async =>
              (await env.serverDocs(collection.path))['a']?['tag'] == 'second',
          reason: 'the backend to apply the writes');
      env.proxy.cut();
      env.proxy.mode = ChaosMode.forward;
      await Future.wait(writes).timeout(const Duration(seconds: 15));

      // Both writes were sent again. The increment was applied a second time (F1). The second write changed
      // nothing on the backend this time, so its acknowledgement carries the unchanged update time of the
      // document. The other SDKs do not apply an acknowledged write to a cached document that already has that
      // version, and keep the old tag in the cache (without a pending write) until the document is read from the
      // backend. The port applies it when the cached document is only the result of earlier acknowledgements
      // (LocalStore._shouldApplyAcknowledgedWrite), so the cache is right at once.
      final Map<String, Object?> server =
          (await env.serverDocs(collection.path))['a']!;
      expect(server, <String, Object?>{'n': 2, 'tag': 'second'});
      final DocumentSnapshot<Map<String, Object?>> cached =
          await doc.get(Source.cache);
      expect(cached.metadata.hasPendingWrites, isFalse);
      expect(cached.data, server);

      // And it stays right after the document is read from the backend.
      expect((await doc.get(Source.server)).data, server);
      expect((await doc.get(Source.cache)).data, server);
    },
        // Over WebChannel a write with an increment is never sent before the answers to the earlier writes arrived
        // (WriteSendAheadGate): while the answer to the first write is held back the second one is not sent, so the
        // backend never has both. The lost acknowledgement itself is covered by the scenarios above.
        skip: webTransportSkipReason(
            'needs two increments in flight at once; the web transport does not send an increment ahead'));

    test('survive a stalled connection that is then cut', () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      await collection.doc('warmup').set(<String, Object?>{});
      await collection.doc('warmup').delete();

      env.proxy.mode = ChaosMode.stall;
      final List<Future<void>> writes = issueWrites(db, collection);
      await pause(1500);
      // The stalled bytes never arrive: the connection dies.
      env.proxy.cut();
      env.proxy.restore();
      await Future.wait(writes).timeout(const Duration(seconds: 20));
      await expectLanded(db, collection);
    });

    test('survive a connection that swallows the traffic for a while',
        () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      await collection.doc('warmup').set(<String, Object?>{});
      await collection.doc('warmup').delete();

      // The requests and the answers on the way are lost, the connections stay open: nothing fails by itself.
      env.proxy.mode = ChaosMode.blackHole;
      final List<Future<void>> writes = issueWrites(db, collection);
      await pause(1500);
      env.proxy.mode = ChaosMode.forward;
      // The client has to notice by itself: the keepalive of gRPC (30 s + 20 s), or the timeout of a WebChannel
      // request (20 s).
      await Future.wait(writes).timeout(const Duration(seconds: 70));
      await expectLanded(db, collection);
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('survive a stalled connection that recovers, and latency', () async {
      final Firestore db = await env.newClient();
      final CollectionReference<Map<String, Object?>> collection =
          await prepare(db);
      env.proxy.delay = const Duration(milliseconds: 30);
      env.proxy.mode = ChaosMode.stall;
      final List<Future<void>> writes = issueWrites(db, collection);
      await pause(1500);
      env.proxy.mode = ChaosMode.forward;
      await Future.wait(writes).timeout(const Duration(seconds: 20));
      env.proxy.delay = Duration.zero;
      await expectLanded(db, collection);
    });
  }, skip: chaosSkipReason);
}
