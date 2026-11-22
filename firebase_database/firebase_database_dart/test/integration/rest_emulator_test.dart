// Owner U. The read-only REST client alone against the Database emulator. Expectations are what
// rtdb_emulator_probe.md measured ("REST", "Auth on REST"); the section is named in each test.
@Tags(<String>['emulator'])
@TestOn('vm')
library;

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/emulator_token.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';
import 'emulator_rig.dart';

void main() {
  group('REST client against the emulator', skip: emulatorSkipReason, () {
    test(
      'get: present, absent (null), forbidden (401 -> permission_denied) '
      '(probe "Read, write, query"; "Auth on REST": denied is 401)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        await rig.setRules(<String, Object?>{
          'open': <String, Object?>{'.read': true},
          'closed': <String, Object?>{'.read': false},
        });
        await rig.write('/open/v', <String, Object?>{'x': 1});
        await rig.write('/closed/v', 1);
        final RestRigClient rest = rig.openRest();
        expect(await rest.client.get(defaultSpec('/open/v')), <String, Object?>{
          'x': 1,
        });
        expect(await rest.client.get(defaultSpec('/open/none')), isNull);
        await expectLater(
          rest.client.get(defaultSpec('/closed/v')),
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

    test(
      'auth= with a mock token applies the rules on auth.uid (probe "Auth on '
      'REST": sub becomes auth.uid)',
      () async {
        final EmulatorRig rig = EmulatorRig.create();
        await rig.setRules(<String, Object?>{
          'users': <String, Object?>{
            r'$uid': <String, Object?>{
              '.read': r'auth != null && auth.uid == $uid',
            },
          },
        });
        await rig.write('/users/u1', 'mine');
        await rig.write('/users/u2', 'theirs');
        final RestRigClient rest = rig.openRest(
          tokens: FakeTokenSource(
            auth: createMockUserToken(<String, Object?>{
              'sub': 'u1',
            }, projectId: emulatorProjectId),
          ),
        );
        expect(await rest.client.get(defaultSpec('/users/u1')), 'mine');
        await expectLater(
          rest.client.get(defaultSpec('/users/u2')),
          throwsA(isA<ServerActionsException>()),
        );
      },
    );

    test('a listen is a GET, then the data at /a/b, then ok', () async {
      final EmulatorRig rig = EmulatorRig.create();
      await rig.write('/a/b', <String, Object?>{'c': 1});
      final RestRigClient rest = rig.openRest();
      final List<String> statuses = <String>[];
      rest.client.listen(
        defaultSpec('/a/b'),
        hashProvider: const FixedHash(),
        onComplete: (String status, Object? data) => statuses.add(status),
      );
      await eventually(
        () => statuses.isEmpty ? null : true,
        what: 'the listen answer',
      );
      expect(statuses, <String>[statusOk]);
      final DelegateCall update = rest.delegate.callsOf('dataUpdate').single;
      expect(update.path, '/a/b');
      expect(update.data, <String, Object?>{'c': 1});
    });

    test('writes complete with read_only and change nothing', () async {
      final EmulatorRig rig = EmulatorRig.create();
      final RestRigClient rest = rig.openRest();
      final List<String> statuses = <String>[];
      rest.client.put(
        '/w',
        1,
        onComplete: (String status, Object? data) => statuses.add(status),
      );
      await eventually(
        () => statuses.isEmpty ? null : true,
        what: 'the put answer',
      );
      expect(statuses, <String>[statusReadOnly]);
      expect(await rig.read('/w'), isNull);
    });
  });
}
