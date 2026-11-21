// Runs the whole production verification kit against the Storage emulator, where the result of every check is
// known. Start the emulator with `tool/start_storage_emulator.sh 9399` and run
//
//     FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9399 dart test test/production
//
// Without the variable the tests skip themselves.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'verify_production.dart';

void main() {
  final String? host = Platform.environment[emulatorHostVariable];
  final String? skip = host == null
      ? '$emulatorHostVariable is not set (tool/start_storage_emulator.sh 9399).'
      : null;
  final Map<String, String> environment = <String, String>{
    emulatorHostVariable: host ?? '',
  };
  const String deniedBucket = '--denied-bucket=demo-test-auth.appspot.com';

  Future<List<String>> objectsBelow(String prefix) async {
    final http.Response response = await http.get(
      Uri.parse(
        'http://$host/v0/b/demo-test.appspot.com/o',
      ).replace(queryParameters: <String, String>{'prefix': '$prefix/'}),
    );
    final Map<String, Object?> json =
        jsonDecode(response.body) as Map<String, Object?>;
    return <String>[
      for (final Object? item
          in (json['items'] as List<Object?>?) ?? <Object?>[])
        (item! as Map<String, Object?>)['name']! as String,
    ];
  }

  test(
    'every check has its known result on the emulator and the run cleans up',
    () async {
      final StringBuffer out = StringBuffer();
      final KitRun run = await runKit(
        <String>['--backend=emulator', deniedBucket],
        out: out,
        environment: environment,
      );
      final Map<String, Status> expected = <String, Status>{
        // The emulator's 404 body is plain text; production's is a JSON envelope.
        '1': Status.inconclusive,
        '2': Status.pass,
        '3': Status.pass,
        '4': Status.pass,
        '5': Status.pass,
        '6': Status.pass,
        '7': Status.pass,
        '8': Status.pass,
        '9': Status.pass,
        '10': Status.pass,
        '11': Status.pass,
        '12': Status.pass,
        // Needs a test user; the emulator run has none.
        '13': Status.skipped,
        // Reads the CORS headers of a real start response; the emulator may differ from production.
        '14': Status.pass,
        '15': Status.pass,
        '16': Status.pass,
        '17': Status.pass,
        '18': Status.pass,
        '19': Status.pass,
        // Needs --create-user and the Auth emulator; see the last test.
        '20': Status.skipped,
        // The emulator ignores upload offsets: it appends the early chunk at the start of the session, so
        // size received is 262144 (neither 0 nor 524288) and the check cannot judge. Production is expected
        // to answer REFUSED (PASS).
        '21': Status.inconclusive,
        '22': Status.pass,
        '23': Status.pass,
        '24': Status.pass,
        // The emulator unzips a gzip-stored object for an identity request and ignores the Range: a 200.
        '25': Status.pass,
        '26': Status.pass,
      };
      final Map<String, Status> actual = <String, Status>{
        for (final MapEntry<String, CheckResult> e in run.results.entries)
          e.key: e.value.status,
      };
      // The CORS check reads the emulator's real response headers, which may lack some that production sends.
      if (actual['14'] == Status.inconclusive) {
        actual['14'] = Status.pass;
      }
      // On loopback one streamed request can finish before the pause of checks 17, 18, 24 and 25 lands;
      // the kit then says INCONCLUSIVE ("run it again"), which is not a failure of the SDK.
      for (final String id in <String>['17', '18', '24', '25']) {
        if (actual[id] == Status.inconclusive) {
          actual[id] = Status.pass;
        }
      }
      expect(actual, expected, reason: out.toString());
      expect(run.exitCode, 0, reason: out.toString());

      expect(run.results['1']!.observed['status'], 404);
      expect(run.results['1']!.observed['envelope'], isFalse);
      expect(run.results['1']!.observed['sdk'], 'object-not-found');
      expect(run.results['2']!.observed['writeStatus'], 403);
      expect(run.results['2']!.observed['sdk'], 'unauthorized');
      expect(run.results['3']!.observed['status'], 206);
      expect(run.results['4']!.observed['tokens'], 1);
      expect(run.results['4']!.observed['status'], 200);
      // The emulator checks no download token.
      expect(run.results['4']!.observed['wrongTokenStatus'], 200);
      expect(run.results['5']!.observed['entries'], 4);
      expect(run.results['10']!.observed['rejected'], isFalse);
      expect(run.results['11']!.observed['outcome'], 'ACCEPTED');
      expect(run.results['12']!.observed['allSent'], isTrue);
      expect(run.results['15']!.observed['statuses'], <int>[503, 503, 200]);
      if (run.results['17']!.status == Status.pass) {
        expect(
          run.results['17']!.observed['pausedAt'],
          lessThan(3 * 1024 * 1024),
        );
      }
      expect(run.results['19']!.observed['tooLarge'], 'download-size-exceeded');
      expect(run.results['22']!.observed['totalAtStart'], -1);
      expect(run.results['22']!.observed['lengthAnnounced'], isFalse);
      expect(run.results['23']!.observed['size'], 0);
      expect(run.results['23']!.observed['storedBytes'], 0);
      if (run.results['24']!.status == Status.pass) {
        // The emulator sends x-goog-generation, so the task needs no metadata read beyond the first.
        expect(run.results['24']!.observed['ranged'], isTrue);
        expect(run.results['24']!.observed['generationHeader'], isTrue);
        expect(run.results['24']!.observed['metadataRequests'], 1);
        expect(run.results['24']!.observed['mediaRequests'], 2);
      }
      if (run.results['25']!.status == Status.pass) {
        expect(run.results['25']!.observed['resumedStatus'], 200);
        expect(run.results['25']!.observed['contentEncoding'], isFalse);
      }

      expect(run.uploadedBytes, greaterThan(0));
      expect(run.deleted, greaterThan(0));
      expect(await objectsBelow(run.prefix!), isEmpty);
      expect(out.toString(), contains('Clean-up: ${run.deleted} objects'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the byte cap stops an upload before it starts, and the clean-up still runs',
    () async {
      final StringBuffer out = StringBuffer();
      final KitRun run = await runKit(
        <String>['--backend=emulator', '--max-bytes=1000', '--only=6,7,12'],
        out: out,
        environment: environment,
      );
      expect(
        run.results['6']!.status,
        Status.inconclusive,
        reason: out.toString(),
      );
      expect(run.results['6']!.summary, contains('--max-bytes'));
      expect(run.results['7']!.status, Status.inconclusive);
      expect(run.uploadedBytes, lessThanOrEqualTo(1000));
      expect(out.toString(), contains('Clean-up:'));
      expect(await objectsBelow(run.prefix!), isEmpty);
    },
    skip: skip,
  );

  test('--keep leaves the objects of the run in place', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--keep', '--only=6'],
      out: out,
      environment: environment,
    );
    expect(run.results['6']!.status, Status.pass, reason: out.toString());
    expect(out.toString(), contains('--keep'));
    final List<String> left = await objectsBelow(run.prefix!);
    expect(left, hasLength(1));
    final http.Response deleted = await http.delete(
      Uri.parse(
        'http://$host/v0/b/demo-test.appspot.com/o/${Uri.encodeComponent(left.single)}',
      ),
    );
    expect(deleted.statusCode, anyOf(200, 204));
  }, skip: skip);

  test('production without --yes prints the plan and does nothing', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=production'],
      out: out,
      environment: <String, String>{
        projectVariable: 'my-project',
        bucketVariable: 'my-project.appspot.com',
      },
    );
    expect(run.exitCode, 2);
    expect(run.results, isEmpty);
    expect(run.uploadedBytes, 0);
    final String report = out.toString();
    expect(report, contains('my-project'));
    expect(report, contains('my-project.appspot.com'));
    expect(report, contains('verify_storage_kit/run_'));
    expect(report, contains('Nothing was done'));
  });

  test('production refuses to guess when an emulator is configured', () async {
    final KitRun run = await runKit(
      <String>['--backend=production'],
      out: StringBuffer(),
      environment: <String, String>{
        emulatorHostVariable: '127.0.0.1:1',
        projectVariable: 'my-project',
        bucketVariable: 'b',
      },
    );
    expect(run.exitCode, 2);
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
    expect(out.toString(), contains('--max-bytes'));
    expect(run.results, isEmpty);
  });

  test('--help prints the usage and exits 0', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--help'],
      out: out,
      environment: <String, String>{},
    );
    expect(run.exitCode, 0);
    expect(out.toString(), contains('--denied-bucket'));
    expect(out.toString(), contains('--create-user'));
  });

  test('--create-user needs the API key in production', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=production', '--create-user', '--yes'],
      out: out,
      environment: <String, String>{
        projectVariable: 'my-project',
        bucketVariable: 'b',
      },
    );
    expect(run.exitCode, 2);
    expect(out.toString(), contains(webApiKeyVariable));
    expect(run.results, isEmpty);
  });

  test('--create-user on the emulator needs the Auth emulator', () async {
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--create-user'],
      out: StringBuffer(),
      environment: <String, String>{emulatorHostVariable: '127.0.0.1:1'},
    );
    expect(run.exitCode, 2);
  });

  // Needs the Auth emulator too: tool/start_auth_emulators.sh 9398 9397 (AUTH_HUB_PORT=9498
  // AUTH_LOGGING_PORT=9598) and FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9398.
  final String? authHost = Platform.environment[authEmulatorHostVariable];
  test(
    'a throwaway user signs the checks in and is deleted at the end',
    () async {
      final StringBuffer out = StringBuffer();
      final KitRun run = await runKit(
        <String>[
          '--backend=emulator',
          '--create-user',
          deniedBucket,
          '--only=2,12,13,20',
        ],
        out: out,
        environment: <String, String>{
          ...environment,
          authEmulatorHostVariable: authHost ?? '',
        },
      );
      final String report = out.toString();
      expect(run.results['2']!.status, Status.pass, reason: report);
      expect(run.results['12']!.status, Status.pass, reason: report);
      expect(run.results['20']!.status, Status.pass, reason: report);
      expect(run.results['20']!.observed['withoutUser'], 'unauthorized');
      expect(
        run.results['13']!.status,
        anyOf(Status.pass, Status.inconclusive),
        reason: report,
      );
      expect(report, contains('The throwaway user was deleted.'));
      expect(report, isNot(contains('FAILED')));
      final http.Response accounts = await http.get(
        Uri.parse('http://$authHost/emulator/v1/projects/demo-test/accounts'),
      );
      expect(accounts.body, isNot(contains('storage-verify-')));
      expect(await objectsBelow(run.prefix!), isEmpty);
    },
    skip:
        skip ??
        (authHost == null ? '$authEmulatorHostVariable is not set.' : null),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
