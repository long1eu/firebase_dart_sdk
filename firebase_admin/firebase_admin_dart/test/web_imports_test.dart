// The libraries for the web must reach neither dart:io nor dart:ffi on the web; tool/check_web_imports.dart follows the imports
// (web compilers accept dart:io, so web_compile_test.dart cannot tell).

@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

ProcessResult _check(List<String> entries) => Process.runSync(
  Platform.resolvedExecutable,
  <String>['../../tool/check_web_imports.dart', '.', ...entries],
);

void main() {
  test('the main library and auth.dart reach neither dart:io nor dart:ffi', () {
    final ProcessResult result = _check(<String>[
      'lib/firebase_admin_dart.dart',
      'lib/auth.dart',
      'lib/app_check.dart',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('the check sees the dart:io of adc.dart', () {
    final ProcessResult result = _check(<String>['lib/adc.dart']);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    expect(result.stdout, contains('dart:io is reached on the web through'));
  });
}
