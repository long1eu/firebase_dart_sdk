// Keeps test/spec/sync_point_spec.g.dart (the spec as a Dart string, which is what the scenario
// tests read so that they also run in a browser) equal to test/spec/syncPointSpec.json. After
// replacing the JSON file, regenerate with
//
//     UPDATE_GOLDEN=1 dart test test/spec/sync_point_spec_embedded_test.dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'sync_point_spec_runner.dart';

const String _specFile = 'test/spec/syncPointSpec.json';
const String _generated = 'test/spec/sync_point_spec.g.dart';
const String _quotes = "'''";

/// The content of the generated file for the spec text [json].
String generate(String json) {
  // A raw string cannot hold its own delimiter; a dollar sign or a backslash is fine in one.
  if (json.contains(_quotes)) {
    throw StateError(
      '$_specFile contains three single quotes in a row, which the raw string cannot hold.',
    );
  }
  return '// GENERATED from syncPointSpec.json by sync_point_spec_embedded_test.dart. Do not edit:\n'
      '// replace the JSON file and regenerate (see that test).\n'
      '\n'
      '/// The text of `test/spec/syncPointSpec.json`.\n'
      'const String syncPointSpecJson = r$_quotes\n'
      '$json$_quotes;\n';
}

void main() {
  test('sync_point_spec.g.dart holds syncPointSpec.json unchanged', () {
    final String json = File(_specFile).readAsStringSync();
    final String expected = generate(json);
    final File generated = File(_generated);
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      generated.writeAsStringSync(expected);
      return;
    }
    expect(
      generated.readAsStringSync() == expected,
      isTrue,
      reason: '$_generated is out of date. Run with UPDATE_GOLDEN=1.',
    );
    // The raw string starts with a line break the file does not have; JSON ignores it.
    expect(
      loadSyncPointScenarios().map((SyncPointScenario s) => s.name),
      loadSyncPointScenarios(json).map((SyncPointScenario s) => s.name),
    );
  });
}
