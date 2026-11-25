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

  /// Expects each of [writes] to return without throwing and its Future not to fail while time
  /// runs (the fake server never answers, so the Future stays pending).
  void expectAccepted(FakeTime time, List<Future<void> Function()> writes) {
    final List<Object> errors = <Object>[];
    for (final Future<void> Function() write in writes) {
      late final Future<void> future;
      expect(() => future = write(), returnsNormally);
      future.catchError((Object e) => errors.add(e));
    }
    time.elapse(const Duration(seconds: 5));
    expect(errors, isEmpty);
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
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').set(nested(31)),
          () => db.ref('x').set(<String, Object?>{'.value': 1, '.priority': 2}),
          () => db.ref('x').set(<String, Object?>{'a': 1, '.priority': 'p'}),
          () => db.ref('x').set(<Object?>[1, 2, null, 4]),
          () => db.ref('x').set(<String, Object?>{'a': 'b' * 1000}),
        ]);
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
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').setPriority(null),
          () => db.ref('x').setPriority(1.5),
          () => db.ref('x').setPriority('p'),
          () => db.ref('x').set(1, priority: ServerValue.timestamp),
        ]);
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
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').set(ServerValue.timestamp),
          () => db.ref('x').set(ServerValue.increment(1)),
          () => db.ref('x').set(ServerValue.increment(1.5)),
          () =>
              db.ref('x').update(<String, Object?>{'a': ServerValue.timestamp}),
        ]);
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
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').update(<String, Object?>{'a/.priority': 1}),
        ]);
        expect(
          () => db.ref('x').update(<String, Object?>{'a/.priority': true}),
          throwsArgumentError,
        );
      });
    });

    test('accepts multi-segment paths that do not overlap', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').update(<String, Object?>{
            'a/b': 1,
            'a/c': 2,
            'd': null,
          }),
        ]);
      });
    });
  });

  // A merge holding an object with a priority and no value gets no answer from the server
  // (emulator, 30 writes measured on 2026-11-25; V1 to V10 are the variants of that run), so
  // update and onDisconnect.update refuse it; set and transactions send the parsed node, in which
  // such an object is empty, and are unchanged (decisions section 11).
  group('an object with a priority and no value', () {
    const Map<String, Object?> p5 = <String, Object?>{'.priority': 5};
    final List<(String, Map<String, Object?>, String)> refused =
        <(String, Map<String, Object?>, String)>[
          (
            'V1 .value null',
            <String, Object?>{
              'n': <String, Object?>{'.value': null, '.priority': 5},
            },
            '/x/n',
          ),
          (
            'V2 a null child',
            <String, Object?>{
              'n': <String, Object?>{'.priority': 5, 'a': null},
            },
            '/x/n',
          ),
          (
            'V3 an empty child',
            <String, Object?>{
              'n': <String, Object?>{'.priority': 5, 'a': <String, Object?>{}},
            },
            '/x/n',
          ),
          (
            'V6 a deeper object',
            <String, Object?>{
              'n': <String, Object?>{'a': p5},
            },
            '/x/n/a',
          ),
          (
            'V9 a list element',
            <String, Object?>{
              'n': <Object?>[p5],
            },
            '/x/n/0',
          ),
          ('V10 a multi-path key', <String, Object?>{'n/x': p5}, '/x/n/x'),
          ('a child (A8)', <String, Object?>{'n': p5}, '/x/n'),
          (
            'a child next to a valid one (A14)',
            <String, Object?>{'n': p5, 'y': 1},
            '/x/n',
          ),
          (
            'a deeper object next to a value (A15)',
            <String, Object?>{
              'n': <String, Object?>{'a': p5, 'b': 1},
            },
            '/x/n/a',
          ),
          (
            'nulls two levels down',
            <String, Object?>{
              'n': <String, Object?>{
                '.priority': 5,
                'a': <String, Object?>{'b': null},
              },
            },
            '/x/n',
          ),
          (
            'an object inside .value',
            <String, Object?>{
              'n': <String, Object?>{
                '.value': <String, Object?>{'a': p5},
                '.priority': 1,
              },
            },
            '/x/n/a',
          ),
        ];

    Matcher refusal(String path) => throwsA(
      isA<ArgumentError>().having(
        (ArgumentError e) => '${e.message}',
        'message',
        allOf(
          contains("'$path'"),
          contains('a priority and no value'),
          contains('null'),
          contains('.value'),
        ),
      ),
    );

    for (final (String name, Map<String, Object?> values, String path)
        in refused) {
      test('update refuses $name', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref('x').update(values), refusal(path));
        });
      });

      test('onDisconnect.update refuses $name', () {
        withDb((FirebaseDatabase db, FakeTime _) {
          expect(() => db.ref('x').onDisconnect.update(values), refusal(path));
        });
      });
    }

    final Map<String, Object?> answered = <String, Object?>{
      'V4 an empty child, no priority': <String, Object?>{
        'a': <String, Object?>{},
      },
      'V5 an empty object': <String, Object?>{},
      'V7 a null priority': <String, Object?>{'.priority': null},
      'V8 a value with a priority': <String, Object?>{
        '.value': 1,
        '.priority': 5,
      },
    };
    for (final MapEntry<String, Object?> entry in answered.entries) {
      test('update and onDisconnect.update accept ${entry.key}', () {
        withDb((FirebaseDatabase db, FakeTime time) {
          expectAccepted(time, <Future<void> Function()>[
            () => db.ref('x').update(<String, Object?>{'n': entry.value}),
            () => db.ref('x').onDisconnect.update(<String, Object?>{
              'n': entry.value,
            }),
          ]);
        });
      });
    }

    test('a refused update shows nothing locally', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        db.ref('x').set(<String, Object?>{'k': 1});
        final List<Object?> values = <Object?>[];
        db.ref('x').onValue.listen((DatabaseEvent e) {
          values.add(e.snapshot.value);
        });
        time.elapse(Duration.zero);
        expect(
          () => db.ref('x').update(<String, Object?>{
            'n': <String, Object?>{'.priority': 5},
            'y': 1,
          }),
          throwsArgumentError,
        );
        time.elapse(const Duration(seconds: 1));
        expect(values, <Object?>[
          <String, Object?>{'k': 1},
        ]);
      });
    });

    test('update accepts the forms the server answers', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').update(<String, Object?>{'.priority': 5}),
          () => db.ref('x').update(<String, Object?>{'n/.priority': 5}),
          () => db.ref('x').update(<String, Object?>{
            'n': <String, Object?>{'.value': 1, '.priority': 5},
          }),
          () => db.ref('x').update(<String, Object?>{
            'n': <String, Object?>{'a': 1, '.priority': 5},
          }),
          () => db.ref('x').update(<String, Object?>{'n': null}),
        ]);
      });
    });

    test('onDisconnect accepts the forms the server answers', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').onDisconnect.update(<String, Object?>{
            '.priority': 5,
          }),
          () => db.ref('x').onDisconnect.update(<String, Object?>{
            'n': <String, Object?>{'.value': 1, '.priority': 5},
          }),
          () => db.ref('x').onDisconnect.set(null, priority: 5),
          () => db.ref('x').onDisconnect.set(<String, Object?>{
            'n': <String, Object?>{'.priority': 5},
          }),
        ]);
      });
    });

    test('set and push().set are unchanged (the child is dropped)', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db.ref('x').set(null, priority: 5),
          () => db.ref('x').set(<String, Object?>{'.priority': 5}),
          () => db.ref('x').set(<String, Object?>{'.value': 1, '.priority': 5}),
          () => db.ref('y').set(<String, Object?>{
            'n': <String, Object?>{'.priority': 5},
            'k': 1,
          }),
          () => db.ref('x').push().set(<String, Object?>{
            'n': <String, Object?>{'.priority': 5},
          }),
        ]);
        Object? value;
        db.ref('y').onValue.listen((DatabaseEvent e) {
          value = e.snapshot.value;
        });
        time.elapse(Duration.zero);
        expect(value, <String, Object?>{'k': 1});
      });
    });

    test('a transaction result is unchanged', () {
      withDb((FirebaseDatabase db, FakeTime time) {
        expectAccepted(time, <Future<void> Function()>[
          () => db
              .ref('x')
              .runTransaction(
                (Object? _) => Transaction.success(const <String, Object?>{
                  'n': <String, Object?>{'.priority': 5},
                }),
              ),
          () => db
              .ref('y')
              .runTransaction(
                (Object? _) => Transaction.success(null, priority: 5),
              ),
        ]);
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
