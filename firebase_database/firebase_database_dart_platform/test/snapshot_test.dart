// Snapshots and events through the official firebase_database API, and the
// location members of references (path, key, parent, root, child), which
// create no client.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/data_snapshot.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart'
    show DatabaseEventPlatform, QueryModifier, QueryModifiers;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<FirebaseDatabase> newDatabase() async =>
    FirebaseDatabase.instanceFor(app: await newApp());

/// `ref.get()` answered by the server with [value].
Future<DataSnapshot> serverGet(DatabaseReference ref, Object? value) async {
  final Future<DataSnapshot> future = ref.get();
  await settle();
  server.answerGet(ref.path.substring(1), value);
  return future;
}

void main() {
  registerForTests();

  group('event types', () {
    test('every event type maps to the same type and back', () {
      for (final DatabaseEventType type in DatabaseEventType.values) {
        final fs.DatabaseEventType client = clientEventType(type);
        expect(client.name, type.name);
        expect(flutterFireEventType(client), type);
      }
    });
  });

  group('snapshots', () {
    test('key, exists, value and priority are the client snapshot', () async {
      final FirebaseDatabase db = await newDatabase();
      final DataSnapshot snapshot = await serverGet(
        db.ref('users/ada'),
        <String, Object?>{'.priority': 3, 'name': 'Ada', 'age': 36},
      );
      expect(snapshot.key, 'ada');
      expect(snapshot.exists, isTrue);
      expect(snapshot.value, <Object?, Object?>{'age': 36, 'name': 'Ada'});
      expect(snapshot.priority, 3);
    });

    test('a missing location does not exist and has a null value', () async {
      final FirebaseDatabase db = await newDatabase();
      final DataSnapshot snapshot = await serverGet(db.ref('none'), null);
      expect(snapshot.exists, isFalse);
      expect(snapshot.value, isNull);
      expect(snapshot.key, 'none');
    });

    test('value is mutable and memoised per snapshot', () async {
      final FirebaseDatabase db = await newDatabase();
      final DataSnapshot snapshot = await serverGet(
        db.ref('a'),
        <String, Object?>{
          'x': 1,
          'list': <Object?>[1, 2],
        },
      );
      final Object? first = snapshot.value;
      expect(first, isA<Map<Object?, Object?>>());
      final Map<Object?, Object?> map = first! as Map<Object?, Object?>;
      map['id'] = snapshot.key;
      (map['list']! as List<Object?>).add(3);
      expect(snapshot.value, same(first));
      expect(snapshot.value, <Object?, Object?>{
        'id': 'a',
        'list': <Object?>[1, 2, 3],
        'x': 1,
      });
    });

    test('two listeners of one stream get distinct values', () async {
      final FirebaseDatabase db = await newDatabase();
      final Stream<DatabaseEvent> stream = db.ref('a').onValue;
      final List<Object?> first = <Object?>[];
      final List<Object?> second = <Object?>[];
      final StreamSubscription<DatabaseEvent> one = stream.listen(
        (DatabaseEvent e) => first.add(e.snapshot.value),
      );
      final StreamSubscription<DatabaseEvent> two = stream.listen(
        (DatabaseEvent e) => second.add(e.snapshot.value),
      );
      await settle();
      server.answerListen('a', <String, Object?>{'x': 1});
      await settle();
      expect(first.single, <Object?, Object?>{'x': 1});
      expect(second.single, <Object?, Object?>{'x': 1});
      expect(first.single, isNot(same(second.single)));
      (first.single! as Map<Object?, Object?>)['x'] = 2;
      expect(second.single, <Object?, Object?>{'x': 1});
      await one.cancel();
      await two.cancel();
    });

    test('hasChild reads a path of several keys', () async {
      final FirebaseDatabase db = await newDatabase();
      final DataSnapshot snapshot = await serverGet(
        db.ref('a'),
        <String, Object?>{
          'b': <String, Object?>{'c': 1},
        },
      );
      expect(snapshot.hasChild('b'), isTrue);
      expect(snapshot.hasChild('b/c'), isTrue);
      expect(snapshot.hasChild('b/d'), isFalse);
      expect(snapshot.hasChild('z'), isFalse);
    });

    test('child takes several keys and list indices, with its ref', () async {
      final FirebaseDatabase db = await newDatabase();
      final DataSnapshot snapshot = await serverGet(
        db.ref('a'),
        <String, Object?>{
          'b': <Object?>['zero', 'one'],
        },
      );
      final DataSnapshot child = snapshot.child('b/1');
      expect(child.value, 'one');
      expect(child.key, '1');
      expect(child.ref.path, '/a/b/1');
      expect(snapshot.child('missing').exists, isFalse);
    });

    test('children are lazy, in index order, each with its ref', () async {
      final FirebaseDatabase db = await newDatabase();
      final DataSnapshot snapshot = await serverGet(
        db.ref('scores'),
        <String, Object?>{'b': 2, 'a': 1, '10': 3, '9': 4},
      );
      final List<DataSnapshot> children = snapshot.children.toList();
      expect(children.map((DataSnapshot c) => c.key), <String>[
        '9',
        '10',
        'a',
        'b',
      ]);
      expect(children.map((DataSnapshot c) => c.value), <Object?>[4, 3, 1, 2]);
      expect(children.map((DataSnapshot c) => c.ref.path), <String>[
        '/scores/9',
        '/scores/10',
        '/scores/a',
        '/scores/b',
      ]);
    });

    test('children of an ordered query follow that order', () async {
      final FirebaseDatabase db = await newDatabase();
      final Future<DatabaseEvent> event = db
          .ref('scores')
          .orderByValue()
          .once();
      await settle();
      server.answerListen('scores', <String, Object?>{'a': 3, 'b': 1, 'c': 2});
      final DataSnapshot snapshot = (await event).snapshot;
      expect(snapshot.children.map((DataSnapshot c) => c.key), <String>[
        'b',
        'c',
        'a',
      ]);
    });
  });

  group('events', () {
    test('a child event carries its type and previous child key', () async {
      final FirebaseDatabase db = await newDatabase();
      final List<DatabaseEvent> events = <DatabaseEvent>[];
      final StreamSubscription<DatabaseEvent> sub = db
          .ref('list')
          .onChildAdded
          .listen(events.add);
      await settle();
      server.answerListen('list', <String, Object?>{'a': 1, 'b': 2});
      await settle();
      expect(events.map((DatabaseEvent e) => e.type), <DatabaseEventType>[
        DatabaseEventType.childAdded,
        DatabaseEventType.childAdded,
      ]);
      expect(events.map((DatabaseEvent e) => e.previousChildKey), <String?>[
        null,
        'a',
      ]);
      expect(events.map((DatabaseEvent e) => e.snapshot.value), <Object?>[
        1,
        2,
      ]);
      await sub.cancel();
    });

    test('a value event has type value and no previous key', () async {
      final FirebaseDatabase db = await newDatabase();
      final Future<DatabaseEvent> once = db.ref('a').once();
      await settle();
      server.answerListen('a', 5);
      final DatabaseEvent event = await once;
      expect(event.type, DatabaseEventType.value);
      expect(event.previousChildKey, isNull);
      expect(event.snapshot.value, 5);
      expect(event.snapshot.ref.path, '/a');
    });

    test('an event snapshot is made once per event', () async {
      final FirebaseApp app = await newApp();
      final DartFirebaseDatabase platform = DartFirebaseDatabase.forApp(
        app,
        null,
      );
      final Future<DatabaseEventPlatform> first = platform
          .ref('a')
          .onValue(QueryModifiers(<QueryModifier>[]))
          .first;
      await settle();
      server.answerListen('a', <String, Object?>{'x': 1});
      final DatabaseEventPlatform event = await first;
      expect(event, isA<DartDatabaseEvent>());
      expect(event.snapshot, same(event.snapshot));
      expect(event.snapshot.value, same(event.snapshot.value));
    });
  });

  group('reference locations', () {
    test('path has a leading slash and is / at the root', () async {
      final FirebaseDatabase db = await newDatabase();
      expect(db.ref().path, '/');
      expect(db.ref('').path, '/');
      expect(db.ref('a/b').path, '/a/b');
      expect(db.ref('/a//b/').path, '/a/b');
      expect(createdClients, isEmpty);
    });

    test('key is the last key and null at the root', () async {
      final FirebaseDatabase db = await newDatabase();
      expect(db.ref().key, isNull);
      expect(db.ref('a/b').key, 'b');
      expect(createdClients, isEmpty);
    });

    test('parent is one key up and null at the root', () async {
      final FirebaseDatabase db = await newDatabase();
      expect(db.ref('a/b').parent!.path, '/a');
      expect(db.ref('a').parent!.path, '/');
      expect(db.ref().parent, isNull);
      expect(createdClients, isEmpty);
    });

    test('root is the root from any depth', () async {
      final FirebaseDatabase db = await newDatabase();
      expect(db.ref('a/b/c').root.path, '/');
      expect(db.ref('a/b/c').root.key, isNull);
      expect(createdClients, isEmpty);
    });

    test('child takes several keys', () async {
      final FirebaseDatabase db = await newDatabase();
      final DatabaseReference child = db.ref('a').child('b/c');
      expect(child.path, '/a/b/c');
      expect(child.key, 'c');
      expect(child.parent!.path, '/a/b');
      expect(createdClients, isEmpty);
    });

    test('an invalid key fails at the first I/O, not at child', () async {
      final FirebaseDatabase db = await newDatabase();
      final DatabaseReference bad = db.ref('a').child('b.c');
      expect(bad.key, 'b.c');
      expect(createdClients, isEmpty);
      await expectLater(bad.set(1), throwsArgumentError);
    });

    test('the ref of a query is its location', () async {
      final FirebaseDatabase db = await newDatabase();
      expect(db.ref('a/b').orderByKey().limitToFirst(1).ref.path, '/a/b');
      expect(createdClients, isEmpty);
    });
  });
}
