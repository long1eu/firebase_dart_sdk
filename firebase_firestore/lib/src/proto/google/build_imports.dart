// File created by
// Lung Razvan <long1eu>
// on 01/09/2019

import 'dart:io';
import 'package:path/path.dart';

void main() {
  final Directory directory = Directory('${Directory.current.path}/lib/src/proto/google');
  final List<Directory> dirs = directory.listSync(recursive: true).whereType<Directory>().toList();

  final StringBuffer _buffer = StringBuffer();
  for (Directory dir in dirs) {
    final List<String> names = dir
        .listSync()
        .whereType<File>()
        .map((File it) => it.absolute.path)
        .where((String it) => !it.endsWith('user.dart'))
        .map(basename)
        .toList()
          ..sort();

    final StringBuffer buffer = StringBuffer();
    for (String name in names) {
      buffer.writeln('export \'$name\';');
    }

    File('${dir.absolute.path}/user.dart').writeAsStringSync(buffer.toString());

    _buffer.writeln('export \'${dir.absolute.path.split('/lib/src/proto/google/')[1]}/user.dart\';');
  }
  File('${directory.path}/user.dart').writeAsStringSync(_buffer.toString());
}
