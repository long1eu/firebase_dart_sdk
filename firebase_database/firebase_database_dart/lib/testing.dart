/// Fakes for testing code that uses `package:firebase_database_dart`: a scripted in-memory server
/// ([FakeDatabaseServer]), a database connected to it ([databaseWithFakeServer]) and in-memory persistence
/// ([fakePersistence]).
///
/// No stability promise beyond the package's contract tests.
///
/// ```dart
/// final FakeDatabaseServer server = FakeDatabaseServer();
/// final FirebaseDatabase db = databaseWithFakeServer(
///   app,
///   server,
///   persistence: fakePersistence(serverCache: <String, Object?>{'a': 1}),
/// );
/// ```
library firebase_database_dart.testing;

// Imported for the references in the documentation above.
import 'src/api/fake_database.dart';
import 'src/api/fake_database_server.dart';

export 'src/api/fake_database.dart'
    show databaseWithFakeServer, fakePersistence;
export 'src/api/fake_database_server.dart' show FakeDatabaseServer;
