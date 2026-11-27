// An update key that parses to the empty path (`''`, `'/'`, `'//'`, `'///'`) names the location
// itself. `update` and `OnDisconnect.update` refuse it at the call with an ArgumentError that names
// the key, alone or beside another key; nothing is sent and the local view does not change. Why,
// with the server's answer to such a merge and the JS and Android behaviour:
// docs/database_decisions.md, section 11 ("What we gave up") and section 25, row 34.
//
// The "alone" cases are the new refusal. The "before a key" and "after a key" cases were refused
// before as well (two paths where one contains the other); they pin that the error now names the
// key. The cases with a deep key, a key with slashes around a name and `.priority` are controls
// that stay accepted.
//
// The fake server answers no request in these tests: the local data comes from an unanswered set.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

const List<String> _spellings = <String>['', '/', '//', '///'];

/// A database on a [FakeDatabaseServer] that never answers, `r = {a: {k: 1, j: 2}, sib: 5}`
/// written locally, and value listeners at `r/a` and `r` logging `a:<value>` and `r:<value>`.
final class _Rig {
  _Rig(this.time) {
    db = databaseWithFakeServer(newTestApp(), server);
    db
        .ref('r/a')
        .onValue
        .listen(
          (DatabaseEvent e) =>
              log.add('a:${e.snapshot.value}/${e.snapshot.priority}'),
        );
    db
        .ref('r')
        .onValue
        .listen((DatabaseEvent e) => log.add('r:${e.snapshot.value}'));
    db.ref('r').set(<String, Object?>{
      'a': <String, Object?>{'k': 1, 'j': 2},
      'sib': 5,
    });
    time.elapse(const Duration(seconds: 1));
  }

  final FakeTime time;
  final FakeDatabaseServer server = FakeDatabaseServer();
  final List<String> log = <String>[];
  late final FirebaseDatabase db;

  /// Runs [write], expects an ArgumentError whose message matches every one of [message], then
  /// lets time run and expects no new event and no request with the action [action]. A write that
  /// does not throw fails at once: its Future is dropped, not awaited (the fake server never
  /// answers it).
  void expectRefused(
    List<Matcher> message,
    String action,
    Future<void> Function() write,
  ) {
    final List<String> before = List<String>.of(log);
    expect(
      () {
        write().ignore();
      },
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}',
          'message',
          allOf(message),
        ),
      ),
    );
    time.elapse(const Duration(seconds: 1));
    expect(log, before);
    expect(
      server.requests.where((String r) => r.startsWith('$action ')),
      isEmpty,
    );
  }

  /// [expectRefused] for the key [key], printed whole.
  void expectKeyRefused(
    String key,
    String action,
    Future<void> Function() write,
  ) => expectRefused(
    <Matcher>[
      contains('contains the key "$key", which names the location itself'),
    ],
    action,
    write,
  );
}

void _withRig(void Function(_Rig rig) body) =>
    fakeTime((FakeTime time) => body(_Rig(time)));

/// The shapes of the update map for [key]: alone, before another key, after another key.
Map<String, Map<String, Object?>> _shapes(String key) =>
    <String, Map<String, Object?>>{
      'alone': <String, Object?>{key: 7},
      'before a key': <String, Object?>{key: 7, 'n': 3},
      'after a key': <String, Object?>{'n': 3, key: 7},
    };

/// The two refusing calls at [path] of [rig], by name, with the request action each would send.
Map<String, (String, Future<void> Function(Map<String, Object?>))> _calls(
  _Rig rig,
  String? path,
) {
  final DatabaseReference ref = path == null ? rig.db.ref() : rig.db.ref(path);
  return <String, (String, Future<void> Function(Map<String, Object?>))>{
    'update': ('m', ref.update),
    'onDisconnect.update': ('om', ref.onDisconnect.update),
  };
}

