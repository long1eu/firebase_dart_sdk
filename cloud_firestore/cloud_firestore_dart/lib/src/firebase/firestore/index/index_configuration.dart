import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';

/// Parses an index configuration in the JSON format of the Firebase CLI
/// (https://firebase.google.com/docs/reference/firestore/indexes/#json_format)
/// into the field indexes it defines. Port of the parsing done by
/// `FirebaseFirestore.setIndexConfiguration(String)` of the Android SDK and
/// `parseIndexes` of the JS SDK.
///
/// Unlike the backend, the SDK does not distinguish between collection ID and
/// collection group indices and hence the `queryScope` field is ignored, as
/// are `fieldOverrides`. A field with `"arrayConfig": "CONTAINS"` is a
/// contains segment, one with `"order": "ASCENDING"` is ascending, any other
/// field is descending.
///
/// Throws an [ArgumentError] when [json] is not valid JSON or does not have
/// the expected shape (an index without `collectionGroup`, a field without
/// `fieldPath`).
List<FieldIndex> parseIndexConfiguration(String json) {
  try {
    return parseIndexConfigurationMap(jsonDecode(json));
  } on FormatException catch (e) {
    throw ArgumentError('Failed to parse index configuration: $e');
  }
}

/// [parseIndexConfiguration] for an already decoded JSON object.
List<FieldIndex> parseIndexConfigurationMap(Object? configuration) {
  final Map<String, Object?> root = _object(configuration, 'configuration');

  final List<FieldIndex> parsedIndexes = <FieldIndex>[];
  final Object? indexes = root['indexes'];
  if (indexes == null) {
    return parsedIndexes;
  }

  for (final Object? indexObject in _array(indexes, 'indexes')) {
    final Map<String, Object?> definition = _object(indexObject, 'index');
    final String collectionGroup =
        _string(definition['collectionGroup'], 'collectionGroup');

    final List<IndexSegment> segments = <IndexSegment>[];
    final Object? fields = definition['fields'];
    if (fields != null) {
      for (final Object? fieldObject in _array(fields, 'fields')) {
        final Map<String, Object?> field = _object(fieldObject, 'field');
        final FieldPath fieldPath = FieldPath.fromServerFormat(
            _string(field['fieldPath'], 'fieldPath'));
        if (field['arrayConfig'] == 'CONTAINS') {
          segments.add(IndexSegment(fieldPath, SegmentKind.contains));
        } else if (field['order'] == 'ASCENDING') {
          segments.add(IndexSegment(fieldPath, SegmentKind.ascending));
        } else {
          segments.add(IndexSegment(fieldPath, SegmentKind.descending));
        }
      }
    }

    parsedIndexes.add(FieldIndex(FieldIndex.unknownId, collectionGroup,
        segments, FieldIndex.initialState));
  }
  return parsedIndexes;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw ArgumentError(
      'Failed to parse index configuration: "$name" is not an object');
}

List<Object?> _array(Object? value, String name) {
  if (value is List<Object?>) {
    return value;
  }
  throw ArgumentError(
      'Failed to parse index configuration: "$name" is not an array');
}

String _string(Object? value, String name) {
  if (value is String) {
    return value;
  }
  throw ArgumentError(
      'Failed to parse index configuration: "$name" is missing or not a string');
}
