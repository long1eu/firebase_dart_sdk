// Golden listing of the exported public API (names, parameters).
//
// A failing test means the public surface changed. Review the diff of
// test/public_api.golden.txt; if the change is intended, regenerate it with
//
//     UPDATE_GOLDEN=1 flutter test test/public_api_golden_test.dart
//
// The listing is read from the source text by public_api_lister.dart, not built
// with dart:mirrors as in the other two database packages: Flutter code cannot
// use mirrors. The format is the same, except that nullability and default
// values are kept.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'public_api_lister.dart';

void main() {
  test('exported public API matches the golden listing', () {
    final File golden = File('test/public_api.golden.txt');
    final String actual = listPublicApi('firebase_database_dart_platform.dart');
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
          'UPDATE_GOLDEN=1 flutter test test/public_api_golden_test.dart '
          'and review the diff of test/public_api.golden.txt.',
    );
  });
}
