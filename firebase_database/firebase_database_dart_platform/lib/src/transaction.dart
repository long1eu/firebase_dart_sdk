/// Transactions: FlutterFire's handler on the client's, and
/// [DartTransactionResult].
library;

import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/data_snapshot.dart';
import 'package:firebase_database_dart_platform/src/errors.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_dart_platform/src/values.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';

/// The client handler that runs FlutterFire's [handler].
///
/// Each run hands [handler] the [mutableCopy] of the client's current value
/// (the client may run it up to 26 times, each with a fresh copy); a returned
/// `Transaction.abort()` becomes `fs.Transaction.abort()`, a
/// `Transaction.success(value)` becomes `fs.Transaction.success` of the
/// [transformValue] of the value. An exception [handler] throws propagates
/// unchanged.
fs.TransactionHandler clientHandler(TransactionHandler handler) =>
    throw UnimplementedError();

/// `DatabaseReferencePlatform.runTransaction` of [ref]: client
/// `runTransaction(clientHandler(handler), applyLocally: applyLocally)`
/// through [guard], whose result becomes a [DartTransactionResult].
///
/// The exception [handler] threw fails the Future as the same object (never
/// converted). An abort completes with `committed: false` and the snapshot
/// the handler saw. With `applyLocally: false` no local event is raised
/// before the server's answer (a client rule).
Future<DartTransactionResult> runDartTransaction(
  DartReference ref,
  TransactionHandler handler, {
  required bool applyLocally,
}) => throw UnimplementedError();

/// The implementation of [TransactionResultPlatform]: client
/// `TransactionResult.committed` and `.snapshot`.
class DartTransactionResult extends TransactionResultPlatform {
  /// A result with [committed] and [snapshot].
  DartTransactionResult(super.committed, this.snapshot);

  /// `TransactionResultPlatform.snapshot`: the snapshot of the location after
  /// the transaction, or the one the handler saw when it aborted.
  @override
  final DartDataSnapshot snapshot;
}
