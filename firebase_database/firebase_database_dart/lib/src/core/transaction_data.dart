/// The state of one transaction. JS: `core/Repo.ts` (`Transaction`, `TransactionStatus`); Android:
/// `core/Repo.java` (`TransactionData`, `TransactionStatus`), `Transaction.java` (`Handler`).
library;

import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// The most times a transaction is rerun after `datastale` before it aborts with `maxretry`.
const int maxTransactionRetries = 25;

/// Where a transaction is in its life.
enum TransactionStatus {
  /// Waiting to be run (or rerun) and sent.
  run,

  /// Sent to the server, waiting for the answer.
  sent,

  /// Finished; its callback has run or is about to.
  completed,

  /// Sent, and must abort when the answer arrives.
  sentNeedsAbort,

  /// Must abort before it is sent.
  needsAbort,
}

/// What the update function returns: a new value or an abort.
sealed class TransactionOutcome {
  const TransactionOutcome();

  /// Abort the transaction.
  static const TransactionOutcome abort = TransactionAbort();
}

/// Commit [value] (JSON, may contain server values).
final class TransactionSuccess extends TransactionOutcome {
  /// Creates the outcome.
  const TransactionSuccess(this.value);

  /// The new value.
  final Object? value;
}

/// Abort the transaction.
final class TransactionAbort extends TransactionOutcome {
  /// Use [TransactionOutcome.abort].
  const TransactionAbort();
}

/// The user's update function: given the current value (JSON), returns the outcome. May run
/// several times.
///
/// `currentValue` is a fresh, mutable deep copy on every call (a new `Map`/`List` tree): the
/// function may change it and return it, and nothing else sees the change.
typedef TransactionUpdate = TransactionOutcome Function(Object? currentValue);

/// Called once at the end: [error] null on success, whether it [committed], and the resulting
/// data.
typedef TransactionCompletion =
    void Function(DatabaseError? error, bool committed, Node? snapshot);

/// The mutable state of one transaction in Repo's transaction queue tree.
final class TransactionData {
  /// Creates a transaction at [path].
  TransactionData({
    required this.path,
    required this.update,
    required this.onComplete,
    required this.order,
    required this.applyLocally,
    required this.unwatcher,
  });

  /// Where it runs.
  final Path path;

  /// The update function.
  final TransactionUpdate update;

  /// The completion callback.
  final TransactionCompletion? onComplete;

  /// Its position in the global order of transactions.
  final int order;

  /// Whether local events show the transaction's value before the server confirms it.
  final bool applyLocally;

  /// Removes the value listener the transaction keeps on [path].
  final void Function() unwatcher;

  /// The state.
  TransactionStatus status = TransactionStatus.run;

  /// The number of reruns.
  int retryCount = 0;

  /// Why it must abort, once known.
  DatabaseError? abortReason;

  /// The write id of the current attempt.
  WriteId? currentWriteId;

  /// The data the current attempt read.
  Node? currentInputSnapshot;

  /// The data the current attempt wrote, unresolved (sent to the server).
  Node? currentOutputSnapshotRaw;

  /// The data the current attempt wrote, with server values resolved (applied locally).
  Node? currentOutputSnapshotResolved;
}
