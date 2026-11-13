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
const Set<String> _libraries = <String>{
  'common.dart',
  'sqlite_database.dart',
  // For browsers; exercised by test/browser/web_persistence_test.dart.
  'sqlite_database_web.dart',
  // The OPFS worker of sqlite_database_web.dart, compiled to JavaScript;
  // exercised by test/browser/web_persistence_opfs_test.dart.
  'sqlite_opfs_worker.dart',
};

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
  'cache_indexes.dart',
  'emulator_mock_user_token.dart',
  'lifecycle.dart',
  'lite.dart',
  'server.dart',
  'two_clients_one_cache.dart',
  'database_recovery.dart',
};

/// Lines an example must print, for the examples the README points new users
/// to first. They show that each step of the example did what it says, not
/// only that the program exited.
const Map<String, List<String>> _expectedOutput = <String, List<String>>{
  'main.dart': <String>[
    'added alan with a generated id of 20 characters',
    'ada: {age: 36, name: Ada}',
    'older than 40: Alan',
    'listener: [Ada, Alan]',
    'listener after the batch: [Ada, Alan, Grace]',
    'alan is now 42',
    'count: 3',
  ],
  'server.dart': <String>[
    'POST /tasks -> 201 {}',
    'GET /tasks/<id> -> 200 {"title":"Write the docs","done":false}',
    'POST /tasks/<id>/done -> 200 {"changed":true}',
    'GET /tasks?done=false -> 200 [{"title":"Ship it","done":false}]',
    'GET /stats -> 200 {"done":1,"open":1}',
    'GET /tasks/missing -> 404 {"error":"no task missing"}',
  ],
  'two_clients_one_cache.dart': <String>[
    'main isolate: wrote online',
    'background isolate: took the lease and wrote online',
    'main isolate: secondary, answers from the cache',
    'main isolate: reads {from: background isolate} from the cache',
    'main isolate: write acknowledged while secondary: false',
    'background isolate: terminated',
    'main isolate: primary again, write acknowledged: true',
  ],
  'database_recovery.dart': <String>[
    'write failed with unavailable, nothing was stored',
    'write tried again: {step: 2}',
    'listener: {step: 2}',
    'listener after 3 failed attempts to store the change: {step: 3}',
  ],
  'offline_persistence.dart': <String>[
    'offline read: {text: written online} (from cache: true)',
    'offline write: {text: changed offline} (pending: true)',
    'after sync: {text: changed offline}',
  ],
  'lite.dart': <String>[
    'big: [NYC, LA, SF]',
    'pages: [LA, NYC] [SF, SEA]',
    'totals: {cities: 4, people: 13643000}',
    'after terminate: true',
  ],
};

void main() {
  checkTestsLeaveNothingBehind();

  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final Object skip = emulator == null || emulator.isEmpty
      ? 'The examples need the Firestore emulator: set FIRESTORE_EMULATOR_HOST.'
      : false;

  final List<String> examples =
      Directory('example')
          .listSync()
          .whereType<File>()
          .map((File file) => file.uri.pathSegments.last)
          .where(
            (String name) =>
                name.endsWith('.dart') && !_libraries.contains(name),
          )
          .toList()
        ..sort();

  test('every example topic has a file', () {
    expect(examples.toSet(), containsAll(_expected));
    expect(_expected, containsAll(_expectedOutput.keys));
  });

  for (final String name in examples) {
    test(
      'example/$name runs against the emulator and exits cleanly',
      () async {
        final Process process = await Process.start(
          Platform.resolvedExecutable,
          <String>['run', 'example/$name'],
        );
        final Future<String> stdoutText = process.stdout
            .transform(utf8.decoder)
            .join();
        final Future<String> stderrText = process.stderr
            .transform(utf8.decoder)
            .join();

        final int exitCode = await process.exitCode.timeout(
          const Duration(minutes: 2),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        final String output = await stdoutText;
        final String errors = await stderrText;

        expect(
          exitCode,
          0,
          reason: exitCode == -1
              ? 'example/$name did not exit within 2 minutes.\n$output\n$errors'
              : 'example/$name failed.\n$output\n$errors',
        );
        expect(errors, isEmpty, reason: 'example/$name wrote to stderr.');
        expect(
          output.trim(),
          isNotEmpty,
          reason: 'example/$name printed nothing.',
        );
        final List<String>? lines = _expectedOutput[name];
        if (lines != null) {
          expect(
            LineSplitter.split(output),
            containsAllInOrder(lines),
            reason: 'example/$name printed something else.',
          );
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
