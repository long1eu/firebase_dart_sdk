// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_app_dart/internal.dart';

/// A set of changes to a view
class ViewChange {
  const ViewChange(this.snapshot, this.limboChanges);

  final ViewSnapshot? snapshot;
  final List<LimboDocumentChange> limboChanges;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('snapshot', snapshot)
          ..add('limboChanges', limboChanges))
        .toString();
  }
}
