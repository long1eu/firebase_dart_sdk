// The validation tables at the API edge: one case per upstream rule (JS core/util/validation.ts,
// api/Reference_impl.ts; Android utilities/Validation.java), contract C5, C21 and the server value forms.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  /// Runs [body] with a database on a fake server, inside a fake clock.
  void withDb(void Function(FirebaseDatabase db, FakeTime time) body) {
    fakeTime((FakeTime time) {
      final FirebaseDatabase db = databaseWithFakeServer(
        newTestApp(),
        FakeDatabaseServer(),
      );
      body(db, time);
    });
  }

  Map<String, Object?> nested(int depth) {
    Object? value = 1;
    for (int i = 0; i < depth; i++) {
      value = <String, Object?>{'k': value};
    }
    return value! as Map<String, Object?>;
  }

  group('set() values', () {
    final Map<String, Object?> invalid = <String, Object?>{
      'key with .': <String, Object?>{'a.b': 1},
      'key with #': <String, Object?>{'a#b': 1},
      r'key with $': <String, Object?>{r'a$b': 1},
      'key with [': <String, Object?>{'a[b': 1},
      'key with ]': <String, Object?>{'a]b': 1},
      'key with /': <String, Object?>{'a/b': 1},
      'key with a control character': <String, Object?>{'a\u0001b': 1},
      'key with DEL': <String, Object?>{'a\u007fb': 1},
      'empty key': <String, Object?>{'': 1},
      'key with a lone surrogate': <String, Object?>{'a\ud800': 1},
      'non-String key': <Object, Object?>{1: 'x'},
      'NaN': double.nan,
      'Infinity': double.infinity,
      '-Infinity': double.negativeInfinity,
      'NaN below': <String, Object?>{'a': double.nan},
      '.value next to children': <String, Object?>{'.value': 1, 'a': 2},
      'depth 33': nested(33),
      'key path longer than 768 bytes': <String, Object?>{'a' * 769: 1},
      'string with a lone surrogate': 'a\udc00',
      'a function': () {},
      'an unsupported type': DateTime(2020),
      'invalid .priority type': <String, Object?>{'.priority': true, 'a': 1},
    };
    for (final MapEntry<String, Object?> entry in invalid.entries) {
      test('refuses ${entry.key}', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref('x').set(entry.value), throwsArgumentError);
        });
      });
    }

    test('refuses a string over 10 MiB', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(
          () => db.ref('x').set('a' * (10 * 1024 * 1024 + 1)),
          throwsArgumentError,
        );
      });
    });

    test('accepts depth 32, .priority, .value and lists', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        db.ref('x').set(nested(31));
        db.ref('x').set(<String, Object?>{'.value': 1, '.priority': 2});
        db.ref('x').set(<String, Object?>{'a': 1, '.priority': 'p'});
        db.ref('x').set(<Object?>[1, 2, null, 4]);
        db.ref('x').set(<String, Object?>{'a': 'b' * 1000});
      });
    });

    test('refuses a path deeper than 32 segments', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        final String path = List<String>.filled(33, 'a').join('/');
        expect(() => db.ref(path).set(1), throwsArgumentError);
      });
    });
  });

  group('priorities', () {
    for (final Object? priority in <Object?>[
      true,
      double.nan,
      double.infinity,
      <String, Object?>{'a': 1},
      <Object?>[1],
      'a\ud800',
    ]) {
      test('set(priority: $priority) throws', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(
            () => db.ref('x').set(1, priority: priority),
            throwsArgumentError,
          );
        });
      });

      test('setPriority($priority) throws', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref('x').setPriority(priority), throwsArgumentError);
        });
      });
    }

    test('null, numbers, strings and server values are priorities', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        db.ref('x').setPriority(null);
        db.ref('x').setPriority(1.5);
        db.ref('x').setPriority('p');
        db.ref('x').set(1, priority: ServerValue.timestamp);
      });
    });
  });

  group('server values', () {
    final Map<String, Object?> invalid = <String, Object?>{
      'unknown op': <String, Object?>{'.sv': 'foo'},
      'increment of a string': <String, Object?>{
        '.sv': <String, Object?>{'increment': 'x'},
      },
      'increment with another key': <String, Object?>{
        '.sv': <String, Object?>{'increment': 1, 'x': 2},
      },
      'unknown map op': <String, Object?>{
        '.sv': <String, Object?>{'other': 1},
      },
      'timestamp with a sibling': <String, Object?>{'.sv': 'timestamp', 'a': 1},
      'nested unknown op': <String, Object?>{
        'x': <String, Object?>{'.sv': 'bogus'},
      },
      'in a list': <Object?>[
        <String, Object?>{'.sv': 'bogus'},
      ],
    };

    for (final MapEntry<String, Object?> entry in invalid.entries) {
      test('set refuses ${entry.key}', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref('x').set(entry.value), throwsArgumentError);
        });
      });

      test('update refuses ${entry.key}', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(
            () => db.ref('x').update(<String, Object?>{'a': entry.value}),
            throwsArgumentError,
          );
        });
      });

      test('onDisconnect.set refuses ${entry.key}', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(
            () => db.ref('x').onDisconnect.set(entry.value),
            throwsArgumentError,
          );
        });
      });

      test('onDisconnect.update refuses ${entry.key}', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(
            () => db.ref('x').onDisconnect.update(<String, Object?>{
              'a': entry.value,
            }),
            throwsArgumentError,
          );
        });
      });

      test('a transaction result with ${entry.key} fails the transaction', () {
        withDb((FirebaseDatabase db, FakeTime time) {
          Object? failure;
          db
              .ref('x')
              .runTransaction((Object? _) => Transaction.success(entry.value))
              .then<void>(
                (TransactionResult _) {},
                onError: (Object e) => failure = e,
              );
          time.elapse(Duration.zero);
          expect(failure, isA<ArgumentError>());
        });
      });
    }

    test('priority refuses an unknown server value', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(
          () => db.ref('x').setPriority(<String, Object?>{'.sv': 'bogus'}),
          throwsArgumentError,
        );
        expect(
          () => db.ref('x').set(1, priority: <String, Object?>{'.sv': 'bogus'}),
          throwsArgumentError,
        );
      });
    });

    test('accepts ServerValue.timestamp and ServerValue.increment', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        db.ref('x').set(ServerValue.timestamp);
        db.ref('x').set(ServerValue.increment(1));
        db.ref('x').set(ServerValue.increment(1.5));
        db.ref('x').update(<String, Object?>{'a': ServerValue.timestamp});
      });
    });
  });

  group('update()', () {
    test('refuses overlapping paths', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(
          () => db.ref('x').update(<String, Object?>{'a': 1, 'a/b': 2}),
          throwsArgumentError,
        );
      });
    });

    test('refuses an invalid key in a path', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(
          () => db.ref('x').update(<String, Object?>{'a/b#': 1}),
          throwsArgumentError,
        );
      });
    });

    test('accepts a .priority path and refuses an invalid priority there', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        db.ref('x').update(<String, Object?>{'a/.priority': 1});
        expect(
          () => db.ref('x').update(<String, Object?>{'a/.priority': true}),
          throwsArgumentError,
        );
      });
    });

    test('accepts multi-segment paths that do not overlap', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        db.ref('x').update(<String, Object?>{'a/b': 1, 'a/c': 2, 'd': null});
      });
    });
  });

  group('.info is read only', () {
    final Map<String, FutureOr<Object?> Function(DatabaseReference r)> writes =
        <String, FutureOr<Object?> Function(DatabaseReference r)>{
          'set': (DatabaseReference r) => r.set(1),
          'update': (DatabaseReference r) =>
              r.update(<String, Object?>{'a': 1}),
          'setPriority': (DatabaseReference r) => r.setPriority(1),
          'remove': (DatabaseReference r) => r.remove(),
          'push': (DatabaseReference r) => r.push(),
          'runTransaction': (DatabaseReference r) =>
              r.runTransaction((Object? v) => const Transaction.abort()),
          'onDisconnect.set': (DatabaseReference r) => r.onDisconnect.set(1),
          'onDisconnect.update': (DatabaseReference r) =>
              r.onDisconnect.update(<String, Object?>{'a': 1}),
          'onDisconnect.remove': (DatabaseReference r) =>
              r.onDisconnect.remove(),
        };
    for (final MapEntry<String, FutureOr<Object?> Function(DatabaseReference)>
        entry
        in writes.entries) {
      test('${entry.key} under .info throws', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(
            () => entry.value(db.ref('.info/connected')),
            throwsArgumentError,
          );
        });
      });
    }

    test('keepSynced on .info throws', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(
          () => db.ref('.info/connected').keepSynced(true),
          throwsArgumentError,
        );
      });
    });
  });

  group('paths and keys', () {
    for (final String path in <String>[
      'a.b',
      'a#b',
      r'a$b',
      'a[b',
      'a]b',
      'a\u0001',
      'a\ud800',
    ]) {
      test('ref(${Uri.encodeComponent(path)}) throws', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref(path), throwsArgumentError);
        });
      });

      test('child(${Uri.encodeComponent(path)}) throws', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref('x').child(path), throwsArgumentError);
        });
      });
    }

    test('child("") throws', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(() => db.ref('x').child(''), throwsArgumentError);
      });
    });

    test('.info is a valid root path only', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(db.ref('.info/connected').path, '/.info/connected');
        expect(db.ref().child('.info').path, '/.info');
        expect(() => db.ref('a').child('.info'), throwsArgumentError);
      });
    });

    test('ref accepts the C27 forms', () {
      withDb((FirebaseDatabase db, FakeTime _) {
        expect(db.ref().path, '/');
        expect(db.ref('').path, '/');
        expect(db.ref('/').path, '/');
        expect(db.ref('a/b').path, '/a/b');
        expect(db.ref('/a/b').path, '/a/b');
        expect(db.ref('a//b').path, '/a/b');
        expect(db.ref('x').child('a//b').path, '/x/a/b');
      });
    });

    test('DataSnapshot.hasChild refuses an invalid path', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        DataSnapshot? snapshot;
        db.ref('x').set(1);
        db.ref('x').once().then((DatabaseEvent e) => snapshot = e.snapshot);
        time.elapse(Duration.zero);
        expect(() => snapshot!.hasChild('a.b'), throwsArgumentError);
      });
    });
  });

  group('constructor', () {
    test('mockUserToken without emulatorHost throws', () {
      expect(
        () => FirebaseDatabase(newTestApp(), mockUserToken: 'token'),
        throwsArgumentError,
      );
    });
  });
}
