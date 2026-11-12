// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:meta/meta.dart';

/// A [CollectionReference] can be used for adding documents, getting document references, and
/// querying for documents (using the methods inherited from [Query]).
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class CollectionReference<T extends dynamic> extends Query<T> {
  @internal
  CollectionReference(ResourcePath path, Firestore firestore,
      [FirestoreDataConverter<T>? converter])
      : assert(
            path.length.remainder(2) == 1,
            'Invalid collection reference. Collection references must have an odd number of '
            'segments, but ${path.canonicalString} has ${path.length}'),
        super(core.Query(path), firestore, converter);

  /// Return The id of the collection.
  String get id => query.path.last;

  /// Gets a [DocumentReference] to the document that contains this collection. Only subcollections
  /// are contained in a document. For root collections, returns null.
  ///
  /// Returns the [DocumentReference] that contains this collection or null if this is a root
  /// collection.
  DocumentReference<Map<String, Object?>>? get parent {
    final ResourcePath parentPath = query.path.popLast();
    if (parentPath.isEmpty) {
      return null;
    } else {
      return DocumentReference<Map<String, Object?>>(
          DocumentKey.fromPath(parentPath), firestore);
    }
  }

  /// Gets the path of this collection (relative to the root of the database) as a slash-separated
  /// string.
  ///
  /// Returns the path of this collection.
  String get path => query.path.canonicalString;

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within
  /// this collection.
  ///
  /// [documentPath] a slash-separated relative path to a document.
  ///
  /// Returns the [DocumentReference] instance.
  DocumentReference<T> doc([String? documentPath]) => document(documentPath);

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within
  /// this collection. Same as [doc].
  @Deprecated('Use doc instead.')
  DocumentReference<T> document([String? documentPath]) {
    final String path = documentPath ?? autoId();
    return DocumentReference<T>.forPath(
        query.path.appendField(ResourcePath.fromString(path)),
        firestore,
        converter);
  }

  /// Adds a new document to this collection with the specified data, assigning it a document ID
  /// automatically.
  ///
  /// [data] a [Map] containing the data for the new document.
  ///
  /// Returns a Future that will be resolved with the [DocumentReference] of the newly created
  /// document.
  Future<DocumentReference<T>> add(T data) async {
    checkNotNull<Object>(data, 'Provided data must not be null.');
    final DocumentReference<T> ref = document();
    await ref.set(data);
    return ref;
  }

  /// Returns a collection reference to the same collection that converts data
  /// with [converter] (type [U]) when reading and writing. Use
  /// [withoutConverter] to go back to raw maps.
  @override
  CollectionReference<U> withConverter<U extends Object?>(
      FirestoreDataConverter<U> converter) {
    return CollectionReference<U>(query.path, firestore, converter);
  }

  /// Returns a collection reference to the same collection that reads and
  /// writes raw `Map<String, Object?>` values.
  @override
  CollectionReference<Map<String, Object?>> withoutConverter() {
    return CollectionReference<Map<String, Object?>>(query.path, firestore);
  }
}
