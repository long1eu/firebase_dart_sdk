// Points generated Data Connect code at this package, so that it runs on the VM without Flutter.
//
// Usage: dart run firebase_data_connect_dart:rewrite_generated [--check] <directory>
//
// In every .dart file under <directory> it replaces the line
//   import 'package:firebase_data_connect/firebase_data_connect.dart';
// with
//   import 'package:firebase_data_connect_dart/flutterfire.dart';
// and every line
//   import 'package:flutter/foundation.dart';
// with
//   import 'package:meta/meta.dart';
// (either quote style), then removes repeated identical import lines, keeping the first. It refuses
// (exit 1, file and line named, nothing written) when a file imports any other package:flutter/
// library, or imports foundation.dart with show, hide or as. It is idempotent. With --check it
// writes nothing and exits 1 when a file would change. Exit 2 is a usage error. The application
// depends on firebase_data_connect_dart and meta.

import 'dart:io';

final RegExp _dataConnectImport = RegExp(
  r'''^\s*import\s+(['"])package:firebase_data_connect/firebase_data_connect\.dart\1\s*;\s*$''',
);
final RegExp _foundationImport = RegExp(
  r'''^\s*import\s+(['"])package:flutter/foundation\.dart\1\s*;\s*$''',
);
final RegExp _flutterImport = RegExp(r'''^\s*import\s+['"]package:flutter/''');
final RegExp _anyImport = RegExp(r'^\s*import\s.*;\s*$');

const String _compatImport =
    "import 'package:firebase_data_connect_dart/flutterfire.dart';";
const String _metaImport = "import 'package:meta/meta.dart';";

/// Runs the command with [arguments] and sets the exit code.
void main(List<String> arguments) {
  exitCode = run(arguments);
}

/// Runs the command; returns the exit code: 0 done, 1 refused or (with `--check`) a file would
/// change, 2 usage error.
int run(List<String> arguments) {
  final bool check = arguments.contains('--check');
  final List<String> rest = <String>[
    for (final String argument in arguments)
      if (argument != '--check') argument,
  ];
  if (rest.length != 1 || rest.single.startsWith('-')) {
    stderr.writeln(
      'usage: dart run firebase_data_connect_dart:rewrite_generated [--check] <directory>',
    );
    return 2;
  }
  final Directory directory = Directory(rest.single);
  if (!directory.existsSync()) {
    stderr.writeln('rewrite_generated: ${directory.path} is not a directory');
    return 2;
  }
  final Map<File, String> changes = <File, String>{};
  final List<String> refusals = <String>[];
  for (final File file in _dartFiles(directory)) {
    final String original = file.readAsStringSync();
    final _Rewrite rewrite = _rewrite(original);
    if (rewrite.refusals.isNotEmpty) {
      for (final String refusal in rewrite.refusals) {
        refusals.add('${file.path}:$refusal');
      }
    } else if (rewrite.text != original) {
      changes[file] = rewrite.text;
    }
  }
  return _finish(changes, refusals, check: check);
}

int _finish(
  Map<File, String> changes,
  List<String> refusals, {
  required bool check,
}) {
  if (refusals.isNotEmpty) {
    refusals.forEach(stderr.writeln);
    stderr.writeln('rewrite_generated: refused; no file was written');
    return 1;
  }
  if (check) {
    for (final File file in changes.keys) {
      stdout.writeln('would change ${file.path}');
    }
    return changes.isEmpty ? 0 : 1;
  }
  changes.forEach(_writeThroughTemporary);
  stdout.writeln('rewrite_generated: ${changes.length} file(s) changed');
  return 0;
}

List<File> _dartFiles(Directory directory) {
  final List<File> files = <File>[
    for (final FileSystemEntity entity in directory.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

/// The rewritten text of one file, or why it is refused (`<line>: <reason>` each).
final class _Rewrite {
  _Rewrite(this.text, this.refusals);

  final String text;
  final List<String> refusals;
}

_Rewrite _rewrite(String original) {
  final List<String> lines = original.split('\n');
  final List<String> output = <String>[];
  final List<String> refusals = <String>[];
  final Set<String> imports = <String>{};
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final bool carriageReturn = line.endsWith('\r');
    final String content = carriageReturn
        ? line.substring(0, line.length - 1)
        : line;
    final String? replaced = _replacement(content, i + 1, refusals);
    final String kept = replaced ?? content;
    if (_anyImport.hasMatch(kept) && !imports.add(kept.trim())) {
      continue;
    }
    output.add(carriageReturn ? '$kept\r' : kept);
  }
  return _Rewrite(output.join('\n'), refusals);
}

/// The replacement of [line] (number [number]), or null to keep it. Adds to [refusals] a Flutter
/// import that is not the plain `foundation.dart` import.
String? _replacement(String line, int number, List<String> refusals) {
  if (_dataConnectImport.hasMatch(line)) {
    return _compatImport;
  }
  if (_foundationImport.hasMatch(line)) {
    return _metaImport;
  }
  if (_flutterImport.hasMatch(line)) {
    refusals.add(
      '$number: imports a package:flutter/ library other than a plain '
      "import 'package:flutter/foundation.dart';",
    );
  }
  return null;
}

void _writeThroughTemporary(File file, String text) {
  final String name = file.uri.pathSegments.last;
  final File temporary = File(
    '${file.parent.path}/.$name.rewrite_generated.tmp',
  );
  temporary.writeAsStringSync(text, flush: true);
  temporary.renameSync(file.path);
}
