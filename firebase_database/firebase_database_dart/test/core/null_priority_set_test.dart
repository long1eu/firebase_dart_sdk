// A set of a null priority (`p r/x/.priority null`) as the test server plays it. Measured on
// production by the lead (prodkit_production_run13_check40_2026-11-26.txt, check 40): the server
// answers ok in every case; it pushes nothing when the write changes nothing (x missing, or x
// without a priority) and pushes the null at the `.priority` path when it does (x loses its
// priority, or an emptied x that kept only a priority is removed). A non-null priority on a
// missing node is refused with `invalid_parameters`. The emulator differs (it pushes the null in
// every case) and is not what the test server plays.
//
// Each case names the line of check 40 it stands on: (b1) to (b6) are the raw frames, (a) the
// client API writes.
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/json_server_model.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

/// The start data of each case of check 40 (b), at r.
const Map<String, Object?> _rWithK = <String, Object?>{'k': 1};
const Map<String, Object?> _xNoPriority = <String, Object?>{
  'k': 1,
  'x': <String, Object?>{'v': 1},
};
const Map<String, Object?> _xPriority2 = <String, Object?>{
  'k': 1,
  'x': <String, Object?>{'v': 1, '.priority': 2},
};
const Map<String, Object?> _xPriority5 = <String, Object?>{
  'k': 1,
  'x': <String, Object?>{'v': 1, '.priority': 5},
};

/// A model holding [r] at r; with [emptyX] x/v is then removed, so x keeps only its priority.
JsonServerModel _model(Object? r, {bool emptyX = false}) {
  final JsonServerModel model = JsonServerModel(
    r == null ? null : <String, Object?>{'r': r},
  );
  if (emptyX) {
    expect(model.write('r/x/v', null), isTrue);
  }
  return model;
}

/// A listen hash provider for an empty cache.
final class _NoHash implements ListenHashProvider {
  @override
  String simpleHash() => '';

  @override
  bool shouldIncludeCompoundHash() => false;

  @override
  WireCompoundHash compoundHash() =>
      const WireCompoundHash(posts: <String>[], hashes: <String>['']);
}

/// A delegate that logs each data push as `d <path> <data>` (`m` for a merge).
final class _Recorder implements ServerActionsDelegate {
  final List<String> log = <String>[];

  @override
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) => log.add('${isMerge ? 'm' : 'd'} $path $data');

  @override
  void onRangeMergeUpdate(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => log.add('rm $path');

  @override
  void onConnect() {}

  @override
  void onDisconnect() {}

  @override
  void onAuthStatus(String status, {String? explanation}) {}

  @override
  void onAppCheckStatus(String status, {String? explanation}) {}

  @override
  void onServerShutdown(String reason) {}

  @override
  void onServerInfoUpdate(Map<String, Object?> updates) {}
}

/// A connected fake holding [r] at r (x/v removed after with [emptyX]), with an answered listen
/// at r; the log is empty.
(FakeServerActions, _Recorder) _fakeWithListen(
  Object? r, {
  bool emptyX = false,
}) {
  final _Recorder recorder = _Recorder();
  final FakeServerActions fake = FakeServerActions(recorder)
    ..initialize()
    ..connect();
  if (r != null) {
    fake.writeByOtherClient('r', r);
  }
  if (emptyX) {
    fake.writeByOtherClient('r/x/v', null);
  }
  fake.listen(
    QuerySpec.defaultAt(Path('r')).toListenSpec(),
    hashProvider: _NoHash(),
    onComplete: (String status, Object? data) {},
  );
  fake.respond(fake.callsOf('listen').single);
  recorder.log.clear();
  return (fake, recorder);
}

