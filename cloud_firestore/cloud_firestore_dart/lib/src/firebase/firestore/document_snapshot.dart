// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_json.dart'
    as snapshot_json;
import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:meta/meta.dart';

/// A [DocumentSnapshot] contains data read from a document in your [Firestore] database. The data can be extracted with
/// the [data] or [get] methods.
///
/// If the [DocumentSnapshot‘ points to a non-existing document, [data] and its corresponding methods will return null.
/// You can always explicitly check for a document's existence by calling [exists].
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class DocumentSnapshot<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  DocumentSnapshot(
    this._firestore,
    this._key,
    this.document, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  })  : _converter = converter,
        metadata = SnapshotMetadata(hasPendingWrites, isFromCache);

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  factory DocumentSnapshot.fromDocument(
    Firestore firestore,
    Document doc, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) {
    return DocumentSnapshot<T>(firestore, doc.key, doc,
        isFromCache: isFromCache,
        hasPendingWrites: hasPendingWrites,
        converter: converter);
  }

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  factory DocumentSnapshot.fromNoDocument(
    Firestore firestore,
    DocumentKey key, {
    required bool isFromCache,
    required bool hasPendingWrites,
    FirestoreDataConverter<T>? converter,
  }) {
    return DocumentSnapshot<T>(firestore, key, null,
        isFromCache: isFromCache,
        hasPendingWrites: hasPendingWrites,
        converter: converter);
  }

  /// Builds a [DocumentSnapshot] from the JSON object written by [toJson], for the [firestore] instance.
  ///
  /// The snapshot is not from cache and has no pending writes. Pass the [converter] of the original snapshot to get
  /// typed data back. Throws a [FirestoreError] if [json] is not a valid document snapshot JSON object, for example
  /// one of a different project or database.
  ///
  /// This is the JS SDK `documentSnapshotFromJSON()`.
  factory DocumentSnapshot.fromJson(
    Firestore firestore,
    Map<String, Object?> json, {
    FirestoreDataConverter<T>? converter,
  }) {
    return snapshot_json.documentSnapshotFromJson<T>(firestore, json, converter);
  }

  final Firestore _firestore;

  final FirestoreDataConverter<T>? _converter;

  final DocumentKey _key;

  /// Is null if the document doesn't exist
  @internal
  final Document? document;

  /// The metadata for this document snapshot.
  final SnapshotMetadata metadata;

  /// The value of the `type` field written by [toJson].
  static const String jsonType = 'firestore/documentSnapshot/1.0';

  /// Returns a JSON-serializable representation of this snapshot, which [DocumentSnapshot.fromJson] reads back and
  /// `Firestore.documentSnapshotsFromJson` listens from.
  ///
  /// The `bundle` field holds the document as a Firestore bundle (empty when the document does not exist). Throws a
  /// [FirestoreError] (failed-precondition) if the snapshot has pending writes: await `waitForPendingWrites()` first.
  ///
  /// This is the JS SDK `DocumentSnapshot.toJSON()`; the JSON is interchangeable with the one of the JS SDK (Node).
  Map<String, Object?> toJson() => snapshot_json.documentSnapshotToJson(
      _firestore, _key, document, metadata.hasPendingWrites);

  /// The id of the document.
  String get id => _key.path.last;

  /// Returns true if the document existed in this snapshot.
  bool get exists => document != null;

  /// Returns the fields of the document as a Map or null if the document doesn't exist. Field values will be converted
  /// to their native Dart representation.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  T? get data => getData(ServerTimestampBehavior.none);

  /// Returns the fields of the document as a Map or null if the document doesn't exist. Field values will be converted
  /// to their native Dart representation.
  ///
  /// [serverTimestampBehavior] Configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  ///
  /// If this snapshot comes from a reference or query with a converter (see
  /// `withConverter`), the result is the converted value of type [T].
  T? getData(ServerTimestampBehavior serverTimestampBehavior) {
    final Document? doc = document;
    if (doc == null) {
      return null;
    }
    final FirestoreDataConverter<T>? converter = _converter;
    if (converter == null) {
      return _rawData(doc, serverTimestampBehavior) as T;
    }
    final QueryDocumentSnapshot<Map<String, Object?>> raw =
        QueryDocumentSnapshot<Map<String, Object?>>.fromDocument(
      _firestore,
      doc,
      fromCache: metadata.isFromCache,
      hasPendingWrites: metadata.hasPendingWrites,
    );
    return converter.fromFirestore(
        raw, SnapshotOptions(serverTimestamps: serverTimestampBehavior));
  }

  Map<String, Object?> _rawData(
      Document doc, ServerTimestampBehavior serverTimestampBehavior) {
    final _FieldValueOptions fieldValueOptions =
        _FieldValueOptions(serverTimestampBehavior: serverTimestampBehavior);
    return _convertObject(doc.data, fieldValueOptions);
  }

  /// Returns whether or not the field exists in the document. Returns false if the document does not exist.
  ///
  /// [field] the path to the field.
  ///
  /// Returns true if the field exists.
  bool contains(String field) {
    return containsPath(FieldPath.fromDotSeparatedPath(field));
  }

  /// Returns whether or not the field exists in the document. Returns false if the document does  not exist.
  ///
  /// [fieldPath] the path to the field.
  ///
  /// Returns true if the field exists.
  bool containsPath(FieldPath fieldPath) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    return document?.getField(fieldPath.internalPath) != null;
  }

  /// The value of [field], or `null` if the field or the document does not exist. Same as [get].
  Object? operator [](String field) => get(field);

  /// Returns the value at the field or null if the field doesn't exist.
  ///
  /// [field] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the value at the given field or null.
  Object? get(String field,
      [ServerTimestampBehavior? serverTimestampBehavior]) {
    return getField(FieldPath.fromDotSeparatedPath(field),
        serverTimestampBehavior ?? ServerTimestampBehavior.none);
  }

  /// Returns the value at the field or null if the field or document doesn't exist.
  ///
  /// [fieldPath] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the value at the given field or null.
  Object? getField(FieldPath fieldPath,
      [ServerTimestampBehavior? serverTimestampBehavior]) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');

    final _FieldValueOptions fieldValueOptions = _FieldValueOptions(
        serverTimestampBehavior:
            serverTimestampBehavior ?? ServerTimestampBehavior.none);
    return _getInternal(fieldPath.internalPath, fieldValueOptions);
  }

  /// Returns the value of the field as a bool. If the value is not a bool this will throw a state error.
  ///
  /// [field] the path to the field.
  ///
  /// Returns the value of the field
  bool? getBool(String field) => _getTypedValue<bool>(field);

  /// Returns the value of the field as a double.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  double? getDouble(String field) {
    final num? val = _getTypedValue(field);
    return val != null ? val.toDouble() : null;
  }

  /// Returns the value of the field as a int.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  int? getInt(String field) {
    final num? val = _getTypedValue(field);
    return val != null ? val.toInt() : null;
  }

  /// Returns the value of the field as a String.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a String.
  /// Returns the value of the field
  String? getString(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DateTime].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Throws [StateError] if the value is not a Date.
  /// Returns the value of the field
  DateTime? getDate(String field,
      [ServerTimestampBehavior? serverTimestampBehavior]) {
    checkNotNull(field, 'Provided field path must not be null.');
    final Object? maybeDate = _getInternal(
      FieldPath.fromDotSeparatedPath(field).internalPath,
      _FieldValueOptions(
        serverTimestampBehavior:
            serverTimestampBehavior ?? ServerTimestampBehavior.none,
        timestampsInSnapshotsEnabled: false,
      ),
    );
    return _castTypedValue(maybeDate, field);
  }

  /// Returns the value of the field as a [Timestamp].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Throws [StateError] if the value is not a timestamp field.
  /// Returns the value of the field
  Timestamp? getTimestamp(String field,
      [ServerTimestampBehavior? serverTimestampBehavior]) {
    checkNotNull(field, 'Provided field path must not be null.');
    final Object? maybeTimestamp = _getInternal(
      FieldPath.fromDotSeparatedPath(field).internalPath,
      _FieldValueOptions(
          serverTimestampBehavior:
              serverTimestampBehavior ?? ServerTimestampBehavior.none),
    );
    return _castTypedValue(maybeTimestamp, field);
  }

  /// Returns the value of the field as a [Blob].
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a Blob.
  /// Returns the value of the field
  Blob? getBlob(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [GeoPoint].
  ///
  /// [field] The path to the field.
  ///
  /// Throws [StateError] if the value is not a [GeoPoint].
  /// Returns the value of the field
  GeoPoint? getGeoPoint(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [VectorValue], or null if the field does not exist.
  ///
  /// Throws [StateError] if the value is not a [VectorValue].
  VectorValue? getVectorValue(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DocumentReference].
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a [DocumentReference].
  /// Returns the value of the field
  DocumentReference<Map<String, Object?>>? getDocumentReference(String field) =>
      _getTypedValue(field);

  /// Gets the reference to the document.
  ///
  /// Returns the reference to the document.
  @Deprecated('Use ref instead.')
  DocumentReference<T> get reference => ref;

  /// Gets the reference to the document. Same as [reference]; this is the name
  /// used by the current official Firestore API.
  DocumentReference<T> get ref =>
      DocumentReference<T>(_key, _firestore, _converter);

  V? _getTypedValue<V>(String field) {
    checkNotNull(field, 'Provided field must not be null.');
    final Object? value = get(field, ServerTimestampBehavior.none);
    return _castTypedValue<V>(value, field);
  }

  V? _castTypedValue<V>(Object? value, String field) {
    if (value == null) {
      return null;
    }

    try {
      final V result = value as V;
      return result;
    } on TypeError catch (_) {
      throw StateError(
          'Field \'$field\' is not a $V, but it is ${value.runtimeType}');
    }
  }

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
      ServerTimestampValue value, _FieldValueOptions options) {
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
    final Timestamp timestamp = value.value;
    if (options.timestampsInSnapshotsEnabled) {
      return timestamp;
    } else {
      return timestamp.toDate();
    }
  }

  Object _convertReference(ReferenceValue value) {
    final DocumentKey key = value.value;
    final DatabaseId refDatabase = value.databaseId;
    final DatabaseId database = _firestore.databaseId;
    if (refDatabase != database) {
      // TODO(long1eu): Somehow support foreign references.
      Log.w('$DocumentSnapshot',
          'Document ${key.path} contains a document reference within a different database (${refDatabase.projectId}/${refDatabase.databaseId}) which is not supported. It will be treated as a reference in the current database (${database.projectId}/${database.databaseId}) instead.');
    }
    return DocumentReference<Map<String, Object?>>(key, _firestore);
  }

  Map<String, Object?> _convertObject(
      ObjectValue objectValue, _FieldValueOptions options) {
    final Map<String, Object?> result = <String, Object?>{};
    for (MapEntry<String, FieldValue> entry in objectValue.internalValue) {
      result[entry.key] = _convertValue(entry.value, options);
    }
    return result;
  }

  List<Object?> _convertArray(
      ArrayValue arrayValue, _FieldValueOptions options) {
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
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('key', _key)
          ..add('metadata', metadata)
          ..add('document', document))
        .toString();
  }
}

/// Holds settings that define field value deserialization options.
class _FieldValueOptions {
  _FieldValueOptions({
    this.serverTimestampBehavior = ServerTimestampBehavior.none,
    this.timestampsInSnapshotsEnabled = true,
  });

  final ServerTimestampBehavior serverTimestampBehavior;
  final bool timestampsInSnapshotsEnabled;
}
