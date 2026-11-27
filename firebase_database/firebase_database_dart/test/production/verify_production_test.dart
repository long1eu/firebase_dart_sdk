// Runs the production verification kit against the Database and Auth emulators, where the result
// of every check is known. Start them and run, from this package:
//
//     tool/start_database_emulator.sh 9130
//     AUTH_HUB_PORT=9498 AUTH_LOGGING_PORT=9598 tool/start_auth_emulators.sh 9398 9397
//     FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9130 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9398 \
//       dart test test/production
//
// The tests that need the emulators skip themselves when a variable is missing or nothing answers.
// With VERIFY_EXPECT_EMPTIED_NODE_FIX=1 the whole run passes --expect-emptied-node-fix and pins
// the results of a client with the emptied-node priority fix in checks 22 and 38; without it
// those results are not pinned (the trunk keeps the JS SDK's behaviour there).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'verify_production.dart';

/// Why the emulator tests are skipped, or null when both emulators answer.
Future<String?> _emulatorsMissing(String? database, String? auth) async {
  if (database == null || auth == null) {
    return '$emulatorHostVariable and $authEmulatorHostVariable must be set (see the header of '
        'this file).';
  }
  for (final String host in <String>[database, auth]) {
    try {
      await http
          .get(Uri.parse('http://$host/'))
          .timeout(const Duration(seconds: 3));
    } on Object {
      return 'Nothing answers at $host.';
    }
  }
  return null;
}

