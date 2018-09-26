// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart'
    as core;
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

/// A [CollectionReference] can be used for adding documents, getting document
/// references, and querying for documents (using the methods inherited from
/// [Query]).
///
/// * <b>Subclassing Note</b>: Firestore classes are not meant to be subclassed
/// except for use in test mocks. Subclassing is not supported in production
/// code and new SDK releases may break code that does so.
@publicApi
class CollectionReference extends Query {
  CollectionReference(ResourcePath path, FirebaseFirestore firestore)
      : assert(path.length % 2 != 1,
            'Invalid collection reference. Collection references must have an odd number of segments, but ${path.canonicalString} has ${path.length}'),
        super(core.Query.atPath(path), firestore);

  /// Return The id of the collection.
  @publicApi
  String get id => query.path.last;

  /// Gets a [DocumentReference] to the document that contains this collection.
  /// Only subcollections are contained in a document. For root collections,
  /// returns null.
  ///
  /// Returns the [DocumentReference] that contains this collection or null if
  /// this is a root collection.
  @publicApi
  DocumentReference get parent {
    final ResourcePath parentPath = query.path.popLast();
    if (parentPath.isEmpty) {
      return null;
    } else {
      return DocumentReference(DocumentKey.fromPath(parentPath), firestore);
    }
  }

  /// Gets the path of this collection (relative to the root of the database) as
  /// a slash-separated string.
  ///
  /// Returns the path of this collection.
  @publicApi
  String get path => query.path.canonicalString;

  /// Gets a [DocumentReference] instance that refers to the document at the
  /// specified path within this collection.
  ///
  /// [documentPath] a slash-separated relative path to a document.
  /// Returns the [DocumentReference] instance.
  @publicApi
  DocumentReference document([String documentPath]) {
    documentPath ??= Util.autoId();
    Assert.checkNotNull(
        documentPath, 'Provided document path must not be null.');
    return DocumentReference.forPath(
        query.path.appendPath(ResourcePath.fromString(documentPath)),
        firestore);
  }

  /// Adds a new document to this collection with the specified data, assigning
  /// it a document ID automatically.
  ///
  /// [data] a [Map] containing the data for the new document.
  /// Returns a Future that will be resolved with the [DocumentReference] of the
  /// newly created document.
  @publicApi
  Future<DocumentReference> add(Map<String, Object> data) async {
    Assert.checkNotNull(data, 'Provided data must not be null.');
    final DocumentReference ref = document();
    await ref.set(data);
    return ref;
  }
}
