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
import 'package:cloud_firestore_dart/src/firebase/firestore/get_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';

/// A [DocumentReference] refers to a document location in a Firestore database and can be used to write, read, or
/// listen to the location. There may or may not exist a document at the referenced location. A [DocumentReference] can
/// also be used to create a [CollectionReference] to a subcollection.
///
/// Get one from [FirebaseFirestore.doc] or [CollectionReference.doc]. Creating a reference does not contact the backend.
/// [T] is the type of the document data, `Map<String, Object?>` unless a converter was attached with
/// [withConverter]. Two references are equal when they point to the same document of the same [FirebaseFirestore] instance
/// with the same converter.
///
/// Writes ([set], [update], [delete]) are applied to the local cache at once and their futures complete when the
/// backend has acknowledged them; while the client is offline the futures do not complete, and the writes are sent
/// when it is back online.
///
/// ```dart
/// final DocumentReference<Map<String, Object?>> sf = firestore.doc(
///   'cities/SF',
/// );
/// await sf.set({'name': 'San Francisco', 'population': 870000});
/// await sf.update({'population': FieldValue.increment(1)});
///
/// final DocumentSnapshot<Map<String, Object?>> snapshot = await sf.get();
/// print(snapshot['population']);
///
/// await sf.delete();
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing
/// is not supported in production code and new SDK releases may break code that does so.
class DocumentReference<T extends dynamic> {
  // TODO(long1eu): We should checkNotNull(firestore), but tests are currently cheating and setting it to null.
  /// Implementation detail of the SDK; not part of the supported API. Use [FirebaseFirestore.doc] or
  /// [CollectionReference.doc].
  DocumentReference._(this._key, this.firestore, [this.converter]);

