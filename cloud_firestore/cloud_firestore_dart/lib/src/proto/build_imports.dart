// File created by
// Lung Razvan <long1eu>
// on 01/09/2019

import 'dart:io';

import 'package:path/path.dart';

void main() {
  final Directory directory = Directory(
    '${Directory.current.path}/lib/src/proto',
  );
  final List<Directory> dirs = directory
      .listSync(recursive: true)
      .whereType<Directory>()
      .toList();

  final StringBuffer userExports = StringBuffer();
  for (Directory dir in dirs) {
    final List<String> names =
        dir
            .listSync()
            .whereType<File>()
            .map((File it) => it.absolute.path)
            .where((String it) => !it.endsWith('index.dart'))
            .map(basename)
            .toList()
          ..sort();

    final StringBuffer buffer = StringBuffer();
    for (String name in names) {
      buffer.writeln('export \'$name\';');
    }

    File(
      '${dir.absolute.path}/index.dart',
    ).writeAsStringSync(buffer.toString());

    userExports.writeln(
      // `posix` separators also on Windows: an import URI always uses `/`.
      'export \'${posix.joinAll(split(relative(dir.path, from: directory.path)))}/index.dart\';',
    );
  }
  File('${directory.path}/user.dart').writeAsStringSync(userExports.toString());
}
