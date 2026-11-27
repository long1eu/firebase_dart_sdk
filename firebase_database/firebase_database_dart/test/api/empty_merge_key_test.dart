// An update key that parses to the empty path (`''`, `'/'`, `'//'`, `'///'`) names the location
// itself. `update` and `OnDisconnect.update` refuse it at the call with an ArgumentError that names
// the key, alone or beside another key; nothing is sent and the local view does not change. The
// emulator refuses such a merge with `invalid_parameters` "Empty strings are not valid keys"
// (measured 2026-11-27, rtdb/from_helper/reports/fix_round/empty_merge_path.md); the JS SDK
// accepts it at the call and replaces the location locally until the server refuses it.
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
        .listen((DatabaseEvent e) => log.add('a:${e.snapshot.value}'));
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

  /// Runs [write], expects an ArgumentError naming [key], then lets time run and expects no new
  /// event and no request with the action [action]. A write that does not throw fails at once:
  /// its Future is dropped, not awaited (the fake server never answers it).
  void expectRefused(String key, String action, Future<void> Function() write) {
    final List<String> before = List<String>.of(log);
    expect(
      () {
        write().ignore();
      },
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          contains('contains the key "$key", which names the location itself'),
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

void main() {
  test('the rig sees its local data', () {
    _withRig((_Rig rig) {
      expect(rig.log, <String>[
        'a:{j: 2, k: 1}',
        'r:{a: {j: 2, k: 1}, sib: 5}',
      ]);
    });
  });

  for (final String key in _spellings) {
    for (final MapEntry<String, Map<String, Object?>> shape in _shapes(
      key,
    ).entries) {
      test(
        'update with the key "$key" ${shape.key} throws and writes nothing',
        () {
          _withRig((_Rig rig) {
            rig.expectRefused(
              key,
              'm',
              () => rig.db.ref('r/a').update(shape.value),
            );
          });
        },
      );

      test(
        'onDisconnect.update with the key "$key" ${shape.key} throws and registers nothing',
        () {
          _withRig((_Rig rig) {
            rig.expectRefused(
              key,
              'om',
              () => rig.db.ref('r/a').onDisconnect.update(shape.value),
            );
          });
        },
      );
    }
  }

  test('update at the root with the key "" throws', () {
    _withRig((_Rig rig) {
      rig.expectRefused(
        '',
        'm',
        () => rig.db.ref().update(<String, Object?>{'': 7}),
      );
    });
  });

  test('a key with slashes around a name is a child, not the location', () {
    _withRig((_Rig rig) {
      rig.db.ref('r/a').update(<String, Object?>{'/n/': 3});
      rig.db.ref('r/a').onDisconnect.update(<String, Object?>{'/n/': 4});
      rig.time.elapse(const Duration(seconds: 1));
      expect(rig.server.requests, containsAll(<String>['m /r/a', 'om /r/a']));
      expect(rig.log.last, 'r:{a: {j: 2, k: 1, n: 3}, sib: 5}');
    });
  });
}
