// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/user_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/keyed_document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/max_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/min_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Helper for parsing raw user input (provided via the API) into internal model classes.
class UserDataConverter {
  UserDataConverter(this.databaseId);

  final DatabaseId databaseId;

  /// Parse document data from a non-merge set() call.
  UserDataParsedSetData parseSetData(Map<String, Object?> input) {
    final UserDataParseAccumulator accumulator = UserDataParseAccumulator(
      UserDataSource.set,
    );
    final ObjectValue updateData =
        _parseData(input, accumulator.rootContext)! as ObjectValue;
    return accumulator.toSetData(updateData);
  }

  /// Parse document data from a set() call with SetOptions.merge() set.
  UserDataParsedSetData parseMergeData(
    Map<String, Object?> input,
    FieldMask? fieldMask,
  ) {
    final UserDataParseAccumulator accumulator = UserDataParseAccumulator(
      UserDataSource.mergeSet,
    );
    final ObjectValue updateData =
        _parseData(input, accumulator.rootContext)! as ObjectValue;

    if (fieldMask != null) {
      // Verify that all elements specified in the field mask are part of the parsed context.
      for (FieldPath field in fieldMask.mask) {
        if (!accumulator.contains(field)) {
          throw ArgumentError(
            'Field \'$field\' is specified in your field mask but not in your input data.',
          );
        }
      }

      return accumulator.toMergeData(updateData, fieldMask);
    } else {
      return accumulator.toMergeData(updateData);
    }
  }

  /// Parse update data from an update() call.
  UserDataParsedUpdateData parseUpdateData(Map<String, Object?> data) {
    checkNotNull(data, 'Provided update data must not be null.');
    final UserDataParseAccumulator accumulator = UserDataParseAccumulator(
      UserDataSource.update,
    );
    final UserDataParseContext context = accumulator.rootContext;

    ObjectValue updateData = ObjectValue.empty;
    for (MapEntry<String, Object?> entry in data.entries) {
      final FieldPath fieldPath = firestore.FieldPath.fromDotSeparatedPath(
        entry.key,
      ).internalPath;
      final Object? fieldValue = entry.value;

      if (fieldValue is firestore.FieldValue && fieldValue.isDelete) {
        // Add it to the field mask, but don't add anything to updateData.
        context.addToFieldMask(fieldPath);
      } else {
        final FieldValue? parsedValue = _parseData(
          fieldValue,
          context.childContextForField(fieldPath),
        );
        if (parsedValue != null) {
          context.addToFieldMask(fieldPath);
          updateData = updateData.set(fieldPath, parsedValue);
        }
      }
    }

    return accumulator.toUpdateData(updateData);
  }

  /// Parses the update data from the update(field, value, field, value...) varargs call, accepting both strings and
  /// FieldPaths.
  UserDataParsedUpdateData parseUpdateDataFromList(
    List<Object?> fieldsAndValues,
  ) {
    // fieldsAndValues.length and alternating types should already be validated by collectUpdateArguments().
    final int length = fieldsAndValues.length;
    hardAssert(
      length.remainder(2) == 0,
      'Expected fieldAndValues to contain an even number of elements',
    );

    final UserDataParseAccumulator accumulator = UserDataParseAccumulator(
      UserDataSource.update,
    );
    final UserDataParseContext context = accumulator.rootContext;
    ObjectValue updateData = ObjectValue.empty;

    for (int i = 0; i < length; i += 2) {
      final Object? fieldPath = fieldsAndValues[i];
      final Object? fieldValue = fieldsAndValues[i + 1];

      hardAssertLazy(
        fieldPath is String || fieldPath is firestore.FieldPath,
        () =>
            'Expected argument to be String or FieldPath, but it was ${fieldPath.runtimeType}.',
      );

      final FieldPath parsedField;

      if (fieldPath is String) {
        parsedField = firestore.FieldPath.fromDotSeparatedPath(
          fieldPath,
        ).internalPath;
      } else {
        final firestore.FieldPath path = fieldPath as firestore.FieldPath;
        parsedField = path.internalPath;
      }

      if (fieldValue is firestore.FieldValue && fieldValue.isDelete) {
        // Add it to the field mask, but don't add anything to updateData.
        context.addToFieldMask(parsedField);
      } else {
        final FieldValue? parsedValue = _parseData(
          fieldValue,
          context.childContextForField(parsedField),
        );
        if (parsedValue != null) {
          context.addToFieldMask(parsedField);
          updateData = updateData.set(parsedField, parsedValue);
        }
      }
    }

    return accumulator.toUpdateData(updateData);
  }

