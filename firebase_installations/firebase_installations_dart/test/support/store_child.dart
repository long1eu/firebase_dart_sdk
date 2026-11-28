import 'dart:io';

import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';

/// A second process for `file_store_test.dart`: opens a `FileKeyValueStore` in the directory given as
/// the first argument and reads one key.
///
/// Prints `ok` when the read succeeds, or the exception code on the first line and the message on the
/// second when it throws a `FirebaseInstallationsException`.
Future<void> main(List<String> arguments) async {
  final FileKeyValueStore store = FileKeyValueStore(arguments.single);
  try {
    await store.read('child-key');
    stdout.writeln('ok');
  } on FirebaseInstallationsException catch (error) {
    stdout
      ..writeln(error.code)
      ..writeln(error.message);
  } finally {
    await store.close();
  }
}
