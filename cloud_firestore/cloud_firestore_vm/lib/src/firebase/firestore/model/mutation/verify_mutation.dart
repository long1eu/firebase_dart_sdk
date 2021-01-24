// File created by
// Lung Razvan <long1eu>
// on 16/01/2021

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

/// A mutation that verifies the existence of the document at the given key with the provided
/// precondition.
///
/// The `verify` operation is only used in Transactions, and this class serves primarily to
/// facilitate serialization into protos.
class VerifyMutation extends Mutation {
  const VerifyMutation(DocumentKey key, Precondition precondition) : super(key, precondition);

  @override
  MaybeDocument applyToLocalView(MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime) {
    throw StateError('VerifyMutation should only be used in Transactions.');
  }

  @override
  MaybeDocument applyToRemoteDocument(MaybeDocument maybeDoc, MutationResult mutationResult) {
    throw StateError('VerifyMutation should only be used in Transactions.');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VerifyMutation && //
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other);

  @override
  int get hashCode => keyAndPreconditionHashCode();

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('key', key)
          ..add('precondition', precondition))
        .toString();
  }
}