  /// Parse a 'query value' (e.g. value in a where filter or a value in a cursor bound).
  ///
  /// [allowArrays] is whether the query value is an array that may directly contain additional arrays (e.g. the operand
  /// of a `whereIn` or `whereNotIn` query).
  FieldValue parseQueryValue(Object? input, {bool allowArrays = false}) {
    final UserDataParseAccumulator accumulator = UserDataParseAccumulator(
      allowArrays ? UserDataSource.arrayArgument : UserDataSource.argument,
    );
    final FieldValue? parsed = _parseData(input, accumulator.rootContext);

    hardAssert(parsed != null, 'Parsed data should not be null.');
    hardAssert(
      accumulator.fieldTransforms.isEmpty,
      'Field transforms should have been disallowed.',
    );
    // Unlike document data, a query value may hold a plain map with a reserved
    // key such as `{'__int__': 5}`. The backend reads it as the BSON value, so
    // the local evaluation of the query has to as well.
    return resolveBsonShapes(parsed!);
  }

  /// Internal helper for parsing user data.
  ///
  /// A [context] object representing the current path being parsed, the source of the data being parsed, etc. Returns
  /// parsed value, or null if the value was a FieldValue sentinel that should not be included in the resulting parsed
  /// data.
  FieldValue? _parseData(Object? input, UserDataParseContext context) {
    if (input is Map) {
      return _parseMap<Object?>(input.cast<String, Object?>(), context);
    } else if (input is firestore.FieldValue) {
      // FieldValues usually parse into transforms (except FieldValue.delete()) in which case we do not want to include
      // this field in our parsed data (as doing so will overwrite the field directly prior to the transform trying to
      // transform it). So we don't add this location to [context.fieldMask] and we return null as our parsing result.
      _parseSentinelFieldValue(input, context);
      return null;
    } else {
      // If the context path is null we are inside an array and we don't support field mask paths more granular than the
      // top-level array.
      final FieldPath? path = context.path;
      if (path != null) {
        context.addToFieldMask(path);
      }

      if (input is List) {
        // TODO(long1eu): Include the path containing the array in the error message.
        // In the case of IN / NOT_IN queries, the parsed data is an array (the set of values to match) that may directly
        // contain additional arrays (each one an individual field value), so this validation is disabled there.
        if (context.arrayElement &&
            context.dataSource != UserDataSource.arrayArgument) {
          throw context.createError('Nested arrays are not supported');
        }
        return _parseList<Object?>(input, context);
      } else {
        return _parseScalarValue(input, context);
      }
    }
  }

  ObjectValue _parseMap<V extends Object?>(
    Map<String, V> map,
    UserDataParseContext context,
  ) {
    final Map<String, FieldValue> result = <String, FieldValue>{};

    if (map.isEmpty) {
      final FieldPath? path = context.path;
      if (path != null && path.isNotEmpty) {
        context.addToFieldMask(path);
      }

      return ObjectValue.empty;
    } else {
      for (MapEntry<String, V> entry in map.entries) {
        final String key = entry.key;
        final FieldValue? parsedValue = _parseData(
          entry.value,
          context.childContextForSegment(key),
        );
        if (parsedValue != null) {
          result[key] = parsedValue;
        }
      }
    }
    return ObjectValue.fromMap(result);
  }

