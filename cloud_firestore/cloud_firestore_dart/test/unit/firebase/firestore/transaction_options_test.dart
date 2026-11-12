import 'package:cloud_firestore_dart/src/firebase/firestore/transaction_options.dart';
import 'package:test/test.dart';

void main() {
  test('default max attempts is 5', () {
    expect(TransactionOptions.defaultOptions.maxAttempts, 5);
    expect(TransactionOptions().maxAttempts, 5);
  });

  test('max attempts is configurable', () {
    expect(TransactionOptions(maxAttempts: 1).maxAttempts, 1);
    expect(
        TransactionOptions(maxAttempts: 3), TransactionOptions(maxAttempts: 3));
    expect(TransactionOptions(maxAttempts: 3).hashCode,
        TransactionOptions(maxAttempts: 3).hashCode);
    expect(TransactionOptions(maxAttempts: 3), isNot(TransactionOptions()));
  });

  test('zero or negative max attempts throw an ArgumentError', () {
    expect(() => TransactionOptions(maxAttempts: 0), throwsArgumentError);
    expect(() => TransactionOptions(maxAttempts: -1), throwsArgumentError);
  });

  test('readOnly defaults to false and takes part in equality', () {
    expect(TransactionOptions().readOnly, isFalse);
    expect(TransactionOptions.defaultOptions.readOnly, isFalse);
    expect(TransactionOptions(readOnly: true).readOnly, isTrue);
    expect(
        TransactionOptions(readOnly: true), TransactionOptions(readOnly: true));
    expect(TransactionOptions(readOnly: true).hashCode,
        TransactionOptions(readOnly: true).hashCode);
    expect(TransactionOptions(readOnly: true), isNot(TransactionOptions()));
    expect(TransactionOptions(readOnly: true).toString(),
        contains('readOnly=true'));
    expect(() => TransactionOptions(maxAttempts: 0, readOnly: true),
        throwsArgumentError);
  });
}
