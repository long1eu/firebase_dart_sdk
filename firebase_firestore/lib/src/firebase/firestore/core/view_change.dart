// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/limbo_document_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';

/// A set of changes to a view
class ViewChange {
  final ViewSnapshot snapshot;
  final List<LimboDocumentChange> limboChanges;

  ViewChange(this.snapshot, this.limboChanges);
}
