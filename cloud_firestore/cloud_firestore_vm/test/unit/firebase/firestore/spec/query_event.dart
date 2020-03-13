// File created by
// Lung Razvan <long1eu>
// on 04/10/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:meta/meta.dart';

/// Object that contains exactly one of either a view snapshot or an error for
/// the given query.
class QueryEvent {
  const QueryEvent({@required this.query, this.view, this.error});

  final Query query;
  final ViewSnapshot view;
  final FirebaseFirestoreError error;

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
