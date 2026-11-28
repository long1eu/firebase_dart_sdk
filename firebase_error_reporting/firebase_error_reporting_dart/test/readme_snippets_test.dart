// Keeps the Dart snippets of the README compiling.
//
// Every ```dart block of README.md is copied into test/readme/readme_snippets.dart, one function per block, and
// that file is analyzed, so a snippet that no longer matches the API is an analyzer error. This test also fails
// when the file is out of date; regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/readme_snippets_test.dart
//
// and fix whatever `dart analyze test/readme` then reports, in the README.
//
// Rules for a snippet: `import` lines are hoisted out of the function; everything else is a statement and may use
// `await`. `app` and `reporter` can be used without declaring them. Blocks fenced otherwise (```dart flutter,
// which needs Flutter) are not compiled.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

const String _readme = 'README.md';
const String _generated = 'test/readme/readme_snippets.dart';

const String _context = '''
late FirebaseApp app;
late ErrorReporter reporter;
''';

final RegExp _open = RegExp(r'^\s*```dart\s*$');
final RegExp _close = RegExp(r'^\s*```\s*$');

String generate() {
  final Set<String> imports = <String>{
    "import 'package:firebase_app_dart/firebase_app_dart.dart';",
    "import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';",
  };
  final List<String> functions = <String>[];
  final List<String> lines = File(_readme).readAsLinesSync();
  for (int i = 0; i < lines.length; i++) {
    if (!_open.hasMatch(lines[i])) {
      continue;
    }
    final int start = i + 1;
    final List<String> body = <String>[];
    for (i++; i < lines.length && !_close.hasMatch(lines[i]); i++) {
      final String line = lines[i];
      if (line.startsWith('import ')) {
        imports.add(line.trim());
      } else {
        body.add(line.isEmpty ? '' : '  $line');
      }
    }
    while (body.isNotEmpty && body.first.isEmpty) {
      body.removeAt(0);
    }
    functions.add(
      <String>[
        '// $_readme:$start',
        'Future<void> readmeLine$start() async {',
        ...body,
        '}',
        '',
      ].join('\n'),
    );
  }
  final List<String> sortedImports = imports.toList()..sort();
  return <String>[
    '// GENERATED from README.md by test/readme_snippets_test.dart. Do not edit: change the README and',
    '// regenerate (see that file).',
    '//',
    '// This file is only analyzed, never run.',
    '',
    '// ignore_for_file: type=lint, unused_local_variable, unused_import',
    '// ignore_for_file: unused_element',
    '',
    ...sortedImports,
    '',
    _context,
    ...functions,
  ].join('\n');
}

void main() {
  test('test/readme/readme_snippets.dart matches the README', () {
    final File generated = File(_generated);
    final String actual = generate();
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      generated.writeAsStringSync(actual);
      return;
    }
    expect(
      generated.existsSync(),
      isTrue,
      reason: 'Missing $_generated. Run with UPDATE_GOLDEN=1.',
    );
    expect(
      generated.readAsStringSync(),
      actual,
      reason:
          'A README snippet changed. Regenerate with UPDATE_GOLDEN=1 dart test '
          'test/readme_snippets_test.dart, then run `dart analyze test/readme`.',
    );
  });

  test(
    'the README snippets compile against the current API',
    () async {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>['analyze', 'test/readme'],
      );
      expect(
        result.exitCode,
        0,
        reason:
            'A README snippet does not compile; fix it in the README and regenerate.\n${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the README has Dart snippets to check', () {
    expect(
      RegExp(
        r'^Future<void> readmeLine',
        multiLine: true,
      ).allMatches(generate()),
      hasLength(greaterThanOrEqualTo(6)),
    );
  });
}
