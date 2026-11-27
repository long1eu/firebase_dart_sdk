/// For authors of persistence engines: the synchronous [PersistenceStorageEngine] interface, its record
/// types, and [databasePersistence], which turns a [PersistenceStorageEngineOpener] into the
/// `DatabasePersistence` a `FirebaseDatabase` takes. The client calls the opener once at start with the
/// instance's [PersistenceKey] and its logger, which receives lease, degraded-mode and storage failures.
///
/// [Path], [ChildKey], [Node], [CompoundWrite], [QuerySpec] and [PruneForest] are the ports of Android's core
/// types that the interface needs; they are exported only here, never from the main library.
/// [Index], [KeyIndex] and [NamedNode] are exported because [Node] and [QuerySpec] name them.
/// `nodeFromJson`, `keyIndex`, `ImmutableTree` and `estimateSerializedNodeSize` are the helpers an engine
/// needs to read, walk and size stored data. An engine stores a query as its path and
/// `QuerySpec.toWireObject()`, and rebuilds it with `QuerySpec.fromPathAndWireObject`.
/// [InMemoryPersistenceStorageEngine] is the reference engine that every engine's behaviour is checked
/// against. [persistenceDatabaseUrl] turns any spelling of a database URL into the one the client
/// puts in [PersistenceKey.databaseUrl], for an engine function that deletes a cache by URL.
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(
///   app,
///   persistence: databasePersistence(
///     opener: (PersistenceKey key, {DatabaseLogger? logger}) async => MyEngine.open(key, logger),
///     cacheSizeBytes: 20 * 1024 * 1024,
///   ),
/// );
/// ```
library firebase_database_dart.storage_engine;

// Imported for the references in the documentation above.
import 'src/core/persistence/database_persistence.dart';
import 'src/core/compound_write.dart';
import 'src/core/path.dart';
import 'src/core/persistence/persistence_storage_engine.dart';
import 'src/core/persistence/persistence_storage_engine_opener.dart';
import 'src/core/persistence/prune_forest.dart';
import 'src/core/snap/child_key.dart';
import 'src/core/snap/indexes/index.dart';
import 'src/core/snap/indexes/key_index.dart';
import 'src/core/snap/named_node.dart';
import 'src/core/snap/node.dart';
import 'src/core/view/query_spec.dart';
import 'src/realtime/database_url.dart';
import 'src/testing/in_memory_persistence_storage_engine.dart';

export 'src/core/persistence/database_persistence.dart'
    show databasePersistence;
export 'src/core/compound_write.dart' show CompoundWrite;
export 'src/core/path.dart' show Path;
export 'src/core/persistence/persistence_storage_engine.dart'
    show PersistenceStorageEngine;
export 'src/core/persistence/persistence_storage_engine_opener.dart'
    show PersistenceKey, PersistenceStorageEngineOpener;
export 'src/core/persistence/prune_forest.dart' show PruneForest;
export 'src/core/persistence/tracked_query.dart' show TrackedQuery;
export 'src/core/snap/child_key.dart' show ChildKey;
export 'src/core/snap/indexes/index.dart' show Index;
export 'src/core/snap/indexes/key_index.dart' show KeyIndex, keyIndex;
export 'src/core/snap/named_node.dart' show NamedNode;
export 'src/core/snap/node.dart' show Node;
export 'src/core/snap/node_from_json.dart' show nodeFromJson;
export 'src/core/user_write_record.dart' show UserWriteRecord;
export 'src/realtime/database_url.dart' show persistenceDatabaseUrl;
export 'src/core/util/immutable_tree.dart' show ImmutableTree;
export 'src/core/util/node_size_estimator.dart' show estimateSerializedNodeSize;
export 'src/core/view/query_spec.dart' show QuerySpec;
export 'src/testing/in_memory_persistence_storage_engine.dart'
    show InMemoryPersistenceStorageEngine;
