// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';

/// QueryView contains all of the info that SyncEngine needs to track for a
/// particular query and view.
class QueryView {
  QueryView(this.query, this.targetId, this.view);

  final Query query;
  final int targetId;
  final View view;
}
