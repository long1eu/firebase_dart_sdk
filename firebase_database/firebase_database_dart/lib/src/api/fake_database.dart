/// Factories of `package:firebase_database_dart/testing.dart`. JS: none; Android: none. Built over
/// `lib/src/testing/fake_server_actions.dart` and `lib/src/testing/in_memory_persistence_storage_engine.dart`.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/api/database_logger.dart';
import 'package:firebase_database_dart/src/api/database_persistence.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';

/// A [FirebaseDatabase] of [app] connected to [server] instead of the network.
///
/// It is memory only unless [persistence] is given (see [fakePersistence]). After a dropped connection it
/// reconnects after [reconnectDelay], fixed, with no backoff.
FirebaseDatabase databaseWithFakeServer(
  FirebaseApp app,
  FakeDatabaseServer server, {
  DatabasePersistence? persistence,
  DatabaseLogger? logger,
  Duration reconnectDelay = const Duration(seconds: 1),
}) => throw UnimplementedError();

/// Persistence over an in-memory engine whose server cache starts as [serverCache] (paths to JSON values),
/// as if a previous session had stored it. Durable for the life of the engine.
DatabasePersistence fakePersistence({
  Map<String, Object?> serverCache = const {},
}) => throw UnimplementedError();
