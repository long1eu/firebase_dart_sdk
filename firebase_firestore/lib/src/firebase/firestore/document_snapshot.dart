// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/reference_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:firebase_firestore/src/firebase/firestore/snapshot_metadata.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A [DocumentSnapshot] contains data read from a document in your [Firestore]
/// database. The data can be extracted with the [data] or [get] methods.
///
/// * If the [DocumentSnapshot‘ points to a non-existing document, [data] and
/// its corresponding methods will return null. You can always explicitly check
/// for a document's existence by calling [exists].
///
/// * <b>Subclassing Note</b>: Firestore classes are not meant to be subclassed
/// except for use in test mocks. Subclassing is not supported in production
/// code and new SDK releases may break code that does so.
@publicApi
class DocumentSnapshot {
  final FirebaseFirestore _firestore;

  final DocumentKey _key;

  /// Is null if the document doesn't exist
  @publicApi
  final Document document;

  /// The metadata for this document snapshot.
  @publicApi
  final SnapshotMetadata metadata;

  DocumentSnapshot(this._firestore, this._key, this.document, bool isFromCache)
      : metadata = SnapshotMetadata(
            document != null && document.hasLocalMutations, isFromCache),
        assert(_firestore != null),
        assert(_key != null);

  factory DocumentSnapshot.fromDocument(
      FirebaseFirestore firestore, Document doc, bool fromCache) {
    return DocumentSnapshot(firestore, doc.key, doc, fromCache);
  }

  factory DocumentSnapshot.fromNoDocument(
      FirebaseFirestore firestore, DocumentKey key, bool fromCache) {
    return DocumentSnapshot(firestore, key, null, fromCache);
  }

  /// @return The id of the document.
  @publicApi
  String get id => _key.path.last;

  /// Returns true if the document existed in this snapshot.
  @publicApi
  bool get exists => document != null;

  /// Returns the fields of the document as a Map or null if the document
  /// doesn't exist. Field values will be converted to their native Dart
  /// representation.
  ///
  /// Returns the fields of the document as a Map or null if the document
  /// doesn't exist.
  Map<String, Object> get data => getData(ServerTimestampBehavior.none);

  /// Returns the fields of the document as a Map or null if the document
  /// doesn't exist. Field values will be converted to their native Dart
  /// representation.
  ///
  /// [serverTimestampBehavior] Configures the behavior for server timestamps
  /// that have not yet been set to their final value.
  /// Returns the fields of the document as a Map or null if the document
  /// doesn't exist.
  @publicApi
  Map<String, Object> getData(ServerTimestampBehavior serverTimestampBehavior) {
    Assert.checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    return document == null
        ? null
        : _convertObject(
            document.data, FieldValueOptions(serverTimestampBehavior));
  }

  /// Returns whether or not the field exists in the document. Returns false if
  /// the document does not exist.
  ///
  /// [field] the path to the field.
  /// Returns true if the field exists.
  @publicApi
  bool contains(String field) {
    return containsPath(FieldPath.fromDotSeparatedPath(field));
  }

  /// Returns whether or not the field exists in the document. Returns false if
  /// the document does not exist.
  ///
  /// [fieldPath] the path to the field.
  /// Returns true if the field exists.
  @publicApi
  bool containsPath(FieldPath fieldPath) {
    Assert.checkNotNull(fieldPath, 'Provided field path must not be null.');
    return (document != null) &&
        (document.getField(fieldPath.internalPath) != null);
  }

  /// Returns the value at the field or null if the field doesn't exist.
  ///
  /// [field] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps
  /// that have not yet been set to their final value.
  /// Returns the value at the given field or null.
  @publicApi
  Object get(String field, [ServerTimestampBehavior serverTimestampBehavior]) {
    return getPath(FieldPath.fromDotSeparatedPath(field),
        serverTimestampBehavior ?? ServerTimestampBehavior.none);
  }

  /// Returns the value at the field or null if the field or document doesn't
  /// exist.
  ///
  /// [fieldPath] the path to the field
  /// [serverTimestampBehavior] configures the behavior for server timestamps
  /// that have not yet been set to their final value.
  /// Returns the value at the given field or null.
  @publicApi
  Object getPath(FieldPath fieldPath,
      [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    Assert.checkNotNull(fieldPath, 'Provided field path must not be null.');
    Assert.checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    return _getInternal(
        fieldPath.internalPath, FieldValueOptions(serverTimestampBehavior));
  }

  /// Returns the value of the field as a bool. If the value is not a bool this
  /// will throw a state error.
  ///
  /// [field] the path to the field.
  /// Returns the value of the field
  @publicApi
  bool getBool(String field) => _getTypedValue(field);

  /// Returns the value of the field as a double.
  ///
  /// [field] the path to the field.
  /// Throws [StateError] if the value is not a number.
  /// Returns the value of the field
  @publicApi
  double getDouble(String field) {
    final num val = _getTypedValue(field);
    return val != null ? val.toDouble() : null;
  }

  /// Returns the value of the field as a String.
  ///
  /// [field] the path to the field.
  /// Throws [StateError] if the value is not a String.
  /// Returns the value of the field
  @publicApi
  String getString(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DateTime].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps
  /// that have not yet been set to their final value.
  /// Throws [StateError] if the value is not a Date.
  /// Returns the value of the field

  @publicApi
  DateTime getDate(String field,
      [ServerTimestampBehavior serverTimestampBehavior]) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    Assert.checkNotNull(field, 'Provided field path must not be null.');
    Assert.checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    final Object maybeDate = _getInternal(
        FieldPath.fromDotSeparatedPath(field).internalPath,
        FieldValueOptions(serverTimestampBehavior, false));
    return _castTypedValue(maybeDate, field);
  }