Future<void> main() async {
  final String? host = Platform.environment[emulatorHostVariable];
  final String? authHost = Platform.environment[authEmulatorHostVariable];
  final String? skip = await _emulatorsMissing(host, authHost);
  final bool expectFix =
      Platform.environment['VERIFY_EXPECT_EMPTIED_NODE_FIX'] == '1';
  final Map<String, String> environment = <String, String>{
    emulatorHostVariable: host ?? '',
    authEmulatorHostVariable: authHost ?? '',
  };

  /// The data at [path] of the kit's namespace, read as the emulator's owner.
  Future<Object?> ownerRead(String path, {bool shallow = false}) async {
    final http.Response response = await http.get(
      Uri.parse('http://$host/$path.json').replace(
        queryParameters: <String, String>{
          'ns': emulatorNamespace,
          if (shallow) 'shallow': 'true',
        },
      ),
      headers: const <String, String>{'Authorization': 'Bearer owner'},
    );
    expect(response.statusCode, 200, reason: response.body);
    return jsonDecode(response.body);
  }

  test(
    'every check has its known result on the emulator, and the run cleans up',
    () async {
      final StringBuffer out = StringBuffer();
      final KitRun run = await runKit(
        <String>[
          '--backend=emulator',
          '--create-user',
          if (expectFix) '--expect-emptied-node-fix',
        ],
        out: out,
        environment: environment,
      );
      final String report = out.toString();
      final Map<String, Status> actual = <String, Status>{
        for (final MapEntry<String, CheckResult> e in run.results.entries)
          e.key: e.value.status,
      };
      expect(actual, <String, Status>{
        for (final Check check in checks) check.id: Status.pass,
      }, reason: report);
      expect(run.exitCode, 0, reason: report);

      Map<String, Object?> observed(String id) => run.results[id]!.observed;
      // The emulator is plain ws and never names another host.
      expect(observed('1')['scheme'], 'http');
      expect(observed('1')['redirected'], isFalse);
      expect(observed('3')['maxSafeType'], 'int');
      // The emulator refuses the whole value in one set; each part alone is accepted.
      expect(observed('3')['oneSet'], startsWith('refused, unknown'));
      expect(observed('9')['warning'], isTrue);
      expect(observed('9')['get'], 'index-not-defined');
      expect(observed('10')['runs'], 2);
      expect(observed('15')['anonymousCode'], 'permission-denied');
      expect(
        observed('15')['anonymousStatus'],
        'permission_denied: Permission denied',
      );
      expect(observed('15')['deniedCode'], 'permission-denied');
      expect(observed('15')['userAccepted'], isTrue);
      expect(observed('16')['foreignCode'], 'permission-denied');
      expect(observed('17')['values'], <Object?>[null, 5, 'not-a-number', 5]);
      expect(observed('18')['dropped'], isFalse);
      expect(observed('19')['cancel'], 'permission-denied');
      expect(observed('19')['writeCode'], 'permission-denied');
      expect(observed('20')['cancel'], 'permission-denied');
      expect(observed('20')['getCode'], 'permission-denied');
      // The emulator keeps the priority of a node emptied by one write and refilled by the next.
      expect(observed('21')['exports'], <String>[
        '{".priority":0.0,"a":1}',
        '{".priority":0.0}',
        '{".priority":0.0,"b":1}',
      ]);
      expect(observed('22')['twoWrites'], 0);
      expect(observed('22')['oneUpdate'], 0);
      if (expectFix) {
        // The writer keeps the priority of the emptied node and shows it after the refill.
        expect(observed('22')['writer'], 0);
        // The same after one update, at 0 s and 5 s: the writer's listener and its get()
        // (deciding).
        expect(observed('22')['writerUpdateListener'], <Object?>[0, 0]);
        expect(observed('22')['writerUpdateGet'], <Object?>[0, 0]);
      } else {
        expect(
          report,
          contains('Informational (no --expect-emptied-node-fix)'),
        );
      }
      expect(observed('23')['listener'], isNull);
      expect(observed('23')['fresh'], isNull);
      // The questions of the core side (checks 27 to 36), as measured on the emulator.
      expect(observed('27')['line1Value'], isNull);
      expect(observed('27')['line1Priority'], isNull);
      expect(observed('27')['line1Export'], '{".priority":5.0}');
      expect(
        observed('27')['line2'],
        contains('could not set priority on non-existent node'),
      );
      expect(
        observed('27')['line3Export'],
        '{".value":"leaf",".priority":3.0}',
      );
      expect(
        observed('28')['4'],
        'd frames/q4 t=1 {"a":{"n":10},"b":{"n":20}}',
      );
      expect(observed('28')['6'], 'm frames/q6 t=3 {"c":{"n":33},"a":null}');
      expect(observed('28')['7'], 'd frames/q7/a/n t=4 5');
      expect(observed('28')['8'], 'NO FRAME');
      expect(observed('28')['10'], 'd frames/q10/aa t=7 {"n":0}');
      // An update below one window child alone. The emulator was measured here; production may
      // send another frame (the property test models this case as a merge at the query path).
      expect(observed('28')['alone'], 'm frames/qalone t=11 {"a/n":7}');
      expect(observed('29')['taggedFirst'], 5);
      expect(observed('30')['client12'], <String, Object?>{'a': 1});
      expect(observed('30')['client13'], 'leaf');
      expect(observed('30')['client14'], observed('30')['server14']);
      // Leaf B: a refused write below the leaf, then its removal; the client ends at the
      // server's 1.
      expect(observed('30')['codeB'], 'permission-denied');
      expect(observed('30')['removedB'], isNull);
      expect(observed('30')['eventsB'], <Object?>[
        1,
        <String, Object?>{'a': 1},
        null,
        1,
      ]);
      expect(observed('30')['serverB'], 1);
      expect(observed('30')['listenerB'], 1);
      expect(observed('30')['getB'], 1);
      expect(observed('30')['freshB'], 1);
      expect(observed('34')['value'], 200);
      expect(observed('35')['restStatus'], 400);
      expect(observed('36')['inOrder'], isTrue);
      expect(observed('36')['last'], 999);
      // Into the window: the entering child alone. Out of it: one merge with the child that
      // re-enters and the leaving child whole (not null).
      expect(observed('37')['initial'], <String>[
        'd frames/priority_window t=60 '
            '{"c1":{".priority":1.0,"n":1},"c2":{".priority":2.0,"n":2}}',
      ]);
      expect(observed('37')['into'], <String>[
        'd frames/priority_window/c4 t=60 {".priority":0,"n":4}',
      ]);
      expect(observed('37')['outOf'], <String>[
        'm frames/priority_window t=60 '
            '{"c2":{".priority":2.0,"n":2},"c4":{".priority":9,"n":4}}',
      ]);
      // Check 38, as measured on the emulator.
      expect(observed('38')['aListenN'], '{"s":"ok","d":{}}');
      expect(observed('38')['aFramesN'], <String>[
        'd emptied/p/n {".priority":5.0}',
      ]);
      expect(observed('38')['aGetN'], '{"s":"ok","d":{".priority":5.0}}');
      expect(observed('38')['aFramesP'], <String>[
        'd emptied/p {"n":{".priority":5.0}}',
      ]);
      expect(observed('38')['aGetP'], '{"s":"ok","d":{"n":{".priority":5.0}}}');
      expect(observed('38')['bUpdate'], 'accepted');
      expect(observed('38')['bUpdateExport'], '{".priority":7}');
      expect(observed('38')['bSetPriority'], 'accepted');
      expect(observed('38')['bSetPriorityExport'], '{".priority":9}');
      if (expectFix) {
        // The client keeps the server's priority of the emptied node: the second run commits.
        expect(observed('38')['cTransaction'], 'committed');
        expect(observed('38')['cRuns'], 2);
        expect(observed('38')['cWithinTwoRuns'], isTrue);
        expect(observed('38')['cTransactionExport'], '{"t":2}');
      }
      // A listen with the hash of the emptied node, and with the hash of the control {b: 1}: the
      // server sends no data for either (the hash matched).
      expect(observed('38')['cHashFrames'], isEmpty);
      expect(observed('38')['cControlFrames'], isEmpty);
      // With a hash that does not match, the server sends the data.
      expect(observed('38')['cWrongFrames'], <String>[
        'd emptied/c_control {"b":1}',
      ]);
      expect(observed('38')['dEmptiedExport'], '{".priority":5.0}');
      expect(observed('38')['dDeletedExport'], 'null');
      expect(observed('38')['dRefilledExport'], '{"b":1}');
      // An update {a: null, .priority: 7} on {a: 1} without priority removes the node here.
      expect(observed('38')['eExportBefore'], 'null');
      expect(observed('38')['eWithinTwoRuns'], isTrue);
      // The restart on the SQLite cache: both clients own the file, the transaction commits.
      expect(observed('38')['fDurable'], <bool>[true, true]);
      if (expectFix) {
        expect(observed('38')['fWithinTwoRuns'], isTrue);
      }
      // Check 39, raw frames on the emulator; production may differ.
      Map<String, Object?> rule(String id) =>
          observed('39')[id]! as Map<String, Object?>;
      expect(rule('q1_a')['export'], 'null');
      expect(rule('q1_ab')['export'], 'null');
      expect(rule('q1_control')['export'], '{".priority":7}');
      expect(rule('q2')['export'], '{".priority":9,"c":{".priority":3.0}}');
      // A put of only a priority gets no answer from the emulator.
      expect(rule('q3_missing')['answers'], <String>[
        '{"s":"NO ANSWER","d":"none within 20 s"}',
      ]);
      expect(rule('q3_emptied')['export'], '{".priority":5.0}');
      expect(rule('q4')['export'], '{".priority":7}');
      expect(rule('q6')['export'], 'null');
      expect(rule('q6_control')['export'], '{"x":{".priority":3}}');
      expect(rule('q7_missing')['answers'].toString(), contains('HTTP 400'));
      expect(rule('q7_parent')['answers'].toString(), contains('HTTP 400'));
      for (final String id in <String>[
        'q1_a',
        'q1_control',
        'q2',
        'q4',
        'q6_control',
      ]) {
        expect(rule(id)['accepted'], startsWith('as stored'), reason: id);
      }
      expect(rule('q5_without')['kind'], 'a range merge (rm)');
      expect(
        rule('q5_withPriority')['kind'],
        'a range merge with no range (rm [])',
      );
      expect(rule('q5_withEmpty')['kind'], 'a range merge (rm)');
      expect(rule('q5_keptH')['kind'], 'ok with no data');
      // Check 40, a null priority on a missing node. Every value pinned here was measured equal on
      // the emulator and on production. The d pushes are not pinned: the emulator pushes data null
      // at x/.priority to the listener at r in b1 to b5, production only in b4 and b5 (where the
      // write changed something).
      final Map<String, Object?> api =
          observed('40')['api']! as Map<String, Object?>;
      const String missingNode = 'could not set priority on non-existent node';
      for (final String id in <String>[
        'sp_null',
        'set_null_p3',
        'set_map_p3',
        'set_list_p3',
        'set_dot_p3',
        'set_value_null_p3',
        'set_value_map_p3',
        'set_dot_null',
        'sp_3',
      ]) {
        expect(api[id], <String, Object?>{
          'write': id == 'sp_3'
              ? 'failed: code unknown, serverStatus "invalid_parameters: $missingNode", '
                    'message "$missingNode"'
              : 'completed ok',
          'listenerBefore': <String>['null priority null'],
          'listenerAfter': <String>[],
          'listenerError': null,
          'get': 'null priority null',
          'freshGet': 'null priority null',
          'export': 'null',
        }, reason: id);
      }
      final Map<String, Object?> refusedAtCall =
          observed('40')['refused']! as Map<String, Object?>;
      expect(refusedAtCall, hasLength(5));
      expect(
        refusedAtCall["child('.priority').set(null)"],
        startsWith(
          'ArgumentError: Invalid argument(s): child failed: path argument was an invalid path',
        ),
      );
      expect(
        refusedAtCall['set(null, priority: true)'],
        startsWith(
          'ArgumentError: Invalid argument(s): set failed: priority argument must be a valid',
        ),
      );
      expect(
        refusedAtCall["set({'.priority': true})"],
        'ArgumentError: Invalid argument (priority): Invalid priority type found: bool: true',
      );
      expect(
        refusedAtCall["set({'.priority': {}})"],
        startsWith(
          'ArgumentError: Invalid argument (priority): Invalid priority type found: _Map',
        ),
      );
      expect(
        refusedAtCall["set({'.value': null, '.priority': 3, 'a': null})"],
        allOf(
          startsWith(
            'ArgumentError: Invalid argument(s): set failed: value argument',
          ),
          contains('contains ".value" child'),
        ),
      );
      final Map<String, Object?> raw =
          observed('40')['raw']! as Map<String, Object?>;
      const String ok = '{"s":"ok","d":""}';
      const String k1 = '{"k":1}';
      const String k1x = '{"k":1,"x":{"v":1}}';
      // Per case: the request number, the data put at r/x/.priority, the answer, the g of r, the
      // export of r.
      final Map<String, (int, Object?, String, String, String)> rawCases =
          <String, (int, Object?, String, String, String)>{
            'b1': (3, null, ok, 'null', 'null'),
            'b2': (8, null, ok, k1, k1),
            'b3': (13, null, ok, k1x, k1x),
            'b4': (18, null, ok, k1x, k1x),
            'b5': (24, null, ok, k1, k1),
            'b6': (
              29,
              3,
              '{"s":"invalid_parameters","d":"$missingNode"}',
              k1,
              k1,
            ),
          };
      for (final MapEntry<String, (int, Object?, String, String, String)> e
          in rawCases.entries) {
        final (int r, Object? data, String answer, String g, String export) =
            e.value;
        expect(raw[e.key], <String, Object?>{
          'sent':
              '{"t":"d","d":{"r":$r,"a":"p","b":{"p":"/<run>/null_priority/raw/'
              '${e.key}/x/.priority","d":${jsonEncode(data)}}}}',
          'answer': answer,
          'g': '{"s":"ok","d":$g}',
          'export': export,
        }, reason: e.key);
      }
      expect(raw['after'], ok);

      final String runId = run.runPath!.split('/').last;
      expect(run.removed, hasLength(2));
      expect(await ownerRead(run.runPath!), isNull);
      expect(await ownerRead(run.removed.last), isNull);
      expect(await ownerRead('$deniedRoot/$runId'), isNull);
      expect(report, contains('The throwaway user was deleted.'));
      expect(report, isNot(contains('FAILED')));
      // The Auth emulator answers a GET of /emulator/v1/.../accounts with "Method GET not
      // allowed"; accounts:query as the owner lists the users.
      final http.Response accounts = await http.post(
        Uri.parse(
          'http://$authHost/identitytoolkit.googleapis.com/v1/projects/demo-test/accounts:query',
        ),
        headers: const <String, String>{
          'Authorization': 'Bearer owner',
          'Content-Type': 'application/json',
        },
        body: '{}',
      );
      expect(accounts.statusCode, 200, reason: accounts.body);
      expect(accounts.body, isNot(contains('database-verify-$runId')));
    },
    skip: skip,
    // The whole run measured 6 minutes on the emulator (README, "Time").
    timeout: const Timeout(Duration(minutes: 12)),
  );

  test('without a user only checks 15 and 20 run', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--only=2,15,20'],
      out: out,
      environment: environment,
    );
    final String report = out.toString();
    expect(run.results['2']!.status, Status.skipped, reason: report);
    expect(run.results['15']!.status, Status.pass, reason: report);
    expect(run.results['15']!.observed['userAccepted'], isFalse);
    expect(run.results['20']!.status, Status.pass, reason: report);
    expect(run.exitCode, 0);
    expect(await ownerRead(run.runPath!), isNull);
  }, skip: skip);

  test('--keep leaves the data of the run in place', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--create-user', '--keep', '--only=6'],
      out: out,
      environment: environment,
    );
    expect(run.results['6']!.status, Status.pass, reason: out.toString());
    expect(out.toString(), contains('--keep'));
    expect(run.removed, isEmpty);
    final Object? left = await ownerRead(run.runPath!, shallow: true);
    expect(left, <String, Object?>{'preflight': true, 'pushed': true});
    final http.Response removed = await http.delete(
      Uri.parse(
        'http://$host/${run.runPath}.json',
      ).replace(queryParameters: <String, String>{'ns': emulatorNamespace}),
      headers: const <String, String>{'Authorization': 'Bearer owner'},
    );
    expect(removed.statusCode, 200);
  }, skip: skip);

  test('rules.json holds the rules the kit installs on the emulator', () {
    final File file = File('../../tool/verify_production_database/rules.json');
    expect(jsonDecode(file.readAsStringSync()), kitRules);
  });

  test('the README shows the same rules as rules.json', () {
    final String readme = File(
      '../../tool/verify_production_database/README.md',
    ).readAsStringSync();
    final RegExpMatch? block = RegExp(
      r'```json\n([\s\S]*?)\n```',
    ).firstMatch(readme);
    expect(block, isNotNull);
    expect(jsonDecode(block!.group(1)!), kitRules);
  });

  test(
    'a stop signal abandons the check, cleans up, deletes the user and exits 130',
    () async {
      final StringBuffer out = StringBuffer();
      final KitRun run = await runKit(
        <String>['--backend=emulator', '--create-user', '--only=28,36'],
        out: out,
        environment: environment,
        stop: Future<void>.delayed(const Duration(seconds: 4)),
      );
      final String report = out.toString();
      expect(run.exitCode, 130, reason: report);
      expect(run.results['28']!.summary, 'Stopped by a signal.');
      expect(run.results.containsKey('36'), isFalse);
      expect(report, contains('waiting 60 s'));
      expect(await ownerRead(run.runPath!), isNull);
      expect(report, contains('The throwaway user was deleted.'));
      final String runId = run.runPath!.split('/').last;
      final http.Response accounts = await http.get(
        Uri.parse('http://$authHost/emulator/v1/projects/demo-test/accounts'),
        headers: const <String, String>{'Authorization': 'Bearer owner'},
      );
      expect(accounts.body, isNot(contains('database-verify-$runId')));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'production refuses a database URL with a query other than ns',
    () async {
      final StringBuffer out = StringBuffer();
      final KitRun run = await runKit(
        <String>['--backend=production', '--yes'],
        out: out,
        environment: <String, String>{
          projectVariable: 'my-project',
          databaseUrlVariable:
              'https://my-project-default-rtdb.firebaseio.com?auth=secret',
        },
      );
      expect(run.exitCode, 2);
      expect(out.toString(), isNot(contains('secret')));
    },
  );

  test('--list names every check with its scope', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--list'],
      out: out,
      environment: <String, String>{},
    );
    expect(run.exitCode, 0);
    final List<String> lines = const LineSplitter().convert(out.toString());
    expect(lines, hasLength(checks.length));
    expect(lines.first, contains('production only'));
  });

  test('production without --yes prints the plan and does nothing', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=production', '--create-user'],
      out: out,
      environment: <String, String>{
        projectVariable: 'my-project',
        databaseUrlVariable: 'https://my-project-default-rtdb.firebaseio.com',
        webApiKeyVariable: 'not-a-real-key',
      },
    );
    expect(run.exitCode, 2);
    expect(run.results, isEmpty);
    final String report = out.toString();
    expect(report, contains('my-project'));
    expect(report, contains('https://my-project-default-rtdb.firebaseio.com'));
    expect(report, contains('$kitRoot/run_'));
    expect(report, contains('Nothing was done'));
    expect(report, isNot(contains('not-a-real-key')));
  });

  test('production refuses to guess when an emulator is configured', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=production', '--yes'],
      out: out,
      environment: <String, String>{
        emulatorHostVariable: '127.0.0.1:1',
        projectVariable: 'my-project',
        databaseUrlVariable: 'https://my-project-default-rtdb.firebaseio.com',
      },
    );
    expect(run.exitCode, 2);
    expect(out.toString(), contains('$emulatorHostVariable is set'));
  });

  test('production needs the database URL, over https', () async {
    for (final Map<String, String> env in <Map<String, String>>[
      <String, String>{projectVariable: 'my-project'},
      <String, String>{
        projectVariable: 'my-project',
        databaseUrlVariable: 'http://my-project-default-rtdb.firebaseio.com',
      },
    ]) {
      final KitRun run = await runKit(
        <String>['--backend=production', '--yes'],
        out: StringBuffer(),
        environment: env,
      );
      expect(run.exitCode, 2);
      expect(run.results, isEmpty);
    }
  });

  test('--create-user needs the API key in production', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=production', '--create-user', '--yes'],
      out: out,
      environment: <String, String>{
        projectVariable: 'my-project',
        databaseUrlVariable: 'https://my-project-default-rtdb.firebaseio.com',
      },
    );
    expect(run.exitCode, 2);
    expect(out.toString(), contains(webApiKeyVariable));
  });

  test('--create-user on the emulator needs the Auth emulator', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--create-user'],
      out: out,
      environment: <String, String>{emulatorHostVariable: '127.0.0.1:1'},
    );
    expect(run.exitCode, 2);
    expect(out.toString(), contains(authEmulatorHostVariable));
  });

  test('an unknown flag prints the usage and exits 64', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--nonsense'],
      out: out,
      environment: <String, String>{emulatorHostVariable: '127.0.0.1:1'},
    );
    expect(run.exitCode, 64);
    expect(out.toString(), contains('--nonsense'));
    expect(out.toString(), contains('--database-url'));
  });

  test('an unknown check id is a usage error', () async {
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--only=1,99'],
      out: StringBuffer(),
      environment: <String, String>{emulatorHostVariable: '127.0.0.1:1'},
    );
    expect(run.exitCode, 2);
  });

  test('--help prints the usage and exits 0', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--help'],
      out: out,
      environment: <String, String>{},
    );
    expect(run.exitCode, 0);
    expect(out.toString(), contains('--create-user'));
    expect(out.toString(), contains('--keep'));
  });

  // The Auth emulator never answers requires-recent-login (its accounts:delete does not look at
  // the sign-in time), so the order of the calls is tested here without a server.
  group('deleteThrowawayUser', () {
    const FirebaseAuthException stale = FirebaseAuthException(
      code: 'requires-recent-login',
      message: 'the sign-in is too old',
    );

    test('signs in again, then deletes', () async {
      final List<String> calls = <String>[];
      final StringBuffer out = StringBuffer();
      final bool deleted = await deleteThrowawayUser(
        out,
        uid: 'u1',
        signIn: () async => calls.add('sign in'),
        delete: () async => calls.add('delete'),
      );
      expect(calls, <String>['sign in', 'delete']);
      expect(deleted, isTrue);
      expect(out.toString(), 'The throwaway user was deleted.\n');
    });

    test('a refused deletion keeps the message', () async {
      final List<String> calls = <String>[];
      final StringBuffer out = StringBuffer();
      final bool deleted = await deleteThrowawayUser(
        out,
        uid: 'u1',
        signIn: () async => calls.add('sign in'),
        delete: () async {
          calls.add('delete');
          throw stale;
        },
      );
      expect(calls, <String>['sign in', 'delete']);
      expect(deleted, isFalse);
      expect(
        out.toString(),
        'Deleting the throwaway user FAILED: auth requires-recent-login. Delete the user with '
        'uid u1 by hand (Authentication > Users in the console).\n',
      );
    });

    test('a failed sign-in does not delete and keeps the message', () async {
      final List<String> calls = <String>[];
      final StringBuffer out = StringBuffer();
      final bool deleted = await deleteThrowawayUser(
        out,
        uid: 'u1',
        signIn: () async {
          calls.add('sign in');
          throw const FirebaseAuthException(
            code: 'network-request-failed',
            message: 'offline',
          );
        },
        delete: () async => calls.add('delete'),
      );
      expect(calls, <String>['sign in']);
      expect(deleted, isFalse);
      expect(
        out.toString(),
        startsWith(
          'Deleting the throwaway user FAILED: auth network-request-failed. ',
        ),
      );
    });
  });
}
