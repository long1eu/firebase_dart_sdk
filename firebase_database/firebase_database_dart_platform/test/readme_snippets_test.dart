// Keeps the Dart snippets of the Flutter migration guide and of this package's README compiling.
//
// Every ```dart block of the files in [_readmes] is copied into its own file under test/readme
// (one file per block, because the blocks import packages that export the same names, such as
// firebase_database and firebase_database_dart), and those files are analyzed, so a snippet that
// no longer matches the API is an analyzer error. This test also fails when the generated files
// are out of date; regenerate them with
//
//     UPDATE_GOLDEN=1 flutter test test/readme_snippets_test.dart
//
// and fix whatever `dart analyze test/readme` then reports, in the guide or the README.
//
// Rules for a snippet: `import` lines and top-level classes are hoisted out of the function;
// everything else is a statement and may use `await`. The names declared in [_context]
// (DefaultFirebaseOptions) can be used without declaring them. A block without an import line gets
// [_defaultImports]. A block fenced as ```dart before (code of another SDK) is skipped.
//
// A block that imports a package this package does not depend on cannot be analyzed here; list
// its path and line in [_needsOtherPackages] (the guide or README still shows it as it is).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Doc path (relative to this package) to the prefix of its generated files.
const Map<String, String> _readmes = <String, String>{
  '../../docs/guides/database_flutter.md': 'guide',
  'README.md': 'readme',
};

/// Directory of the generated files.
const String _generatedDir = 'test/readme';

/// Blocks (`path:line`) that use a package that is not a dependency of this package.
const Set<String> _needsOtherPackages = <String>{};

/// Blocks of route B (the client's own Dart API) without an import line: they use the client, and
/// the `database` of the block before them.
const Set<String> _clientBlocks = <String>{
  '../../docs/guides/database_flutter.md:220',
};

/// What a snippet may assume to exist.
const String _context = '''
/// Stands for the firebase_options.dart that `flutterfire configure` generates.
class DefaultFirebaseOptions {
  static ctx.FirebaseOptions get currentPlatform => throw UnimplementedError();
}
''';

const String _contextImport =
    "import 'package:firebase_core/firebase_core.dart' as ctx show FirebaseOptions;";

/// Imports of a block that has none of its own.
const List<String> _clientImports = <String>[
  "import 'package:firebase_app_dart/firebase_app_dart.dart';",
  "import 'package:firebase_database_dart/firebase_database_dart.dart';",
];

/// Imports added to the defaults of a block that names other packages.
const Map<String, List<String>> _extraImports = <String, List<String>>{
  'README.md:65': <String>[
    "import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';",
  ],
  'README.md:98': <String>[
    "import 'package:firebase_app_check/firebase_app_check.dart';",
    "import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';",
  ],
  'README.md:73': <String>[
    "import 'package:firebase_auth/firebase_auth.dart';",
    "import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';",
  ],
};

const List<String> _defaultImports = <String>[
  "import 'package:firebase_core/firebase_core.dart';",
  "import 'package:firebase_database/firebase_database.dart';",
  "import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';",
];

final RegExp _open = RegExp(r'^\s*```dart\s*$');
final RegExp _close = RegExp(r'^\s*```\s*$');
final RegExp _classStart = RegExp(r'^(abstract\s+|final\s+)?class\s');

