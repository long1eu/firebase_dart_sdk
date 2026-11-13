// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// A [DocumentSnapshot] contains the data read from a document in a Firestore
/// database. The data can be extracted with [data] or [get].
///
/// For a document that does not exist [exists] is false and [data] is null.
///
/// A Firestore Lite snapshot always comes from the backend: it has no
/// metadata.
class DocumentSnapshot<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  DocumentSnapshot(
    this._firestore,
    this._key,
    this.document, [
    this._converter,
  ]);

  final Firestore _firestore;
  final DocumentKey _key;
  final FirestoreDataConverter<T>? _converter;

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  final Document? document;

  /// The ID of the document.
  String get id => _key.path.last;

  /// The reference of the document.
  DocumentReference<T> get ref =>
      DocumentReference<T>(_key, _firestore, _converter);

  /// Whether the document exists.
  bool get exists => document != null;

  /// The data of the document (converted with the converter of the reference
  /// or query it was read through, if any), or null if the document does not
  /// exist.
  T? get data {
    final Document? doc = document;
    if (doc == null) {
      return null;
    }
    final FirestoreDataConverter<T>? converter = _converter;
    if (converter == null) {
      return _convertObject(doc.data) as T;
    }
    return converter.fromFirestore(
      QueryDocumentSnapshot<Map<String, Object?>>(_firestore, doc),
    );
  }

  /// Whether the document has the field at the dot-separated path [field].
  bool contains(String field) {
    return containsPath(FieldPath.fromDotSeparatedPath(field));
  }

  /// Whether the document has the field at [fieldPath].
  bool containsPath(FieldPath fieldPath) {
    return document?.getField(fieldPath.internalPath) != null;
  }

  /// The value of the field at the dot-separated path [field], or null if
  /// there is no such field or document. Never converted.
  Object? operator [](String field) => get(field);

  /// The value of the field at the dot-separated path [field], or null if
  /// there is no such field or document. Never converted.
  Object? get(String field) {
    return getField(FieldPath.fromDotSeparatedPath(field));
  }

  /// The value of the field at [fieldPath], or null if there is no such field
  /// or document. Never converted.
  Object? getField(FieldPath fieldPath) {
    final model.FieldPath path = fieldPath.internalPath;
    final FieldValue? value = document?.getField(path);
    return value == null ? null : _convertValue(value);
  }

  Object? _convertValue(FieldValue value) {
    if (value is ObjectValue) {
      return _convertObject(value);
    } else if (value is ArrayValue) {
      return value.internalValue.map(_convertValue).toList();
    } else if (value is ReferenceValue) {
      return _convertReference(value);
    } else {
      return value.value;
    }
  }

  Map<String, Object?> _convertObject(ObjectValue objectValue) {
    final Map<String, Object?> result = <String, Object?>{};
    for (MapEntry<String, FieldValue> entry in objectValue.internalValue) {
      result[entry.key] = _convertValue(entry.value);
    }
    return result;
  }

  Object _convertReference(ReferenceValue value) {
    final DocumentKey key = value.value;
    final DatabaseId refDatabase = value.databaseId;
    final DatabaseId database = _firestore.databaseId;
    if (refDatabase != database) {
      Log.w(
        'DocumentSnapshot',
        'Document ${_key.path} contains a document reference within a different database (${refDatabase.projectId}/${refDatabase.databaseId}) which is not supported. It will be treated as a reference in the current database (${database.projectId}/${database.databaseId}) instead.',
      );
    }
    return DocumentReference<Map<String, Object?>>(key, _firestore);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSnapshot &&
          runtimeType == other.runtimeType &&
          identical(_firestore, other._firestore) &&
          _key == other._key &&
          _converter == other._converter &&
          document?.data == other.document?.data;

  @override
  int get hashCode => Object.hash(_firestore, _key, document?.data);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', _key)
          ..add('document', document))
        .toString();
  }
}

/// A [QueryDocumentSnapshot] contains the data of a document that exists: one
/// read by a query, or handed to a converter. Its [data] is never null.
class QueryDocumentSnapshot<T extends dynamic> extends DocumentSnapshot<T> {
  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  QueryDocumentSnapshot(
    Firestore firestore,
    Document document, [
    FirestoreDataConverter<T>? converter,
  ]) : super(firestore, document.key, document, converter);

  @override
  T get data => super.data as T;
}

/// A [QuerySnapshot] contains the results of a query: zero or more
/// [QueryDocumentSnapshot]s, in the order of the query.
class QuerySnapshot<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  QuerySnapshot(this.query, List<Document> documents)
    : docs = List<QueryDocumentSnapshot<T>>.unmodifiable(<
        QueryDocumentSnapshot<T>
      >[
        for (final Document document in documents)
          QueryDocumentSnapshot<T>(query.firestore, document, query.converter),
      ]);

  /// The query that produced this snapshot.
  final Query<T> query;

  /// The documents the query matched.
  final List<QueryDocumentSnapshot<T>> docs;

  /// The number of documents.
  int get length => docs.length;

  /// Whether the query matched no document.
  bool get isEmpty => docs.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuerySnapshot &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          const ListEquality<Object?>().equals(docs, other.docs);

  @override
  int get hashCode =>
      Object.hash(query, const ListEquality<Object?>().hash(docs));

  @override
  String toString() => 'QuerySnapshot{query: $query, docs: $docs}';
}
