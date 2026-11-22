/// For authors of persistence engines: the synchronous [PersistenceStorageEngine] interface, its record
/// types, and [databasePersistence], which turns an engine opener into the `DatabasePersistence` a
/// `FirebaseDatabase` takes.
///
/// [Path], [ChildKey], [Node], [CompoundWrite], [QuerySpec] and [PruneForest] are the ports of Android's core
/// types that the interface needs; they are exported only here, never from the main library.
/// [InMemoryPersistenceStorageEngine] is the reference engine that every engine's behaviour is checked
/// against.
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(
///   app,
///   persistence: databasePersistence((PersistenceKey key) async => MyEngine.open(key)),
/// );
/// ```
library firebase_database_dart.storage_engine;

// Imported for the references in the documentation above.
import 'src/api/database_persistence.dart';
import 'src/core/compound_write.dart';
import 'src/core/path.dart';
import 'src/core/persistence/persistence_storage_engine.dart';
import 'src/core/persistence/prune_forest.dart';
import 'src/core/snap/child_key.dart';
import 'src/core/snap/node.dart';
import 'src/core/view/query_spec.dart';
import 'src/testing/in_memory_persistence_storage_engine.dart';

export 'src/api/database_persistence.dart' show databasePersistence;
export 'src/core/compound_write.dart' show CompoundWrite;
export 'src/core/path.dart' show Path;
export 'src/core/persistence/persistence_storage_engine.dart'
    show PersistenceStorageEngine;
export 'src/core/persistence/persistence_storage_engine_opener.dart'
    show PersistenceKey;
export 'src/core/persistence/prune_forest.dart' show PruneForest;
export 'src/core/persistence/tracked_query.dart' show TrackedQuery;
export 'src/core/snap/child_key.dart' show ChildKey;
export 'src/core/snap/node.dart' show Node;
export 'src/core/user_write_record.dart' show UserWriteRecord;
export 'src/core/view/query_spec.dart' show QuerySpec;
export 'src/testing/in_memory_persistence_storage_engine.dart'
    show InMemoryPersistenceStorageEngine;
