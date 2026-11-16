// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_json.dart'
    as snapshot_json;
import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:firebase_app_dart/internal.dart';

/// A [DocumentSnapshot] contains data read from a document in your [FirebaseFirestore] database. The data can be extracted with
/// the [data] or [get] methods.
///
/// If the [DocumentSnapshot] points to a non-existing document, [data] and its corresponding methods will return null.
/// You can always explicitly check for a document's existence by calling [exists].
///
/// A snapshot is immutable: it holds the document as it was when it was read. [metadata] tells whether it came from
/// the local cache and whether it includes local writes that the backend has not acknowledged yet. Values are
/// returned as Dart types: numbers as `int` or `double`, timestamps as [Timestamp], references as
/// [DocumentReference], bytes as [Blob], maps as `Map<String, Object?>` and arrays as `List<Object?>`.
///
/// Unlike the JS SDK, [data] is a getter, not a method. Snapshots come from [DocumentReference.get],
/// [DocumentReference.snapshots], `Transaction.get` and, as [QueryDocumentSnapshot], from query results.
///
/// ```dart
/// final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
///     .doc('cities/SF')
///     .get();
/// if (snapshot.exists) {
///   final Map<String, Object?> data = snapshot.data()!;
///   print(data['name']);
///   print(snapshot['population']); // the same as snapshot.get('population')
///   print((snapshot.get('founded') as Timestamp?)?.toDate());
/// }
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class DocumentSnapshot<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API.
  DocumentSnapshot._(
    this._firestore,
    this._key,
    this._document, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) : _converter = converter,
       metadata = SnapshotMetadata(hasPendingWrites, isFromCache);

  /// Implementation detail of the SDK; not part of the supported API.
  factory DocumentSnapshot._fromDocument(
    FirebaseFirestore firestore,
    Document doc, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) {
    return DocumentSnapshot<T>._(
      firestore,
      doc.key,
      doc,
      isFromCache: isFromCache,
      hasPendingWrites: hasPendingWrites,
      converter: converter,
    );
  }

  /// Implementation detail of the SDK; not part of the supported API.
  factory DocumentSnapshot._fromNoDocument(
    FirebaseFirestore firestore,
    DocumentKey key, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) {
    return DocumentSnapshot<T>._(
      firestore,
      key,
      null,
      isFromCache: isFromCache,
      hasPendingWrites: hasPendingWrites,
      converter: converter,
    );
  }

  /// Builds a [DocumentSnapshot] from the JSON object written by [toJson], for the [firestore] instance.
  ///
  /// The snapshot is not from cache and has no pending writes. Pass the [converter] of the original snapshot to get
  /// typed data back. Throws a [FirestoreException] if [json] is not a valid document snapshot JSON object, for example
  /// one of a different project or database.
  ///
  /// This is the JS SDK `documentSnapshotFromJSON()`.
  factory DocumentSnapshot.fromJson(
    FirebaseFirestore firestore,
    Map<String, Object?> json, {
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.documentSnapshotFromJson<T>(
      firestore,
      json,
      converter,
    );
  }

  final FirebaseFirestore _firestore;

  final FirestoreDataConverter<T>? _converter;

  final DocumentKey _key;

  /// Is null if the document doesn't exist
  final Document? _document;

  /// The metadata for this document snapshot: whether it came from the cache
  /// ([SnapshotMetadata.isFromCache]) and whether it has local writes that the backend has not acknowledged yet
  /// ([SnapshotMetadata.hasPendingWrites]).
  final SnapshotMetadata metadata;

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/documentSnapshot/1.0';

  /// Returns a JSON-serializable representation of this snapshot, which [DocumentSnapshot.fromJson] reads back and
  /// `FirebaseFirestore.documentSnapshotsFromJson` listens from.
  ///
  /// The `bundle` field holds the document as a Firestore bundle (empty when the document does not exist). Throws a
  /// [FirestoreException] (failed-precondition) if the snapshot has pending writes: await `waitForPendingWrites()` first.
  ///
  /// This is the JS SDK `DocumentSnapshot.toJSON()`; the JSON is interchangeable with the one of the JS SDK (Node).
  /// One difference: for a document that does not exist the `bundle` is empty, which this SDK reads back as a missing
  /// document and the JS SDK cannot read.
  ///
  /// ```dart
  /// final Map<String, Object?> json = (await firestore.doc('cities/SF').get())
  ///     .toJson();
  /// // Later, possibly in another program:
  /// final DocumentSnapshot<Map<String, Object?>> restored =
  ///     DocumentSnapshot<Map<String, Object?>>.fromJson(firestore, json);
  /// print(restored.data());
  /// ```
  Map<String, Object?> toJson() => snapshot_json.documentSnapshotToJson(
    _firestore,
    _key,
    document,
    metadata.hasPendingWrites,
  );

  /// The id of the document: the last segment of its path.
  String get id => _key.path.last;

  /// Returns true if the document existed in this snapshot.
  bool get exists => document != null;

  /// The fields of the document, or null if the document doesn't exist. Field values are converted to their
  /// Dart representation. With a converter (see [DocumentReference.withConverter]) it returns the converted [T]
  /// instead, and the converter gets [serverTimestamps] in its [SnapshotOptions].
  ///
  /// A server timestamp (`FieldValue.serverTimestamp()`) that the backend has not set yet is null by default
  /// ([ServerTimestampBehavior.none]); pass [ServerTimestampBehavior.estimate] or
  /// [ServerTimestampBehavior.previous] as [serverTimestamps] to get a value for it.
  ///
  /// ```dart
  /// final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
  ///     .doc('cities/SF')
  ///     .get();
  /// final Map<String, Object?>? data = snapshot.data();
  /// print(data?['name']);
  ///
  /// // Shows a local estimate until the backend sets the timestamp.
  /// final Map<String, Object?>? estimated = snapshot.data(
  ///   serverTimestamps: ServerTimestampBehavior.estimate,
  /// );
  /// print(estimated?['updated']);
  /// ```
  T? data({
    ServerTimestampBehavior serverTimestamps = ServerTimestampBehavior.none,
  }) {
    final Document? doc = document;
    if (doc == null) {
      return null;
    }
    final FirestoreDataConverter<T>? converter = _converter;
    if (converter == null) {
      return _rawData(doc, serverTimestamps) as T;
    }
    final QueryDocumentSnapshot<Map<String, Object?>> raw =
        QueryDocumentSnapshotInternal.fromDocument<Map<String, Object?>>(
          _firestore,
          doc,
          fromCache: metadata.isFromCache,
          hasPendingWrites: metadata.hasPendingWrites,
        );
    return converter.fromFirestore(
      raw,
      SnapshotOptions(serverTimestamps: serverTimestamps),
    );
  }

  Map<String, Object?> _rawData(
    Document doc,
    ServerTimestampBehavior serverTimestampBehavior,
  ) {
    final _FieldValueOptions fieldValueOptions = _FieldValueOptions(
      serverTimestampBehavior: serverTimestampBehavior,
    );
    return _convertObject(doc.data, fieldValueOptions);
  }

  /// Whether the field exists in the document, also when its value is null. False if the document does not
  /// exist.
  ///
  /// [field] is a [String] (dots separate nested fields, `'address.city'`) or a [FieldPath]. Throws an
  /// [ArgumentError] for an invalid path.
  bool contains(Object field) {
    final FieldPath fieldPath = _fieldPathOf(
      'DocumentSnapshot.contains',
      field,
    );
    return document?.getField(fieldPath.internalPath) != null;
  }

  /// The value of [field], or `null` if the field or the document does not exist. Same as [get].
  Object? operator [](Object field) => get(field);

  /// The value of [field], or null if the field or the document doesn't exist.
  ///
  /// [field] is a [String] (dots separate nested fields, `'address.city'`) or a [FieldPath] (for a name that
  /// contains a dot). Throws an [ArgumentError] for an invalid path. [serverTimestamps] configures the value of
  /// a server timestamp that has not been set yet ([ServerTimestampBehavior.none], which gives null, by default).
  ///
  /// The value is the raw stored value: a converter is not applied. Cast it to the type you expect.
  ///
  /// ```dart
  /// final String? city = snapshot.get('address.city') as String?;
  /// final Object? population = snapshot['population']; // same as get
  /// final DateTime? founded = (snapshot.get('founded') as Timestamp?)?.toDate();
  /// ```
  Object? get(
    Object field, {
    ServerTimestampBehavior serverTimestamps = ServerTimestampBehavior.none,
  }) {
    final FieldPath fieldPath = _fieldPathOf('DocumentSnapshot.get', field);
    final _FieldValueOptions fieldValueOptions = _FieldValueOptions(
      serverTimestampBehavior: serverTimestamps,
    );
    return _getInternal(fieldPath.internalPath, fieldValueOptions);
  }

  static FieldPath _fieldPathOf(String methodName, Object field) {
    if (field is FieldPath) {
      return field;
    }
    if (field is String) {
      return FieldPathInternal.fromArgument(methodName, field);
    }
    throw ArgumentError.value(
      field,
      'field',
      'must be a String or a FieldPath',
    );
  }

  /// The reference to the document, with the converter of this snapshot.
  ///
  /// ```dart
  /// await snapshot.reference.update({'visited': true});
  /// ```
  DocumentReference<T> get reference =>
      DocumentReferenceInternal.create<T>(_key, _firestore, _converter);

  Object? _convertValue(FieldValue value, _FieldValueOptions options) {
    if (value is ObjectValue) {
      return _convertObject(value, options);
    } else if (value is ArrayValue) {
      return _convertArray(value, options);
    } else if (value is ReferenceValue) {
      return _convertReference(value);
    } else if (value is TimestampValue) {
      return _convertTimestamp(value, options);
    } else if (value is ServerTimestampValue) {
      return _convertServerTimestamp(value, options);
    } else {
      return value.value;
    }
  }

  Object? _convertServerTimestamp(
    ServerTimestampValue value,
    _FieldValueOptions options,
  ) {
    switch (options.serverTimestampBehavior) {
      case ServerTimestampBehavior.previous:
        final FieldValue? previous = value.previousFieldValue;
        return previous == null ? null : _convertValue(previous, options);
      case ServerTimestampBehavior.estimate:
        return _convertTimestamp(TimestampValue(value.localWriteTime), options);
      case ServerTimestampBehavior.none:
        return value.value;
    }
  }

  Object _convertTimestamp(TimestampValue value, _FieldValueOptions options) {
    return value.value;
  }

  Object _convertReference(ReferenceValue value) {
    final DocumentKey key = value.value;
    final DatabaseId refDatabase = value.databaseId;
    final DatabaseId database = _firestore.modelDatabaseId;
    if (refDatabase != database) {
      // TODO(long1eu): Somehow support foreign references.
      Log.w(
        '$DocumentSnapshot',
        'A document reference to ${key.path} refers to a different database (${refDatabase.projectId}/${refDatabase.databaseId}), which is not supported. It will be treated as a reference in the current database (${database.projectId}/${database.databaseId}) instead.',
      );
    }
    return DocumentReferenceInternal.create<Map<String, Object?>>(
      key,
      _firestore,
    );
  }

  Map<String, Object?> _convertObject(
    ObjectValue objectValue,
    _FieldValueOptions options,
  ) {
    final Map<String, Object?> result = <String, Object?>{};
    for (MapEntry<String, FieldValue> entry in objectValue.internalValue) {
      result[entry.key] = _convertValue(entry.value, options);
    }
    return result;
  }

  List<Object?> _convertArray(
    ArrayValue arrayValue,
    _FieldValueOptions options,
  ) {
    return arrayValue.internalValue
        .map((FieldValue v) => _convertValue(v, options))
        .toList();
  }

  Object? _getInternal(model.FieldPath fieldPath, _FieldValueOptions options) {
    final Document? doc = document;
    if (doc != null) {
      final FieldValue? val = doc.getField(fieldPath);
      if (val != null) {
        return _convertValue(val, options);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSnapshot &&
          runtimeType == other.runtimeType &&
          _firestore == other._firestore &&
          _key == other._key &&
          metadata == other.metadata &&
          _converter == other._converter &&
          // Only the data is compared, not the internal state of the document
          // (version, local mutations).
          document?.data == other.document?.data &&
          document?.key == other.document?.key;

  @override
  int get hashCode {
    return _firestore.hashCode * 31 +
        _key.hashCode * 31 +
        (document?.key.hashCode ?? 0) * 31 +
        (document?.data.hashCode ?? 0) * 31 +
        metadata.hashCode * 31;
  }

  @override
  String toString() =>
      'DocumentSnapshot{key=$_key, metadata=$metadata, doc=$document}';
}

/// Holds settings that define field value deserialization options.
class _FieldValueOptions {
  _FieldValueOptions({
    this.serverTimestampBehavior = ServerTimestampBehavior.none,
  });

  final ServerTimestampBehavior serverTimestampBehavior;
}

/// A [QueryDocumentSnapshot] contains data read from a document in your Firestore database as part
/// of a query. The document is guaranteed to exist and its data can be extracted using the [data]
/// or [get] methods.
///
/// [QueryDocumentSnapshot] offers the same API surface as [DocumentSnapshot]. Since query results
/// contain only existing documents, the [exists] method will always return true and [data] will
/// never be null.
///
/// You get them by iterating a `QuerySnapshot` (or from its `docs`) and from `DocumentChange.document`.
///
/// ```dart
/// final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
///     .collection('cities')
///     .get();
/// for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot) {
///   final Map<String, Object?> data = doc.data(); // never null
///   print('${doc.id}: ${data['name']}');
/// }
/// ```
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class QueryDocumentSnapshot<T extends dynamic> extends DocumentSnapshot<T> {
  QueryDocumentSnapshot._(
    super.firestore,
    super.key,
    Document super.doc,
    bool isFromCache,
    bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  ) : super._(
        isFromCache: isFromCache,
        hasPendingWrites: hasPendingWrites,
        converter: converter,
      );

  factory QueryDocumentSnapshot._fromDocument(
    FirebaseFirestore firestore,
    Document doc, {
    required bool fromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) {
    return QueryDocumentSnapshot<T>._(
      firestore,
      doc.key,
      doc,
      fromCache,
      hasPendingWrites,
      converter,
    );
  }

  /// The fields of the document, or the converted [T] with a converter. Unlike
  /// [DocumentSnapshot.data()] it is never null for a snapshot without a converter: the document exists.
  @override
  T data({
    ServerTimestampBehavior serverTimestamps = ServerTimestampBehavior.none,
  }) {
    // The document always exists here; a null can only be what a converter of a nullable [T] returned.
    return super.data(serverTimestamps: serverTimestamps) as T;
  }
}

/// Members of [DocumentSnapshot] for the SDK itself. Not exported by the public libraries.
extension DocumentSnapshotInternal<T> on DocumentSnapshot<T> {
  /// The model document, or null if the document doesn't exist.
  Document? get document => _document;

  /// A snapshot of the document with [key]: [document], or a missing document if it is null.
  static DocumentSnapshot<T> create<T extends dynamic>(
    FirebaseFirestore firestore,
    DocumentKey key,
    Document? document, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) => DocumentSnapshot<T>._(
    firestore,
    key,
    document,
    isFromCache: isFromCache,
    hasPendingWrites: hasPendingWrites,
    converter: converter,
  );

  /// A snapshot of the existing document [doc].
  static DocumentSnapshot<T> fromDocument<T extends dynamic>(
    FirebaseFirestore firestore,
    Document doc, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) => DocumentSnapshot<T>._fromDocument(
    firestore,
    doc,
    isFromCache: isFromCache,
    hasPendingWrites: hasPendingWrites,
    converter: converter,
  );

  /// A snapshot of the missing document with [key].
  static DocumentSnapshot<T> fromNoDocument<T extends dynamic>(
    FirebaseFirestore firestore,
    DocumentKey key, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) => DocumentSnapshot<T>._fromNoDocument(
    firestore,
    key,
    isFromCache: isFromCache,
    hasPendingWrites: hasPendingWrites,
    converter: converter,
  );
}

/// Members of [QueryDocumentSnapshot] for the SDK itself. Not exported by the public libraries.
extension QueryDocumentSnapshotInternal<T> on QueryDocumentSnapshot<T> {
  /// A snapshot of the existing document [doc] in a query result.
  static QueryDocumentSnapshot<T> fromDocument<T extends dynamic>(
    FirebaseFirestore firestore,
    Document doc, {
    required bool fromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) => QueryDocumentSnapshot<T>._fromDocument(
    firestore,
    doc,
    fromCache: fromCache,
    hasPendingWrites: hasPendingWrites,
    converter: converter,
  );
}
