/// Options to customize transaction behavior for [Firestore.runTransaction].
class TransactionOptions {
  /// Creates the options. [maxAttempts] is the maximum number of times the
  /// transaction is attempted before it fails, it must be at least 1. Throws
  /// an [ArgumentError] otherwise.
  ///
  /// A [readOnly] transaction can only read: writing in it throws, and when it
  /// ends the backend verifies that the documents it read did not change
  /// (retrying like any other transaction otherwise). Unlike a read-write
  /// transaction it does not have to write the documents it reads.
  factory TransactionOptions({
    int maxAttempts = defaultMaxAttempts,
    bool readOnly = false,
  }) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Max attempts must be at least 1',
      );
    }
    return TransactionOptions._(maxAttempts, readOnly);
  }

  const TransactionOptions._(this.maxAttempts, this.readOnly);

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionOptions &&
          maxAttempts == other.maxAttempts &&
          readOnly == other.readOnly;

  @override
  int get hashCode => maxAttempts * 31 + (readOnly ? 1 : 0);

  @override
  String toString() =>
      'TransactionOptions{maxAttempts=$maxAttempts, readOnly=$readOnly}';
}
