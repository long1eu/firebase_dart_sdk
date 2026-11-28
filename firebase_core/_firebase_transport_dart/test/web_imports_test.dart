// The main library must reach neither dart:io nor dart:ffi on the web; tool/check_web_imports.dart
// follows the imports (web compilers accept dart:io, so a web compile cannot tell).

@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

ProcessResult _check(List<String> entries) => Process.runSync(
  Platform.resolvedExecutable,
  <String>['../../tool/check_web_imports.dart', '.', ...entries],
);

void main() {
  test('the main library reaches neither dart:io nor dart:ffi', () {
    final ProcessResult result = _check(<String>[]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('negative control: an entry that imports dart:io is reported', () {
    final ProcessResult result = _check(<String>[
      'lib/src/environment_io.dart',
    ]);
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('dart:io'));
  });
}
