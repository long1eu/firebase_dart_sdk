// Verifies the production verification kit itself (verify_production.dart) against the emulator, where the
// expected results are known. Skipped unless FIRESTORE_EMULATOR_HOST is set; never runs against a real project.
//
// The expectations are the ones of the Standard edition emulator, pinned per check. One check (8) is expected to
// FAIL there, for a known reason that is not about the kit (see the comment below).

import 'dart:io';

import 'package:test/test.dart';

import '../util/test_backend.dart';
import 'verify_production.dart';

void main() {
  final TestBackend backend = TestBackend();
  final String? skip = backend.emulatorHost == null
      ? '${TestBackend.emulatorHostVariable} is not set: the kit is verified against the emulator'
      : backend.isEnterpriseEdition
          ? 'The expectations are the ones of the Standard edition emulator'
          : null;

  final String? authEmulator =
      Platform.environment[authEmulatorHostVariable]?.trim().isEmpty ?? true
          ? null
          : Platform.environment[authEmulatorHostVariable];

  group('arguments', () {
    Future<(KitRun, String)> run(List<String> arguments,
        Map<String, String> environment) async {
      final StringBuffer out = StringBuffer();
      final KitRun result =
          await runKit(arguments, out: out, environment: environment);
      return (result, out.toString());
    }

    test('a backend is required, unknown arguments are rejected', () async {
      expect((await run(<String>[], <String, String>{})).$1.exitCode, 2);
      expect(
          (await run(<String>['--backend=emulator', '--force'],
                  <String, String>{}))
              .$1
              .exitCode,
          2);
      expect(
          (await run(<String>['--backend=emulator'], <String, String>{}))
              .$2,
          contains('FIRESTORE_EMULATOR_HOST is not set'));
    });

    test('production needs the project id and no emulator host', () async {
      final (KitRun noProject, String noProjectOut) =
          await run(<String>['--backend=production', '--yes'], <String, String>{});
      expect(noProject.exitCode, 2);
      expect(noProjectOut, contains('FIRESTORE_TEST_PROJECT_ID is not set'));

      final (KitRun both, String bothOut) =
          await run(<String>['--backend=production', '--yes'], <String, String>{
        'FIRESTORE_TEST_PROJECT_ID': 'some-project',
        'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
      });
      expect(both.exitCode, 2);
      expect(bothOut, contains('FIRESTORE_EMULATOR_HOST is set'));
    });

    test('production does nothing without --yes, and says what it would do',
        () async {
      final (KitRun result, String out) =
          await run(<String>['--backend=production'], <String, String>{
        'FIRESTORE_TEST_PROJECT_ID': 'some-project',
        'FIRESTORE_TEST_DATABASE_ID': 'some-database',
      });
      expect(result.exitCode, 2);
      expect(result.results, isEmpty);
      expect(result.writes, 0);
      expect(out, contains('project:   some-project'));
      expect(out, contains('database:  some-database'));
      expect(out, contains('firestore.googleapis.com:443'));
      expect(out, contains('at most $defaultMaxWrites document writes'));
      expect(out, contains('writes to: verify_production_kit/run_'));
      expect(out, contains('Nothing was done. Pass --yes'));
    });

    test('--list names every check', () async {
      final (KitRun result, String out) =
          await run(<String>['--list'], <String, String>{});
      expect(result.exitCode, 0);
      for (final Check check in checks) {
        expect(out, contains(check.name));
      }
    });
  });

  test('the kit against the emulator gives the known results', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run =
        await runKit(<String>['--backend=emulator'], out: out);
    final String report = out.toString();
    addTearDown(() {
      if (run.exitCode != 1) {
        // ignore: avoid_print
        print(report);
      }
    });
    Status status(String id) => run.results[id]!.status;
    Map<String, Object?> observed(String id) => run.results[id]!.observed;
    String why(String id) => '[$id] ${run.results[id]!.summary}\n$report';

    expect(run.results.keys, checks.map((Check c) => c.id));

    expect(status('1a'), Status.pass, reason: why('1a'));
    expect(status('1b'), Status.pass, reason: why('1b'));
    // The emulator needs no composite index.
    expect(status('1c'), Status.pass, reason: why('1c'));
    expect(observed('1c')['missingIndex'], isFalse);

    // The emulator applies a re-sent write again (chaos finding F1), and the cache agrees (F1b fix).
    expect(status('2'), Status.pass, reason: why('2'));
    expect(observed('2')['incrementCountedBeforeCut'], 1);
    expect(observed('2')['incrementCounted'], 2);
    expect(observed('2')['cacheAgrees'], isTrue);

    // A commit whose answer is lost is retried (chaos finding F2).
    expect(status('3'), Status.pass, reason: why('3'));
    expect(observed('3')['attempts'], 2);
    expect(observed('3')['applied'], 2);
    expect(observed('3')['error'], isNull);

    // The emulator accepts any read time.
    expect(status('4'), Status.pass, reason: why('4'));
    expect(observed('4').keys, <String>['unchanged', '2 hours', '8 days']);

    expect(status('5'), Status.pass, reason: why('5'));

    // Standard edition: null and NaN never match on the backend. The SDK itself matches them, so with the
    // documents cached they are in limbo; the sync engine drops a limbo document that the backend confirms but
    // does not match (4c72e9ea), and the server read gives the result of the backend. Before that fix this check
    // failed here: the server reads did not complete.
    expect(status('6'), Status.pass, reason: why('6'));
    expect(observed('6')['edition'], 'standard', reason: why('6'));
    expect((observed('6')['server']! as Map<String, String>).values,
        everyElement(isEmpty),
        reason: why('6'));
    expect(observed('6')['stuck'], isEmpty, reason: why('6'));
    expect(observed('6')['localDifferences'], hasLength(6), reason: why('6'));

    expect(status('7'), Status.skipped, reason: why('7'));

    // FAILS on the emulator: its JSON front end stores -0 as 0, so -0.0 written over the web transport (and only
    // that) loses its sign. Empty bytes are fine everywhere.
    final List<Object?> problems = observed('8')['problems']! as List<Object?>;
    expect(status('8'), Status.fail, reason: why('8'));
    expect(problems, isNotEmpty);
    for (final Object? problem in problems) {
      expect(problem, contains('written by_web'), reason: why('8'));
      expect(problem, isNot(contains('empty bytes')), reason: why('8'));
    }

    expect(status('9'), Status.pass, reason: why('9'));
    expect(observed('9')['millis'], hasLength(3));

    expect(status('10'), Status.skipped, reason: why('10'));

    expect(status('11'), Status.pass, reason: why('11'));

    expect(
        observed('11')['endpoints'],
        containsAll(<String>[
          'channel',
          'documents:batchGet',
          'documents:commit',
        ]));

    // Firestore Lite: both transports, and REST without a WebChannel session.
    expect(status('12'), Status.pass, reason: why('12'));
    expect(observed('12')['grpcTransport'], 'GrpcTransport');
    expect(observed('12')['restTransport'], 'RestTransport');
    expect(observed('12')['restEndpoints'], <String>[
      'batchGet',
      'beginTransaction',
      'commit',
      'rollback',
      'runAggregationQuery',
      'runQuery',
    ]);

    // Optional: only with the Firebase Auth emulator (tool/start_auth_emulators.sh). The rules of the standard
    // emulator allow everything, so the request with the ID token is served.
    if (authEmulator == null) {
      expect(status('13'), Status.skipped, reason: why('13'));
    } else {
      expect(status('13'), Status.pass, reason: why('13'));
      expect(observed('13')['signInProvider'], 'anonymous');
      expect(observed('13')['outcome'], startsWith('served'));
      expect(observed('13')['accountDeleted'], isTrue);
    }

    // The accounting: within the cap, and everything that was handed out was deleted.
    expect(run.writes, lessThanOrEqualTo(defaultMaxWrites));
    expect(run.writes, greaterThan(20));
    expect(run.deletes, greaterThan(10));
    expect(report, contains('Clean-up: ${run.deletes} documents deleted'));
    expect(report, isNot(contains('Clean-up FAILED')));
    // Check 8 is the only FAIL (the emulator stores -0 as 0), so the exit code is 1.
    expect(
        run.results.entries
            .where((MapEntry<String, CheckResult> e) =>
                e.value.status == Status.fail)
            .map((MapEntry<String, CheckResult> e) => e.key),
        <String>['8'],
        reason: report);
    expect(run.exitCode, 1);
    // Every check printed its verdict.
    for (final Check check in checks) {
      expect(report, contains('[${check.id}] ${run.results[check.id]!.status.label}: '));
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('the write cap stops the run before it is exceeded', () async {
    final StringBuffer out = StringBuffer();
    final KitRun run = await runKit(
        <String>['--backend=emulator', '--only=1a,1c', '--max-writes=5'],
        out: out);
    // 1a spends 3 writes; 1c asks for 6 more and is stopped before it writes.
    expect(run.results['1a']!.status, Status.pass, reason: '$out');
    expect(run.results['1c']!.status, Status.inconclusive, reason: '$out');
    expect(run.results['1c']!.summary, contains('write cap'));
    expect(run.writes, 3);
  }, skip: skip);
}
