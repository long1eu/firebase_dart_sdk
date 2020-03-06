// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

import 'dart:io';

import 'package:tools/run_command.dart';

/// Return the examples app root
Future<String> createPackage(
    String description, String org, String name, String path) async {
  await runCommand(
    'flutter',
    <String>[
      'create',
      '-t',
      'package',
      '--description',
      description,
      '--org',
      org,
      '--project-name',
      name,
      path
    ],
    workingDirectory: Directory.current.absolute.path,
  );

  return _createExampleApp(name, org, path);
}

Future<String> _createExampleApp(String name, String org, String path) async {
  await runCommand(
    'flutter',
    <String>[
      'create',
      '-t',
      'app',
      '--description',
      'Example app for $name',
      '--org',
      org,
      '--project-name',
      '$name\_example',
      '$path/example'
    ],
    workingDirectory: Directory.current.absolute.path,
  );

  return '${Directory.current.absolute.path}/$path/example';
}
