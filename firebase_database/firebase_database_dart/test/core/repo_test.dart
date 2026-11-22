// Repo: event delivery rows of 14_api_contract.md section 4.4 that Repo alone can show (named by
// their D number), cancel delivery, onDisconnect, restoreWrites, number normalisation and close.
// Driven through FakeServerActions and the in-memory storage engine.
//
// Rows not here: D3, D9 to D12, D16, D21 (stream objects, pause, `await for`, cancel Futures: the
// public stream layer); D29 to D31 and D55 (auth revoke, server kill, connection attempts: the
// connection); D33 (app delete), D44 (`once` cancel), D56 and D57 (snapshot refs and priorities:
// the public API). Transactions (D24, D34 to D41) are in repo_transaction_test.dart, get (D46 to
// D54) in repo_get_test.dart.
import 'dart:async';

import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

void main() {
  group('event delivery', () {
    test('D1 no listener runs inside the call', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'a');
      h.answer('a', 1);
      await settle();
      h.log.clear();

      h.set('a', 2);
      h.log.add('returned');
      await settle();
      expect(h.log, <String>['returned', 'S1:V(2)']);
    });

    test(
      'D2 initial events come after listen returns, one server listen',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'a');
        h.answer('a', 1);
        await settle();
        h.log.clear();

        h.listen('S2', 'a');
        h.log.add('returned');
        await settle();
        expect(h.log, <String>['returned', 'S2:V(1)']);
        expect(h.server.callsOf('listen'), hasLength(1));
      },
    );

    test('D4 order inside a change', () async {
      final RepoHarness h = RepoHarness();
      final QueryParams byValue = QueryParams.defaultParams.orderBy(valueIndex);
      h.listen('S1', 'l', types: childTypes, params: byValue);
      h.listen('S2', 'l', params: byValue);
      h.answer('l', <String, Object?>{'a': 1, 'b': 2});
      await settle();
      h.log.clear();

      const Map<String, Object?> update = <String, Object?>{
        'a': null,
        'b': 5,
        'c': 0,
      };
      h.repo.updateChildren(Path('l'), CompoundWrite.fromValue(update), update);
      await settle();
      expect(h.log, <String>[
        'S1:R(a)',
        'S1:A(c,null)',
        'S1:M(b,c)',
        'S1:C(b,c)',
        'S2:V({"b":5,"c":0})',
      ]);
    });

    test('D5 two registrations on one query, in the order added', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'l', types: <EventType>{EventType.childAdded});
      h.listen('S2', 'l', types: <EventType>{EventType.childAdded});
      await settle();

      h.answer('l', <String, Object?>{'a': 1, 'b': 2});
      await settle();
      expect(h.log, <String>[
        'S1:A(a,null)',
        'S2:A(a,null)',
        'S1:A(b,a)',
        'S2:A(b,a)',
      ]);
    });

    test('D6 type order before registration order', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'l');
      h.listen('S2', 'l', types: <EventType>{EventType.childAdded});
      await settle();

      h.answer('l', <String, Object?>{'a': 1});
      await settle();
      expect(h.log, <String>['S2:A(a,null)', 'S1:V({"a":1})']);
    });

    test('D7 deeper location first', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'a');
      h.answer('a', <String, Object?>{'b': 1});
      h.listen('S2', 'a/b');
      await settle();
      h.log.clear();

      h.set('a', <String, Object?>{'b': 2});
      await settle();
      expect(h.log, <String>['S2:V(2)', 'S1:V({"b":2})']);
    });

    test('D8 changes arrive in the order applied', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'a');
      h.answer('a', null);
      h.listen('S2', 'b');
      h.answer('b', null);
      await settle();
      h.log.clear();

      h
        ..set('a', 1)
        ..set('b', 1)
        ..set('a', 2);
      await settle();
      expect(h.log, <String>['S1:V(1)', 'S2:V(1)', 'S1:V(2)']);
    });

    test("D13 a listener's own write goes to the tail", () async {
      final RepoHarness h = RepoHarness();
      h.listen(
        'S1',
        'a',
        after: (DataEvent event) {
          h.log.add('in');
          if (event.snapshot.value == 1) {
            h.set('a', 2);
          }
          h.log.add('out');
        },
      );
      h.answer('a', 0);
      await settle();
      h.log.clear();

      h.set('a', 1);
      await settle();
      expect(h.log, <String>['S1:V(1)', 'in', 'out', 'S1:V(2)', 'in', 'out']);
    });

    test(
      'D14 a listener added during delivery gets only current data',
      () async {
        final RepoHarness h = RepoHarness();
        bool added = false;
        h.listen(
          'S1',
          'a',
          after: (DataEvent event) {
            if (event.snapshot.value == 1 && !added) {
              added = true;
              h.listen('S2', 'a');
            }
          },
        );
        h.answer('a', null);
        await settle();
        h.log.clear();

        h
          ..set('a', 1)
          ..set('a', 2);
        await settle();
        expect(h.log, <String>['S1:V(1)', 'S1:V(2)', 'S2:V(2)']);
      },
    );

    test('D15 a cancel during delivery drops queued events', () async {
      final RepoHarness h = RepoHarness();
      late CallbackEventRegistration s2;
      bool cancelled = false;
      h.listen(
        'S1',
        'l',
        types: <EventType>{EventType.childAdded},
        after: (_) {
          if (!cancelled) {
            cancelled = true;
            h.repo.removeEventCallback(s2);
          }
        },
      );
      s2 = h.listen('S2', 'l', types: <EventType>{EventType.childAdded});
      h.answer('l', null);
      await settle();
      h.log.clear();

      h.set('l', <String, Object?>{'a': 1, 'b': 2});
      await settle();
      expect(h.log, <String>['S1:A(a,null)', 'S1:A(b,a)']);
    });

    test('D17 a throwing listener does not stop the drain', () async {
      final List<Object> errors = <Object>[];
      final RepoHarness h = RepoHarness();
      void guarded(void Function() body) =>
          runZonedGuarded(body, (Object e, StackTrace s) => errors.add(e));
      guarded(() {
        h.listen('S1', 'a', after: (_) => throw StateError('x'));
        h.listen('S2', 'a');
        h.answer('a', null);
      });
      await settle();
      h.log.clear();
      errors.clear();

      guarded(() => h.set('a', 1));
      await settle();
      guarded(() => h.set('a', 2));
      await settle();
      expect(h.log, <String>['S1:V(1)', 'S2:V(1)', 'S1:V(2)', 'S2:V(2)']);
      expect(errors, hasLength(2));
      expect(errors, everyElement(isA<StateError>()));
    });

    test('D18 no yield inside a change', () async {
      const int n = 3;
      final RepoHarness h = RepoHarness(
        dispatcher: EventDispatcher(yieldEvery: n),
      );
      bool scheduled = false;
      h.listen(
        'S1',
        'l',
        types: <EventType>{EventType.childAdded},
        after: (_) {
          if (!scheduled) {
            scheduled = true;
            Timer.run(() => h.log.add('T'));
          }
        },
      );
      h.answer('l', null);
      await settle();
      h.log.clear();

      h.set('l', <String, Object?>{
        for (int i = 0; i < 2 * n; i++) 'k${i.toString().padLeft(5, '0')}': i,
      });
      await settle();
      expect(h.log, <String>[
        for (int i = 0; i < 2 * n; i++)
          'S1:A(k${i.toString().padLeft(5, '0')},'
              '${i == 0 ? 'null' : 'k${(i - 1).toString().padLeft(5, '0')}'})',
        'T',
      ]);
    });

    test('D19 the drain yields between changes', () async {
      const int n = 3;
      final RepoHarness h = RepoHarness(
        dispatcher: EventDispatcher(yieldEvery: n),
      );
      bool scheduled = false;
      h.listen(
        'S1',
        'x',
        types: <EventType>{EventType.childAdded},
        after: (_) {
          if (!scheduled) {
            scheduled = true;
            Timer.run(() => h.log.add('T'));
          }
        },
      );
      h.listen('S2', 'y', types: <EventType>{EventType.childAdded});
      h
        ..answer('x', null)
        ..answer('y', null);
      await settle();
      h.log.clear();

      h
        ..set('x', <String, Object?>{
          for (int i = 0; i < n; i++) 'k${i.toString().padLeft(5, '0')}': i,
        })
        ..set('y', <String, Object?>{'k00000': 0});
      await settle();
      expect(h.log, <String>[
        'S1:A(k00000,null)',
        'S1:A(k00001,k00000)',
        'S1:A(k00002,k00001)',
        'T',
        'S2:A(k00000,null)',
      ]);
    });

    test('D20 local write, then ack', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'a');
      h.answer('a', 1);
      await settle();
      h.log.clear();

      h.set('a', 2, name: 'F');
      await settle();
      h.server.ackLastWrite();
      await settle();
      expect(h.log, <String>['S1:V(2)', 'F:ok']);
    });

    test(
      'D22 local write, then rejection rolls back before the failure',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'a');
        h.answer('a', 1);
        await settle();
        h.log.clear();

        h.set('a', 2, name: 'F');
        await settle();
        h.server.failLastWrite('permission_denied');
        await settle();
        expect(h.log, <String>['S1:V(2)', 'S1:V(1)', 'F:E(permission-denied)']);
      },
    );

    test(
      'D23 an offline write stays pending and completes after reconnect',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'a');
        h.answer('a', 1);
        await settle();
        h.server.disconnect();
        await settle();
        h.log.clear();

        h.set('a', 2, name: 'F');
        await settle();
        h.server.connect();
        h.answer('a', 1);
        await settle();
        h.server.ackLastWrite();
        await settle();
        expect(h.log, <String>['S1:V(2)', 'F:ok']);
        // Repo sends the put once; replaying it after the reconnect is the connection's job.
        expect(h.server.callsOf('put'), hasLength(1));
      },
    );

    test(
      'D25 a partial cache raises child events and no value event',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('P1', 'f/a');
        h.answer('f/a', 1);
        h.listen('P2', 'f/b');
        h.answer('f/b', 2);
        await settle();
        h.log.clear();

        h.listen('S1', 'f', types: childTypes);
        h.listen('S2', 'f');
        await settle();
        h.log.add('answer');
        h.answer('f', <String, Object?>{'a': 1, 'b': 2, 'c': 3});
        await settle();
        expect(h.log, <String>[
          'S1:A(a,null)',
          'S1:A(b,a)',
          'answer',
          'S1:A(c,b)',
          'S2:V({"a":1,"b":2,"c":3})',
        ]);
      },
    );

    test('D26 a pending write is complete data for a new listener', () async {
      final RepoHarness h = RepoHarness();
      h.set('x', <String, Object?>{'k': 1}, name: 'F');
      await settle();

      h.listen('S1', 'x');
      await settle();
      expect(h.log, <String>['S1:V({"k":1})']);
    });

    test('D27 a server cancel reaches only its registrations', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 's');
      h.answer('s', 1);
      h.listen('S2', 't');
      h.answer('t', 2);
      await settle();
      h.log.clear();

      h.server.revokeListen(QuerySpec.defaultAt(Path('s')).toListenSpec());
      await settle();
      expect(h.log, <String>['S1:E(permission-denied)']);
    });

    test('D28 disconnect and reconnect raise .info/connected', () async {
      final RepoHarness h = RepoHarness();
      h.listen('C', '.info/connected');
      h.listen('S1', 'a');
      h.answer('a', 1);
      await settle();
      h.log.clear();

      h.server.disconnect();
      await settle();
      h.server.connect();
      await settle();
      expect(h.log, <String>['C:V(false)', 'C:V(true)']);
    });

    test(
      'D42 onDisconnect writes apply locally after .info/connected false',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('C', '.info/connected');
        h.listen('S1', 'p');
        h.answer('p', 'on');
        h.repo.onDisconnectSetValue(
          Path('p'),
          nodeFromJson('off'),
          onComplete: h.completion('F'),
        );
        await settle();
        h.server.ackLastOnDisconnect();
        await settle();
        h.log.clear();

        h.server.disconnect();
        await settle();
        h.server.connect();
        await settle();
        h.answer('p', 'off');
        await settle();
        h.server.disconnect();
        await settle();
        expect(h.log, <String>[
          'C:V(false)',
          'S1:V("off")',
          'C:V(true)',
          'C:V(false)',
        ]);
      },
    );

    test(
      'D43 a pending write answers a new registration with no server',
      () async {
        final RepoHarness h = RepoHarness();
        h.set('a', 5, name: 'F');
        await settle();

        h.listen('O', 'a');
        await settle();
        expect(h.log, <String>['O:V(5)']);
        expect(h.server.activeListens.values.single.answered, isFalse);
      },
    );

    test('D45 child events of cached data come from the cache', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'l');
      h.answer('l', <String, Object?>{'x': 1, 'y': 2});
      await settle();
      h.log.clear();

      h.listen('O', 'l', types: <EventType>{EventType.childAdded});
      await settle();
      expect(h.log, <String>['O:A(x,null)', 'O:A(y,x)']);
    });

    test('D58 a server cancel ends the registration', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 's');
      h.answer('s', 1);
      await settle();
      h.log.clear();

      h.server.revokeListen(QuerySpec.defaultAt(Path('s')).toListenSpec());
      await settle();
      h.server.deliverDataUpdate('s', 2);
      await settle();
      expect(h.log, <String>['S1:E(permission-denied)']);
    });
  });

  group('cancel delivery (rule 4.6)', () {
    test('a revoked listen delivers one cancel, then nothing', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 's');
      h.answer('s', 1);
      await settle();
      h.log.clear();

      // Data queued before the cancel arrives first; nothing after it.
      h.server.deliverDataUpdate('s', 2);
      h.server.revokeListen(QuerySpec.defaultAt(Path('s')).toListenSpec());
      h.server.deliverDataUpdate('s', 3);
      await settle();
      h.server.deliverDataUpdate('s', 4);
      h.set('s', 5);
      await settle();
      expect(h.log, <String>['S1:V(2)', 'S1:E(permission-denied)']);
    });

    test('a failed listen delivers one cancel, then nothing', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 's');
      h.listen('S2', 's', types: childTypes);
      await settle();

      h.server.respondToListen(
        QuerySpec.defaultAt(Path('s')).toListenSpec(),
        status: 'permission_denied',
        data: 'no',
      );
      await settle();
      h.server.deliverDataUpdate('s', <String, Object?>{'a': 1});
      h.set('s', <String, Object?>{'b': 2});
      await settle();
      expect(h.log, <String>[
        'S1:E(permission-denied)',
        'S2:E(permission-denied)',
      ]);
    });
  });

  group('onDisconnect', () {
    test(
      'a registration counts only after the server acknowledged it',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'p');
        h.answer('p', 'on');
        h.repo.onDisconnectSetValue(Path('p'), nodeFromJson('off'));
        await settle();
        h.log.clear();

        h.server.disconnect();
        await settle();
        expect(h.log, isEmpty);
      },
    );

    test('update registers children; cancel forgets them', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'p');
      h.answer('p', <String, Object?>{'a': 1});
      h.repo.onDisconnectUpdate(
        Path('p'),
        <Path, Node>{Path('b'): nodeFromJson(2)},
        <String, Object?>{'b': 2},
        onComplete: h.completion('U'),
      );
      await settle();
      h.server.ackLastOnDisconnect();
      h.repo.onDisconnectCancel(Path('p/b'), onComplete: h.completion('X'));
      await settle();
      h.server.ackLastOnDisconnect();
      await settle();
      h.log.clear();

      h.server.disconnect();
      await settle();
      expect(h.log, isEmpty);
      expect(
        h.server.callsOf('onDisconnectMerge').single.data,
        <String, Object?>{'b': 2},
      );
    });

    test(
      'an onDisconnect set failed by a drop is sent again when registered again',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'p');
        h.answer('p', 'on');
        h.repo.onDisconnectSetValue(
          Path('p'),
          nodeFromJson('off'),
          onComplete: h.completion('F1'),
        );
        await settle();
        h.server.disconnect();
        await settle();
        h.server.connect();
        await settle();
        h.repo.onDisconnectSetValue(
          Path('p'),
          nodeFromJson('off'),
          onComplete: h.completion('F2'),
        );
        await settle();
        expect(h.callsAt('onDisconnectPut', '/p'), hasLength(2));
        h.server.ackLastOnDisconnect();
        await settle();
        expect(h.log.where((String e) => e.startsWith('F')), <String>[
          'F1:E(disconnected)',
          'F2:ok',
        ]);
        // Registered now: a drop applies it locally.
        h.log.clear();
        h.server.disconnect();
        await settle();
        expect(h.log, <String>['S1:V("off")']);
      },
    );

    test('an onDisconnect cancel after a failed set is sent', () async {
      final RepoHarness h = RepoHarness();
      h.repo.onDisconnectSetValue(
        Path('p'),
        nodeFromJson('off'),
        onComplete: h.completion('F'),
      );
      await settle();
      h.server.disconnect();
      await settle();
      h.server.connect();
      await settle();
      h.repo.onDisconnectCancel(Path('p'), onComplete: h.completion('X'));
      await settle();
      expect(h.callsAt('onDisconnectCancel', '/p'), hasLength(1));
      h.server.ackLastOnDisconnect();
      await settle();
      expect(h.log, <String>['F:E(disconnected)', 'X:ok']);
    });

    test(
      'a sent onDisconnect request fails with disconnected on a drop',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'p');
        h.answer('p', 'on');
        h.repo.onDisconnectSetValue(
          Path('p'),
          nodeFromJson('off'),
          onComplete: h.completion('F'),
        );
        await settle();
        h.log.clear();

        h.server.disconnect();
        await settle();
        // Not acknowledged, so not applied locally either.
        expect(h.log, <String>['F:E(disconnected)']);
      },
    );

    test('an empty update completes without a request', () async {
      final RepoHarness h = RepoHarness();
      h.repo.onDisconnectUpdate(
        Path('p'),
        <Path, Node>{},
        <String, Object?>{},
        onComplete: h.completion('U'),
      );
      await settle();
      expect(h.log, <String>['U:ok']);
      expect(h.server.callsOf('onDisconnectMerge'), isEmpty);
    });

    test('server values resolve when the writes apply locally', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'p');
      h.answer('p', 0);
      h.repo.onDisconnectSetValue(
        Path('p'),
        nodeFromJson(<String, Object?>{'.sv': 'timestamp'}),
      );
      await settle();
      h.server.ackLastOnDisconnect();
      await settle();
      h.log.clear();

      h.server.disconnect();
      await settle();
      expect(h.log, <String>[
        'S1:V(${DateTime.utc(2026).millisecondsSinceEpoch})',
      ]);
    });
  });

  group('writes', () {
    test('an empty update completes at once without a request', () async {
      final RepoHarness h = RepoHarness();
      h.repo.updateChildren(
        Path('a'),
        CompoundWrite.empty,
        const <String, Object?>{},
        onComplete: h.completion('F'),
      );
      await settle();
      expect(h.log, <String>['F:ok']);
      expect(h.server.callsOf('merge'), isEmpty);
    });

    test('numbers are normalised before they leave Repo (C12)', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'n');
      h.answer('n', null);
      await settle();
      h.log.clear();

      h.repo.setValue(
        Path('n'),
        nodeFromJson(<String, Object?>{'z': -0.0, 'f': 5.0, 'h': 1.5}, -0.0),
      );
      h.repo.updateChildren(
        Path('m'),
        CompoundWrite.fromValue(<String, Object?>{'x/y': -0.0}),
        <String, Object?>{'x/y': -0.0},
      );
      h.repo.onDisconnectSetValue(Path('o'), nodeFromJson(-0.0));
      await settle();

      final Object? put = h.server.callsOf('put').single.data;
      expect(put, <String, Object?>{'.priority': 0, 'f': 5, 'h': 1.5, 'z': 0});
      final Map<String, Object?> map = put! as Map<String, Object?>;
      expect(map['z'], isA<int>());
      expect(map['f'], isA<int>());
      expect(map['.priority'], isA<int>());
      final Object? merge = h.server.callsOf('merge').single.data;
      expect(merge, <String, Object?>{'x/y': 0});
      expect((merge! as Map<String, Object?>)['x/y'], isA<int>());
      expect(h.server.callsOf('onDisconnectPut').single.data, isA<int>());
      expect(h.log, <String>['S1:V({"f":5,"h":1.5,"z":0})']);
    });

    test('purgeOutstandingWrites reverts and fails the writes (C34)', () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'a');
      h.answer('a', 1);
      await settle();
      h.log.clear();

      h.set('a', 2, name: 'F');
      await settle();
      h.repo.purgeOutstandingWrites();
      await settle();
      expect(h.log, <String>['S1:V(2)', 'S1:V(1)', 'F:E(write-canceled)']);
    });
  });

  group('restoreWrites', () {
    test('persisted writes are applied and re-sent in write-id order before the '
        'connection starts', () async {
      final InMemoryPersistenceStorageEngine engine =
          InMemoryPersistenceStorageEngine(<UserWriteRecord>[
            UserWriteRecord.merge(
              7,
              Path('b'),
              CompoundWrite.fromValue(<String, Object?>{'x': 2}),
            ),
            UserWriteRecord.overwrite(
              5,
              Path('a'),
              nodeFromJson(1),
              visible: true,
            ),
          ]);
      final RepoHarness h = RepoHarness(persistence: managerOver(engine));
      // The connection starts on the first operation (lazy start), after the restored writes.
      expect(
        h.server.calls.map((ServerCall c) => '${c.action} ${c.path ?? ''}'),
        <String>['put /a', 'merge /b'],
      );

      h.listen('S1', 'a');
      expect(
        h.server.calls
            .map((ServerCall c) => '${c.action} ${c.path ?? ''}')
            .take(3),
        <String>['put /a', 'merge /b', 'initialize '],
      );
      await settle();
      expect(h.log, <String>['S1:V(1)']);

      // The next user write continues after the highest restored id.
      h.set('c', 3);
      expect(
        engine.loadUserWrites().map((UserWriteRecord w) => w.writeId),
        <int>[5, 7, 8],
      );

      // Acknowledging a restored write removes it from the log.
      h.server.respond(h.server.callsOf('put').first);
      await settle();
      expect(
        engine.loadUserWrites().map((UserWriteRecord w) => w.writeId),
        <int>[7, 8],
      );
    });
  });

  group('close (C3, D32)', () {
    test(
      'cancels registrations, fails pending requests, then completes',
      () async {
        final RepoHarness h = RepoHarness();
        h.listen('S1', 'a');
        h.answer('a', 1);
        h.set('b', 1, name: 'F');
        h.get('c');
        await settle();
        h.log.clear();

        // Data queued for S1 before close is dropped.
        h.server.deliverDataUpdate('a', 2);
        await h.repo.close().then((_) => h.log.add('closed'));
        await settle();
        // Registrations first, then the write; the get fails through the connection's shutdown
        // (ServerActionsException('database_closed')).
        expect(h.log.take(2), <String>[
          'S1:E(database-closed)',
          'F:E(database-closed)',
        ]);
        expect(
          h.log.skip(2),
          unorderedEquals(<String>['G:E(database-closed)', 'closed']),
        );
        h.log.clear();

        h.listen('S2', 'a');
        h.get('a');
        h.set('a', 3, name: 'W');
        await h.repo.close().then((_) => h.log.add('closed2'));
        await settle();
        expect(
          h.log,
          containsAll(<String>[
            'S2:E(database-closed)',
            'G:E(database-closed)',
            'W:E(database-closed)',
            'closed2',
          ]),
        );
        expect(h.server.isShutdown, isTrue);
      },
    );
  });

  test(
    'a listen answered with a no_index warning is not logged by the Repo: the connection logs '
    'it (persistent_connection_test B-4.1c)',
    () async {
      final RepoHarness h = RepoHarness();
      h.listen('S1', 'l');
      h.server.respondToListen(
        QuerySpec.defaultAt(Path('l')).toListenSpec(),
        data: <String, Object?>{
          'w': <Object?>['no_index'],
        },
      );
      await settle();
      expect(h.log, <String>['S1:V(null)']);
      expect(
        h.logs.where((String l) => l.contains('unspecified index')),
        isEmpty,
      );
    },
  );

  group('.info', () {
    test('serverTimeOffset moves the server clock and is readable', () async {
      final RepoHarness h = RepoHarness();
      h.listen('O', '.info/serverTimeOffset');
      h.server.deliverServerTimeOffset(250);
      await settle();
      expect(h.log, <String>['O:V(250)']);
      expect(
        h.repo.serverTime(),
        DateTime.utc(2026).millisecondsSinceEpoch + 250,
      );
      expect(h.server.callsOf('listen'), isEmpty);
    });
  });
}
