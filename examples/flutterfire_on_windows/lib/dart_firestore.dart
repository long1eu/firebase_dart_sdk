import 'dart:io';

import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:path_provider/path_provider.dart';

/// Makes `cloud_firestore_dart` the implementation of `cloud_firestore`.
///
/// The only place where the app names `cloud_firestore_dart_platform`. On
/// Windows the official `cloud_firestore` plugin has a native implementation
/// (the Firebase C++ SDK), which Flutter registers before `main()`; `use`
/// replaces it, and must run before the first Firestore operation.
/// `firebase_core` keeps its native implementation.
///
/// With [diskCache] the offline cache is kept in SQLite files under
/// [directory] (or the application support directory when it is empty);
/// otherwise it is in memory.
Future<void> useDartFirestore({
  required bool diskCache,
  String directory = '',
}) async {
  if (!diskCache) {
    CloudFirestoreDart.use();
    return;
  }
  final String path = directory.isNotEmpty
      ? directory
      : '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}firestore';
  await Directory(path).create(recursive: true);
  CloudFirestoreDart.use(openDatabase: sqliteOpener(directory: path));
}
