// Lazy start (parity row inst.lazyStart): a database connects on its first operation that needs
// the server, or on goOnline, never at construction (JS api/Database.ts `_repo`).

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// Runs [body] on a new database over a new server; time is fake and never moves by itself.
void _withDatabase(
  void Function(FirebaseDatabase db, FakeDatabaseServer server, FakeTime time)
  body,
) {
  fakeTime((FakeTime time) {
    final FakeDatabaseServer server = FakeDatabaseServer();
    body(databaseWithFakeServer(newTestApp(), server), server, time);
  });
}

/// Swallows the result of [future]: the tests look at the connection only.
void _ignore(Future<Object?> future) =>
    unawaited(future.then((_) {}, onError: (Object _) {}));

void main() {
  test(
    'constructed, used without the server, and closed: no connection attempt',
    () {
      _withDatabase((
        FirebaseDatabase db,
        FakeDatabaseServer server,
        FakeTime time,
      ) {
        final DatabaseReference ref = db.ref('a/b');
        ref.orderByChild('n').limitToFirst(2).startAt(1);
        ref.child('c').push();
        expect(db.databaseUrl, isNotNull);
        expect(db.app, isNotNull);
        expect(db.isConnected, isFalse);
        time.elapse(const Duration(minutes: 5));
        _ignore(db.close());
        time.elapse(const Duration(minutes: 5));
        expect(server.connectionAttempts, 0);
        expect(server.requests, isEmpty);
      });
    },
  );

  final Map<String, void Function(FirebaseDatabase db)> firstUses =
      <String, void Function(FirebaseDatabase db)>{
        'get': (FirebaseDatabase db) => _ignore(db.ref('a').get()),
        'onValue listen': (FirebaseDatabase db) =>
            db.ref('a').onValue.listen((_) {}, onError: (Object _) {}),
        'query listen': (FirebaseDatabase db) => db
            .ref('a')
            .orderByChild('n')
            .limitToFirst(1)
            .onChildAdded
            .listen((_) {}, onError: (Object _) {}),
        'set': (FirebaseDatabase db) => _ignore(db.ref('a').set(1)),
        'update': (FirebaseDatabase db) =>
            _ignore(db.ref('a').update(<String, Object?>{'b': 1})),
        'remove': (FirebaseDatabase db) => _ignore(db.ref('a').remove()),
        'runTransaction': (FirebaseDatabase db) => _ignore(
          db.ref('a').runTransaction((Object? v) => Transaction.success(1)),
        ),
        'onDisconnect.set': (FirebaseDatabase db) =>
            _ignore(db.ref('a').onDisconnect.set(1)),
        'onDisconnect.cancel': (FirebaseDatabase db) =>
            _ignore(db.ref('a').onDisconnect.cancel()),
        'keepSynced(true)': (FirebaseDatabase db) =>
            _ignore(db.ref('a').keepSynced(true)),
        'onConnected': (FirebaseDatabase db) =>
            db.onConnected.listen((_) {}, onError: (Object _) {}),
        '.info/serverTimeOffset listen': (FirebaseDatabase db) => db
            .ref('.info/serverTimeOffset')
            .onValue
            .listen((_) {}, onError: (Object _) {}),
        'goOnline': (FirebaseDatabase db) => db.goOnline(),
      };

  for (final MapEntry<String, void Function(FirebaseDatabase db)> use
      in firstUses.entries) {
    test('${use.key} as the first operation opens exactly one connection', () {
      _withDatabase((
        FirebaseDatabase db,
        FakeDatabaseServer server,
        FakeTime time,
      ) {
        time.elapse(const Duration(minutes: 1));
        expect(server.connectionAttempts, 0);
        use.value(db);
        time.elapse(const Duration(minutes: 1));
        expect(server.connectionAttempts, 1);
        expect(db.isConnected, isTrue);
        _ignore(db.close());
        time.elapse(Duration.zero);
      });
    });
  }

  test('keepSynced(false) as the first operation does not connect', () {
    _withDatabase((
      FirebaseDatabase db,
      FakeDatabaseServer server,
      FakeTime time,
    ) {
      _ignore(db.ref('a').keepSynced(false));
      time.elapse(const Duration(minutes: 1));
      expect(server.connectionAttempts, 0);
    });
  });

  test(
    'goOffline before the first operation is kept: the operation does not connect, goOnline '
    'does',
    () {
      _withDatabase((
        FirebaseDatabase db,
        FakeDatabaseServer server,
        FakeTime time,
      ) {
        db.goOffline();
        _ignore(db.ref('a').set(1));
        db.ref('b').onValue.listen((_) {}, onError: (Object _) {});
        time.elapse(const Duration(minutes: 1));
        expect(server.connectionAttempts, 0);
        expect(server.requests, isEmpty);

        db.goOnline();
        time.elapse(const Duration(minutes: 1));
        expect(server.connectionAttempts, 1);
        expect(server.requests, containsAll(<String>['p /a', 'q /b']));
      });
    },
  );

  test(
    'with persistence the store opens at construction; the connection waits for the first '
    'operation',
    () {
      fakeTime((FakeTime time) {
        final FakeDatabaseServer server = FakeDatabaseServer();
        final FirebaseDatabase db = databaseWithFakeServer(
          newTestApp(),
          server,
          persistence: fakePersistence(),
        );
        time.elapse(const Duration(minutes: 1));
        expect(db.persistenceEnabled, isTrue);
        expect(server.connectionAttempts, 0);
        _ignore(db.ref('a').get());
        time.elapse(const Duration(minutes: 1));
        expect(server.connectionAttempts, 1);
      });
    },
  );
}
