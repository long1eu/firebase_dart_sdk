/// The outcome of a transaction. JS: `api/Reference_impl.ts` (`TransactionResult`); Android:
/// `Transaction.Handler.onComplete(error, committed, currentData)`.
library;

import 'package:firebase_database_dart/src/api/data_snapshot.dart';
import 'package:meta/meta.dart';

/// What `DatabaseReference.runTransaction` completes with when the transaction did not fail.
@immutable
final class TransactionResult {
  /// Creates a result. The client creates them.
  @internal
  const TransactionResult.internal({
    required this.committed,
    required this.snapshot,
  });

  /// True when the server accepted the handler's value; false when the handler aborted.
  final bool committed;

  /// The location's data after the transaction: the committed value, or on abort the value the handler
  /// last saw.
  final DataSnapshot snapshot;
}