  ArrayValue _parseList<T extends Object?>(
    List<T> list,
    UserDataParseContext context,
  ) {
    final List<FieldValue> result = <FieldValue>[];
    int entryIndex = 0;
    for (T entry in list) {
      final FieldValue? parsedEntry = _parseData(
        entry,
        context.childContextForArrayIndex(entryIndex),
      );
      // Just include nulls in the array for fields being replaced with a sentinel.
      result.add(parsedEntry ?? NullValue.nullValue());
      entryIndex++;
    }
    return ArrayValue.fromList(result);
  }

  /// 'Parses' the provided FieldValue, adding any necessary transforms to [context._fieldTransforms].
  void _parseSentinelFieldValue(
    firestore.FieldValue value,
    UserDataParseContext context,
  ) {
    // Sentinels are only supported with writes, and not within arrays.
    if (!context.isWrite) {
      throw context.createError(
        '${value.methodName}() can only be used with set() and update()',
      );
    }
    final FieldPath? path = context.path;
    if (path == null) {
      throw context.createError(
        '${value.methodName}() is not currently supported inside arrays',
      );
    }

    if (value.isDelete) {
      if (context.dataSource == UserDataSource.mergeSet) {
        // No transform to add for a delete, but we need to add it to our
        // fieldMask so it gets deleted.
        context.addToFieldMask(path);
      } else if (context.dataSource == UserDataSource.update) {
        hardAssert(
          path.isNotEmpty,
          'FieldValue.delete() at the top level should have already been handled.',
        );
        throw context.createError(
          'FieldValue.delete() can only appear at the top level of your update data',
        );
      } else {
        // We shouldn't encounter delete sentinels for queries or non-merge [set()] calls.
        throw context.createError(
          'FieldValue.delete() can only be used with update() and set() with SetOptions.merge()',
        );
      }
    } else if (value.isServerTimestamp) {
      context.addToFieldTransforms(path, ServerTimestampOperation());
    } else if (value.isArrayUnion) {
      final List<FieldValue> parsedElements = _parseArrayTransformElements(
        value.elements,
      );
      final ArrayTransformOperation arrayUnion = ArrayTransformOperationUnion(
        parsedElements,
      );
      context.addToFieldTransforms(path, arrayUnion);
    } else if (value.isArrayRemove) {
      final List<FieldValue> parsedElements = _parseArrayTransformElements(
        value.elements,
      );
      final ArrayTransformOperation arrayRemove = ArrayTransformOperationRemove(
        parsedElements,
      );
      context.addToFieldTransforms(path, arrayRemove);
    } else if (value.isIncrement) {
      final FieldValue operand = parseQueryValue(value.elements[0]);
      final NumericIncrementTransformOperation incrementOperation =
          NumericIncrementTransformOperation(operand as NumberValue);
      context.addToFieldTransforms(path, incrementOperation);
    } else if (value.isMinimum) {
      final FieldValue operand = parseQueryValue(value.elements[0]);
      context.addToFieldTransforms(
        path,
        NumericMinimumTransformOperation(operand as NumberValue),
      );
    } else if (value.isMaximum) {
      final FieldValue operand = parseQueryValue(value.elements[0]);
      context.addToFieldTransforms(
        path,
        NumericMaximumTransformOperation(operand as NumberValue),
      );
    } else {
      throw fail('Unknown FieldValue type: ${value.runtimeType}');
    }
  }

