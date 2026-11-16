import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// Neither `dart:io` nor `dart:js_interop`: no SQLite binding.
OpenDatabase platformSqliteOpener({
  required String? directory,
  required int? pageCacheMb,
  required Uri sqlite3Wasm,
  required Uri? opfsWorker,
  required String storagePrefix,
  required Duration lockTimeout,
}) {
  throw UnsupportedError(
    'cloud_firestore_dart_sqlite needs dart:io (the Dart VM, Flutter) or '
    'dart:js_interop (a browser).',
  );
}
