/// An unofficial, pure-Dart client of the Firebase Realtime Database.
///
/// Create a [FirebaseDatabase] for a `FirebaseApp`, get a [DatabaseReference] with [FirebaseDatabase.ref],
/// listen with its `on<Thing>` streams and write with `set`, `update` and transactions. Errors from the
/// server are [FirebaseDatabaseException]s. This library imports no `dart:io` and no native code.
///
/// Work in progress: tested against the Database emulator, not yet against a production database.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_database_dart/firebase_database_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///   );
///   final FirebaseDatabase db = FirebaseDatabase(app);
///   await db.ref('greetings').push().set(<String, Object?>{'text': 'hello'});
///   final DataSnapshot snapshot = await db.ref('greetings').get();
///   for (final DataSnapshot child in snapshot.children) {
///     print(child.value);
///   }
///   await db.close();
/// }
/// ```
library firebase_database_dart;

// Imported for the references in the documentation above.
import 'src/api/database_reference.dart';
import 'src/api/firebase_database.dart';
import 'src/api/firebase_database_exception.dart';

export 'src/api/data_snapshot.dart' show DataSnapshot;
export 'src/api/database_event.dart' show DatabaseEvent;
export 'src/api/database_event_type.dart' show DatabaseEventType;
export 'src/api/database_logger.dart' show DatabaseLogLevel, DatabaseLogger;
export 'src/core/persistence/database_persistence.dart'
    show DatabasePersistence;
export 'src/api/database_reference.dart' show DatabaseReference;
export 'src/api/firebase_database.dart' show FirebaseDatabase;
export 'src/api/firebase_database_exception.dart'
    show FirebaseDatabaseException;
export 'src/api/mock_user_token.dart' show mockUserTokenFor;
export 'src/api/on_disconnect.dart' show OnDisconnect;
export 'src/api/query.dart' show Query;
export 'src/api/server_value.dart' show ServerValue;
export 'src/api/transaction.dart' show Transaction;
export 'src/api/transaction_handler.dart' show TransactionHandler;
export 'src/api/transaction_result.dart' show TransactionResult;
