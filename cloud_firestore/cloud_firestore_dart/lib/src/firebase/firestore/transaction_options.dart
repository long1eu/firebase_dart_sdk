import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Options to customize transaction behavior for `Firestore.runTransaction`.
class TransactionOptions {
  /// Creates the options. [maxAttempts] is the maximum number of times the
  /// transaction is attempted before it fails, it must be at least 1. Throws
  /// an [ArgumentError] otherwise.
  ///
  /// A [readOnly] transaction can only read (writing in it throws). It is a
  /// read-only transaction of the backend: all its reads, of documents with
  /// `Transaction.get` and of queries and aggregations with
  /// `Transaction.getQuery` and `Transaction.getAggregate`, see the database
  /// as it was at one point in time, also while other clients write. It takes
  /// no locks and commits nothing, so it never conflicts and is not retried
  /// for conflicts; [maxAttempts] only covers failures of the connection.
  ///
  /// [readTime] makes a read-only transaction read the database as it was at
  /// that time instead of the time it starts. The backend keeps past versions
  /// for a limited time only and rejects older read times. Throws an
  /// [ArgumentError] when given without [readOnly].
  factory TransactionOptions({
    int maxAttempts = defaultMaxAttempts,
    bool readOnly = false,
    Timestamp? readTime,
  }) {
    if (readTime != null && !readOnly) {
      throw ArgumentError.value(
        readTime,
        'readTime',
        'A read time needs a read-only transaction (readOnly: true)',
      );
    }
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Max attempts must be at least 1',
      );
    }
    return TransactionOptions._(maxAttempts, readOnly, readTime);
  }

  const TransactionOptions._(this.maxAttempts, this.readOnly, [this.readTime]);

  /// The default maximum number of attempts, 5.
  static const int defaultMaxAttempts = 5;

  /// The options used when none are given.
  static const TransactionOptions defaultOptions = TransactionOptions._(
    defaultMaxAttempts,
    false,
  );

  /// The maximum number of attempts to commit, after which the transaction
  /// fails.
  final int maxAttempts;

  /// Whether the transaction can only read (false by default).
  final bool readOnly;

  /// The time whose state a read-only transaction reads, or null for the time
  /// the transaction starts.
  final Timestamp? readTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionOptions &&
          maxAttempts == other.maxAttempts &&
          readOnly == other.readOnly &&
          readTime == other.readTime;

  @override
  int get hashCode => Object.hash(maxAttempts, readOnly, readTime);

  @override
  String toString() =>
      'TransactionOptions{maxAttempts=$maxAttempts, readOnly=$readOnly'
      '${readTime == null ? '' : ', readTime=$readTime'}}';
}
