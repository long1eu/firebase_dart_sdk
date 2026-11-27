// Streams of the official firebase_database API end with done and no error when the app is
// deleted or the client is closed: a listener without onError survives it. A Future still fails.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The streams under test, each listened to without onError.
final Map<String, Stream<Object?> Function(FirebaseDatabase db)> _streams =
    <String, Stream<Object?> Function(FirebaseDatabase db)>{
      '.info/connected': (FirebaseDatabase db) =>
          db.ref('.info/connected').onValue,
      'onValue': (FirebaseDatabase db) => db.ref('a').onValue,
      'onChildAdded': (FirebaseDatabase db) => db.ref('a').onChildAdded,
      'onChildChanged': (FirebaseDatabase db) => db.ref('a').onChildChanged,
      'onChildMoved': (FirebaseDatabase db) => db.ref('a').onChildMoved,
      'onChildRemoved': (FirebaseDatabase db) => db.ref('a').onChildRemoved,
      'query onValue': (FirebaseDatabase db) =>
          db.ref('q').orderByChild('n').limitToFirst(2).onValue,
    };

/// Listens to every stream of [_streams] on [db] without onError, in a zone that records
/// uncaught errors in [uncaught]; logs `name:event` and `name:done` in [log].
Future<void> _listenAll(
  FirebaseDatabase db,
  List<String> log,
  List<Object> uncaught,
) async {
  runZonedGuarded(() {
    for (final MapEntry<String, Stream<Object?> Function(FirebaseDatabase)> e
        in _streams.entries) {
      e
          .value(db)
          .listen(
            (Object? _) => log.add('${e.key}:event'),
            onDone: () => log.add('${e.key}:done'),
          );
    }
  }, (Object error, StackTrace _) => uncaught.add(error));
  await settle();
  // One listen answered: the default listen at `a`, which every `a` stream shares.
  server.answerListen('a', <String, Object?>{'x': 1});
  await settle();
  expect(log, contains('onValue:event'));
}

void _expectAllDone(List<String> log, List<Object> uncaught) {
  expect(uncaught, isEmpty);
  for (final String name in _streams.keys) {
    expect(
      log.where((String e) => e == '$name:done'),
      hasLength(1),
      reason: name,
    );
  }
}

void main() {
  registerForTests();

  test('app deleted: every stream ends with done, no uncaught error', () async {
    final FirebaseApp app = await newApp();
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app);
    final List<String> log = <String>[];
    final List<Object> uncaught = <Object>[];
    await _listenAll(db, log, uncaught);

    await app.delete();
    await settle();
    _expectAllDone(log, uncaught);
  });

  test(
    'client closed: every stream ends with done, no uncaught error',
    () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app);
      final List<String> log = <String>[];
      final List<Object> uncaught = <Object>[];
      await _listenAll(db, log, uncaught);

      await FirebaseDatabaseDart.clientFor(app).close();
      await settle();
      _expectAllDone(log, uncaught);
    },
  );

  test('a pending get still fails with database-closed at close', () async {
    final FirebaseApp app = await newApp();
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app);
    final Future<DataSnapshot> get = db.ref('g').get();
    await settle();
    final Future<void> expectation = expectLater(
      get,
      throwsDatabaseCode('database-closed'),
    );
    await FirebaseDatabaseDart.clientFor(app).close();
    await expectation;
  });

  test(
    'once() pending at close fails with the StateError of Stream.first',
    () async {
      // FlutterFire's Query.once() is `onValue.first` over the platform stream, so a stream that
      // ends with done gives Stream.first's "No element" StateError, not database-closed.
      final FirebaseApp app = await newApp();
      final FirebaseDatabase db = FirebaseDatabase.instanceFor(app: app);
      final Future<DatabaseEvent> once = db.ref('o').once();
      await settle();
      final Future<void> expectation = expectLater(once, throwsStateError);
      await FirebaseDatabaseDart.clientFor(app).close();
      await expectation;
    },
  );
}
