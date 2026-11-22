// The three FlutterFire quirks this package fixes on purpose, one pin each
// (plan 7.1 to 7.3). A change that brings a quirk back fails here.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart'
    show OrderModifier, QueryModifier, QueryModifiers, StartCursorModifier;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  registerForTests();

  test('children keep their priority', () async {
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(
      app: await newApp(),
    );
    final Future<DataSnapshot> get = db.ref('list').get();
    await settle();
    server.answerGet('list', <String, Object?>{
      'a': <String, Object?>{'.value': 1, '.priority': 20},
      'b': <String, Object?>{'.value': 2, '.priority': 'p'},
      'c': 3,
    });
    final DataSnapshot snapshot = await get;
    expect(snapshot.children.map((DataSnapshot c) => c.priority), <Object?>[
      20,
      'p',
      null,
    ]);
    expect(snapshot.child('a').priority, 20);
  });

  test('child event snapshot ref is the child', () async {
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(
      app: await newApp(),
    );
    final List<DatabaseEvent> events = <DatabaseEvent>[];
    final StreamSubscription<DatabaseEvent> sub = db
        .ref('list')
        .orderByKey()
        .onChildAdded
        .listen(events.add);
    await settle();
    server.answerListen('list', <String, Object?>{'a': 1, 'b': 2});
    await settle();
    expect(events.map((DatabaseEvent e) => e.snapshot.ref.path), <String>[
      '/list/a',
      '/list/b',
    ]);
    expect(events.map((DatabaseEvent e) => e.snapshot.ref.key), <String>[
      'a',
      'b',
    ]);
    await sub.cancel();
  });

  test('startAt(null) is a null cursor, not the string null', () async {
    final FirebaseApp app = await newApp();
    final DartReference ref =
        DartFirebaseDatabase.forApp(app, null).ref('a') as DartReference;
    final QueryModifiers modifiers = QueryModifiers(<QueryModifier>[])
        .order(OrderModifier.orderByChild('x'))
        .start(StartCursorModifier.startAt(null, null));
    final fs.Query query = ref.clientQuery(modifiers);
    final fs.DatabaseReference client = ref.clientRef;
    expect(query, client.orderByChild('x').startAt(null));
    expect(query, isNot(client.orderByChild('x').startAt('null')));
    expect(query, isNot(client.orderByChild('x')));
  });
}
