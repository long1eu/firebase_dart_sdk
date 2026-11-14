import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// Converts the fields of a document to JSON. Timestamps, bytes, geo points,
/// vectors and references become the tagged maps of their `toJson()` (the
/// format of the JS SDK's `toJSON()`, for example
/// `{"type": "firestore/timestamp/1.0", "seconds": ..., "nanoseconds": ...}`),
/// which [fromJsonValue] reads back.
Object? toJsonValue(Object? value) => switch (value) {
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry<String, Object?> entry in map.entries)
      entry.key: toJsonValue(entry.value),
  },
  final List<Object?> list => <Object?>[
    for (final Object? e in list) toJsonValue(e),
  ],
  final Timestamp timestamp => timestamp.toJson(),
  final Blob blob => blob.toJson(),
  final GeoPoint point => point.toJson(),
  final VectorValue vector => vector.toJson(),
  final DocumentReference<dynamic> reference => reference.toJson(),
  final double number when number.isNaN || number.isInfinite =>
    throw UnsupportedError('$number can not be written as JSON'),
  _ => value,
};

/// The Firestore value of a JSON [value]: the tagged maps written by
/// [toJsonValue] become their types again, everything else stays as it is.
Object? fromJsonValue(Firestore firestore, Object? value) {
  switch (value) {
    case final List<Object?> list:
      return <Object?>[
        for (final Object? e in list) fromJsonValue(firestore, e),
      ];
    case final Map<String, Object?> map:
      switch (map['type']) {
        case Timestamp.jsonType:
          return Timestamp.fromJson(map);
        case Blob.jsonType:
          return Blob.fromJson(map);
        case GeoPoint.jsonType:
          return GeoPoint.fromJson(map);
        case VectorValue.jsonType:
          return VectorValue.fromJson(map);
        case DocumentReference.jsonType:
          return DocumentReference<Map<String, Object?>>.fromJson(
            firestore,
            map,
          );
      }
      return <String, Object?>{
        for (final MapEntry<String, Object?> entry in map.entries)
          entry.key: fromJsonValue(firestore, entry.value),
      };
    default:
      return value;
  }
}