/// File name (inside [_generatedDir]) to content.
Map<String, String> generate() {
  final Map<String, String> files = <String, String>{};
  _readmes.forEach((String path, String prefix) {
    final List<String> lines = File(path).readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (!_open.hasMatch(lines[i])) {
        continue;
      }
      final int start = i + 1;
      final Set<String> imports = <String>{};
      final List<String> declarations = <String>[];
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
      if (_needsOtherPackages.contains('$path:$start')) {
        continue;
      }
      while (body.isNotEmpty && body.first.isEmpty) {
        body.removeAt(0);
      }
      while (body.isNotEmpty && body.last.isEmpty) {
        body.removeLast();
      }
      final bool client = _clientBlocks.contains('$path:$start');
      final bool usesContext = body.any(
        (String l) => l.contains('DefaultFirebaseOptions'),
      );
      final List<String> sortedImports =
          (imports.isNotEmpty
                ? imports.toList()
                : <String>[
                    ...(client ? _clientImports : _defaultImports),
                    ...?_extraImports['$path:$start'],
                  ])
            ..sort();
      files['${prefix}_line$start.dart'] = <String>[
        '// GENERATED from the docs by test/readme_snippets_test.dart. Do not edit: change the',
        '// document and regenerate (see that file).',
        '//',
        '// This file is only analyzed, never run.',
        '',
        '// ignore_for_file: type=lint, unused_local_variable, unused_import',
        '// ignore_for_file: unused_element',
        '',
        ...sortedImports,
        '',
        if (usesContext) ...<String>[_contextImport, '', _context],
        '// $path:$start',
        if (client) 'late FirebaseDatabase database;',
        ...declarations,
        'Future<void> ${prefix}Line$start() async {',
        ...body,
        '}',
        '',
      ].join('\n');
    }
  });
  return files;
}

void main() {
  final String? missing = _readmes.keys.cast<String?>().firstWhere(
    (String? path) => !File(path!).existsSync(),
    orElse: () => null,
  );
  final Object skip = missing == null
      ? false
      : 'Needs a repository checkout: $missing is not part of the published package.';

  test('test/readme matches the guide and the README', () {
    final Map<String, String> actual = generate();
    final Directory dir = Directory(_generatedDir);
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      dir.createSync(recursive: true);
      for (final File f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.dart') &&
            !actual.containsKey(f.uri.pathSegments.last)) {
          f.deleteSync();
        }
      }
      actual.forEach((String name, String content) {
        File('$_generatedDir/$name').writeAsStringSync(content);
      });
      return;
    }
    final Set<String> onDisk = dir.existsSync()
        ? dir
              .listSync()
              .whereType<File>()
              .map((File f) => f.uri.pathSegments.last)
              .toSet()
        : <String>{};
    expect(
      onDisk,
      actual.keys.toSet(),
      reason: 'A snippet was added or removed. Run with UPDATE_GOLDEN=1.',
    );
    actual.forEach((String name, String content) {
      expect(
        File('$_generatedDir/$name').readAsStringSync(),
        content,
        reason:
            'A snippet changed. Regenerate with UPDATE_GOLDEN=1 flutter test '
            'test/readme_snippets_test.dart, then run `dart analyze test/readme`.',
      );
    });
  }, skip: skip);

  test(
    'the snippets compile against the current API',
    () async {
      final ProcessResult result = await Process.run(_dart(), <String>[
        'analyze',
        _generatedDir,
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            'A snippet does not compile; fix it in the guide or the README and regenerate.\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the guide and the README have Dart snippets to check', () {
    final String names = generate().keys.join('\n');
    expect(
      RegExp(r'^guide_', multiLine: true).allMatches(names),
      hasLength(greaterThanOrEqualTo(5)),
    );
    expect(
      RegExp(r'^readme_', multiLine: true).allMatches(names),
      hasLength(greaterThanOrEqualTo(4)),
    );
  }, skip: skip);
}

/// The `dart` of the Flutter SDK that runs this test (`flutter analyze` would wait for the lock
/// that `flutter test` holds).
String _dart() {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && File('$root/bin/cache/dart-sdk/bin/dart').existsSync()) {
    return '$root/bin/cache/dart-sdk/bin/dart';
  }
  final String exe = Platform.resolvedExecutable;
  final int cache = exe.indexOf('/bin/cache/');
  if (cache > 0 &&
      File(
        '${exe.substring(0, cache)}/bin/cache/dart-sdk/bin/dart',
      ).existsSync()) {
    return '${exe.substring(0, cache)}/bin/cache/dart-sdk/bin/dart';
  }
  return 'dart';
}
