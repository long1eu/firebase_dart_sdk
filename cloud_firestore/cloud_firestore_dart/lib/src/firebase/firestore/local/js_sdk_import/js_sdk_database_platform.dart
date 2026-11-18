/// Opening and deleting the JS SDK's IndexedDB database, without importing `dart:js_interop` where it does not exist.
library;

export 'js_sdk_database_web.dart'
    if (dart.library.io) 'js_sdk_database_io.dart';
