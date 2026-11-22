// Golden listing of the exported public API (names, parameters, deprecations).
//
// A failing test means the public surface changed. Review the diff of
// test/public_api.golden.txt; if the change is intended, regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/public_api_golden_test.dart
//
// The listing is built with dart:mirrors by the generator of the client package
// (it has no name of its own hard-coded), so it works under `dart test` (JIT),
// not in AOT.

import 'dart:io';

// Loaded so that the library can be found by the mirror system.
// ignore: unused_import
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:test/test.dart';

import '../../firebase_database_dart/test/api/support/public_api_describer.dart';

void main() {
  test('exported public API matches the golden listing', () {
    final File golden = File('test/public_api.golden.txt');
    final String actual = describePublicApi(
      'firebase_database_dart_sqlite',
      'firebase_database_dart_sqlite.dart',
    );
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync(actual);
      return;
    }
    expect(
      golden.existsSync(),
      isTrue,
      reason: 'Missing golden file. Run with UPDATE_GOLDEN=1.',
    );
    expect(
      actual,
      golden.readAsStringSync(),
      reason:
          'The public API changed. If intended, regenerate with '
          'UPDATE_GOLDEN=1 dart test test/public_api_golden_test.dart '
          'and review the diff of test/public_api.golden.txt.',
    );
  });
}
