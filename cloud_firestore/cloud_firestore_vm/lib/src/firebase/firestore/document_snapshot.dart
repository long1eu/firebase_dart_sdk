// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart' as model;
import 'package:cloud_firestore_vm/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/snapshot_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/user_data_writer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/document.pb.dart' show Value;
import 'package:meta/meta.dart';

/// A [DocumentSnapshot] contains data read from a document in your [Firestore] database. The data can be extracted with
/// the [data] or [get] methods.
///
/// If the [DocumentSnapshot‘ points to a non-existing document, [data] and its corresponding methods will return null.
/// You can always explicitly check for a document's existence by calling [exists].
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class DocumentSnapshot {
  DocumentSnapshot(
    this._firestore,
    this._key,
    this.document, {
    @required bool isFromCache,
    @required bool hasPendingWrites,
  })  : metadata = SnapshotMetadata(hasPendingWrites, isFromCache),
        assert(_firestore != null),
        assert(_key != null);

  factory DocumentSnapshot.fromDocument(
    Firestore firestore,
    Document doc, {
    @required bool isFromCache,
    @required bool hasPendingWrites,
  }) {
    return DocumentSnapshot(firestore, doc.key, doc, isFromCache: isFromCache, hasPendingWrites: hasPendingWrites);
  }

  factory DocumentSnapshot.fromNoDocument(
    Firestore firestore,
    DocumentKey key, {
    @required bool isFromCache,
    @required bool hasPendingWrites,
  }) {
    return DocumentSnapshot(firestore, key, null, isFromCache: isFromCache, hasPendingWrites: hasPendingWrites);
  }

  final Firestore _firestore;

  final DocumentKey _key;

  /// Is null if the document doesn't exist
  final Document document;

  /// The metadata for this document snapshot.
  final SnapshotMetadata metadata;

  /// The id of the document.
  String get id => _key.path.last;

  /// Returns true if the document existed in this snapshot.
  bool get exists => document != null;

  /// Returns the fields of the document as a Map or null if the document doesn't exist. Field values will be converted
  /// to their native Dart representation.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  Map<String, Object> get data => getData(ServerTimestampBehavior.none);

  /// Returns the fields of the document as a Map or null if the document doesn't exist. Field values will be converted
  /// to their native Dart representation.
  ///
  /// [serverTimestampBehavior] Configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the fields of the document as a Map or null if the document doesn't exist.
  Map<String, Object> getData(ServerTimestampBehavior serverTimestampBehavior) {
    checkNotNull(serverTimestampBehavior, 'Provided serverTimestampBehavior value must not be null.');
    final UserDataWriter userDataWriter = UserDataWriter(_firestore, serverTimestampBehavior);
    return document == null ? null : userDataWriter.convertObject(document.data.fields);
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
    return (document != null) && (document.getField(fieldPath.internalPath) != null);
  }

  Object operator [](String field) => get(field);

  /// Returns the value at the field or null if the field doesn't exist.
  ///
  /// [field] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the value at the given field or null.
  Object get(String field, [ServerTimestampBehavior serverTimestampBehavior]) {
    return getField(FieldPath.fromDotSeparatedPath(field), serverTimestampBehavior ?? ServerTimestampBehavior.none);
  }

  /// Returns the value at the field or null if the field or document doesn't exist.
  ///
  /// [fieldPath] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Returns the value at the given field or null.
  Object getField(FieldPath fieldPath, [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    checkNotNull(serverTimestampBehavior, 'Provided serverTimestampBehavior value must not be null.');

    return _getInternal(fieldPath.internalPath, serverTimestampBehavior);
  }

  /// Returns the value of the field as a bool. If the value is not a bool this will throw a state error.
  ///
  /// [field] the path to the field.
  ///
  /// Returns the value of the field
  bool getBool(String field) => _getTypedValue<bool>(field);

  /// Returns the value of the field as a double.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  double getDouble(String field) {
    final num val = _getTypedValue(field);
    return val != null ? val.toDouble() : null;
  }

  /// Returns the value of the field as a int.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  int getInt(String field) {
    final num val = _getTypedValue(field);
    return val != null ? val.toInt() : null;
  }

  /// Returns the value of the field as a String.
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a String.
  /// Returns the value of the field
  String getString(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DateTime].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Throws [StateError] if the value is not a Date.
  /// Returns the value of the field
  DateTime getDate(String field, [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    checkNotNull(field, 'Provided field path must not be null.');
    checkNotNull(serverTimestampBehavior, 'Provided serverTimestampBehavior value must not be null.');
    final Timestamp timestamp = getTimestamp(field, serverTimestampBehavior);
    return timestamp?.toDate();
  }

  /// Returns the value of the field as a [Timestamp].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps that have not yet been set to their final
  /// value.
  ///
  /// Throws [StateError] if the value is not a timestamp field.
  /// Returns the value of the field
  Timestamp getTimestamp(String field, [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    checkNotNull(field, 'Provided field path must not be null.');
    checkNotNull(serverTimestampBehavior, 'Provided serverTimestampBehavior value must not be null.');
    final Object maybeTimestamp =
        _getInternal(FieldPath.fromDotSeparatedPath(field).internalPath, serverTimestampBehavior);
    return _castTypedValue(maybeTimestamp, field);
  }

  /// Returns the value of the field as a [Blob].
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a Blob.
  /// Returns the value of the field
  Blob getBlob(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [GeoPoint].
  ///
  /// [field] The path to the field.
  ///
  /// Throws [StateError] if the value is not a [GeoPoint].
  /// Returns the value of the field
  GeoPoint getGeoPoint(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DocumentReference].
  ///
  /// [field] the path to the field.
  ///
  /// Throws [StateError] if the value is not a [DocumentReference].
  /// Returns the value of the field
  DocumentReference getDocumentReference(String field) => _getTypedValue(field);

  /// Gets the reference to the document.
  ///
  /// Returns the reference to the document.
  DocumentReference get reference => DocumentReference(_key, _firestore);

  T _getTypedValue<T>(String field) {
    checkNotNull(field, 'Provided field must not be null.');
    final Object value = get(field, ServerTimestampBehavior.none);
    return _castTypedValue<T>(value, field);
  }

  T _castTypedValue<T>(Object value, String field) {
    if (value == null) {
      return null;
    }

    try {
      final T result = value;
      return result;
    } on TypeError catch (_) {
      throw StateError('Field \'$field\' is not a $T, but it is ${value.runtimeType}');
    }
  }

  Object _getInternal(model.FieldPath fieldPath, ServerTimestampBehavior serverTimestampBehavior) {
    if (document != null) {
      final Value val = document.getField(fieldPath);
      if (val != null) {
        final UserDataWriter userDataWriter = UserDataWriter(_firestore, serverTimestampBehavior);
        return userDataWriter.convertValue(val);
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
          (document == null ? other.document == null : document == other.document) &&
          metadata == other.metadata;

  @override
  int get hashCode {
    return _firestore.hashCode * 31 +
        _key.hashCode * 31 +
        (document == null ? 0 : document.hashCode) * 31 +
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
