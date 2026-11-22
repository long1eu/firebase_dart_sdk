// Queries (modifiers in canonical order, streams, get, keepSynced) and the
// I/O members of references (push, writes, transaction, onDisconnect),
// through the official firebase_database API where it reaches them and the
// platform classes where it does not.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/on_disconnect.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart'
    show
        DatabaseEventPlatform,
        EndCursorModifier,
        LimitModifier,
        OrderModifier,
        QueryModifier,
        QueryModifiers,
        StartCursorModifier;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The platform reference of [path] in a new app's instance.
Future<DartReference> platformRef(String path) async {
  final FirebaseApp app = await newApp();
  return DartFirebaseDatabase.forApp(app, null).ref(path) as DartReference;
}

QueryModifiers modifiersOf(List<QueryModifier> modifiers) =>
    QueryModifiers(modifiers);

final Matcher isProgrammerError = anyOf(isArgumentError, isStateError);

void main() {
  registerForTests();

  group('modifiers', () {
    test("startAt(1).orderByChild('x') equals the client query "
        "orderByChild('x').startAt(1)", () async {
      final DartReference ref = await platformRef('a');
      final QueryModifiers modifiers = QueryModifiers(<QueryModifier>[])
          .start(StartCursorModifier.startAt(1, null))
          .order(OrderModifier.orderByChild('x'));
      expect(
        ref.clientQuery(modifiers),
        ref.clientRef.orderByChild('x').startAt(1),
      );
    });

    test('any call order gives orderBy, start, end, limit', () async {
      final DartReference ref = await platformRef('a');
      final fs.Query query = ref.clientQuery(
        modifiersOf(<QueryModifier>[
          LimitModifier.limitToLast(2),
          EndCursorModifier.endAt(9, 'k'),
          StartCursorModifier.startAt(1, 'j'),
          OrderModifier.orderByValue(),
        ]),
      );
      expect(
        query,
        ref.clientRef
            .orderByValue()
            .startAt(1, key: 'j')
            .endAt(9, key: 'k')
            .limitToLast(2),
      );
    });

    test('every modifier maps to its client call', () async {
      final DartReference ref = await platformRef('a');
      final fs.DatabaseReference client = ref.clientRef;
      final Map<List<QueryModifier>, fs.Query> cases =
          <List<QueryModifier>, fs.Query>{
            <QueryModifier>[OrderModifier.orderByKey()]: client.orderByKey(),
            <QueryModifier>[OrderModifier.orderByPriority()]: client
                .orderByPriority(),
            <QueryModifier>[OrderModifier.orderByChild('c/d')]: client
                .orderByChild('c/d'),
            <QueryModifier>[StartCursorModifier.startAfter('s', null)]: client
                .startAfter('s'),
            <QueryModifier>[EndCursorModifier.endBefore(true, null)]: client
                .endBefore(true),
            <QueryModifier>[LimitModifier.limitToFirst(3)]: client.limitToFirst(
              3,
            ),
          };
      cases.forEach((List<QueryModifier> modifiers, fs.Query expected) {
        expect(ref.clientQuery(modifiersOf(modifiers)), expected);
      });
      expect(ref.clientQuery(modifiersOf(<QueryModifier>[])), client);
    });

    test('equalTo arrives as startAt plus endAt', () async {
      final DartReference ref = await platformRef('a');
      final QueryModifiers modifiers = QueryModifiers(<QueryModifier>[])
          .order(OrderModifier.orderByChild('x'))
          .start(StartCursorModifier.startAt(5, 'k'))
          .end(EndCursorModifier.endAt(5, 'k'));
      expect(
        ref.clientQuery(modifiers),
        ref.clientRef.orderByChild('x').startAt(5, key: 'k').endAt(5, key: 'k'),
      );
    });

    test('an invalid combination is a stream error then done', () async {
      final DartReference ref = await platformRef('a');
      final QueryModifiers twoOrders = modifiersOf(<QueryModifier>[
        OrderModifier.orderByKey(),
        OrderModifier.orderByValue(),
      ]);
      final Stream<DatabaseEventPlatform> stream = ref.observe(
        twoOrders,
        DatabaseEventType.value,
      );
      await expectLater(
        stream,
        emitsInOrder(<Object>[emitsError(isProgrammerError), emitsDone]),
      );
    });

    test('an invalid combination fails get with the raw error', () async {
      final DartReference ref = await platformRef('a');
      await expectLater(
        ref.get(
          modifiersOf(<QueryModifier>[
            OrderModifier.orderByKey(),
            StartCursorModifier.startAt('a', 'key-not-allowed'),
          ]),
        ),
        throwsA(isProgrammerError),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('streams', () {
    test('one onValue stream listened twice gives each listener its initial '
        'event', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final Stream<DatabaseEvent> stream = db.ref('a').onValue;
      expect(stream.isBroadcast, isFalse);
      final List<Object?> first = <Object?>[];
      final List<Object?> second = <Object?>[];
      final StreamSubscription<DatabaseEvent> one = stream.listen(
        (DatabaseEvent e) => first.add(e.snapshot.value),
      );
      await settle();
      server.answerListen('a', 1);
      await settle();
      final StreamSubscription<DatabaseEvent> two = stream.listen(
        (DatabaseEvent e) => second.add(e.snapshot.value),
      );
      await settle();
      expect(first, <Object?>[1]);
      expect(second, <Object?>[1]);
      expect(server.requests.where((String r) => r == 'q /a'), hasLength(1));
      await one.cancel();
      await two.cancel();
    });

    test('cancelling the last listener removes the server listen', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final StreamSubscription<DatabaseEvent> sub = db
          .ref('a')
          .onValue
          .listen(null);
      await settle();
      server.answerListen('a', 1);
      await settle();
      await sub.cancel();
      await settle();
      expect(server.requests, containsAllInOrder(<String>['q /a', 'n /a']));
    });

    test('every event type reaches its stream', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference ref = db.ref('list');
      final List<String> log = <String>[];
      final List<StreamSubscription<DatabaseEvent>> subs =
          <StreamSubscription<DatabaseEvent>>[
            ref.onValue.listen((DatabaseEvent e) => log.add('V')),
            ref.onChildAdded.listen(
              (DatabaseEvent e) => log.add('A:${e.snapshot.key}'),
            ),
            ref.onChildChanged.listen(
              (DatabaseEvent e) => log.add('C:${e.snapshot.key}'),
            ),
            ref.onChildRemoved.listen(
              (DatabaseEvent e) => log.add('R:${e.snapshot.key}'),
            ),
            ref.orderByValue().onChildMoved.listen(
              (DatabaseEvent e) => log.add('M:${e.snapshot.key}'),
            ),
          ];
      await settle();
      server.answerListen('list', <String, Object?>{'a': 1, 'b': 2});
      await settle();
      log.clear();
      server.push('list', <String, Object?>{'b': 0, 'c': 3});
      await settle();
      expect(log, containsAll(<String>['R:a', 'A:c', 'C:b', 'M:b', 'V']));
      for (final StreamSubscription<DatabaseEvent> sub in subs) {
        await sub.cancel();
      }
    });

    test('server cancel is permission-denied then done', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final Stream<DatabaseEvent> stream = db.ref('a').onValue;
      final Future<void> expectation = expectLater(
        stream,
        emitsInOrder(<Object>[
          emits(isA<DatabaseEvent>()),
          emitsError(isDatabaseCode('permission-denied')),
          emitsDone,
        ]),
      );
      await settle();
      server.answerListen('a', 1);
      await settle();
      server.cancelListen('a', 'permission_denied');
      await expectation;
    });
  });

  group('get', () {
    test('get answers with the server value of the query', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final Future<DataSnapshot> get = db.ref('a').get();
      await settle();
      expect(server.requests, contains('g /a'));
      server.answerGet('a', <String, Object?>{'b': 1});
      final DataSnapshot snapshot = await get;
      expect(snapshot.value, <Object?, Object?>{'b': 1});
      expect(snapshot.ref.path, '/a');
    });

    test('a refused get is permission-denied of firebase_core', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final Future<DataSnapshot> get = db.ref('a').get();
      await settle();
      server.failGet('a', 'permission_denied');
      await expectLater(get, throwsDatabaseCode('permission-denied'));
    });
  });

  group('keepSynced', () {
    test('keepSynced is a flag per query, not a counter', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference ref = db.ref('a');
      await ref.keepSynced(true);
      await ref.keepSynced(true);
      await settle();
      expect(server.requests.where((String r) => r == 'q /a'), hasLength(1));
      await ref.keepSynced(false);
      await settle();
      expect(server.requests.last, 'n /a');
    });

    test('keepSynced of an invalid query fails with the raw error', () async {
      final DartReference ref = await platformRef('a');
      await expectLater(
        ref.keepSynced(
          modifiersOf(<QueryModifier>[LimitModifier.limitToFirst(0)]),
          true,
        ),
        throwsA(isProgrammerError),
      );
    });
  });

  group('reference I/O', () {
    test('push makes a local key under the location, no write', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference child = db.ref('list').push();
      expect(child.key, hasLength(20));
      expect(child.parent!.path, '/list');
      expect(createdClients, hasLength(1));
      await settle();
      expect(server.requests.where((String r) => r.startsWith('p ')), isEmpty);
    });

    test('set writes the transformed value', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference ref = db.ref('a');
      final Future<void> write = ref.set(<Object?, Object?>{1: 'one'});
      final DatabaseEvent local = await ref.once();
      expect(local.snapshot.value, <Object?, Object?>{'1': 'one'});
      expect(server.requests, contains('p /a'));
      server.ackLastWrite();
      await write;
    });

    test('setWithPriority writes the value and its priority', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference ref = db.ref('a');
      final Future<void> write = ref.setWithPriority('v', 7);
      final DataSnapshot local = (await ref.once()).snapshot;
      expect(local.value, 'v');
      expect(local.priority, 7);
      server.ackLastWrite();
      await write;
    });

    test('update merges the transformed values', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference ref = db.ref('a');
      final Future<void> write = ref.update(<String, Object?>{
        'b/c': <Object?, Object?>{2: 'two'},
      });
      await settle();
      expect(server.requests, contains('m /a'));
      server.ackLastWrite();
      await write;
    });

    test('setPriority sets the priority of the location', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final DatabaseReference ref = db.ref('a');
      final Future<void> write = ref.set(1);
      final Future<void> priority = ref.setPriority('p');
      final DataSnapshot local = (await ref.once()).snapshot;
      expect(local.priority, 'p');
      server.ackLastWrite();
      server.ackLastWrite();
      await write;
      await priority;
    });

    test('remove of the platform reference removes the value', () async {
      final DartReference ref = await platformRef('a');
      final Future<void> remove = ref.remove();
      await settle();
      expect(server.requests, contains('p /a'));
      server.ackLastWrite();
      await remove;
    });

    test('a rejected write is permission-denied of firebase_core', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final Future<void> write = db.ref('a').set(1);
      await settle();
      server.failLastWrite('permission_denied');
      await expectLater(write, throwsDatabaseCode('permission-denied'));
    });

    test('runTransaction commits the value the handler returns', () async {
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(
        app: await newApp(),
      );
      final Future<TransactionResult> result = db
          .ref('n')
          .runTransaction((Object? current) => Transaction.success(1));
      await settle();
      server.ackLastWrite();
      final TransactionResult done = await result;
      expect(done.committed, isTrue);
      expect(done.snapshot.value, 1);
    });

    test('onDisconnect is of this reference and creates no client', () async {
      final DartReference ref = await platformRef('a/b');
      final DartOnDisconnect onDisconnect = ref.onDisconnect();
      expect(onDisconnect.ref.path, '/a/b');
      expect(createdClients, isEmpty);
    });
  });
}
