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
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/keyed_document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:meta/meta.dart';

/// A [DocumentReference] refers to a document location in a Firestore
/// database and can be used to read or write that location. The document may
/// or may not exist.
///
/// This is the reference of Firestore Lite: every read and write is one
/// request to the backend. There are no listeners.
class DocumentReference<T extends dynamic> implements KeyedDocumentReference {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.doc] or [CollectionReference.doc].
  @internal
  DocumentReference(this.key, this.firestore, [this.converter]);

  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.doc] or [CollectionReference.doc].
  @internal
  factory DocumentReference.forPath(
    ResourcePath path,
    Firestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) {
    if (path.isEmpty) {
      throw ArgumentError(
        'Invalid document reference. A document path must not be empty.',
      );
    }
    if (path.length.remainder(2) != 0) {
      throw ArgumentError(
        'Invalid document reference. Document references must have an even number of segments, but '
        '${path.canonicalString} has ${path.length}',
      );
    }
    return DocumentReference<T>(
      DocumentKey.fromPath(path),
      firestore,
      converter,
    );
  }

  /// Creates the reference [toJson] wrote, for [firestore].
  factory DocumentReference.fromJson(
    Firestore firestore,
    Map<String, Object?> json, {
    FirestoreDataConverter<T>? converter,
  }) {
    final Object? referencePath = json['referencePath'];
    if (json['type'] != jsonType || referencePath is! String) {
      throw ArgumentError.value(
        json,
        'json',
        'Not a JSON representation of a DocumentReference',
      );
    }
    final ResourcePath path = ResourcePath.fromString(referencePath);
    if (path.length == 0) {
      throw ArgumentError.value(
        json,
        'json',
        'The referencePath must be a document path',
      );
    }
    return DocumentReference<T>.forPath(path, firestore, converter);
  }

  /// The `type` of the JSON representation of a reference (the same as in the
  /// main library and in the JS SDK).
  static const String jsonType = 'firestore/documentReference/1.0';

  /// A JSON representation of this reference, for [DocumentReference.fromJson].
  /// The converter is not part of it.
  Map<String, Object> toJson() {
    return <String, Object>{
      'type': jsonType,
      'referencePath': key.path.canonicalString,
    };
  }

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  @override
  final DocumentKey key;

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  @override
  DatabaseId get databaseId => firestore.modelDatabaseId;

  /// The Firestore instance of this reference.
  final Firestore firestore;

  /// The converter applied to the data read and written through this
  /// reference, if any.
  final FirestoreDataConverter<T>? converter;

  /// Returns a reference to the same document that reads and writes objects
  /// of type [U] through [converter].
  DocumentReference<U> withConverter<U extends Object?>(
    FirestoreDataConverter<U> converter,
  ) {
    return DocumentReference<U>(key, firestore, converter);
  }

  /// Returns a reference to the same document without a converter.
  DocumentReference<Map<String, Object?>> withoutConverter() {
    return DocumentReference<Map<String, Object?>>(key, firestore);
  }

  /// The ID of the document within its collection.
  String get id => key.path.last;

  /// The collection this document is in. It keeps the converter of this
  /// reference (as in the JS SDK; the main library of this package returns an
  /// unconverted collection).
  CollectionReference<T> get parent {
    return CollectionReference<T>.forPath(
      key.path.popLast(),
      firestore,
      converter,
    );
  }

  /// The path of the document, relative to the root of the database.
  String get path => key.path.canonicalString;

  /// Gets a [CollectionReference] to the subcollection at [collectionPath],
  /// relative to this document.
  CollectionReference<Map<String, Object?>> collection(String collectionPath) {
    checkNonEmptyPath('DocumentReference.collection', collectionPath);
    return CollectionReference<Map<String, Object?>>.forPath(
      key.path.appendField(ResourcePath.fromString(collectionPath)),
      firestore,
    );
  }

  /// Reads the document from the backend.
  Future<DocumentSnapshot<T>> get() async {
    final List<MaybeDocument> result = await firestore.run(
      (Datastore datastore) =>
          datastore.transactionClient.lookup(<DocumentKey>[key]),
    );
    hardAssert(
      result.length == 1,
      'Expected a single document result, got ${result.length}.',
    );
    final MaybeDocument document = result.first;
    return DocumentSnapshot<T>(
      firestore,
      key,
      document is Document ? document : null,
      converter,
    );
  }

  /// Writes [data] to the document. If the document does not exist yet, it is
  /// created. With merge [options] the data is merged into the existing
  /// document.
  ///
  /// The future completes when the backend has applied the write.
  Future<void> set(T data, [SetOptions? options]) =>
      _set(data, options, 'DocumentReference.set');

  /// [set] for the public method [methodName], which the errors name.
  Future<void> _set(T data, SetOptions? options, String methodName) async {
    final SetOptions setOptions = options ?? SetOptions.overwrite;
    checkNotNull<Object>(data, 'Provided data must not be null.');
    final Map<String, Object?> rawData = toRawData<T>(data, converter, options);
    final UserDataParsedSetData parsed = setOptions.merge
        ? firestore.dataConverter.parseMergeData(
            rawData,
            setOptions.fieldMask,
            methodName: methodName,
            targetDoc: key,
            hasConverter: converter != null,
          )
        : firestore.dataConverter.parseSetData(
            rawData,
            methodName: methodName,
            targetDoc: key,
            hasConverter: converter != null,
          );
    return _commit(parsed.toMutation(key, Precondition.none));
  }

  /// Updates the fields in [data] (dot-separated field paths to values) of
  /// the document. Fails with [FirestoreErrorCode.notFound] if the document
  /// does not exist.
  Future<void> update(Map<String, Object?> data) async {
    final UserDataParsedUpdateData parsed = firestore.dataConverter
        .parseUpdateData(
          data,
          methodName: 'DocumentReference.update',
          targetDoc: key,
        );
    return _commit(parsed.toMutation(key, Precondition(exists: true)));
  }

  /// Updates fields of the document. [data] alternates fields (a `String`
  /// or a `FieldPath`) and values. Fails with [FirestoreErrorCode.notFound]
  /// if the document does not exist.
  Future<void> updateFromList(List<Object?> data) async {
    const String methodName = 'DocumentReference.updateFromList';
    final UserDataParsedUpdateData parsed = firestore.dataConverter
        .parseUpdateDataFromList(
          collectUpdateArguments(1, data, methodName: methodName),
          methodName: methodName,
          targetDoc: key,
        );
    return _commit(parsed.toMutation(key, Precondition(exists: true)));
  }

  /// Deletes the document. Deleting a document that does not exist succeeds.
  Future<void> delete() => _commit(DeleteMutation(key, Precondition.none));

  Future<void> _commit(Mutation mutation) {
    return firestore.run<void>(
      (Datastore datastore) =>
          datastore.transactionClient.commit(<Mutation>[mutation]),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentReference &&
          runtimeType == other.runtimeType &&
          identical(firestore, other.firestore) &&
          key == other.key &&
          converter == other.converter;

  @override
  int get hashCode => Object.hash(firestore, key, converter);

  @override
  String toString() => 'DocumentReference{path: $path}';
}

/// Members of the Firestore Lite [DocumentReference] for the SDK itself. Not
/// exported by the public libraries.
extension LiteDocumentReferenceInternal<T> on DocumentReference<T> {
  /// [DocumentReference.set] for the public method [methodName] (for example
  /// `CollectionReference.add`), which the errors name.
  Future<void> setFor(String methodName, T data) =>
      _set(data, null, methodName);
}
