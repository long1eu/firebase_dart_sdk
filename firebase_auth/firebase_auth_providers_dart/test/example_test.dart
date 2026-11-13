// Runs example/main.dart as its own process: against the Firebase Auth
// emulator when FIREBASE_AUTH_EMULATOR_HOST is set (see
// test/auth_emulator_test.dart), and without it, where it only prints how to
// run it.

@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

Future<ProcessResult> _runExample(Map<String, String> environment) {
  return Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'example/main.dart'],
    environment: environment,
    includeParentEnvironment: false,
  );
}

void main() {
  final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;

  test(
    'example/main.dart signs in against the Auth emulator',
    () async {
      final ProcessResult result = await _runExample(Platform.environment);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, isEmpty);
      final List<String> lines = (result.stdout as String).split('\n');
      expect(
        lines,
        contains(
          matches(
            RegExp(r'^signed in: \S+ \(anonymous: true\), token expires '),
          ),
        ),
      );
    },
    skip: host == null
        ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'example/main.dart prints a note without the emulator',
    () async {
      final ProcessResult result = await _runExample(
        Map<String, String>.of(Platform.environment)
          ..remove('FIREBASE_AUTH_EMULATOR_HOST'),
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, startsWith('Set FIREBASE_AUTH_EMULATOR_HOST'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