  /// Helper to parse a scalar value (i.e. not a Map or List)
  ///
  /// Returns the parsed value, or null if the value was a FieldValue sentinel that should not be included in the
  /// resulting parsed data.
  FieldValue _parseScalarValue(Object? input, UserDataParseContext context) {
    if (input == null) {
      return NullValue.nullValue();
    } else if (input is int) {
      return IntegerValue.valueOf(input);
    } else if (input is double) {
      return DoubleValue.valueOf(input);
    } else if (input is bool) {
      return BoolValue.valueOf(input);
    } else if (input is String) {
      return StringValue.valueOf(input);
    } else if (input is DateTime) {
      return TimestampValue.valueOf(Timestamp.fromDate(input));
    } else if (input is Timestamp) {
      final Timestamp timestamp = input;
      final int seconds = timestamp.seconds;
      // The const constructor of [Timestamp] only checks its range with asserts, which a release build skips.
      TimestampInternal.validateRange(seconds, timestamp.nanoseconds);
      // Firestore backend truncates precision down to microseconds. To ensure offline mode works the same with regards
      // to truncation, perform the truncation immediately without waiting for the backend to do that.
      final int truncatedNanoseconds = timestamp.nanoseconds ~/ 1000 * 1000;
      return TimestampValue.valueOf(Timestamp(seconds, truncatedNanoseconds));
    } else if (input is GeoPoint) {
      // The const constructor of [GeoPoint] only checks its range with asserts, which a release build skips.
      if (!(input.latitude >= -90 && input.latitude <= 90)) {
        throw context.createError(
          'Latitude must be in the range of [-90, 90] but was ${input.latitude}',
        );
      }
      if (!(input.longitude >= -180 && input.longitude <= 180)) {
        throw context.createError(
          'Longitude must be in the range of [-180, 180] but was ${input.longitude}',
        );
      }
      return GeoPointValue.valueOf(input);
    } else if (input is Blob) {
      return BlobValue.valueOf(input);
    } else if (input is VectorValue) {
      return VectorFieldValue.fromList(input.toArray());
    } else if (input is MinKey) {
      return MinKeyValue.instance();
    } else if (input is MaxKey) {
      return MaxKeyValue.instance();
    } else if (input is Int32Value) {
      return Int32FieldValue.valueOf(input);
    } else if (input is Decimal128Value) {
      return Decimal128FieldValue.valueOf(input);
    } else if (input is BsonObjectId) {
      return BsonObjectIdValue.valueOf(input);
    } else if (input is BsonTimestamp) {
      return BsonTimestampValue.valueOf(input);
    } else if (input is RegexValue) {
      return RegexFieldValue.valueOf(input);
    } else if (input is DocumentReference) {
      final DocumentReference ref = input;
      final DatabaseId otherDb = ref.firestore.modelDatabaseId;
      if (otherDb != databaseId) {
        throw context.createError(
          'Document reference is for database ${otherDb.projectId}/${otherDb.databaseId} but '
          'should be for database ${databaseId.projectId}/${databaseId.databaseId}',
        );
      }
      return ReferenceValue.valueOf(databaseId, ref.key);
    } else if (input is KeyedDocumentReference) {
      final DatabaseId otherDb = input.databaseId;
      if (otherDb != databaseId) {
        throw context.createError(
          'Document reference is for database ${otherDb.projectId}/${otherDb.databaseId} but '
          'should be for database ${databaseId.projectId}/${databaseId.databaseId}',
        );
      }
      return ReferenceValue.valueOf(databaseId, input.key);
    } else {
      throw context.createError('Unsupported type: ${input.runtimeType}');
    }
  }

  List<FieldValue> _parseArrayTransformElements(List<Object?> elements) {
    final UserDataParseAccumulator accumulator = UserDataParseAccumulator(
      UserDataSource.argument,
    );
    final List<FieldValue> result = <FieldValue>[];
    for (int i = 0; i < elements.length; i++) {
      final Object? element = elements[i];
      // Although array transforms are used with writes, the actual elements being unioned or removed are not considered
      // writes since they cannot contain any FieldValue sentinels, etc.
      final UserDataParseContext context = accumulator.rootContext;
      // Sentinels are not allowed inside array transforms, so the parsed value is never null.
      // Like a query value, an element may be a plain map with a reserved key such as `{'__int__': 5}`, which the
      // backend reads as the BSON value.
      result.add(
        resolveBsonShapes(
          _parseData(element, context.childContextForArrayIndex(i))!,
        ),
      );
    }
    return result;
  }
}