  /// Returns the value of the field as a [Timestamp].
  ///
  /// [field] the path to the field.
  /// [serverTimestampBehavior] configures the behavior for server timestamps
  /// that have not yet been set to their final value.
  /// Throws [StateError] if the value is not a timestamp field.
  /// Returns the value of the field
  @publicApi
  Timestamp getTimestamp(
      String field, ServerTimestampBehavior serverTimestampBehavior) {
    serverTimestampBehavior ??= ServerTimestampBehavior.none;
    Assert.checkNotNull(field, 'Provided field path must not be null.');
    Assert.checkNotNull(serverTimestampBehavior,
        'Provided serverTimestampBehavior value must not be null.');
    final Object maybeTimestamp = _getInternal(
        FieldPath.fromDotSeparatedPath(field).internalPath,
        FieldValueOptions(serverTimestampBehavior));
    return _castTypedValue(maybeTimestamp, field);
  }

  /// Returns the value of the field as a [Blob].
  ///
  /// [field] the path to the field.
  /// Throws [StateError] if the value is not a Blob.
  /// Returns the value of the field
  @publicApi
  Blob getBlob(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [GeoPoint].
  ///
  /// [field] The path to the field.
  /// Throws [StateError] if the value is not a [GeoPoint].
  /// Returns the value of the field

  @publicApi
  GeoPoint getGeoPoint(String field) => _getTypedValue(field);

  /// Returns the value of the field as a [DocumentReference].
  ///
  /// [field] the path to the field.
  /// Throws [StateError] if the value is not a [DocumentReference].
  /// Returns the value of the field

  @publicApi
  DocumentReference getDocumentReference(String field) => _getTypedValue(field);

  /// Gets the reference to the document.
  ///
  /// Returns the reference to the document.
  @publicApi
  DocumentReference get reference => DocumentReference(_key, _firestore);

  T _getTypedValue<T>(String field) {
    Assert.checkNotNull(field, 'Provided field must not be null.');
    final Object value = get(field, ServerTimestampBehavior.none);
    return _castTypedValue<T>(value, field);
  }

  T _castTypedValue<T>(Object value, String field) {
    if (value == null) {
      return null;
    } else if (value is T) {
      throw StateError('Field "$field" is not a $T');
    }
    return value as T;
  }

  Object _convertValue(FieldValue value, FieldValueOptions options) {
    if (value is ObjectValue) {
      return _convertObject(value, options);
    } else if (value is ArrayValue) {
      return _convertArray(value, options);
    } else if (value is ReferenceValue) {
      final ReferenceValue referenceValue = value;
      final DocumentKey key = referenceValue.valueWith(options);
      final DatabaseId refDatabase = value.databaseId;
      final DatabaseId database = _firestore.databaseId;
      if (refDatabase != database) {
        // TODO: Somehow support foreign references.
        Log.w(
            'DocumentSnapshot',
            'Document ${key.path} contains a document reference within a different database '
            '(${refDatabase.projectId}/${refDatabase.databaseId}) which is not supported. It will be treated as a reference in '
            'the current database (${database.projectId}/${database.databaseId}) instead.');
      }
      return DocumentReference(key, _firestore);
    } else {
      return value.valueWith(options);
    }
  }

  Map<String, Object> _convertObject(
      ObjectValue objectValue, FieldValueOptions options) {
    final Map<String, Object> result = <String, Object>{};
    for (MapEntry<String, FieldValue> entry in objectValue.internalValue) {
      result[entry.key] = _convertValue(entry.value, options);
    }
    return result;
  }

  List<Object> _convertArray(ArrayValue arrayValue, FieldValueOptions options) {
    final List<Object> result = List<Object>(arrayValue.internalValue.length);
    for (FieldValue v in arrayValue.internalValue) {
      result.add(_convertValue(v, options));
    }
    return result;
  }

  Object _getInternal(model.FieldPath fieldPath, FieldValueOptions options) {
    if (document != null) {
      final FieldValue val = document.getField(fieldPath);
      if (val != null) {
        return _convertValue(val, options);
      }
    }
    return null;
  }
}
