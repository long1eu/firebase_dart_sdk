// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:meta/meta.dart';

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
class QueryDocumentSnapshot<T extends dynamic> extends DocumentSnapshot<T> {
  QueryDocumentSnapshot._(
    Firestore firestore,
    DocumentKey key,
    Document doc,
    bool isFromCache,
    bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  ) : super(
          firestore,
          key,
          doc,
          isFromCache: isFromCache,
          hasPendingWrites: hasPendingWrites,
          converter: converter,
        );

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  factory QueryDocumentSnapshot.fromDocument(
    Firestore firestore,
    Document doc, {
    required bool fromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) {
    return QueryDocumentSnapshot<T>._(
        firestore, doc.key, doc, fromCache, hasPendingWrites, converter);
  }

  /// Returns the fields of the document as a Map. Field values will be converted to their native
  /// Dart representation.
  ///
  /// Returns the fields of the document as a Map.
  @override
  T get data {
    // The document always exists here; a null can only be what a converter of a nullable [T] returned.
    return super.data as T;
  }

  /// Returns the fields of the document as a Map. Field values will be converted to their native
  /// Dart representation.
  ///
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been
  /// set to their final value.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  @override
  T getData(ServerTimestampBehavior serverTimestampBehavior) {
    return super.getData(serverTimestampBehavior) as T;
  }
}
