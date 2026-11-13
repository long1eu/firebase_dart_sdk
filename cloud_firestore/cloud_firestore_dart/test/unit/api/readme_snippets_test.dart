// Keeps the Dart snippets of the READMEs compiling.
//
// Every ```dart block of the four READMEs (repository root, this package,
// firebase_app_dart, firebase_auth_providers_dart), of docs/migrating_from_vm_packages.md (whose
// "before" blocks are fenced as ```dart before and skipped) and of the guides in docs/guides is copied into
// test/readme/readme_snippets.dart, one function per block, and that file is analyzed (here, and by any
// `dart analyze test`), so a snippet that no longer matches the API is an
// analyzer error. This test also fails when the file is out of date;
// regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/unit/api/readme_snippets_test.dart
//
// and fix whatever `dart analyze test/readme` then reports, in the README.
//
// Rules for a snippet: `import` lines and top-level classes are hoisted out
// of the function; everything else is a statement and may use `await`. The
// names declared in [_context] (app, firestore, users, ...) can be used
// without declaring them. An import of a file of this package's example/
// folder (`import 'sqlite_database.dart';`, which the guides tell the reader
// to copy) is rewritten to import that file, so the snippet is checked
// against it.
//
// A block fenced as ```dart lite is a snippet for Firestore Lite: its classes
// have the names of the main library, so these blocks go to a file of their
// own (test/readme/readme_lite_snippets.dart) that imports
// `package:cloud_firestore_dart/lite.dart` instead, with `app` and
// `firestore` in scope.

import 'dart:io';

import 'package:test/test.dart';

/// README path (relative to this package) to the prefix of its functions.
const Map<String, String> _readmes = <String, String>{
  '../../README.md': 'rootReadme',
  'README.md': 'firestoreReadme',
  '../../firebase_core/firebase_app_dart/README.md': 'appReadme',
  '../../firebase_auth/firebase_auth_providers_dart/README.md':
      'authProvidersReadme',
  '../../docs/migrating_from_vm_packages.md': 'migrationGuide',
  '../../docs/guides/getting_started.md': 'gettingStartedGuide',
  '../../docs/guides/offline_persistence.md': 'persistenceGuide',
  '../../docs/guides/multiple_clients.md': 'multipleClientsGuide',
  '../../docs/guides/pipelines.md': 'pipelinesGuide',
  '../../docs/guides/lite.md': 'liteGuide',
  '../../docs/guides/emulator_and_testing.md': 'testingGuide',
};

/// `import 'name.dart';` of a file that the reader copies from example/.
final RegExp _exampleImport = RegExp(r"^import '(\w+\.dart)';");

/// [line] (an import) with a file of example/ imported from there.
String _resolveImport(String line) {
  final RegExpMatch? match = _exampleImport.firstMatch(line);
  if (match != null && File('example/${match[1]}').existsSync()) {
    return "import '../../example/${match[1]}';";
  }
  return line;
}

const String _generated = 'test/readme/readme_snippets.dart';
const String _generatedLite = 'test/readme/readme_lite_snippets.dart';

/// What a snippet may assume to exist.
const String _context = '''
late FirebaseApp app;
late Firestore firestore;
late CollectionReference<Map<String, Object?>> users;
late Query<Map<String, Object?>> query;
late List<int> bundleBytes;
late String password;
late String keyFilePath;
''';

final RegExp _open = RegExp(r'^\s*```dart\s*$');
final RegExp _openLite = RegExp(r'^\s*```dart lite\s*$');

/// What a Firestore Lite snippet may assume to exist.
const String _liteContext = '''
late FirebaseApp app;
late Firestore firestore;
''';
final RegExp _close = RegExp(r'^\s*```\s*$');
final RegExp _classStart = RegExp(r'^(abstract\s+)?class\s');

