// Golden listing of the exported public API (names, parameters, deprecations).
//
// A failing test means the public surface changed. Review the diff of the
// golden file named in the failure; if the change is intended, regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/api/public_api_golden_test.dart
//
// The listing is built by support/public_api_describer.dart with dart:mirrors,
// so it works under `dart test` (JIT), not in AOT.

import 'dart:io';

// Loaded so that the libraries can be found by the mirror system.
// ignore: unused_import
import 'package:firebase_database_dart/firebase_database_dart.dart';
// ignore: unused_import
import 'package:firebase_database_dart/storage_engine.dart';
// ignore: unused_import
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/public_api_describer.dart';

void main() {
  for (final (String library, String golden, String what)
      in <(String, String, String)>[
        ('firebase_database_dart.dart', 'public_api.golden.txt', 'public'),
        (
          'storage_engine.dart',
          'storage_engine_api.golden.txt',
          'storage engine',
        ),
        ('testing.dart', 'testing_api.golden.txt', 'testing'),
      ]) {
    test('exported $what API matches the golden listing', () {
      final File file = File('test/api/$golden');
      final String actual = describePublicApi(
        'firebase_database_dart',
        library,
      );
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        file.writeAsStringSync(actual);
        return;
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Missing golden file. Run with UPDATE_GOLDEN=1.',
      );
      expect(
        actual,
        file.readAsStringSync(),
        reason:
            'The $what API changed. If intended, regenerate with '
            'UPDATE_GOLDEN=1 dart test test/api/public_api_golden_test.dart '
            'and review the diff of test/api/$golden.',
      );
    });
  }
}
