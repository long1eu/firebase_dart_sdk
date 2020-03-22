// File created by
// Lung Razvan <long1eu>
// on 05/10/2018

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:test/test.dart';

import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

void main() {
  const String eagerGc = 'eager-gc';

  SpecTestCase testCase;

  setUp(() async {
    testCase = SpecTestCase(
      (_, String name) {
        return createSQLitePersistence(
            'firebase/firestore/spec/sqlite_spec_test_${Uri.encodeQueryComponent(name)}b');
      },
      (Set<String> tags) => tags.contains(eagerGc),
    );
    await testCase.specSetUp(<String, dynamic>{});
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));
  });

  test('testSpecTests', () async {
    bool ranAtLeastOneTest = false;

    // Enumerate the .json files containing the spec tests.
    final List<Pair<String, Map<String, dynamic>>> parsedSpecFiles =
        <Pair<String, Map<String, dynamic>>>[];
    final Directory jsonDir =
        Directory('${Directory.current.path}/test/res/json');
    final List<File> jsonFiles = jsonDir //
        .listSync()
        .where((FileSystemEntity it) => it is File && it.path.endsWith('.json'))
        .cast<File>()
        .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));

    bool exclusiveMode = false;
    for (File f in jsonFiles) {
      final String json = f.readAsStringSync();
      final Map<String, dynamic> fileJSON = jsonDecode(json);
      exclusiveMode =
          exclusiveMode || SpecTestCase.anyTestsAreMarkedExclusive(fileJSON);
      parsedSpecFiles.add(Pair<String, Map<String, dynamic>>(
          basenameWithoutExtension(f.path), fileJSON));
    }

    for (Pair<String, Map<String, dynamic>> parsedSpecFile in parsedSpecFiles) {
      final String fileName = parsedSpecFile.first;
      final Map<String, dynamic> fileJSON = parsedSpecFile.second;

      // Print the names of the files and tests regardless of whether verbose logging is enabled.
      SpecTestCase.info('Spec test file: $fileName');

      // Iterate over the tests in the file and run them.

      final Iterable<String> keys = fileJSON.keys;

      for (String key in keys) {
        final Map<String, dynamic> testJSON = fileJSON[key];
        final String describeName = testJSON['describeName'];
        final String itName = testJSON['itName'];
        final String name = '$describeName $itName';
        final Map<String, dynamic> config = testJSON['config'];
        final List<dynamic> steps = testJSON['steps'];
        final Set<String> tags = SpecTestCase.getTestTags(testJSON);

        final bool runTest = testCase.shouldRunTest(tags) &&
            (!exclusiveMode || tags.contains(SpecTestCase.exclusiveTag));
        if (runTest) {
          try {
            SpecTestCase.info(
                '------------------------------------------------------------------');
            SpecTestCase.info('  Spec test: $name');
            SpecTestCase.info(
                '------------------------------------------------------------------');
            testCase.currentName = name;
            await testCase.runSteps(steps, config);
            ranAtLeastOneTest = true;
          } on TestFailure catch (_) {
            await testCase.specTearDown(isError: true);

            //throw StateError('Spec test failure: $name\n  $e');
            rethrow;
          }
        } else {
          SpecTestCase.info('  [SKIPPED] Spec test: $name');
        }
      }
    }

    expect(ranAtLeastOneTest, isTrue);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
