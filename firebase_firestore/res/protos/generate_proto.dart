// File created by
// Lung Razvan <long1eu>
// on 16/10/2018

import 'dart:io';

void main() async {
  final String lib = '${Directory.current.path}/lib/src/proto';
  final String path = '${Directory.current.path}/res/protos';

  await Directory(path)
      .list(recursive: true)
      .where((FileSystemEntity it) => it.path.endsWith('.proto'))
      .map((FileSystemEntity it) => it.path.split('/res/protos/')[1])
      .asyncMap((String it) async {
    if (!File('$lib/$it').parent.existsSync()) {
      File('$lib/$it').parent.createSync(recursive: true);
    }

    return Process.run(
      'protoc',
      <String>[
        it,
        '--dart_out=$lib',
      ],
      workingDirectory: path,
    );
  }).toList();
}