void main() {
  group('JsonServerModel.changesNothing', () {
    for (final (String label, JsonServerModel Function() model, bool want)
        in <(String, JsonServerModel Function(), bool)>[
          // (b1) r missing: ok, no push.
          ('r missing', () => _model(null), true),
          // (b2) r={k:1}, x missing: ok, no push.
          ('x missing', () => _model(_rWithK), true),
          // (b3) x {v:1} without a priority: ok, no push.
          ('x with a value, no priority', () => _model(_xNoPriority), true),
          // (b4) x {v:1} priority 2: the null is pushed at r/x/.priority.
          ('x with priority 2', () => _model(_xPriority2), false),
          // (b5) x emptied keeping priority 5: the null is pushed at r/x/.priority.
          (
            'x emptied, keeping priority 5',
            () => _model(_xPriority5, emptyX: true),
            false,
          ),
        ]) {
      test('set null at r/x/.priority, $label: $want', () {
        expect(model().changesNothing('r/x/.priority', null), want);
      });
    }

    // (b6) a non-null priority on a missing x is refused, not silent.
    test('a non-null priority is never silent', () {
      expect(_model(_rWithK).changesNothing('r/x/.priority', 3), isFalse);
      expect(_model(_xNoPriority).changesNothing('r/x/.priority', 3), isFalse);
    });

    // Check 40 measured sets only; an update keeps its push (check 39 Q14 rules apply).
    test('a merge is never silent', () {
      expect(
        _model(_rWithK).changesNothing('r/x', <String, Object?>{
          '.priority': null,
        }, merge: true),
        isFalse,
      );
    });

    test('a path not ending in .priority is never silent', () {
      expect(_model(_rWithK).changesNothing('r/x', null), isFalse);
      expect(_model(null).changesNothing('r/x', null), isFalse);
      expect(_model(null).changesNothing('', null), isFalse);
    });
  });

  group('JsonServerModel.write of a set at r/x/.priority', () {
    for (final (
          String label,
          Object? r,
          bool emptyX,
          Object? priority,
          bool accepted,
          Object? before,
          Object? after,
        )
        in <(String, Object?, bool, Object?, bool, Object?, Object?)>[
          // (b1) r missing: {"s":"ok"}, export of r null before and after.
          ('b1 null, r missing', null, false, null, true, null, null),
          // (b2) r={k:1}, x missing: {"s":"ok"}, export {"k":1} before and after.
          ('b2 null, x missing', _rWithK, false, null, true, _rWithK, _rWithK),
          // (b3) x no priority: {"s":"ok"}, export {"k":1,"x":{"v":1}} before and after.
          (
            'b3 null, x without a priority',
            _xNoPriority,
            false,
            null,
            true,
            _xNoPriority,
            _xNoPriority,
          ),
          // (b4) x priority 2: {"s":"ok"}, export after {"k":1,"x":{"v":1}}.
          (
            'b4 null, x with priority 2',
            _xPriority2,
            false,
            null,
            true,
            _xPriority2,
            _xNoPriority,
          ),
          // (b5) x emptied keeping 5: {"s":"ok"}, export {"k":1,"x":{".priority":5}} then {"k":1}.
          (
            'b5 null, x emptied keeping priority 5',
            _xPriority5,
            true,
            null,
            true,
            <String, Object?>{
              'k': 1,
              'x': <String, Object?>{'.priority': 5},
            },
            _rWithK,
          ),
          // (b6) p r/x/.priority 3, x missing: invalid_parameters, export {"k":1} unchanged.
          (
            'b6 3, x missing (refused)',
            _rWithK,
            false,
            3,
            false,
            _rWithK,
            _rWithK,
          ),
        ]) {
      test(label, () {
        final JsonServerModel model = _model(r, emptyX: emptyX);
        expect(model.export('r', hidden: true), before);
        expect(model.write('r/x/.priority', priority), accepted);
        expect(model.export('r', hidden: true), after);
      });
    }
  });

  group('FakeServerActions: a null priority set at r/x/.priority, listen at r', () {
    for (final (String label, Object? r, bool emptyX, List<String> pushes)
        in <(String, Object?, bool, List<String>)>[
          // (b1) and (b2): ok, no frame but the answer.
          ('r missing', null, false, const <String>[]),
          ('x missing', _rWithK, false, const <String>[]),
          // (b3): ok, no frame but the answer.
          ('x without a priority', _xNoPriority, false, const <String>[]),
          // (b4) and (b5): the d frame of null at r/x/.priority, then the answer.
          (
            'x with priority 2',
            _xPriority2,
            false,
            const <String>['d /r/x/.priority null'],
          ),
          (
            'x emptied, keeping priority 5',
            _xPriority5,
            true,
            const <String>['d /r/x/.priority null'],
          ),
        ]) {
      test('own put, $label: pushes $pushes, answered ok', () {
        final (FakeServerActions fake, _Recorder recorder) = _fakeWithListen(
          r,
          emptyX: emptyX,
        );
        fake.put(
          '/r/x/.priority',
          null,
          onComplete: (String status, Object? data) =>
              recorder.log.add('answer $status'),
        );
        fake.ackLastWrite();
        expect(recorder.log, <String>[...pushes, 'answer ok']);
        expect(fake.pendingWrites, isEmpty);
      });

      test('another client, $label: pushes $pushes', () {
        final (FakeServerActions fake, _Recorder recorder) = _fakeWithListen(
          r,
          emptyX: emptyX,
        );
        fake.writeByOtherClient('r/x/.priority', null);
        expect(recorder.log, pushes);
      });
    }

    // (b6): invalid_parameters, no push, nothing stored.
    test('own put of priority 3, x missing: refused, no push', () {
      final (FakeServerActions fake, _Recorder recorder) = _fakeWithListen(
        _rWithK,
      );
      fake.put(
        '/r/x/.priority',
        3,
        onComplete: (String status, Object? data) =>
            recorder.log.add('answer $status $data'),
      );
      fake.ackLastWrite();
      expect(recorder.log, <String>[
        'answer invalid_parameters could not set priority on non-existent node',
      ]);
      expect(fake.dataAt('r'), _rWithK);
    });
  });

  group('Repo: a null priority set on a missing node, listener at r', () {
    // (a) setPriority(null) at a missing node: completed ok; the listener attached before got
    // NO EVENT; get() gives null. (b1), (b2): the server pushes nothing.
    for (final (String label, Object? r, String value)
        in <(String, Object?, String)>[
          ('r missing', null, 'null'),
          ('x missing', _rWithK, '{"k":1}'),
        ]) {
      test('$label: completes ok, no event, nothing pending', () async {
        final RepoHarness h = RepoHarness();
        h.listen('S', 'r');
        h.answer('r', r);
        await settle();
        h.set('r/x/.priority', null, name: 'W');
        await settle();
        expect(h.callsAt('put', '/r/x/.priority'), hasLength(1));
        h.server.ackLastWrite();
        await settle();
        expect(h.log, <String>['S:V($value)', 'W:ok']);
        expect(h.server.pendingWrites, isEmpty);
        expect(h.server.dataAt('r'), r);
      });
    }
  });
}
