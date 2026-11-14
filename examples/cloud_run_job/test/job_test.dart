// The retry helper on its own, and the job as a program against the Firestore
// emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
//
// The tests that need the emulator are skipped without FIRESTORE_EMULATOR_HOST.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_run_job/retry.dart';
import 'package:test/test.dart';

void main() {
  group('withRetries', () {
    late List<Duration> pauses;
    Future<void> sleep(Duration delay) async => pauses.add(delay);

    setUp(() => pauses = <Duration>[]);

    test('retries unavailable errors with a growing, capped backoff', () async {
      int calls = 0;
      final String result = await withRetries(
        'op',
        () async {
          if (++calls < 5) {
            throw FirestoreError('offline', FirestoreErrorCode.unavailable);
          }
          return 'done';
        },
        maxAttempts: 5,
        initialDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 3),
        random: _MaxRandom(),
        sleep: sleep,
      );
      expect(result, 'done');
      expect(calls, 5);
      expect(pauses, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 3),
      ]);
    });

    test('throws other errors at once', () async {
      int calls = 0;
      await expectLater(
        withRetries('op', () async {
          calls++;
          throw FirestoreError('no', FirestoreErrorCode.permissionDenied);
        }, sleep: sleep),
        throwsA(isA<FirestoreError>()),
      );
      expect(calls, 1);
      expect(pauses, isEmpty);
    });

    test('gives up after maxAttempts with the last error', () async {
      int calls = 0;
      await expectLater(
        withRetries(
          'aggregation',
          () async {
            calls++;
            throw FirestoreError('busy', FirestoreErrorCode.resourceExhausted);
          },
          maxAttempts: 3,
          sleep: sleep,
        ),
        throwsA(
          isA<RetriesExhausted>()
              .having((RetriesExhausted e) => e.attempts, 'attempts', 3)
              .having(
                (RetriesExhausted e) => e.lastError,
                'lastError',
                isA<FirestoreError>(),
              ),
        ),
      );
      expect(calls, 3);
      expect(pauses, hasLength(2));
    });

    test('an attempt that does not finish in time counts as failed', () async {
      int calls = 0;
      final int result = await withRetries(
        'op',
        () {
          calls++;
          return calls == 1 ? Completer<int>().future : Future<int>.value(7);
        },
        attemptTimeout: const Duration(milliseconds: 10),
        sleep: sleep,
      );
      expect(result, 7);
      expect(calls, 2);
    });
  });

  group('the job against the emulator', () {
    final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];
    final String run = 'job-test-${DateTime.now().microsecondsSinceEpoch}';
    final Map<String, String> environment = <String, String>{
      ...Platform.environment,
      'ORDERS_COLLECTION': '$run/data/orders',
      'REPORT_DOCUMENT': '$run/report',
    };

    Future<ProcessResult> dart(String program, [Map<String, String>? extra]) {
      return Process.run(
        Platform.resolvedExecutable,
        <String>['run', program],
        environment: <String, String>{...environment, ...?extra},
        includeParentEnvironment: false,
      ).timeout(const Duration(minutes: 2));
    }

    test(
      'summarizes the orders and writes the report once per execution',
      () async {
        expect((await dart('bin/seed.dart')).exitCode, 0);

        final ProcessResult first = await dart('bin/job.dart', <String, String>{
          'CLOUD_RUN_EXECUTION': 'execution-1',
        });
        expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
        expect(
          first.stdout,
          contains('summary: 7 paid orders, revenue 280.00, average 40.00'),
        );
        expect(first.stdout, contains('written for execution-1'));

        // A retry of the same execution (Cloud Run retries a failed task)
        // finds the report written and does not count the run twice.
        final ProcessResult retry = await dart('bin/job.dart', <String, String>{
          'CLOUD_RUN_EXECUTION': 'execution-1',
        });
        expect(retry.exitCode, 0);
        expect(retry.stdout, contains('already written for execution-1'));

        final ProcessResult next = await dart('bin/job.dart', <String, String>{
          'CLOUD_RUN_EXECUTION': 'execution-2',
        });
        expect(next.stdout, contains('written for execution-2'));
      },
      skip: emulator == null || emulator.isEmpty
          ? 'Set FIRESTORE_EMULATOR_HOST to run the job against the emulator.'
          : false,
    );
  });

  test(
    'exits with 1 after its retries when the backend is unreachable',
    () async {
      // Nothing listens on port 9: every attempt fails with unavailable.
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'bin/job.dart'],
        environment: <String, String>{
          ...Platform.environment,
          'FIRESTORE_EMULATOR_HOST': '127.0.0.1:9',
          'MAX_ATTEMPTS': '2',
        },
        includeParentEnvironment: false,
      ).timeout(const Duration(minutes: 2));
      expect(result.exitCode, 1);
      expect(result.stderr, contains('aggregation: attempt 1 failed'));
      expect(result.stderr, contains('aggregation failed 2 times'));
    },
  );

  test('exits with 78 when no backend is configured', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/job.dart'],
      environment: Map<String, String>.of(Platform.environment)
        ..remove('FIRESTORE_EMULATOR_HOST')
        ..remove('FIREBASE_PROJECT_ID'),
      includeParentEnvironment: false,
    ).timeout(const Duration(minutes: 2));
    expect(result.exitCode, 78);
  });
}

/// Always the largest jitter, so that the pauses are the backoff itself.
class _MaxRandom implements Random {
  @override
  double nextDouble() => 1;

  @override
  bool nextBool() => true;

  @override
  int nextInt(int max) => max - 1;
}