  /// Implementation detail of the SDK; not part of the supported API. Use [FirebaseFirestore.doc] or
  /// [CollectionReference.doc].
  factory DocumentReference._forPath(
    ResourcePath path,
    FirebaseFirestore firestore, [
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

    return DocumentReference<T>._(
      DocumentKey.fromPath(path),
      firestore,
      converter,
    );
  }

  /// Builds a [DocumentReference] of [firestore] from a JSON map created by [toJson], optionally with a [converter].
  ///
  /// Throws an [ArgumentError] if [json] does not have that shape or `referencePath` is not a document path. This is
  /// the JS SDK `DocumentReference.fromJSON()`.
  factory DocumentReference.fromJson(
    FirebaseFirestore firestore,
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
    return DocumentReference<T>._forPath(path, firestore, converter);
  }

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/documentReference/1.0';

  final DocumentKey _key;

  /// Returns a JSON-serializable representation of this reference: its `type` ([jsonType]) and `referencePath`, like
  /// the JS SDK's `DocumentReference.toJSON()`. The Firestore instance and the converter are not part of it; read it
  /// back with [DocumentReference.fromJson].
  Map<String, Object> toJson() {
    return <String, Object>{
      'type': jsonType,
      'referencePath': key.path.canonicalString,
    };
  }

  /// The Firestore instance this reference belongs to. A `WriteBatch` or a `Transaction` only accepts references of
  /// its own instance.
  final FirebaseFirestore firestore;

  /// The converter attached with [withConverter], or null for raw maps.
  final FirestoreDataConverter<T>? converter;

  /// Returns a reference to the same document that converts data with
  /// [fromFirestore] and [toFirestore] (type [U]) when reading and writing. Use [withoutConverter]
  /// to go back to raw maps.
  ///
  /// [set] then takes a [U], and snapshots return a [U] from `data()`. [update] still takes a map of fields, as in the
  /// other SDKs.
  ///
  /// ```dart
  /// final DocumentReference<String> name = firestore
  ///     .doc('cities/SF')
  ///     .withConverter<String>(
  ///       fromFirestore: (snapshot, options) => snapshot['name'] as String,
  ///       toFirestore: (name, options) => {'name': name},
  ///     );
  /// await name.set('San Francisco');
  /// ```
  DocumentReference<U> withConverter<U extends Object?>({
    required FromFirestore<U> fromFirestore,
    required ToFirestore<U> toFirestore,
  }) {
    return DocumentReference<U>._(
      key,
      firestore,
      FirestoreDataConverter<U>.from(
        fromFirestore: fromFirestore,
        toFirestore: toFirestore,
      ),
    );
  }

  /// Returns a reference to the same document that reads and writes raw
  /// `Map<String, Object?>` values (the equivalent of `withConverter(null)`
  /// in the JS SDK).
  DocumentReference<Map<String, Object?>> withoutConverter() {
    return DocumentReference<Map<String, Object?>>._(key, firestore);
  }

  /// The id of the document: the last segment of its [path].
  String get id => key.path.last;

  /// Gets a [CollectionReference] to the collection that contains this document.
  ///
  /// Returns the [CollectionReference] that contains this document, with the converter of this reference.
  CollectionReference<T> get parent {
    return CollectionReferenceInternal.create<T>(
      key.path.popLast(),
      firestore,
      converter,
    );
  }

  /// Gets the path of this document (relative to the root of the database) as a slash-separated string, such as
  /// `cities/SF`.
  ///
  /// Returns the path of this document.
  String get path => key.path.canonicalString;

  /// Gets a [CollectionReference] instance that refers to the subcollection at the specified path relative to this
  /// document.
  ///
  /// [collectionPath] a slash-separated relative path to a subcollection. Throws an [ArgumentError] if it is empty
  /// or names a document instead of a collection.
  ///
  /// Returns the [CollectionReference] instance, which reads raw maps.
  ///
  /// ```dart
  /// final CollectionReference<Map<String, Object?>> landmarks = firestore
  ///     .doc('cities/SF')
  ///     .collection('landmarks');
  /// await landmarks.add({'name': 'Golden Gate Bridge'});
  /// ```
  CollectionReference<Map<String, Object?>> collection(String collectionPath) {
    checkNotNull(collectionPath, 'Provided collection path must not be null.');
    checkNonEmptyPath('DocumentReference.collection', collectionPath);
    return CollectionReferenceInternal.create<Map<String, Object?>>(
      key.path.appendField(ResourcePath.fromString(collectionPath)),
      firestore,
    );
  }

  /// Writes to the document referred to by this DocumentReference. If the document does not yet exist, it will be
  /// created. If you pass [SetOptions], the provided data can be merged into an existing document.
  ///
  /// [data] a map of the fields and values for the document (or a [T] that the converter turns into one).
  /// [options] an object to configure the set behavior. By default (`SetOptions()`) the document is replaced
  /// with [data]; `SetOptions(merge: true)` only writes the fields in [data] and keeps the others, and
  /// [SetOptions.mergeFields] only writes the listed fields.
  ///
  /// Returns a Future that will be resolved when the write finishes, that is when the backend has acknowledged it.
  /// The write is applied to the local cache at once, so reads and listeners see it immediately; while the client is
  /// offline the future does not complete. The future fails with an [ArgumentError] when [data] holds a value
  /// Firestore cannot store, and with a [FirestoreException] when the backend rejects the write (for example
  /// [FirestoreErrorCode.permissionDenied]).
  ///
  /// Values can be `null`, `bool`, `int`, `double`, `String`, `Timestamp`, `DateTime`, `GeoPoint`, `Blob`,
  /// [DocumentReference], `VectorValue`, lists and maps of those, and the sentinels of `FieldValue` such as
  /// `FieldValue.serverTimestamp()`.
  ///
  /// ```dart
  /// final DocumentReference<Map<String, Object?>> sf = firestore.doc(
  ///   'cities/SF',
  /// );
  /// await sf.set({
  ///   'name': 'San Francisco',
  ///   'population': 870000,
  ///   'updated': FieldValue.serverTimestamp(),
  /// });
  ///
  /// // Change one field and keep the others.
  /// await sf.set({'capital': false}, const SetOptions(merge: true));
  /// ```
  Future<void> set(T data, [SetOptions? options]) =>
      _set(data, options, 'DocumentReference.set');

  /// [set] for the public method [methodName], which the errors name.
  Future<void> _set(T data, SetOptions? options, String methodName) async {
    final SetOptions setOptions = options ?? const SetOptions();
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

    await voidErrorTransformer(
      () => firestore.client.write(<Mutation>[
        parsed.toMutation(key, Precondition.none),
      ]),
    );
  }

  /// Updates fields in the document referred to by this [DocumentReference]. If no document exists yet, the update will
  /// fail.
  ///
  /// [data] a map of field/value pairs to update. Each key is a `String`, in which dots separate nested fields, or a
  /// [FieldPath], for a field name that contains a dot. The fields that are not in [data] keep their values. Use
  /// `FieldValue.delete()` as a value to remove a field.
  ///
  /// Returns a Future that will be resolved when the write finishes, that is when the backend has acknowledged it.
  /// The update is applied to the local cache at once; while the client is offline the future does not complete.
  /// When the document does not exist the backend rejects the update and the future fails with a [FirestoreException]
  /// with the code [FirestoreErrorCode.notFound]. The future fails with an [ArgumentError] for an invalid field path
  /// or value.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').update({
  ///   'population': FieldValue.increment(1000),
  ///   'stats.visits': 12, // a nested field
  ///   'nickname': FieldValue.delete(),
  ///   FieldPath(['stats', 'last.year']): 870000, // a field name with a dot
  /// });
  /// ```
  Future<void> update(Map<Object, Object?> data) async {
    final UserDataParsedUpdateData parsedData = firestore.dataConverter
        .parseUpdateMap(
          data,
          methodName: 'DocumentReference.update',
          targetDoc: key,
        );
    await voidErrorTransformer(
      () => firestore.client.write(<Mutation>[
        parsedData.toMutation(key, Precondition(exists: true)),
      ]),
    );
  }

  /// Deletes the document referred to by this [DocumentReference].
  ///
  /// Returns a Future that will be resolved when the delete completes, that is when the backend has acknowledged
  /// it. Deleting a document that does not exist succeeds. The subcollections of the document are not deleted. As
  /// with [set], the delete is applied to the local cache at once and the future does not complete while the client
  /// is offline.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').delete();
  /// ```
  Future<void> delete() {
    return voidErrorTransformer(
      () => firestore.client.write(<DeleteMutation>[
        DeleteMutation(key, Precondition.none),
      ]),
    );
  }

  /// Reads the document referenced by this [DocumentReference].
  ///
  /// By default, [get] attempts to provide up-to-date data when possible by waiting for data from the server, but it
  /// may return cached data or fail if you are offline and the server cannot be reached. This behavior can be altered
  /// with [options].
  ///
  /// The [GetOptions.source] of [options] configures the get behavior:
  ///
  /// * [Source.serverAndCache] (the default): waits for the backend; when the client is offline it answers from the
  ///   cache, and fails with [FirestoreErrorCode.unavailable] if the cache has no copy of the document.
  /// * [Source.server]: fails with [FirestoreErrorCode.unavailable] when the backend cannot be reached.
  /// * [Source.cache]: answers from the cache only; fails with [FirestoreErrorCode.unavailable] when the cache does
  ///   not know the document. A document the cache knows to be missing gives a snapshot whose
  ///   [DocumentSnapshot.exists] is false.
  ///
  /// Returns a Future that will be resolved with a [DocumentSnapshot] of the document at this
  /// [DocumentReference]. A document that does not exist gives a snapshot whose [DocumentSnapshot.exists] is false;
  /// it is not an error. Writes that the backend has not acknowledged yet are included. This is the JS SDK `getDoc`,
  /// `getDocFromServer` and `getDocFromCache`.
  ///
  /// ```dart
  /// final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
  ///     .doc('cities/SF')
  ///     .get();
  /// if (snapshot.exists) {
  ///   print(snapshot.data());
  /// }
  ///
  /// final DocumentSnapshot<Map<String, Object?>> cached = await firestore
  ///     .doc('cities/SF')
  ///     .get(const GetOptions(source: Source.cache));
  /// ```
  Future<DocumentSnapshot<T>> get([GetOptions? options]) async {
    final Source source = options?.source ?? Source.serverAndCache;

    if (source == Source.cache) {
      final Document? doc = await firestore.client.getDocumentFromLocalCache(
        key,
      );
      final bool hasPendingWrites = doc != null && doc.hasLocalMutations;

      return DocumentSnapshotInternal.create<T>(
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
    return _firstAndCancel(
      _getSnapshotsInternal(const ListenOptions.all()).map((
        DocumentSnapshot<T> snapshot,
      ) {
        if (!snapshot.exists && snapshot.metadata.isFromCache) {
          // TODO(long1eu): Reconsider how to raise missing documents when offline.
          //  If we're online and the document doesn't exist then we set the result of the Future with a document with
          //  document.exists set to false. If we're offline however, we set the Error on the Task. Two options:
          //    1. Cache the negative response from the server so we can deliver that even when you're offline.
          //    2. Actually set the Error of the Task if the document doesn't exist when you are offline.
          throw FirestoreException(
            message: 'Failed to get document because the client is offline.',
            errorCode: FirestoreErrorCode.unavailable,
          );
        } else if (snapshot.exists &&
            snapshot.metadata.isFromCache &&
            source == Source.server) {
          throw FirestoreException(
            message:
                'Failed to get document from server. (However, this document does exist in the local cache. Run again '
                'without setting the source to Source.server to retrieve the cached document.)',
            errorCode: FirestoreErrorCode.unavailable,
          );
        } else {
          return snapshot;
        }
      }),
    );
  }

  /// A stream of snapshots of this document: the current contents first, then a new snapshot every
  /// time the contents change.
  ///
  /// The first snapshot can come from the local cache before the backend answers. A document that does not exist (or
  /// is deleted) gives a snapshot whose [DocumentSnapshot.exists] is false. Local writes raise a snapshot at once,
  /// with `metadata.hasPendingWrites` true. While the client is offline the stream keeps delivering changes from the
  /// cache.
  ///
  /// With [includeMetadataChanges] a snapshot also arrives when only the [DocumentSnapshot.metadata] changed (for
  /// example when a local write is acknowledged). With [ListenSource.cache] as [source] the events come from the
  /// local cache only and the backend is not contacted for this listener.
  ///
  /// The listener is registered when you listen to the stream and removed when you cancel the subscription. Each
  /// call returns a new single-subscription stream. An error (for example
  /// [FirestoreErrorCode.permissionDenied]) is delivered on the stream, which then closes. This is the JS SDK
  /// `onSnapshot`.
  ///
  /// ```dart
  /// final StreamSubscription<DocumentSnapshot<Map<String, Object?>>> subscription =
  ///     firestore
  ///         .doc('cities/SF')
  ///         .snapshots()
  ///         .listen(
  ///           (DocumentSnapshot<Map<String, Object?>> snapshot) {
  ///             print(snapshot.exists ? snapshot.data() : 'no such document');
  ///           },
  ///           onError: (Object error) => print('listen failed: $error'),
  ///         );
  /// // ...
  /// await subscription.cancel();
  ///
  /// firestore.doc('cities/SF').snapshots(includeMetadataChanges: true).listen((
  ///   DocumentSnapshot<Map<String, Object?>> snapshot,
  /// ) {
  ///   final bool saved = !snapshot.metadata.hasPendingWrites;
  ///   print(saved ? 'saved on the server' : 'local change, not saved yet');
  /// });
  /// ```
  Stream<DocumentSnapshot<T>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    return _getSnapshotsInternal(
      _internalOptions(includeMetadataChanges, source),
    );
  }

  Stream<DocumentSnapshot<T>> _getSnapshotsInternal(ListenOptions options) {
    final core.Query query = core.Query(key.path);

    return listenToQuery(firestore.client, query, options).map((
      ViewSnapshot snapshot,
    ) {
      hardAssert(
        snapshot.documents.length <= 1,
        'Too many documents returned on a document query',
      );
      final Document? document = snapshot.documents.getDocument(key);

      if (document != null) {
        final bool hasPendingWrites = snapshot.mutatedKeys.contains(
          document.key,
        );
        return DocumentSnapshotInternal.fromDocument<T>(
          firestore,
          document,
          isFromCache: snapshot.isFromCache,
          hasPendingWrites: hasPendingWrites,
          converter: converter,
        );
      } else {
        // We don't raise `hasPendingWrites` for deleted documents.
        const bool hasPendingWrites = false;
        return DocumentSnapshotInternal.fromNoDocument<T>(
          firestore,
          key,
          isFromCache: snapshot.isFromCache,
          hasPendingWrites: hasPendingWrites,
          converter: converter,
        );
      }
    });
  }

  static ListenOptions _internalOptions(
    bool includeMetadataChanges, [
    ListenSource source = ListenSource.defaultSource,
  ]) {
    return ListenOptions(
      source: source,
      includeDocumentMetadataChanges: includeMetadataChanges,
      includeQueryMetadataChanges: includeMetadataChanges,
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
  int get hashCode =>
      key.hashCode * 31 ^ firestore.hashCode * 31 ^ converter.hashCode;
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

/// Members of [DocumentReference] for the SDK itself. Not exported by the public libraries.
extension DocumentReferenceInternal<T> on DocumentReference<T> {
  /// The key of the document this reference points to.
  DocumentKey get key => _key;

  /// [DocumentReference.set] for the public method [methodName] (for example
  /// `CollectionReference.add`), which the errors name.
  Future<void> setFor(String methodName, T data) =>
      _set(data, null, methodName);

  /// A reference to the document with [key] in [firestore].
  static DocumentReference<T> create<T extends dynamic>(
    DocumentKey key,
    FirebaseFirestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) => DocumentReference<T>._(key, firestore, converter);

  /// A reference to the document at [path] in [firestore]. Throws an [ArgumentError] if [path] is not a document
  /// path.
  static DocumentReference<T> forPath<T extends dynamic>(
    ResourcePath path,
    FirebaseFirestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) => DocumentReference<T>._forPath(path, firestore, converter);
}
