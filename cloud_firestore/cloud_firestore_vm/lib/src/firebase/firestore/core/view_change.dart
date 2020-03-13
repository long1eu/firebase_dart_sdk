// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';

/// A set of changes to a view
class ViewChange {
  const ViewChange(this.snapshot, this.limboChanges);

  final ViewSnapshot snapshot;
  final List<LimboDocumentChange> limboChanges;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('snapshot', snapshot)
          ..add('limboChanges', limboChanges))
        .toString();
  }
}
