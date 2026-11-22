/// Factories of `package:firebase_database_dart/testing.dart`. JS: none; Android: none. Built over
/// `lib/src/testing/fake_server_actions.dart` and `lib/src/testing/in_memory_persistence_storage_engine.dart`.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/api/database_logger.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';

/// A [FirebaseDatabase] of [app] connected to [server] instead of the network.
///
/// It is memory only unless [persistence] is given (see [fakePersistence]). After a dropped connection it
/// reconnects after [reconnectDelay], fixed, with no backoff. Each connection sends the token of the app's
/// `authProvider` (none when the app has no provider), which [FakeDatabaseServer.receivedAuthTokens]
/// records.
FirebaseDatabase databaseWithFakeServer(
  FirebaseApp app,
  FakeDatabaseServer server, {
  DatabasePersistence? persistence,
  DatabaseLogger? logger,
  Duration reconnectDelay = const Duration(seconds: 1),
}) {
  Future<String?> tokenSource(bool forceRefresh) async {
    final AuthTokenProvider provider = app.authProvider;
    if (identical(provider, app)) {
      return null;
    }
    try {
      return (await provider.getAccessToken(forceRefresh: forceRefresh)).token;
    } on Object {
      return null;
    }
  }

  final AuthTokenProvider provider = app.authProvider;
  return firebaseDatabaseWithConnection(
    app,
    persistence: persistence,
    logger: logger,
    connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
        server.connect(
          delegate,
          reconnectDelay: reconnectDelay,
          tokenSource: tokenSource,
          tokenChanges: identical(provider, app)
              ? null
              : provider.onTokenChanged,
        ),
  );
}

/// Persistence over an in-memory engine whose server cache starts as [serverCache] (paths to JSON values),
/// as if a previous session had stored it. Durable for the life of the engine.
///
/// Each entry is stored as server data and as a complete, inactive tracked default query at its path, so
/// `Query.get` can answer from it offline.
DatabasePersistence fakePersistence({
  Map<String, Object?> serverCache = const {},
}) {
  PersistenceStorageEngine? engine;
  return databasePersistence(
    opener: (PersistenceKey key, {DatabaseLogger? logger}) async {
      final PersistenceStorageEngine? existing = engine;
      if (existing != null) {
        return existing;
      }
      final InMemoryPersistenceStorageEngine created =
          InMemoryPersistenceStorageEngine()..logger = logger;
      final int now = DateTime.now().millisecondsSinceEpoch;
      int id = 0;
      created.beginTransaction();
      try {
        for (final MapEntry<String, Object?> entry in serverCache.entries) {
          final Path path = Path(entry.key);
          created
            ..overwriteServerCache(path, nodeFromJson(entry.value))
            ..saveTrackedQuery(
              TrackedQuery(
                id: id++,
                querySpec: QuerySpec.defaultAt(path),
                lastUse: now,
                complete: true,
                active: false,
              ),
            );
        }
        created.setTransactionSuccessful();
      } finally {
        created.endTransaction();
      }
      return engine = created;
    },
  );
}
