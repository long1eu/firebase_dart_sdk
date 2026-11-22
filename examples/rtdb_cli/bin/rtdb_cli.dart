// Reads and writes the Firebase Realtime Database. See README.md.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:rtdb_cli/commands.dart';
import 'package:rtdb_cli/parsing.dart';

Future<void> main(List<String> arguments) async {
  try {
    await buildRunner(out: stdout).run(arguments);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on UsageError catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on ConfigurationError catch (e) {
    stderr.writeln(e);
    exitCode = 78;
  } on FirebaseDatabaseException catch (e) {
    stderr.writeln('${e.code}: ${e.message}');
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 66;
  }
}
