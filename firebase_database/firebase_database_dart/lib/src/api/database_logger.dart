/// The logging types of the public API. JS: `core/util/util.ts` (`enableLogging`); Android:
/// `Logger.java`, `core/utilities/LogWrapper.java`.
///
/// Logging is a constructor parameter of `FirebaseDatabase`: pass a [DatabaseLogger] and the client calls
/// it with a [DatabaseLogLevel] (`debug`, `info`, `warning`, `error`) and a message. The client
/// puts database paths and index names in messages, never a token, a value you read or write, or
/// a query's bound values; a text from the server is passed on cut at 1 KiB ([DatabaseLogger]
/// lists what a message holds). With no logger the client is silent. There is no global switch;
/// FlutterFire's `setLoggingEnabled` is the shim's, which passes a callback that reads its own
/// flag.
library;

// Imported for the references in the documentation above.
import 'package:firebase_database_dart/src/core/util/logger.dart';

export 'package:firebase_database_dart/src/core/util/logger.dart'
    show DatabaseLogLevel, DatabaseLogger;
