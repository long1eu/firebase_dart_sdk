/// What a transaction handler returns. JS: `api/Reference_impl.ts` (`runTransaction`, `undefined` to abort);
/// Android: `Transaction.java` (`Result`, `success`, `abort`); FlutterFire: `transaction.dart`.
library;

import 'package:meta/meta.dart';

/// The answer of a `TransactionHandler`: write a new value with [Transaction.success], or stop with
/// [Transaction.abort].
///
/// ```dart
/// final TransactionResult result = await db.ref('counters/likes').runTransaction(
///   (Object? current) => Transaction.success(((current as num?) ?? 0) + 1),
/// );
/// ```
@immutable
final class Transaction {
  /// Commits [value], and [priority] when given, as the location's new data. The value follows the rules of
  /// `DatabaseReference.set`; it may hold `ServerValue` placeholders.
  const Transaction.success(Object? value, {Object? priority})
    : _aborted = false,
      _value = value,
      _priority = priority;

  /// Stops the transaction with no write: the `TransactionResult` has `committed` false and the snapshot
  /// the handler last saw.
  const Transaction.abort() : _aborted = true, _value = null, _priority = null;

  final bool _aborted;
  final Object? _value;
  final Object? _priority;
}

/// The client's view of a [Transaction]. Not exported.
@internal
extension TransactionInternals on Transaction {
  /// Whether the handler aborted.
  bool get aborted => _aborted;

  /// The value to commit; null when [aborted].
  Object? get value => _value;

  /// The priority to commit, or null to keep none.
  Object? get priority => _priority;
}
