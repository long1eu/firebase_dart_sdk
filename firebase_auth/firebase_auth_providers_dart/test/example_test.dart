// Runs the programs of example/ as their own processes: against the Firebase
// Auth emulator when FIREBASE_AUTH_EMULATOR_HOST is set (see
// test/auth_emulator_test.dart; firestore_wiring.dart also needs
// FIRESTORE_AUTH_RULES_EMULATOR_HOST), and without it, where they only print
// how to run them. service_account.dart and adc_server.dart need a real
// project, so they only run without their variables.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

/// The lines each emulator example prints, in this order.
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
  'email_password.dart': <Matcher>[
    equals('signed up: anonymous false, email verified false'),
    equals('signed out: true'),
    equals('signed in again, same user: true'),
    matches(RegExp(r'^wrong password: (wrong-password|invalid-credential)$')),
    equals('address taken: email-already-in-use'),
    equals('weak password: weak-password'),
    equals('bad address: invalid-email'),
    equals('still signed in: true'),
  ],
  'custom_token.dart': <Matcher>[
    equals('signed in with the uid of the token: true'),
    equals('sign-in provider: custom'),
    equals('role claim: tester'),
    equals('a malformed token: invalid-custom-token'),
  ],
  'persistent_session.dart': <Matcher>[
    equals('first run, signed in: false'),
    equals('second run, same user: true'),
    equals('fresh ID token for the user: true'),
    equals('session file removed: true'),
  ],
  'firestore_wiring.dart': <Matcher>[
    equals('signed out, write refused: permissionDenied'),
    equals('signed in, read back: hello'),
    equals('read of another user refused: permissionDenied'),
  ],
};

/// The first words each example prints when its variables are not set.
const Map<String, String> _notes = <String, String>{
  'main.dart': 'Set FIREBASE_AUTH_EMULATOR_HOST',
  'account_flows.dart': 'Set FIREBASE_AUTH_EMULATOR_HOST',
  'email_password.dart': 'Set FIREBASE_AUTH_EMULATOR_HOST',
  'custom_token.dart': 'Set FIREBASE_AUTH_EMULATOR_HOST',
  'persistent_session.dart': 'Set FIREBASE_AUTH_EMULATOR_HOST',
  'firestore_wiring.dart': 'Set FIREBASE_AUTH_EMULATOR_HOST',
  'service_account.dart': 'Set FIREBASE_SERVICE_ACCOUNT_KEY_FILE',
  'adc_server.dart': 'Set FIREBASE_PROJECT_ID',
};

/// The variables that point the examples at an emulator or a real project.
const List<String> _variables = <String>[
  'FIREBASE_AUTH_EMULATOR_HOST',
  'FIRESTORE_AUTH_RULES_EMULATOR_HOST',
  'FIREBASE_SERVICE_ACCOUNT_KEY_FILE',
  'FIREBASE_PROJECT_ID',
];

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
  final String? rulesHost =
      Platform.environment['FIRESTORE_AUTH_RULES_EMULATOR_HOST'];

  test('every example has a test', () {
    final List<String> examples = Directory('example')
        .listSync()
        .whereType<File>()
        .map((File file) => file.uri.pathSegments.last)
        .where((String name) => name.endsWith('.dart'))
        .toList();
    expect(examples, unorderedEquals(_notes.keys));
    expect(_notes.keys, containsAll(_expectedOutput.keys));
  });

  _expectedOutput.forEach((String name, List<Matcher> lines) {
    final bool needsRules = name == 'firestore_wiring.dart';
    test(
      'example/$name runs against the emulators',
      () async {
        final ProcessResult result = await _runExample(
          name,
          Map<String, String>.of(Platform.environment)
            ..remove('FIREBASE_SERVICE_ACCOUNT_KEY_FILE')
            ..remove('FIREBASE_PROJECT_ID'),
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(
          // LineSplitter: print ends lines with \r\n on Windows.
          const LineSplitter().convert(result.stdout as String),
          containsAllInOrder(lines),
        );
      },
      skip: host == null
          ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
          : needsRules && (rulesHost == null || rulesHost.isEmpty)
          ? 'FIRESTORE_AUTH_RULES_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  _notes.forEach((String name, String note) {
    test(
      'example/$name prints a note without its variables',
      () async {
        final Map<String, String> environment = Map<String, String>.of(
          Platform.environment,
        )..removeWhere((String key, _) => _variables.contains(key));
        final ProcessResult result = await _runExample(name, environment);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, startsWith(note));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
