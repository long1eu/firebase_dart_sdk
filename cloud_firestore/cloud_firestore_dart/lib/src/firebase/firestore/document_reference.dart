// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/converter_util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/listen_to_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_listen_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:meta/meta.dart';

/// A [DocumentReference] refers to a document location in a Firestore database and can be used to write, read, or
/// listen to the location. There may or may not exist a document at the referenced location. A [DocumentReference] can
/// also be used to create a [CollectionReference] to a subcollection.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing
/// is not supported in production code and new SDK releases may break code that does so.
class DocumentReference<T extends dynamic> {
  // TODO(long1eu): We should checkNotNull(firestore), but tests are currently cheating and setting it to null.
  @internal
  DocumentReference(this.key, this.firestore, [this.converter]);

  @internal
  factory DocumentReference.forPath(ResourcePath path, Firestore firestore,
      [FirestoreDataConverter<T>? converter]) {
    if (path.length.remainder(2) != 0) {
      throw ArgumentError(
          'Invalid document reference. Document references must have an even number of segments, but '
          '${path.canonicalString} has ${path.length}');
    }

    return DocumentReference<T>(
        DocumentKey.fromPath(path), firestore, converter);
  }

  /// Builds a [DocumentReference] of [firestore] from a JSON map created by [toJson], optionally with a [converter].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape or `referencePath` is not a document path. This is
  /// the JS SDK `DocumentReference.fromJSON()`.
  factory DocumentReference.fromJson(
    Firestore firestore,
    Map<String, Object?> json, {
    FirestoreDataConverter<T>? converter,
  }) {
    final Object? referencePath = json['referencePath'];
    if (json['type'] != jsonType || referencePath is! String) {
      throw ArgumentError.value(
          json, 'json', 'Not a JSON representation of a DocumentReference');
    }
    final ResourcePath path = ResourcePath.fromString(referencePath);
    if (path.length == 0) {
      throw ArgumentError.value(
          json, 'json', 'The referencePath must be a document path');
    }
    return DocumentReference<T>.forPath(path, firestore, converter);
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/documentReference/1.0';

  @internal
  final DocumentKey key;

  /// Returns a JSON-serializable representation of this reference: its `type` ([jsonType]) and `referencePath`, like
  /// the JS SDK's `DocumentReference.toJSON()`. The Firestore instance and the converter are not part of it; read it
  /// back with [DocumentReference.fromJson].
  Map<String, Object> toJson() {
    return <String, Object>{
      'type': jsonType,
      'referencePath': key.path.canonicalString,
    };
  }

  /// Gets the Firestore instance associated with this document reference.
  final Firestore firestore;

  /// The converter attached with [withConverter], or null for raw maps.
  final FirestoreDataConverter<T>? converter;

  /// Returns a reference to the same document that converts data with
  /// [converter] (type [U]) when reading and writing. Use [withoutConverter]
  /// to go back to raw maps.
  DocumentReference<U> withConverter<U extends Object?>(
      FirestoreDataConverter<U> converter) {
    return DocumentReference<U>(key, firestore, converter);
  }

  /// Returns a reference to the same document that reads and writes raw
  /// `Map<String, Object?>` values (the equivalent of `withConverter(null)`
  /// in the JS SDK).
  DocumentReference<Map<String, Object?>> withoutConverter() {
    return DocumentReference<Map<String, Object?>>(key, firestore);
  }

  String get id => key.path.last;

  /// Gets a [CollectionReference] to the collection that contains this document.
  ///
  /// Returns the [CollectionReference] that contains this document.
  CollectionReference<Map<String, Object?>> get parent {
    return CollectionReference<Map<String, Object?>>(
        key.path.popLast(), firestore);
  }

  /// Gets the path of this document (relative to the root of the database) as a slash-separated  string.
  ///
  /// Returns the path of this document.
  String get path => key.path.canonicalString;

  /// Gets a [CollectionReference] instance that refers to the subcollection at the specified path relative to this
  /// document.
  ///
  /// [collectionPath] a slash-separated relative path to a subcollection.
  ///
  /// Returns the [CollectionReference] instance.
  CollectionReference<Map<String, Object?>> collection(String collectionPath) {
    checkNotNull(collectionPath, 'Provided collection path must not be null.');
    return CollectionReference<Map<String, Object?>>(
        key.path.appendField(ResourcePath.fromString(collectionPath)),
        firestore);
  }

  /// Writes to the document referred to by this DocumentReference. If the document does not yet exist, it will be
  /// created. If you pass [SetOptions], the provided data can be merged into an existing document.
  ///
  /// [data] a map of the fields and values for the document.
  /// [options] an object to configure the set behavior.
  ///
  /// Returns a Future that will be resolved when the write finishes.
  Future<void> set(T data, [SetOptions? options]) async {
    final SetOptions setOptions = options ?? SetOptions.overwrite;
    checkNotNull<Object>(data, 'Provided data must not be null.');
    final Map<String, Object?> rawData =
        toRawData<T>(data, converter, options);
    final UserDataParsedSetData parsed = setOptions.merge
        ? firestore.dataConverter.parseMergeData(rawData, setOptions.fieldMask)
        : firestore.dataConverter.parseSetData(rawData);

    await voidErrorTransformer(() =>
        firestore.client
        .write(<Mutation>[parsed.toMutation(key, Precondition.none)]));
  }

  /// Updates fields in the document referred to by this DocumentReference. If no document exists yet, the update will
  /// fail.
  ///
  /// [data] is a List of field/value pairs to be updated.
  ///
  /// The first item should be the field to update followed by the value. Repeat this pattern for any additional
  /// field/value pairs.
  ///
  /// Returns a Future that will be resolved when the write finishes.
  Future<void> updateFromList(List<Object?> data) async {
    final UserDataParsedUpdateData parsedData = firestore.dataConverter
        .parseUpdateDataFromList(collectUpdateArguments(1, data));
    await voidErrorTransformer(() => firestore.client
        .write(<Mutation>[
      parsedData.toMutation(key, Precondition(exists: true))
    ]));
  }

  /// Updates fields in the document referred to by this [DocumentReference]. If no document exists yet, the update will
  /// fail.
  ///
  /// [data] a map of field/value pairs to update. Fields can contain dots to reference nested fields within the
  /// document.
  ///
  /// Returns a Future that will be resolved when the write finishes.
  Future<void> update(Map<String, Object?> data) async {
    final UserDataParsedUpdateData parsedData =
        firestore.dataConverter.parseUpdateData(data);
    await voidErrorTransformer(() => firestore.client
        .write(<Mutation>[
      parsedData.toMutation(key, Precondition(exists: true))
    ]));
  }

  /// Deletes the document referred to by this [DocumentReference].
  ///
  /// Returns a Future that will be resolved when the delete completes.
  Future<void> delete() {
    return voidErrorTransformer(() => firestore.client
        .write(<DeleteMutation>[DeleteMutation(key, Precondition.none)]));
  }

  /// Reads the document referenced by this [DocumentReference].
  ///
  /// By default, [get] attempts to provide up-to-date data when possible by waiting for data from the server, but it
  /// may return cached data or fail if you are offline and the server cannot be reached. This behavior can be altered
  /// via the [Source] parameter.
  ///
  /// [source] a value to configure the get behavior.
  ///
  /// Returns a Future that will be resolved with the contents of the [Document] at this [DocumentReference].
  Future<DocumentSnapshot<T>> get([Source? source]) async {
    source ??= Source.defaultSource;

    if (source == Source.cache) {
      final Document? doc =
          await firestore.client.getDocumentFromLocalCache(key);
      final bool hasPendingWrites = doc != null && doc.hasLocalMutations;

      return DocumentSnapshot<T>(
        firestore,
        key,
        doc,
        isFromCache: true,
        hasPendingWrites: hasPendingWrites,
        converter: converter,
      );
    } else {
      return _getViaSnapshotListener(source);
    }
  }

  Future<DocumentSnapshot<T>> _getViaSnapshotListener(Source source) {
    return _firstAndCancel(_getSnapshotsInternal(const ListenOptions.all())
        .map((DocumentSnapshot<T> snapshot) {
      if (!snapshot.exists && snapshot.metadata.isFromCache) {
        // TODO(long1eu): Reconsider how to raise missing documents when offline.
        //  If we're online and the document doesn't exist then we set the result of the Future with a document with
        //  document.exists set to false. If we're offline however, we set the Error on the Task. Two options:
        //    1. Cache the negative response from the server so we can deliver that even when you're offline.
        //    2. Actually set the Error of the Task if the document doesn't exist when you are offline.
        throw FirestoreError(
            'Failed to get document because the client is offline.',
            FirestoreErrorCode.unavailable);
      } else if (snapshot.exists &&
          snapshot.metadata.isFromCache &&
          source == Source.server) {
        throw FirestoreError(
            'Failed to get document from server. (However, this document does exist in the local cache. Run again '
            'without setting source to Source.SERVER to retrieve the cached document.)',
            FirestoreErrorCode.unavailable);
      } else {
        return snapshot;
      }
    }));
  }

  Stream<DocumentSnapshot<T>> get snapshots {
    final ListenOptions options = _internalOptions(MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  Stream<DocumentSnapshot<T>> getSnapshots([MetadataChanges? changes]) {
    final ListenOptions options =
        _internalOptions(changes ?? MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  /// Starts listening with the given [options], which also select the
  /// [ListenSource]: with [ListenSource.cache] the events are raised from the
  /// local cache only (local writes, cache updates) and the backend is not
  /// contacted for this listener.
  Stream<DocumentSnapshot<T>> getSnapshotsWithOptions(SnapshotListenOptions options) {
    return _getSnapshotsInternal(
        _internalOptions(options.metadataChanges, options.source));
  }

  Stream<DocumentSnapshot<T>> _getSnapshotsInternal(ListenOptions options) {
    final core.Query query = core.Query(key.path);

    return listenToQuery(firestore.client, query, options).map((ViewSnapshot snapshot) {
      hardAssert(snapshot.documents.length <= 1,
          'Too many documents returned on a document query');
      final Document? document = snapshot.documents.getDocument(key);

      if (document != null) {
        final bool hasPendingWrites =
            snapshot.mutatedKeys.contains(document.key);
        return DocumentSnapshot<T>.fromDocument(
          firestore,
          document,
          isFromCache: snapshot.isFromCache,
          hasPendingWrites: hasPendingWrites,
          converter: converter,
        );
      } else {
        // We don't raise `hasPendingWrites` for deleted documents.
        const bool hasPendingWrites = false;
        return DocumentSnapshot<T>.fromNoDocument(
          firestore,
          key,
          isFromCache: snapshot.isFromCache,
          hasPendingWrites: hasPendingWrites,
          converter: converter,
        );
      }
    });
  }

  /// Converts the  API [MetadataChanges] object to the internal options object.
  static ListenOptions _internalOptions(MetadataChanges metadataChanges,
      [ListenSource source = ListenSource.defaultSource]) {
    return ListenOptions(
      source: source,
      includeDocumentMetadataChanges:
          metadataChanges == MetadataChanges.include,
      includeQueryMetadataChanges: metadataChanges == MetadataChanges.include,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentReference &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          firestore == other.firestore &&
          converter == other.converter;

  @override
  int get hashCode => key.hashCode * 31 ^ firestore.hashCode * 31 ^ converter.hashCode;
}

/// Returns the first event of [stream] and waits for the subscription to be
/// completely cancelled, so a subsequent listen on the same query doesn't race
/// with the removal of the previous listener.
Future<T> _firstAndCancel<T>(Stream<T> stream) async {
  await for (final T value in stream) {
    return value;
  }
  throw StateError('No element');
}
