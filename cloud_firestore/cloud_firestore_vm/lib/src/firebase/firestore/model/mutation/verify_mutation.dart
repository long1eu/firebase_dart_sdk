import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

/// A mutation that does not write anything: the backend only checks its [precondition] against the document, and
/// fails the commit if it does not hold. It is only sent as part of a transaction, to verify the documents that were
/// read but not written, and it is never applied locally.
class VerifyMutation extends Mutation {
  const VerifyMutation(DocumentKey key, Precondition precondition)
    : super(key, precondition);

  @override
  MaybeDocument applyToRemoteDocument(
    MaybeDocument? maybeDoc,
    MutationResult mutationResult,
  ) {
    throw fail('VerifyMutation should only be used in Transactions.');
  }

  @override
  MaybeDocument? applyToLocalView(
    MaybeDocument? maybeDoc,
    MaybeDocument? baseDoc,
    Timestamp localWriteTime,
  ) {
    throw fail('VerifyMutation should only be used in Transactions.');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VerifyMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other);

  @override
  int get hashCode => keyAndPreconditionHashCode();

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('precondition', precondition))
        .toString();
  }
}