void main() {
  test('the rig sees its local data', () {
    _withRig((_Rig rig) {
      expect(rig.log, <String>[
        'a:{j: 2, k: 1}/null',
        'r:{a: {j: 2, k: 1}, sib: 5}',
      ]);
    });
  });

  for (final String method in <String>['update', 'onDisconnect.update']) {
    for (final String key in _spellings) {
      for (final MapEntry<String, Map<String, Object?>> shape in _shapes(
        key,
      ).entries) {
        test(
          '$method with the key "$key" ${shape.key} throws and sends nothing',
          () {
            _withRig((_Rig rig) {
              final (
                String action,
                Future<void> Function(Map<String, Object?>) call,
              ) = _calls(
                rig,
                'r/a',
              )[method]!;
              rig.expectKeyRefused(key, action, () => call(shape.value));
            });
          },
        );
      }
    }

    for (final String key in <String>['', '/']) {
      test('$method at the root with the key "$key" throws', () {
        _withRig((_Rig rig) {
          final (
            String action,
            Future<void> Function(Map<String, Object?>) call,
          ) = _calls(
            rig,
            null,
          )[method]!;
          rig.expectKeyRefused(
            key,
            action,
            () => call(<String, Object?>{key: 7}),
          );
        });
      });
    }

    test('$method with {"": 7} points to set()', () {
      _withRig((_Rig rig) {
        final (
          String action,
          Future<void> Function(Map<String, Object?>) call,
        ) = _calls(
          rig,
          'r/a',
        )[method]!;
        rig.expectRefused(
          <Matcher>[contains('Use set() to replace the location')],
          action,
          () => call(<String, Object?>{'': 7}),
        );
      });
    });

    test('$method with {"": null} throws and points to remove()', () {
      _withRig((_Rig rig) {
        final (
          String action,
          Future<void> Function(Map<String, Object?>) call,
        ) = _calls(
          rig,
          'r/a',
        )[method]!;
        rig.expectRefused(
          <Matcher>[
            contains('contains the key "", which names the location itself'),
            contains('Use remove() to delete the location'),
            isNot(contains('set()')),
          ],
          action,
          () => call(<String, Object?>{'': null}),
        );
      });
    });

    test('$method prints a long key cut to 20 characters, with its length', () {
      _withRig((_Rig rig) {
        final (
          String action,
          Future<void> Function(Map<String, Object?>) call,
        ) = _calls(
          rig,
          'r/a',
        )[method]!;
        rig.expectRefused(
          <Matcher>[
            contains('contains the key "${'/' * 20}..." (1000 characters)'),
            isNot(contains('/' * 21)),
          ],
          action,
          () => call(<String, Object?>{'/' * 1000: 7}),
        );
      });
    });
  }

  test(
    'keys with slashes around and inside names are children, not the location',
    () {
      _withRig((_Rig rig) {
        rig.db.ref('r/a').update(<String, Object?>{
          '/n/': 3,
          'b//c///d/': 1,
          '//e/f': 2,
        });
        rig.db.ref('r/a').onDisconnect.update(<String, Object?>{
          '/n/': 4,
          'b//c///d/': 5,
        });
        rig.time.elapse(const Duration(seconds: 1));
        expect(rig.server.requests, containsAll(<String>['m /r/a', 'om /r/a']));
        expect(
          rig.log.last,
          'r:{a: {b: {c: {d: 1}}, e: {f: 2}, j: 2, k: 1, n: 3}, sib: 5}',
        );
      });
    },
  );

  test('.priority alone still targets the location and is accepted', () {
    _withRig((_Rig rig) {
      rig.db.ref('r/a').update(<String, Object?>{'.priority': 4});
      rig.db.ref('r/a').onDisconnect.update(<String, Object?>{'.priority': 6});
      rig.time.elapse(const Duration(seconds: 1));
      expect(rig.server.requests, containsAll(<String>['m /r/a', 'om /r/a']));
      expect(rig.log, contains('a:{j: 2, k: 1}/4'));
    });
  });
}
