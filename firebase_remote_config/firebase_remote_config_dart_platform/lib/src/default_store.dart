import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart_platform/src/default_store_io.dart'
    if (dart.library.js_interop) 'package:firebase_remote_config_dart_platform/src/default_store_web.dart';

KeyValueStore? _sharedStore;

/// The store of every per-app instance when `FirebaseRemoteConfigDart.use`
/// got none: one per isolate (not per process), created on first call.
///
/// On the VM it keeps its files in `firebase_dart` under the application
/// support directory; on the web it is the IndexedDB database
/// `firebase_dart_kv`. The records of each app are kept under the app's
/// `persistenceKey`, so the apps can share it.
KeyValueStore defaultStore() => _sharedStore ??= createDefaultStore();
