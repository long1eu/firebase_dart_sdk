/// Creating the IndexedDB persistence, without importing `dart:js_interop` where it does not exist.
library;

export 'web/indexeddb_persistence_web.dart'
    if (dart.library.io) 'indexeddb_persistence_io.dart';