String generate({bool lite = false}) {
  final RegExp open = lite ? _openLite : _open;
  final Set<String> imports = <String>{
    if (lite)
      "import 'package:cloud_firestore_dart/lite.dart';"
    else
      "import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';",
    "import 'package:firebase_app_dart/firebase_app_dart.dart';",
  };
  final List<String> declarations = <String>[];
  final List<String> functions = <String>[];

  _readmes.forEach((String path, String prefix) {
    final List<String> lines = File(path).readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (!open.hasMatch(lines[i])) {
        continue;
      }
      final int start = i + 1;
      final List<String> body = <String>[];
      for (i++; i < lines.length && !_close.hasMatch(lines[i]); i++) {
        final String line = lines[i];
        if (line.startsWith('import ')) {
          imports.add(_resolveImport(line.trim()));
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
      functions.add(<String>[
        '// $path:$start',
        'Future<void> ${prefix}Line$start() async {',
        ...body,
        '}',
        '',
      ].join('\n'));
    }
  });

  final List<String> sortedImports = imports.toList()..sort();
  return <String>[
    '// GENERATED from the README files by',
    '// test/unit/api/readme_snippets_test.dart. Do not edit: change the README',
    '// and regenerate (see that file).',
    '//',
    '// This file is only analyzed, never run.',
    '',
    '// ignore_for_file: type=lint, unused_local_variable, unused_import',
    '// ignore_for_file: unused_element',
    '',
    ...sortedImports,
    '',
    if (lite) _liteContext else _context,
    ...declarations,
    ...functions,
  ].join('\n');
}

void main() {
  final String? missing = _readmes.keys.cast<String?>().firstWhere(
      (String? path) => !File(path!).existsSync(),
      orElse: () => null);

  test('test/readme/readme_snippets.dart matches the READMEs', () {
    final File generated = File(_generated);
    final String actual = generate();
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      generated.writeAsStringSync(actual);
      return;
    }
    expect(generated.existsSync(), isTrue,
        reason: 'Missing $_generated. Run with UPDATE_GOLDEN=1.');
    expect(generated.readAsStringSync(), actual,
        reason: 'A README snippet changed. Regenerate with UPDATE_GOLDEN=1 '
            'dart test test/unit/api/readme_snippets_test.dart, then run '
            '`dart analyze test/readme`.');
  },
      skip: missing == null
          ? false
          : 'Needs a repository checkout: $missing is not part of the '
              'published package.');

  test('test/readme/readme_lite_snippets.dart matches the READMEs', () {
    final File generated = File(_generatedLite);
    final String actual = generate(lite: true);
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      generated.writeAsStringSync(actual);
      return;
    }
    expect(generated.existsSync(), isTrue,
        reason: 'Missing $_generatedLite. Run with UPDATE_GOLDEN=1.');
    expect(generated.readAsStringSync(), actual,
        reason: 'A README snippet changed. Regenerate with UPDATE_GOLDEN=1 '
            'dart test test/unit/api/readme_snippets_test.dart, then run '
            '`dart analyze test/readme`.');
    expect(RegExp('^Future<void> ', multiLine: true).allMatches(actual),
        isNotEmpty,
        reason: 'The READMEs have no Firestore Lite snippet to check');
  },
      skip: missing == null
          ? false
          : 'Needs a repository checkout: $missing is not part of the '
              'published package.');

  test('the README snippets compile against the current API', () async {
    final ProcessResult result = await Process.run(
        Platform.resolvedExecutable, <String>['analyze', 'test/readme']);
    expect(result.exitCode, 0,
        reason: 'A README snippet does not compile; fix it in the README and '
            'regenerate.\n${result.stdout}\n${result.stderr}');
  },
      skip: missing == null
          ? false
          : 'Needs a repository checkout: $missing is not part of the '
              'published package.',
      timeout: const Timeout(Duration(minutes: 3)));

  test('the READMEs have Dart snippets to check', () {
    expect(RegExp('^Future<void> ', multiLine: true).allMatches(generate()),
        hasLength(greaterThanOrEqualTo(7)));
  },
      skip: missing == null
          ? false
          : 'Needs a repository checkout: $missing is not part of the '
              'published package.');

  // test/readme/migration_example.dart (analyzed with the snippets above) has
  // the before/after code of every numbered section of the migration guide
  // that changes code; the last section (the example app) has none.
  test('the migration example covers every section of the migration guide',
      () {
    final List<String> sections = RegExp(r'^## (\d+)\. ', multiLine: true)
        .allMatches(
            File('../../docs/migrating_from_vm_packages.md').readAsStringSync())
        .map((Match m) => m.group(1)!)
        .toList();
    expect(sections, hasLength(greaterThanOrEqualTo(9)));
    final String example =
        File('test/readme/migration_example.dart').readAsStringSync();
    for (final String section in sections.take(sections.length - 1)) {
      expect(example, contains('// Section $section. '),
          reason: 'Section $section of the migration guide has no '
              'before/after code in test/readme/migration_example.dart');
    }
  },
      skip: missing == null
          ? false
          : 'Needs a repository checkout: $missing is not part of the '
              'published package.');
}
