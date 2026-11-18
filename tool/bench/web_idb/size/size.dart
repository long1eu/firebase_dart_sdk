// Compiles memory_app.dart and sqlite_app.dart with dart2js (-O2, as
// tool/check_size.sh) and with dart2wasm (-O2, the default), and prints the
// sizes, raw and gzipped, plus the share of the dart2js output that is code of
// the SQLite layer, by library group (from --dump-info).
//
//   cd tool/bench/web_idb && dart pub get && dart size/size.dart [out dir]
//
// Part of docs/spikes/indexeddb_cache.md.

import 'dart:convert';
import 'dart:io';

final String here = File.fromUri(Platform.script).parent.path;

int gz(List<int> bytes) => gzip.encode(bytes).length;

String row(String name, File file) {
  final List<int> bytes = file.readAsBytesSync();
  return '| $name | ${bytes.length} | ${gz(bytes)} |';
}

Future<void> run(List<String> args) async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    args,
    workingDirectory: '$here/..',
  );
  if (result.exitCode != 0) {
    stderr.writeln(
      '${args.join(' ')} failed:\n${result.stdout}${result.stderr}',
    );
    exit(2);
  }
}

Future<void> main(List<String> arguments) async {
  final String out = arguments.isEmpty
      ? Directory.systemTemp.createTempSync('web_idb_size').path
      : arguments.single;
  Directory(out).createSync(recursive: true);
  final List<String> lines = <String>[
    'Dart ${Platform.version.split(' ').first}',
    '| file | bytes | gzipped |',
    '| --- | ---: | ---: |',
  ];
  for (final String app in <String>['memory', 'sqlite']) {
    final String source = '$here/${app}_app.dart';
    await run(<String>[
      'compile',
      'js',
      '-O2',
      '--dump-info=json',
      '-o',
      '$out/$app.js',
      source,
    ]);
    await run(<String>[
      'compile',
      'wasm',
      '-O2',
      '-o',
      '$out/$app.wasm',
      source,
    ]);
    lines
      ..add(row('$app.js (dart2js -O2)', File('$out/$app.js')))
      ..add(row('$app.wasm (dart2wasm -O2)', File('$out/$app.wasm')))
      ..add(row('$app.mjs (dart2wasm loader)', File('$out/$app.mjs')));

    // The dart2js dump: size of the code per library group.
    final Map<String, Object?> info =
        jsonDecode(File('$out/$app.js.info.json').readAsStringSync())
            as Map<String, Object?>;
    final Map<String, Object?> libraries =
        (info['elements']! as Map<String, Object?>)['library']!
            as Map<String, Object?>;
    final Map<String, int> groups = <String, int>{};
    for (final Map<String, Object?> library
        in libraries.values.cast<Map<String, Object?>>()) {
      final String uri =
          (library['canonicalUri'] ?? library['name'])! as String;
      final int size = library['size']! as int;
      final String group = uri.contains('/firestore/local/sqlite/')
          ? 'cloud_firestore_dart local/sqlite/'
          : uri.contains('/firestore/local/memory/')
          ? 'cloud_firestore_dart local/memory/'
          : uri.startsWith('package:sqlite3/')
          ? 'package:sqlite3'
          : uri.startsWith('package:cloud_firestore_dart_sqlite/')
          ? 'package:cloud_firestore_dart_sqlite'
          : uri.startsWith('package:cloud_firestore_dart/')
          ? 'cloud_firestore_dart, the rest'
          : 'everything else';
      groups[group] = (groups[group] ?? 0) + size;
    }
    lines.add('');
    lines.add('$app.js by library group (dart2js dump-info, bytes of code):');
    for (final MapEntry<String, int> entry in groups.entries) {
      lines.add('  ${entry.key}: ${entry.value}');
    }
    lines.add('');
  }
  final Directory web = Directory(
    '$here/../../../../cloud_firestore/cloud_firestore_dart/test/browser',
  );
  for (final String asset in <String>[
    'sqlite3.wasm',
    'opfs/sqlite_opfs_worker.js',
  ]) {
    final File file = File('${web.path}/$asset');
    if (file.existsSync()) {
      lines.add(row(asset, file));
    }
  }
  print(lines.join('\n'));
  print('Output in $out');
}
