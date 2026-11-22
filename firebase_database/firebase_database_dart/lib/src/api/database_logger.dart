/// The logging types of the public API. JS: `core/util/util.ts` (`enableLogging`); Android:
/// `Logger.java`, `core/utilities/LogWrapper.java`.
///
/// Logging is a constructor parameter of `FirebaseDatabase`: pass a [DatabaseLogger] and the client calls
/// it with a [DatabaseLogLevel] and a message that never holds a token. With no logger the client is
/// silent. There is no global switch; FlutterFire's `setLoggingEnabled` is the shim's, which passes a
/// callback that reads its own flag.
library;

// Imported for the references in the documentation above.
import 'package:firebase_database_dart/src/api/merge_shims.dart';

// MERGE: point this export at 'package:firebase_database_dart/src/core/util/logger.dart' (seam change A10)
// and delete merge_shims.dart.
export 'package:firebase_database_dart/src/api/merge_shims.dart'
    show DatabaseLogLevel, DatabaseLogger;
