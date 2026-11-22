// Owner U. The connection half alone (PersistentConnection over the io connector) against the
// Database emulator. Every expectation is what rtdb_emulator_probe.md measured; the section is
// named in each test. Run with FIREBASE_DATABASE_EMULATOR_HOST set (see emulator_rig.dart).
@Tags(<String>['emulator'])
@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/emulator_token.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';
import 'emulator_rig.dart';

/// The JS leaf hash of a string (probe "Listen details": `sha1('string:'+value)`, base64,
/// matches the emulator exactly).
String stringLeafHash(String value) =>
    base64Encode(sha1.convert(utf8.encode('string:$value')).bytes);

void main() {
  group('connection against the emulator', skip: emulatorSkipReason, () {
    test('a default listen gets the data, then ok, then a child write '
        '(probe "Envelope and requests", row q)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.write('/a', <String, Object?>{'x': 1});
      final RigClient client = await rig.open();
      final List<Ack> acks = client.listen(defaultSpec('/a'));
      final Ack ack = await client.first(acks);
      expect(ack.status, statusOk);
      final DelegateCall initial = client.updatesAt('/a').single;
      expect(initial.data, <String, Object?>{'x': 1});
      expect(initial.isMerge, isFalse);
      expect(initial.tag, isNull);
      expect(
        client.delegate.calls.indexOf(initial),
        lessThan(ack.callsBefore),
        reason: 'the push comes before the ok',
      );
      await rig.write('/a/y', 2);
      final DelegateCall child = await client.update(
        (DelegateCall c) => c.path == '/a/y',
      );
      expect(child.data, 2);
      expect(child.isMerge, isFalse);
    });

    test('a listen on an empty path is answered ok with no push '
        '(probe "Envelope and requests", row q)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final RigClient client = await rig.open();
      final Ack ack = await client.first(client.listen(defaultSpec('/empty')));
      expect(ack.status, statusOk);
      expect(client.updatesAt('/empty'), isEmpty);
    });

    test(
      'a tagged limit listen gets the changed child only, with its tag '
      '(probe "Listen details": limit queries get the child that changed)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        await rig.write('/people', <String, Object?>{'a': 1, 'b': 2, 'c': 3});
        final RigClient client = await rig.open();
        final List<Ack> acks = client.listen(
          keyLimitSpec('/people', 1),
          tag: 1,
        );
        expect((await client.first(acks)).status, statusOk);
        final DelegateCall initial = client.updatesAt('/people').single;
        expect(initial.tag, 1);
        expect((initial.data! as Map<String, Object?>).keys, contains('a'));
        final int before = client.delegate.calls.length;
        await rig.write('/people/0', 1);
        final DelegateCall changed = await client.update(
          (DelegateCall c) => c.path == '/people/0',
          from: before,
        );
        expect(changed.data, 1);
        expect(changed.tag, 1);
        expect(changed.isMerge, isFalse);
        expect(
          client.delegate.calls
              .skip(before)
              .where(
                (DelegateCall c) =>
                    c.method == 'dataUpdate' && c.path != '/people/0',
              ),
          isEmpty,
          reason: 'no push for the child that left the window (probe item 14)',
        );
      },
    );

    test('put and merge: the listener push comes before the ack '
        '(probe "Envelope and requests", rows p and m)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final RigClient client = await rig.open();
      expect(
        (await client.first(client.listen(defaultSpec('/w')))).status,
        statusOk,
      );

      final Ack put = await client.put('/w/a', <String, Object?>{'x': 1});
      expect(put.status, statusOk);
      final DelegateCall putPush = client.updatesAt('/w/a').single;
      expect(putPush.data, <String, Object?>{'x': 1});
      expect(putPush.isMerge, isFalse);
      expect(client.delegate.calls.indexOf(putPush), lessThan(put.callsBefore));

      final (RequestResultCallback callback, List<Ack> acks) = client
          .recorder();
      client.connection.merge('/w/a', <String, Object?>{
        'x': 5,
        'w': 6,
      }, onComplete: callback);
      final Ack merge = await client.first(acks);
      expect(merge.status, statusOk);
      final DelegateCall mergePush = client
          .updatesAt('/w/a')
          .lastWhere((DelegateCall c) => c.isMerge!);
      expect(mergePush.data, <String, Object?>{'x': 5, 'w': 6});
      expect(
        client.delegate.calls.indexOf(mergePush),
        lessThan(merge.callsBefore),
      );
      expect(await rig.read('/w/a'), <String, Object?>{'x': 5, 'w': 6});
    });

    test(
      'get: present, absent (null) and forbidden (permission_denied) '
      '(probe "Envelope and requests", row g; "Auth": denied operations)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        await rig.setRules(<String, Object?>{
          'open': <String, Object?>{'.read': true},
          'closed': <String, Object?>{'.read': false},
        });
        await rig.write('/open/v', <String, Object?>{'w': 6, 'x': 5});
        await rig.write('/closed/v', 1);
        final RigClient client = await rig.open();
        expect(
          await client.connection.get(defaultSpec('/open/v')),
          <String, Object?>{'w': 6, 'x': 5},
        );
        expect(await client.connection.get(defaultSpec('/open/none')), isNull);
        await expectLater(
          client.connection.get(defaultSpec('/closed/v')),
          throwsA(
            isA<ServerActionsException>().having(
              (ServerActionsException e) => e.status,
              'status',
              'permission_denied',
            ),
          ),
        );
      },
    );

    test('onDisconnect put, merge and cancel apply when the first client '
        'closes, seen by a second one as a single merge '
        '(probe "onDisconnect")', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.write('/od', <String, Object?>{'keep': 1, 'cancelme': 'stay'});
      final RigClient leaving = await rig.open();
      final RigClient watcher = await rig.open();
      expect(
        (await watcher.first(watcher.listen(defaultSpec('/od')))).status,
        statusOk,
      );

      final List<Ack> acks = <Ack>[];
      void record(String status, Object? data) =>
          acks.add((status: status, data: data, callsBefore: 0));
      leaving.connection
        ..onDisconnectPut('/od/p', 'gone', onComplete: record)
        ..onDisconnectMerge('/od', <String, Object?>{
          'm/a': 1,
          'm/b': 2,
        }, onComplete: record)
        ..onDisconnectPut('/od/cancelme', 'x', onComplete: record)
        ..onDisconnectCancel('/od/cancelme', onComplete: record);
      await eventually(
        () => acks.length == 4 ? true : null,
        what: '4 onDisconnect acks',
      );
      expect(acks.map((Ack a) => a.status), everyElement(statusOk));

      final int before = watcher.delegate.calls.length;
      await leaving.connection.shutdown();
      final DelegateCall merge = await watcher.update(
        (DelegateCall c) => c.path == '/od' && c.isMerge!,
        from: before,
      );
      final Map<String, Object?> data = merge.data! as Map<String, Object?>;
      expect(data['p'], 'gone');
      expect(
        data['m/a'],
        1,
        reason: 'merge keys arrive as paths (probe item 13)',
      );
      expect(data['m/b'], 2);
      expect(data.containsKey('cancelme'), isFalse);
      expect(await rig.read('/od'), <String, Object?>{
        'keep': 1,
        'cancelme': 'stay',
        'p': 'gone',
        'm': <String, Object?>{'a': 1, 'b': 2},
      });
      expect(
        watcher.delegate.calls
            .skip(before)
            .where((DelegateCall c) => c.method == 'dataUpdate'),
        hasLength(1),
        reason: 'one merge push for all the onDisconnect writes',
      );
    });

    test('auth with an unsigned mock token: ok, then rules on auth.uid; a put '
        'refused by the rules is permission_denied (probe "Auth"; addendum 2 '
        'item 14: iat 0 is accepted)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.setRules(<String, Object?>{
        'users': <String, Object?>{
          r'$uid': <String, Object?>{
            '.read': r'auth != null && auth.uid == $uid',
            '.write': r'auth != null && auth.uid == $uid',
          },
        },
      });
      final RigClient client = await rig.open(
        tokens: FakeTokenSource(
          auth: createMockUserToken(<String, Object?>{
            'sub': 'u1',
          }, projectId: emulatorProjectId),
        ),
      );
      final DelegateCall auth = await eventually(
        () => client.delegate.callsOf('authStatus').firstOrNull,
        what: 'the auth answer',
      );
      expect(auth.status, statusOk);
      expect((await client.put('/users/u1/x', 1)).status, statusOk);
      expect(await client.connection.get(defaultSpec('/users/u1/x')), 1);
      expect((await client.put('/users/u2/x', 1)).status, 'permission_denied');
      expect(await rig.read('/users/u2'), isNull);
    });

    test('a signed-out client is refused by an auth rule (probe "Auth": '
        'denied operations)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.setRules(<String, Object?>{
        '.read': 'auth != null',
        '.write': 'auth != null',
      });
      final RigClient client = await rig.open();
      expect((await client.put('/x', 1)).status, 'permission_denied');
    });

    test('a put the rules refuse (validation) is permission_denied and writes '
        'nothing (probe "Auth": newData.isString())', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.setRules(<String, Object?>{
        '.read': true,
        's': <String, Object?>{'.write': 'newData.isString()'},
      });
      final RigClient client = await rig.open();
      expect((await client.put('/s', 5)).status, 'permission_denied');
      expect(await rig.read('/s'), isNull);
      expect((await client.put('/s', 'ok')).status, statusOk);
    });

    test('a rules change cancels the default and the tagged listen at the path '
        '(probe "Listen revoked after a rules change")', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.setRules(<String, Object?>{'.read': true, '.write': true});
      await rig.write('/d', <String, Object?>{'a': 1, 'b': 2});
      final RigClient client = await rig.open();
      final List<Ack> plain = client.listen(defaultSpec('/d'));
      final List<Ack> tagged = client.listen(keyLimitSpec('/d', 1), tag: 9);
      expect((await client.first(plain)).status, statusOk);
      expect((await client.first(tagged)).status, statusOk);
      await rig.setRules(<String, Object?>{'.read': false, '.write': true});
      await eventually(
        () => plain.length == 2 && tagged.length == 2 ? true : null,
        what: 'both listens cancelled',
      );
      expect(plain.last.status, 'permission_denied');
      expect(tagged.last.status, 'permission_denied');
      await expectLater(
        client.connection.get(defaultSpec('/d')),
        throwsA(isA<ServerActionsException>()),
      );
    });

    test('a listen with the correct hash gets ok and no data; a wrong hash '
        'gets the data (probe addendum C)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.write('/h', 'hello');
      await rig.write('/g', 'hello');
      final RigClient client = await rig.open();
      final Ack same = await client.first(
        client.listen(defaultSpec('/h'), hash: stringLeafHash('hello')),
      );
      expect(same.status, statusOk);
      expect(client.updatesAt('/h'), isEmpty);
      final Ack wrong = await client.first(
        client.listen(defaultSpec('/g'), hash: 'AAAA'),
      );
      expect(wrong.status, statusOk);
      expect(client.updatesAt('/g').single.data, 'hello');
    });

    test('server values: the timestamp arrives resolved near now, increment '
        'adds (probe "Server values": increment 3 then 6)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final RigClient client = await rig.open();
      expect(
        (await client.first(client.listen(defaultSpec('/sv')))).status,
        statusOk,
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      expect(
        (await client.put('/sv/ts', <String, Object?>{
          '.sv': 'timestamp',
        })).status,
        statusOk,
      );
      final Object? ts = client.updatesAt('/sv/ts').single.data;
      expect(ts, isA<int>());
      expect(((ts! as int) - now).abs(), lessThan(5000));
      const Map<String, Object?> increment = <String, Object?>{
        '.sv': <String, Object?>{'increment': 3},
      };
      expect((await client.put('/sv/n', increment)).status, statusOk);
      expect((await client.put('/sv/n', increment)).status, statusOk);
      expect(
        client.updatesAt('/sv/n').map((DelegateCall c) => c.data),
        <Object?>[3, 6],
      );
    });

    test('numbers arrive unchanged: 1.0, 2^53+1, int64 max, -0.0 (probe '
        'addendum A)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final RigClient client = await rig.open();
      expect(
        (await client.first(client.listen(defaultSpec('/n')))).status,
        statusOk,
      );
      final Map<String, Object?> numbers = <String, Object?>{
        'one': 1.0,
        'big': 9007199254740993,
        'max': 9223372036854775807,
        'negzero': -0.0,
      };
      for (final MapEntry<String, Object?> entry in numbers.entries) {
        expect(
          (await client.put('/n/${entry.key}', entry.value)).status,
          statusOk,
        );
      }
      for (final String key in numbers.keys) {
        final Object? pushed = client.updatesAt('/n/$key').single.data;
        final Object? got = await client.connection.get(defaultSpec('/n/$key'));
        for (final Object? value in <Object?>[pushed, got]) {
          _expectSameNumber(value, numbers[key], key);
        }
      }
      expect(await rig.readRaw('/n/one'), '1.0');
      expect(await rig.readRaw('/n/big'), '9007199254740993');
      expect(await rig.readRaw('/n/max'), '9223372036854775807');
      expect(await rig.readRaw('/n/negzero'), '-0.0');
    });

    test('a 1 MiB string is written and read back (probe "Frame and message '
        'limits": 100 KB in 7 frames, 5 MB in 308)', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final RigClient client = await rig.open();
      final String big = 'x' * (1024 * 1024);
      expect((await client.put('/big', big)).status, statusOk);
      expect(await client.connection.get(defaultSpec('/big')), big);
    });

    test(
      'emoji across a frame boundary at either parity arrive intact (probe '
      'addendum 2 item 5: a cut inside a pair corrupts, inside UTF-8 drops)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        final RigClient client = await rig.open();
        final String even = '\u{1F600}' * 9000;
        final String odd = 'a$even';
        expect((await client.put('/e/even', even)).status, statusOk);
        expect((await client.put('/e/odd', odd)).status, statusOk);
        expect(await rig.read('/e/even'), even);
        expect(await rig.read('/e/odd'), odd);
        expect(await client.connection.get(defaultSpec('/e/odd')), odd);
      },
    );
  });
}

void _expectSameNumber(Object? actual, Object? expected, String key) {
  expect(actual.runtimeType, expected.runtimeType, reason: '$key type');
  expect(actual, expected, reason: key);
  if (expected is double) {
    expect(
      (actual! as double).isNegative,
      expected.isNegative,
      reason: '$key sign',
    );
  }
}
