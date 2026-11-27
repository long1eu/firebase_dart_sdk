// Parity row emu.env: FirebaseDatabase.emulatorHostFromEnvironment reads FIREBASE_DATABASE_EMULATOR_HOST
// of the running process. The read is checked in a child process started with the variable set,
// set to blanks, and set to a value with blanks around it.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const String _child =
    'test/api/support/print_emulator_host_from_environment.dart';

Future<Object?> _readInChild(String value) async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>[_child],
    environment: <String, String>{'FIREBASE_DATABASE_EMULATOR_HOST': value},
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode((result.stdout as String).trim());
}

void main() {
  test('the variable of the process is read', () async {
    expect(await _readInChild('127.0.0.1:9000'), '127.0.0.1:9000');
  });

  test('blanks around the value are dropped', () async {
    expect(await _readInChild('  localhost:9100 '), 'localhost:9100');
  });

  test('an empty value reads as null', () async {
    expect(await _readInChild('  '), isNull);
  });
}
