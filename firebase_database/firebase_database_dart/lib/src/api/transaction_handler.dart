/// The function a transaction runs. JS: `api/Reference_impl.ts` (`transactionUpdate`); Android:
/// `Transaction.Handler.doTransaction`.
library;

// Imported for the references in the documentation below.
import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:firebase_database_dart/src/api/transaction.dart';

/// Computes the new value of a location from its [currentValue], for [DatabaseReference.runTransaction].
///
/// The handler is synchronous and may run several times: first with the value the client holds locally
/// (null when it holds none, also when the server has data), then again with the server's value each time
/// the server says the local one was stale. An abort on that first null ends the transaction with no
/// write. To get the server's value, return a value for null instead (`Transaction.success(null)` works):
/// when the server holds other data, it answers that the value was stale and the handler runs again with
/// the server's value. Each run gets a fresh, mutable deep copy of the value, without its priority, so
/// changing the map or list it receives (lists can grow) and returning it is safe. Return
/// [Transaction.success] to write or
/// [Transaction.abort] to stop. An exception thrown by the handler aborts the transaction and fails its
/// Future with that same object.
typedef TransactionHandler = Transaction Function(Object? currentValue);
