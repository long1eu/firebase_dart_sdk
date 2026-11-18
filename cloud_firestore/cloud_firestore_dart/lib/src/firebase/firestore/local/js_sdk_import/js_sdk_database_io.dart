import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database.dart';

/// Whether this platform can hold a database of the JS SDK: only the web.
const bool jsSdkDatabaseSupported = false;

/// There is no IndexedDB here.
Future<JsSdkDatabase?> openJsSdkDatabase(String name) async => null;

/// There is no IndexedDB here.
Future<void> deleteJsSdkDatabase(String name) async {}

/// There is no LocalStorage here.
bool isJsSdkClientZombied(String storagePrefix, String clientId) => false;
