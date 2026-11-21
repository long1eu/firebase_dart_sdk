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
        '14': Status.pass,
        '15': Status.pass,
      };
      expect(
        <String, Status>{
          for (final MapEntry<String, CheckResult> e in run.results.entries)
            e.key: e.value.status,
        },
        expected,
        reason: out.toString(),
      );
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

  test('--auth=user needs the whole test user in the environment', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
      <String>['--backend=emulator', '--auth=user'],
      out: out,
      environment: <String, String>{
        emulatorHostVariable: '127.0.0.1:1',
        userEmailVariable: 'someone@example.com',
      },
    );
    expect(run.exitCode, 2);
    expect(out.toString(), contains(userPasswordVariable));
    expect(out.toString(), isNot(contains('someone@example.com')));
  });
}
