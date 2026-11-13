// Compiles the two sample applications next to this file to JavaScript and
// checks the result. Run it through tool/check_size.sh.
//
//   dart tool/size/check_size.dart <package_config.json> <output directory>
//
// For both applications it prints the size of the JavaScript, raw and
// gzipped, and how much of it is code of cloud_firestore_dart. For the lite
// application it also checks, with the `--dump-info` output of the compiler,
//   - that no code of the local store, the sync engine, the remote store or
//     the WebChannel transport is in the program, and
//   - that the program is within the budget below.
//
// Exits with 1 when a check fails.

import 'dart:convert';
import 'dart:io';

/// The budget of the lite application, in characters of JavaScript and in
/// bytes of its gzipped form. Measured with Dart 3.12.2: 415,850 and 128,303.
/// The numbers move with the Dart SDK (most of the program is the Dart
/// runtime), so CI runs this check with that SDK. Raise the budget
/// deliberately, with the new numbers in this comment and in the README.
const int liteBudget = 450000;
const int liteGzipBudget = 140000;

/// Libraries of the main library that a lite program must not contain code
/// of, as parts of their URI.
const List<String> forbiddenInLite = <String>[
  '/firestore/local/',
  '/firestore/core/sync_engine.dart',
  '/firestore/core/view.dart',
  '/firestore/core/event_manager.dart',
  '/firestore/core/firestore_client.dart',
  '/firestore/remote/remote_store.dart',
  '/firestore/remote/datastore/web/web_channel',
  '/firestore/bundle/',
  'package:sqlite3/',
];

class Build {
  Build(this.name, this.size, this.gzipSize, this.libraries);

  final String name;
  final int size;
  final int gzipSize;

  /// The size of the code of each library in the program, by URI.
  final Map<String, int> libraries;

  int get packageSize => libraries.entries
      .where(
        (MapEntry<String, int> entry) =>
            entry.key.startsWith('package:cloud_firestore_dart/'),
      )
      .fold(0, (int sum, MapEntry<String, int> entry) => sum + entry.value);
}

Future<Build> build(String name, String packages, String out) async {
  final String source = File.fromUri(
    Platform.script.resolve('${name}_app.dart'),
  ).path;
  final String js = '$out/${name}_app.js';
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>[
      'compile',
      'js',
      '-O2',
      '--dump-info=json',
      '--packages=$packages',
      '-o',
      js,
      source,
    ],
  );
  if (result.exitCode != 0) {
    stderr.writeln(
      'Compiling $source failed:\n${result.stdout}${result.stderr}',
    );
    exit(2);
  }
  final List<int> bytes = File(js).readAsBytesSync();
  final Map<String, Object?> info =
      jsonDecode(File('$js.info.json').readAsStringSync())
          as Map<String, Object?>;
  final Map<String, Object?> libraries =
      (info['elements']! as Map<String, Object?>)['library']!
          as Map<String, Object?>;
  return Build(
    name,
    utf8.decode(bytes).length,
    gzip.encode(bytes).length,
    <String, int>{
      for (final Map<String, Object?> library
          in libraries.values.cast<Map<String, Object?>>())
        (library['canonicalUri'] ?? library['name'])! as String:
            library['size']! as int,
    },
  );
}

String thousands(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+$)'),
  (Match match) => ',',
);

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/size/check_size.dart <package_config.json> <out dir>',
    );
    exit(2);
  }
  Directory(arguments[1]).createSync(recursive: true);
  final Build lite = await build('lite', arguments[0], arguments[1]);
  final Build full = await build('full', arguments[0], arguments[1]);

  print('Dart ${Platform.version.split(' ').first}, dart compile js -O2');
  print('app    JavaScript    gzipped    of it cloud_firestore_dart');
  for (final Build build in <Build>[lite, full]) {
    print(
      '${build.name.padRight(6)} '
      '${thousands(build.size).padLeft(10)} '
      '${thousands(build.gzipSize).padLeft(10)} '
      '${thousands(build.packageSize).padLeft(10)}',
    );
  }

  final List<String> failures = <String>[];
  final List<String> unexpected = <String>[
    for (final MapEntry<String, int> library in lite.libraries.entries)
      if (library.value > 0 && forbiddenInLite.any(library.key.contains))
        '${library.key} (${library.value})',
  ]..sort();
  if (unexpected.isEmpty) {
    print(
      'lite: no code of the local store, the sync engine, the remote store '
      'or WebChannel',
    );
  } else {
    failures.add(
      'The lite application contains code that Firestore Lite must not pull '
      'in:\n  ${unexpected.join('\n  ')}',
    );
  }
  // The check of the dump is only worth something while it can tell the two
  // programs apart.
  if (!full.libraries.entries.any(
    (MapEntry<String, int> library) =>
        library.value > 0 && library.key.contains('/firestore/local/'),
  )) {
    failures.add(
      'The full application has no code of the local store: the dump-info '
      'check no longer sees what it is looking for.',
    );
  }
  if (lite.size > liteBudget) {
    failures.add(
      'The lite application is ${thousands(lite.size)} characters of '
      'JavaScript, over the budget of ${thousands(liteBudget)}.',
    );
  }
  if (lite.gzipSize > liteGzipBudget) {
    failures.add(
      'The lite application is ${thousands(lite.gzipSize)} bytes gzipped, '
      'over the budget of ${thousands(liteGzipBudget)}.',
    );
  }
  if (failures.isEmpty) {
    print(
      'lite: within the budget of ${thousands(liteBudget)} '
      '(${thousands(liteGzipBudget)} gzipped)',
    );
    return;
  }
  failures.forEach(stderr.writeln);
  exit(1);
}
