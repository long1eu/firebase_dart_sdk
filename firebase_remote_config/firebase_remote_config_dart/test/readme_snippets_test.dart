// Keeps the Dart snippets of the Installations and Remote Config READMEs and of the Remote Config guide
// compiling.
//
// Every ```dart block of those files is copied into test/readme/readme_snippets.dart, one function per
// block, and that file is analyzed (here, and by any `dart analyze`), so a snippet that no longer matches
// the API is an analyzer error. This test also fails when the file is out of date; regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/readme_snippets_test.dart
//
// and fix whatever `dart analyze test/readme` then reports, in the README or the guide.
//
// Rules for a snippet: `import` lines and top-level classes are hoisted out of the function; everything
// else is a statement and may use `await`. The names declared in [_context] (app, store, installations,
// remoteConfig) can be used without declaring them. A block fenced as ```dart flutter (or anything else
// than a bare ```dart) is skipped.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// README path (relative to this package) to the prefix of its functions.
const Map<String, String> _readmes = <String, String>{
  'README.md': 'remoteConfigReadme',
  '../../firebase_installations/firebase_installations_dart/README.md':
      'installationsReadme',
  '../../docs/guides/remote_config.md': 'remoteConfigGuide',
};

const String _generated = 'test/readme/readme_snippets.dart';

/// What a snippet may assume to exist.
const String _context = '''
late FirebaseApp app;
late KeyValueStore store;
late FirebaseInstallations installations;
late FirebaseRemoteConfig remoteConfig;
''';

final RegExp _open = RegExp(r'^\s*```dart\s*$');
final RegExp _close = RegExp(r'^\s*```\s*$');
final RegExp _classStart = RegExp(r'^(abstract\s+|final\s+)?class\s');

String generate() {
  final Set<String> imports = <String>{
    "import 'dart:async';",
    "import 'package:firebase_app_dart/firebase_app_dart.dart';",
    "import 'package:firebase_installations_dart/firebase_installations_dart.dart';",
    "import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';",
  };
  final List<String> declarations = <String>[];
  final List<String> functions = <String>[];

  _readmes.forEach((String path, String prefix) {
    final List<String> lines = File(path).readAsLinesSync();
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
        } else if (_classStart.hasMatch(line)) {
          for (; i < lines.length; i++) {
            declarations.add(lines[i]);
            if (lines[i] == '}') {
              break;
            }
          }
          declarations.add('');
        } else {
          body.add(line.isEmpty ? '' : '  $line');
        }
      }
      while (body.isNotEmpty && body.first.isEmpty) {
        body.removeAt(0);
      }
      while (body.isNotEmpty && body.last.isEmpty) {
        body.removeLast();
      }
      functions.add(
        <String>[
          '// $path:$start',
          'Future<void> ${prefix}Line$start() async {',
          ...body,
          '}',
          '',
        ].join('\n'),
      );
    }
  });

  final List<String> sortedImports = imports.toList()..sort();
  return <String>[
    '// GENERATED from the README files by test/readme_snippets_test.dart. Do not edit: change the',
    '// README and regenerate (see that file).',
    '//',
    '// This file is only analyzed, never run.',
    '',
    '// ignore_for_file: type=lint, unused_local_variable, unused_import, unnecessary_import',
    '// ignore_for_file: unused_element',
    '',
    ...sortedImports,
    '',
    _context,
    ...declarations,
    ...functions,
  ].join('\n');
}

void main() {
  final String? missing = _readmes.keys.cast<String?>().firstWhere(
    (String? path) => !File(path!).existsSync(),
    orElse: () => null,
  );
  final Object skip = missing == null
      ? false
      : 'Needs a repository checkout: $missing is not part of the published package.';

  test('test/readme/readme_snippets.dart matches the READMEs', () {
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
  }, skip: skip);

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
            'A README snippet does not compile; fix it in the README and regenerate.\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the READMEs and the guide have Dart snippets to check', () {
    final String actual = generate();
    expect(
      RegExp(
        r'^Future<void> remoteConfigReadme',
        multiLine: true,
      ).allMatches(actual),
      hasLength(greaterThanOrEqualTo(4)),
    );
    expect(
      RegExp(
        r'^Future<void> installationsReadme',
        multiLine: true,
      ).allMatches(actual),
      hasLength(greaterThanOrEqualTo(4)),
    );
    expect(
      RegExp(
        r'^Future<void> remoteConfigGuide',
        multiLine: true,
      ).allMatches(actual),
      hasLength(greaterThanOrEqualTo(8)),
    );
  }, skip: skip);
}
