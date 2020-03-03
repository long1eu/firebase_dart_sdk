// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// A [QueryDocumentSnapshot] contains data read from a document in your Firestore database as part
/// of a query. The document is guaranteed to exist and its data can be extracted using the [data]
/// or [get] methods.
///
/// [QueryDocumentSnapshot] offers the same API surface as [DocumentSnapshot]. Since query results
/// contain only existing documents, the [exists] method will always return true and [data] will
/// never be null.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class QueryDocumentSnapshot extends DocumentSnapshot {
  QueryDocumentSnapshot._(
    FirebaseFirestore firestore,
    DocumentKey key,
    Document doc,
    bool isFromCache,
    bool hasPendingWrites,
  ) : super(
          firestore,
          key,
          doc,
          isFromCache: isFromCache,
          hasPendingWrites: hasPendingWrites,
        );

  factory QueryDocumentSnapshot.fromDocument(
    FirebaseFirestore firestore,
    Document doc, {
    bool fromCache,
    bool hasPendingWrites,
  }) {
    return QueryDocumentSnapshot._(firestore, doc.key, doc, fromCache, hasPendingWrites);
  }

  /// Returns the fields of the document as a Map. Field values will be converted to their native
  /// Dart representation.
  ///
  /// Returns the fields of the document as a Map.
  @override
  Map<String, Object> get data {
    final Map<String, Object> result = super.data;
    hardAssert(result != null, 'Data in a QueryDocumentSnapshot should be non-null');
    return result;
  }

  /// Returns the fields of the document as a Map. Field values will be converted to their native
  /// Dart representation.
  ///
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been
  /// set to their final value.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  @override
  Map<String, Object> getData(ServerTimestampBehavior serverTimestampBehavior) {
    Preconditions.checkNotNull(serverTimestampBehavior);
    final Map<String, Object> result = super.getData(serverTimestampBehavior);
    hardAssert(result != null, 'Data in a QueryDocumentSnapshot should be non-null');
    return result;
  }
}
