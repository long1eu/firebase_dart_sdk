import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
// The default FieldValue factory of the platform interface. The values it makes
// are decoded too, for a FieldValue created before this implementation was
// registered.
// ignore: implementation_imports
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_field_value.dart';

import 'document_reference.dart';
import 'firestore.dart';

/// Converts values between the platform interface types (what `cloud_firestore`
/// hands to a platform implementation) and the `cloud_firestore_dart` types.
abstract final class ValueCodec {
  /// A value from `cloud_firestore` to the value `cloud_firestore_dart` writes.
  ///
  /// Throws an [ArgumentError] for a type Firestore cannot store.
  static Object? encode(Object? value) {
    return switch (value) {
      null || bool() || num() || String() => value,
      Timestamp() => fs.Timestamp(value.seconds, value.nanoseconds),
      DateTime() => fs.Timestamp.fromDate(value),
      GeoPoint() => fs.GeoPoint(value.latitude, value.longitude),
      Blob() => fs.Blob(value.bytes),
      Uint8List() => fs.Blob(value),
      VectorValue() => fs.VectorValue(value.toArray()),
      DocumentReferencePlatform() => _encodeReference(value),
      FieldValuePlatform() => _encodeFieldValue(
        FieldValuePlatform.getDelegate(value),
      ),
      MethodChannelFieldValue() => _encodeFieldValue(value),
      FieldPath() => fs.FieldPath(value.components),
      FieldPathType.documentId => fs.FieldPath.documentId,
      Map<dynamic, dynamic>() => encodeMap(value),
      Iterable<dynamic>() => value.map(encode).toList(),
      // Our own value types pass through: an app may use them on purpose (the
      // BSON types have no FlutterFire equivalent).
      fs.FieldValue() ||
      fs.Timestamp() ||
      fs.GeoPoint() ||
      fs.Blob() ||
      fs.VectorValue() ||
      fs.DocumentReference<Object?>() ||
      fs.Int32Value() ||
      fs.BsonObjectId() ||
      fs.BsonTimestamp() ||
      fs.Decimal128Value() ||
      fs.RegexValue() ||
      fs.MinKey() ||
      fs.MaxKey() => value,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Unsupported type ${value.runtimeType} for a Firestore value',
      ),
    };
  }

  /// [encode] for the values of a map with `String` keys.
  static Map<String, Object?> encodeMap(Map<dynamic, dynamic> data) {
    return <String, Object?>{
      for (final MapEntry<dynamic, dynamic> entry in data.entries)
        _key(entry.key): encode(entry.value),
    };
  }

  /// [encode] for an update map keyed by [FieldPath]: the same map keyed by
  /// `cloud_firestore_dart` field paths.
  static Map<Object, Object?> encodeUpdate(Map<FieldPath, dynamic> data) {
    return <Object, Object?>{
      for (final MapEntry<FieldPath, dynamic> entry in data.entries)
        fs.FieldPath(entry.key.components): encode(entry.value),
    };
  }

  /// [encode] for a field of a filter or an order: a [FieldPath], a
  /// [FieldPathType] or a dotted `String`.
  static fs.FieldPath encodeField(Object? field) {
    return switch (field) {
      FieldPath() => fs.FieldPath(field.components),
      FieldPathType.documentId => fs.FieldPath.documentId,
      String() => fs.FieldPath.fromString(field),
      fs.FieldPath() => field,
      _ => throw ArgumentError.value(
        field,
        'field',
        'Expected a FieldPath, FieldPath.documentId or a String',
      ),
    };
  }

  /// A value read by `cloud_firestore_dart` to the value `cloud_firestore`
  /// expects. Document references belong to [firestore] unless they point to
  /// another instance this package created.
  static Object? decode(Object? value, DartFirebaseFirestore firestore) {
    return switch (value) {
      null || bool() || num() || String() => value,
      fs.Timestamp() => Timestamp(value.seconds, value.nanoseconds),
      fs.GeoPoint() => GeoPoint(value.latitude, value.longitude),
      fs.Blob() => Blob(value.bytes),
      fs.VectorValue() => VectorValue(value.toArray()),
      fs.DocumentReference<Object?>() => DartDocumentReference(
        DartFirebaseFirestore.forDelegate(value.firestore) ?? firestore,
        value.path,
      ),
      Map<dynamic, dynamic>() => decodeMap(value, firestore),
      List<dynamic>() => <Object?>[
        for (final Object? item in value) decode(item, firestore),
      ],
      // The BSON types and anything else without a FlutterFire equivalent.
      _ => value,
    };
  }

  /// [decode] for the values of a map.
  static Map<String, Object?> decodeMap(
    Map<dynamic, dynamic> data,
    DartFirebaseFirestore firestore,
  ) {
    return <String, Object?>{
      for (final MapEntry<dynamic, dynamic> entry in data.entries)
        entry.key as String: decode(entry.value, firestore),
    };
  }

  static String _key(Object? key) {
    if (key is String) {
      return key;
    }
    throw ArgumentError.value(key, 'key', 'Map keys must be Strings');
  }

  static fs.DocumentReference<Map<String, Object?>> _encodeReference(
    DocumentReferencePlatform reference,
  ) {
    final FirebaseFirestorePlatform owner = reference.firestore;
    if (owner is! DartFirebaseFirestore) {
      throw ArgumentError.value(
        reference,
        'value',
        'A DocumentReference of another Firestore implementation '
            '(${owner.runtimeType}) cannot be written with cloud_firestore_dart',
      );
    }
    return owner.delegate.doc(reference.path);
  }

  static Object _encodeFieldValue(Object? delegate) {
    if (delegate is fs.FieldValue) {
      return delegate;
    }
    if (delegate is MethodChannelFieldValue) {
      final Object? operand = delegate.value;
      return switch (delegate.type) {
        FieldValueType.arrayUnion => fs.FieldValue.arrayUnion(
          (operand! as List<dynamic>).map(encode).toList(),
        ),
        FieldValueType.arrayRemove => fs.FieldValue.arrayRemove(
          (operand! as List<dynamic>).map(encode).toList(),
        ),
        FieldValueType.delete => fs.FieldValue.delete(),
        FieldValueType.serverTimestamp => fs.FieldValue.serverTimestamp(),
        FieldValueType.incrementDouble || FieldValueType.incrementInteger =>
          fs.FieldValue.increment(operand! as num),
        FieldValueType.minimumDouble ||
        FieldValueType.minimumInteger => fs.FieldValue.minimum(operand! as num),
        FieldValueType.maximumDouble ||
        FieldValueType.maximumInteger => fs.FieldValue.maximum(operand! as num),
      };
    }
    throw ArgumentError.value(
      delegate,
      'value',
      'Unsupported FieldValue delegate ${delegate.runtimeType}',
    );
  }
}
