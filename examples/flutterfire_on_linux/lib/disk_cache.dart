import 'dart:io';

import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the offline cache of Firestore in SQLite files under [directory] (or
/// the application support directory when it is empty), instead of memory.
///
/// The only place where the app names `cloud_firestore_dart_platform`: on Linux
/// the package registers itself with a memory cache, and `use` replaces that
/// configuration before the first Firestore operation.
Future<void> enableDiskCache(String directory) async {
  final String path = directory.isNotEmpty
      ? directory
      : '${(await getApplicationSupportDirectory()).path}/firestore';
  await Directory(path).create(recursive: true);
  CloudFirestoreDart.use(openDatabase: sqliteOpener(directory: path));
}
