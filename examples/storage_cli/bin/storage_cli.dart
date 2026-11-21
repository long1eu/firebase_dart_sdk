// Lists, uploads, downloads, prints, inspects and deletes Cloud Storage
// objects. See README.md.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:storage_cli/commands.dart';
import 'package:storage_cli/storage_from_env.dart';

Future<void> main(List<String> arguments) async {
  try {
    await buildRunner(out: stdout, err: stderr).run(arguments);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on ConfigurationError catch (e) {
    stderr.writeln(e);
    exitCode = 78;
  } on FirebaseStorageException catch (e) {
    stderr.writeln('Storage: ${e.code}: ${e.message}');
    exitCode = e.code == 'object-not-found' ? 66 : 1;
  } on FirebaseAuthException catch (e) {
    stderr.writeln('Sign-in: ${e.code}: ${e.message}');
    exitCode = 77;
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 66;
  }
}
