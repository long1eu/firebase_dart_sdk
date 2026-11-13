// Runs the programs of example/ as their own processes: against the Firebase
// Auth emulator when FIREBASE_AUTH_EMULATOR_HOST is set (see
// test/auth_emulator_test.dart), and without it, where they only print how to
// run them.

@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

/// The lines each example prints against the emulator, in this order.
final Map<String, List<Matcher>> _expectedOutput = <String, List<Matcher>>{
  'main.dart': <Matcher>[
    matches(RegExp(r'^signed in: \S+ \(anonymous: true\), token expires ')),
  ],
  'account_flows.dart': <Matcher>[
    equals('signed up, email verified: false'),
    equals('email verified: true'),
    equals('display name: Ada Lovelace'),
    equals('reset code is for this address: true'),
    matches(
      RegExp(r'^old password refused: (wrong-password|invalid-credential)$'),
    ),
    equals('signed in with the new password, same user: true'),
    equals('account deleted, signed in: false'),
  ],
};

Future<ProcessResult> _runExample(
  String name,
  Map<String, String> environment,
) {
  return Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'example/$name'],
    environment: environment,
    includeParentEnvironment: false,
  );
}

void main() {
  final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;

  test('every example has a test', () {
    final List<String> examples = Directory('example')
        .listSync()
        .whereType<File>()
        .map((File file) => file.uri.pathSegments.last)
        .where((String name) => name.endsWith('.dart'))
        .toList();
    expect(examples, unorderedEquals(_expectedOutput.keys));
  });

  _expectedOutput.forEach((String name, List<Matcher> lines) {
    test(
      'example/$name runs against the Auth emulator',
      () async {
        final ProcessResult result = await _runExample(
          name,
          Platform.environment,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(
          (result.stdout as String).split('\n'),
          containsAllInOrder(lines),
        );
      },
      skip: host == null
          ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'example/$name prints a note without the emulator',
      () async {
        final ProcessResult result = await _runExample(
          name,
          Map<String, String>.of(Platform.environment)
            ..remove('FIREBASE_AUTH_EMULATOR_HOST'),
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, startsWith('Set FIREBASE_AUTH_EMULATOR_HOST'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
