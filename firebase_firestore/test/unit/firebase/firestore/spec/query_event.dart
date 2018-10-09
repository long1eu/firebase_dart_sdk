// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:meta/meta.dart';

/// Object that contains exactly one of either a view snapshot or an error for
/// the given query.
class QueryEvent {
  final Query query;
  final ViewSnapshot view;
  final FirebaseFirestoreError error;

  QueryEvent({@required this.query, this.view, this.error});

  QueryEvent copyWith({
    Query query,
    ViewSnapshot view,
    FirebaseFirestoreError error,
  }) {
    return QueryEvent(
      query: query ?? this.query,
      view: view ?? this.view,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('view', view)
          ..add('error', error))
        .toString();
  }
}
