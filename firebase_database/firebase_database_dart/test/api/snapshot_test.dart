// DataSnapshot export (contract section 3: C11 to C15, C29, C37).

import 'dart:convert';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
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

  DataSnapshot snap(
    FirebaseDatabase db,
    Object? json, {
    String path = 'p',
    Index index = priorityIndex,
  }) => DataSnapshot.internal(db.ref(path), nodeFromJson(json), index);

  test('key, exists and an absent value', () {
    withDb((FirebaseDatabase db) {
      final DataSnapshot empty = snap(db, null, path: 'a/b');
      expect(empty.key, 'b');
      expect(empty.exists, isFalse);
      expect(empty.value, isNull);
      expect(empty.priority, isNull);
      expect(empty.hasChildren, isFalse);
      expect(empty.childrenCount, 0);
      expect(empty.children, isEmpty);
      expect(empty.toJson(), isNull);
      expect(snap(db, 1, path: '').key, isNull);
    });
  });

  test(
    'numbers: integral doubles read as int, -0.0 and fractions stay (C12)',
    () {
      withDb((FirebaseDatabase db) {
        expect(snap(db, 5.0).value, isA<int>());
        expect(snap(db, 5.0).value, 5);
        expect(snap(db, 1.5).value, 1.5);
        final Object? negativeZero = snap(db, -0.0).value;
        expect(negativeZero, isA<double>());
        expect((negativeZero! as double).isNegative, isTrue);
        // Parsed, because dart2js refuses the literal (on the web it reads as ...992).
        final int big = int.parse('9007199254740993');
        expect(snap(db, big).value, big);
      });
    },
  );

  test(
    'maps and lists at every depth, unmodifiable and memoised (C11, C13, C15)',
    () {
      withDb((FirebaseDatabase db) {
        final DataSnapshot s = snap(db, <String, Object?>{
          'name': 'ada',
          'age': 36.0,
          'tags': <String, Object?>{'0': 'a', '1': 'b', '3': 'd'},
          'sparse': <String, Object?>{'0': 'a', '9': 'b'},
        });
        final Object? value = s.value;
        expect(identical(value, s.value), isTrue);
        expect(value, <String, Object?>{
          'name': 'ada',
          'age': 36,
          'tags': <Object?>['a', 'b', null, 'd'],
          'sparse': <String, Object?>{'0': 'a', '9': 'b'},
        });
        if (value case {'name': final String name, 'age': final num age}) {
          expect(name, 'ada');
          expect(age, 36);
        } else {
          fail('the value does not match the pattern');
        }
        expect(
          () => (value as Map<String, Object?>)['x'] = 1,
          throwsUnsupportedError,
        );
        expect(
          () => ((value as Map<String, Object?>)['tags']! as List<Object?>)[0] =
              'z',
          throwsUnsupportedError,
        );
      });
    },
  );

  test('child, hasChild and priorities (C14)', () {
    withDb((FirebaseDatabase db) {
      final DataSnapshot s = snap(db, <String, Object?>{
        '.priority': 'top',
        'a': <String, Object?>{
          '.priority': 5,
          'b': <String, Object?>{'.value': 'x', '.priority': 1.0},
        },
        'list': <Object?>['p', 'q'],
      });
      expect(s.priority, 'top');
      expect(s.child('a').priority, 5);
      expect(s.child('a/b').value, 'x');
      expect(s.child('a/b').priority, 1);
      expect(s.child('a/b').priority, isA<int>());
      expect(s.child('a/b').ref.path, '/p/a/b');
      expect(s.child('list/0').value, 'p');
      expect(s.child('missing').exists, isFalse);
      expect(s.hasChild('a/b'), isTrue);
      expect(s.hasChild('a/c'), isFalse);
      expect(s.hasChildren, isTrue);
      expect(s.childrenCount, 2);
      expect(snap(db, 'leaf').hasChildren, isFalse);
    });
  });

  test(
    "children iterate in the query's index order, each with its own ref (C37)",
    () {
      withDb((FirebaseDatabase db) {
        final Map<String, Object?> data = <String, Object?>{
          'b': 1,
          'a': 3,
          '10': 2,
          '9': 0,
        };
        expect(snap(db, data).children.map((DataSnapshot c) => c.key), <String>[
          '9',
          '10',
          'a',
          'b',
        ]);
        final DataSnapshot byValue = snap(db, data, index: valueIndex);
        expect(byValue.children.map((DataSnapshot c) => c.key), <String>[
          '9',
          'b',
          '10',
          'a',
        ]);
        expect(byValue.children.first.ref.path, '/p/9');
      });
    },
  );

  test('toJson is the export form, so jsonEncode works (C29)', () {
    withDb((FirebaseDatabase db) {
      final DataSnapshot s = snap(db, <String, Object?>{
        'a': <String, Object?>{'.value': 1, '.priority': 2},
        'b': 'x',
        '.priority': 'p',
      });
      expect(s.toJson(), <String, Object?>{
        'a': <String, Object?>{'.value': 1, '.priority': 2},
        'b': 'x',
        '.priority': 'p',
      });
      expect(jsonDecode(jsonEncode(s)), <String, Object?>{
        'a': <String, Object?>{'.value': 1, '.priority': 2},
        'b': 'x',
        '.priority': 'p',
      });
    });
  });

  test(
    'toJson exports a value and a priority stored as 1.0 as 1, and 1.5 as 1.5',
    () {
      withDb((FirebaseDatabase db) {
        // The emulator sends every stored numeric priority as a double (`".priority":1.0`). The
        // checks hold on every compiler: on dart2js `1.0 is int` is already true, `1.5 is int` never.
        final DataSnapshot s = snap(db, <String, Object?>{
          'whole': <String, Object?>{'.value': 1.0, '.priority': 1.0},
          'frac': <String, Object?>{'.value': 1.5, '.priority': 1.5},
        });
        final Map<String, Object?> json = s.toJson()! as Map<String, Object?>;
        final Map<String, Object?> whole =
            json['whole']! as Map<String, Object?>;
        final Map<String, Object?> frac = json['frac']! as Map<String, Object?>;
        expect(whole['.value'], allOf(isA<int>(), 1));
        expect(whole['.priority'], allOf(isA<int>(), 1));
        expect(frac['.value'], allOf(isNot(isA<int>()), 1.5));
        expect(frac['.priority'], allOf(isNot(isA<int>()), 1.5));
        expect(jsonEncode(s.child('whole')), '{".value":1,".priority":1}');
      });
    },
  );

  test('a written 5.0 reads back as int 5 before the server answers (C12)', () {
    fakeTime((FakeTime time) {
      final FirebaseDatabase db = databaseWithFakeServer(
        newTestApp(),
        FakeDatabaseServer(),
      );
      time.elapse(Duration.zero);
      Object? value;
      db.ref('n').set(<String, Object?>{'x': 5.0, 'z': -0.0});
      db.ref('n').once().then((DatabaseEvent e) => value = e.snapshot.value);
      time.elapse(Duration.zero);
      expect(value, <String, Object?>{'x': 5, 'z': 0});
      expect((value as Map<String, Object?>)['x'], isA<int>());
    });
  });
}
