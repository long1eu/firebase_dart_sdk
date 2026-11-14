// Imports a JSON file into a collection, exports a query to JSON, and watches
// a query. See README.md.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli/commands.dart';
import 'package:cli/firestore_from_env.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

Future<void> main(List<String> arguments) async {
  try {
    await buildRunner().run(arguments);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on ConfigurationError catch (e) {
    stderr.writeln(e);
    exitCode = 78;
  } on FirestoreError catch (e) {
    stderr.writeln('Firestore: ${e.message}');
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 66;
  } on FormatException catch (e) {
    stderr.writeln('Not valid JSON: ${e.message}');
    exitCode = 65;
  }
}
