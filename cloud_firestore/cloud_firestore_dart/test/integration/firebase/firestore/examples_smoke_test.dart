// Runs every example of example/ as its own process against the Firestore
// emulator and checks that it finishes with exit code 0, without an uncaught
// error and without hanging (an instance that is not terminated keeps the
// process alive).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

/// Files of example/ that are libraries, not programs.
const Set<String> _libraries = <String>{'common.dart', 'sqlite_database.dart'};

/// The topics that must stay covered; a missing file fails the test.
const Set<String> _expected = <String>{
  'main.dart',
  'crud_and_listeners.dart',
  'queries.dart',
  'aggregations.dart',
  'converters.dart',
  'transactions_and_batches.dart',
  'bundles.dart',
  'snapshot_json.dart',
  'offline_persistence.dart',
  'emulator_mock_user_token.dart',
  'lifecycle.dart',
};

void main() {
  checkTestsLeaveNothingBehind();

  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final Object skip = emulator == null || emulator.isEmpty
      ? 'The examples need the Firestore emulator: set FIRESTORE_EMULATOR_HOST.'
      : false;

  final List<String> examples = Directory('example')
      .listSync()
      .whereType<File>()
      .map((File file) => file.uri.pathSegments.last)
      .where(
          (String name) => name.endsWith('.dart') && !_libraries.contains(name))
      .toList()
    ..sort();

  test('every example topic has a file', () {
    expect(examples.toSet(), containsAll(_expected));
  });

  for (final String name in examples) {
    test('example/$name runs against the emulator and exits cleanly', () async {
      final Process process = await Process.start(
        Platform.resolvedExecutable,
        <String>['run', 'example/$name'],
      );
      final Future<String> stdoutText =
          process.stdout.transform(utf8.decoder).join();
      final Future<String> stderrText =
          process.stderr.transform(utf8.decoder).join();

      final int exitCode = await process.exitCode
          .timeout(const Duration(minutes: 2), onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      });
      final String output = await stdoutText;
      final String errors = await stderrText;

      expect(exitCode, 0,
          reason: exitCode == -1
              ? 'example/$name did not exit within 2 minutes.\n$output\n$errors'
              : 'example/$name failed.\n$output\n$errors');
      expect(errors, isEmpty, reason: 'example/$name wrote to stderr.');
      expect(output.trim(), isNotEmpty,
          reason: 'example/$name printed nothing.');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
  }
}
