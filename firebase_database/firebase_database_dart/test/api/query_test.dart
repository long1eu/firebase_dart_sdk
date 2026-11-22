// Query building and query validation (contract C5, C28, C36; JS api/Reference_impl.ts
// validateNoPreviousOrderByCall, validateQueryEndpoints, validateLimit and the constraint classes).

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  void withDb(void Function(FirebaseDatabase db) body) {
    fakeTime((FakeTime time) {
      body(databaseWithFakeServer(newTestApp(), FakeDatabaseServer()));
    });
  }

  Map<String, Object?> wire(Query q) => q.spec.params.toWireObject();

  group('validation', () {
    final Map<String, Query Function(DatabaseReference r)> stateErrors =
        <String, Query Function(DatabaseReference r)>{
          'orderByKey twice': (DatabaseReference r) =>
              r.orderByKey().orderByKey(),
          'orderByValue after orderByChild': (DatabaseReference r) =>
              r.orderByChild('a').orderByValue(),
          'orderByPriority after orderByKey': (DatabaseReference r) =>
              r.orderByKey().orderByPriority(),
          'orderByChild after orderByPriority': (DatabaseReference r) =>
              r.orderByPriority().orderByChild('a'),
          'orderByKey after a limit and orderByValue': (DatabaseReference r) =>
              r.orderByValue().limitToFirst(1).orderByKey(),
          'startAt twice': (DatabaseReference r) => r.startAt(1).startAt(2),
          'startAfter after startAt': (DatabaseReference r) =>
              r.startAt(1).startAfter(2),
          'endAt twice': (DatabaseReference r) => r.endAt(1).endAt(2),
          'endBefore after endAt': (DatabaseReference r) =>
              r.endAt(1).endBefore(2),
          'equalTo after startAt': (DatabaseReference r) =>
              r.startAt(1).equalTo(2),
          'equalTo after endAt': (DatabaseReference r) => r.endAt(1).equalTo(2),
          'startAt after equalTo': (DatabaseReference r) =>
              r.equalTo(1).startAt(2),
          'endAt after equalTo': (DatabaseReference r) => r.equalTo(1).endAt(2),
          'limitToFirst twice': (DatabaseReference r) =>
              r.limitToFirst(1).limitToFirst(2),
          'limitToLast after limitToFirst': (DatabaseReference r) =>
              r.limitToFirst(1).limitToLast(2),
        };
    for (final MapEntry<String, Query Function(DatabaseReference)> entry
        in stateErrors.entries) {
      test('${entry.key} throws a StateError', () {
        withDb((FirebaseDatabase db) {
          expect(() => entry.value(db.ref('q')), throwsStateError);
        });
      });
    }

    final Map<String, Query Function(DatabaseReference r)> argumentErrors =
        <String, Query Function(DatabaseReference r)>{
          r'orderByChild("$key")': (DatabaseReference r) =>
              r.orderByChild(r'$key'),
          r'orderByChild("$priority")': (DatabaseReference r) =>
              r.orderByChild(r'$priority'),
          r'orderByChild("$value")': (DatabaseReference r) =>
              r.orderByChild(r'$value'),
          'orderByChild("")': (DatabaseReference r) => r.orderByChild(''),
          'orderByChild("/")': (DatabaseReference r) => r.orderByChild('/'),
          'orderByChild with an invalid path': (DatabaseReference r) =>
              r.orderByChild('a.b'),
          'limitToFirst(0)': (DatabaseReference r) => r.limitToFirst(0),
          'limitToLast(-1)': (DatabaseReference r) => r.limitToLast(-1),
          'an invalid key argument': (DatabaseReference r) =>
              r.startAt(1, key: 'a.b'),
          'an empty key argument': (DatabaseReference r) => r.endAt(1, key: ''),
          'a NaN bound': (DatabaseReference r) => r.startAt(double.nan),
          'orderByKey with a number bound': (DatabaseReference r) =>
              r.orderByKey().startAt(1),
          'orderByKey with a null bound': (DatabaseReference r) =>
              r.orderByKey().endAt(null),
          'orderByKey with a key argument': (DatabaseReference r) =>
              r.orderByKey().startAt('a', key: 'b'),
          'orderByKey equalTo with a key argument': (DatabaseReference r) =>
              r.orderByKey().equalTo('a', key: 'b'),
          'orderByKey after a number bound': (DatabaseReference r) =>
              r.startAt(1).orderByKey(),
          'orderByKey after a bound with a key': (DatabaseReference r) =>
              r.endAt('a', key: 'b').orderByKey(),
          'orderByPriority with a bool bound': (DatabaseReference r) =>
              r.orderByPriority().startAt(true),
          'default order with a bool bound': (DatabaseReference r) =>
              r.endBefore(false),
          'orderByValue with an object bound': (DatabaseReference r) =>
              r.orderByValue().startAt(<String, Object?>{'a': 1}),
          'orderByChild with an object equalTo': (DatabaseReference r) =>
              r.orderByChild('x').equalTo(<String, Object?>{'a': 1}),
          'orderByValue after an object bound': (DatabaseReference r) =>
              r.startAt(<String, Object?>{'a': 1}).orderByValue(),
        };
    for (final MapEntry<String, Query Function(DatabaseReference)> entry
        in argumentErrors.entries) {
      test('${entry.key} throws an ArgumentError', () {
        withDb((FirebaseDatabase db) {
          expect(() => entry.value(db.ref('q')), throwsArgumentError);
        });
      });
    }

    test('invalid query throws in release mode', () {
      // The checks are not asserts: they run whatever the mode.
      withDb((FirebaseDatabase db) {
        expect(() => db.ref('q').orderByKey().orderByValue(), throwsStateError);
        expect(() => db.ref('q').limitToFirst(0), throwsArgumentError);
      });
    });

    test('valid combinations build', () {
      withDb((FirebaseDatabase db) {
        final DatabaseReference r = db.ref('q');
        r.orderByKey().startAt('a').endAt('z').limitToFirst(3);
        r.orderByKey().startAfter('a').endBefore('z');
        r.orderByKey().equalTo('a');
        r.orderByValue().startAt(1, key: 'k').endAt(9).limitToLast(2);
        r.orderByChild('a/b').equalTo('x', key: 'k');
        r.orderByPriority().startAt(null).endAt('p');
        r.startAt(1).endAt(2).limitToFirst(1).orderByValue();
        r.limitToLast(1).orderByChild('a');
      });
    });
  });

  group('building', () {
    test('startAt(null) is a bound', () {
      withDb((FirebaseDatabase db) {
        final Query q = db.ref('q').startAt(null);
        expect(q.spec.params.hasStart, isTrue);
        expect(wire(q), <String, Object?>{'sp': null, 'sin': true});
        expect(
          wire(db.ref('q').orderByPriority().startAt(null, key: 'a')),
          <String, Object?>{'sp': null, 'sn': 'a', 'sin': true},
        );
      });
    });

    test('orderBy and limits reach the wire object', () {
      withDb((FirebaseDatabase db) {
        expect(
          wire(db.ref('q').orderByChild('b').startAt(1).limitToFirst(2)),
          <String, Object?>{'sp': 1, 'sin': true, 'l': 2, 'vf': 'l', 'i': 'b'},
        );
        expect(wire(db.ref('q').orderByKey()), <String, Object?>{'i': '.key'});
        expect(
          wire(db.ref('q').orderByValue().limitToLast(3)),
          <String, Object?>{'l': 3, 'vf': 'r', 'i': '.value'},
        );
        expect(wire(db.ref('q').orderByPriority()), isEmpty);
        expect(
          wire(db.ref('q').orderByValue().equalTo(5, key: 'k')),
          <String, Object?>{
            'sp': 5,
            'sn': 'k',
            'sin': true,
            'ep': 5,
            'en': 'k',
            'ein': true,
            'i': '.value',
          },
        );
      });
    });

    test('a user -0.0 or 5.0 bound is normalised', () {
      withDb((FirebaseDatabase db) {
        expect(wire(db.ref('q').orderByValue().startAt(-0.0))['sp'], 0);
        final Object? five = wire(
          db.ref('q').orderByValue().startAt(5.0),
        )['sp'];
        expect(five, 5);
        expect(five, isA<int>());
      });
    });

    test('a query is immutable and equal by database, path and params', () {
      withDb((FirebaseDatabase db) {
        final DatabaseReference r = db.ref('q');
        final Query a = r.orderByValue();
        expect(r.spec.params.isDefault, isTrue);
        expect(a, r.orderByValue());
        expect(a.hashCode, r.orderByValue().hashCode);
        expect(a, isNot(r));
        expect(r, db.ref('/q'));
        expect(a.limitToFirst(1), isNot(a));
      });
    });

    test('ref, path and url (C28)', () {
      withDb((FirebaseDatabase db) {
        final Query q = db.ref('a b/c').orderByKey().limitToFirst(1);
        expect(q.ref, db.ref('a b/c'));
        expect(q.path, '/a b/c');
        expect(
          q.url.toString(),
          'https://test-project-default-rtdb.firebaseio.com/a%20b/c',
        );
        expect(
          db.ref().url.toString(),
          'https://test-project-default-rtdb.firebaseio.com/',
        );
        expect(q.database, same(db));
      });
    });

    test('reference navigation', () {
      withDb((FirebaseDatabase db) {
        final DatabaseReference r = db.ref('a/b');
        expect(r.key, 'b');
        expect(r.parent, db.ref('a'));
        expect(r.parent!.parent, db.ref());
        expect(db.ref().parent, isNull);
        expect(db.ref().key, isNull);
        expect(r.root, db.ref());
        expect(r.child('c/d').path, '/a/b/c/d');
      });
    });

    test('push makes ordered unique keys without a request', () {
      withDb((FirebaseDatabase db) {
        final DatabaseReference a = db.ref('m').push();
        final DatabaseReference b = db.ref('m').push();
        expect(a.parent, db.ref('m'));
        expect(a.key, hasLength(20));
        expect(a.key!.compareTo(b.key!), lessThan(0));
      });
    });

    test('databaseUrl is derived from the project id (C27)', () {
      withDb((FirebaseDatabase db) {
        expect(
          db.databaseUrl.toString(),
          'https://test-project-default-rtdb.firebaseio.com',
        );
      });
    });

    test('refFromUrl', () {
      withDb((FirebaseDatabase db) {
        expect(
          db.refFromUrl('https://test-project-default-rtdb.firebaseio.com/a/b'),
          db.ref('a/b'),
        );
        expect(
          db.refFromUrl('https://test-project-default-rtdb.firebaseio.com'),
          db.ref(),
        );
        expect(
          () => db.refFromUrl('https://other-default-rtdb.firebaseio.com/a'),
          throwsArgumentError,
        );
      });
    });
  });
}
