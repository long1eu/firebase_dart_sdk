import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/web.dart';

/// The default store on the web: the IndexedDB database `firebase_dart_kv`.
KeyValueStore createDefaultStore() => IndexedDbKeyValueStore();
