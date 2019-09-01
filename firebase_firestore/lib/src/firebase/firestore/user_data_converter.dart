// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/user_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart'
    as firestore;
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/blob_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/bool_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/geo_point_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/integer_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/reference_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/string_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// Helper for parsing raw user input (provided via the API) into internal model
/// classes.
class UserDataConverter {
  UserDataConverter(this.databaseId);

  final DatabaseId databaseId;

  /// Parse document data from a non-merge set() call.
  UserDataParsedSetData parseSetData(Map<String, Object> input) {
    final UserDataParseAccumulator accumulator =
        UserDataParseAccumulator(UserDataSource.set);
    final FieldValue updateData = _parseData(input, accumulator.rootContext);
    return accumulator.toSetData(updateData);
  }

  /// Parse document data from a set() call with SetOptions.merge() set.
  UserDataParsedSetData parseMergeData(
      Map<String, Object> input, FieldMask fieldMask) {
    final UserDataParseAccumulator accumulator =
        UserDataParseAccumulator(UserDataSource.mergeSet);
    final ObjectValue updateData = _parseData(input, accumulator.rootContext);

    if (fieldMask != null) {
      // Verify that all elements specified in the field mask are part of the
      // parsed context.
      for (FieldPath field in fieldMask.mask) {
        if (!accumulator.contains(field)) {
          throw ArgumentError(
              'Field \'$field\' is specified in your field mask but not in your'
              ' input data.');
        }
      }

      return accumulator.toMergeData(updateData, fieldMask);
    } else {
      return accumulator.toMergeData(updateData);
    }
  }

  /// Parse update data from an update() call.
  UserDataParsedUpdateData parseUpdateData(Map<String, Object> data) {
    Assert.checkNotNull(data, 'Provided update data must not be null.');
    final UserDataParseAccumulator accumulator =
        UserDataParseAccumulator(UserDataSource.update);
    final UserDataParseContext context = accumulator.rootContext;

    ObjectValue updateData = ObjectValue.empty;
    for (MapEntry<String, Object> entry in data.entries) {
      final FieldPath fieldPath =
          firestore.FieldPath.fromDotSeparatedPath(entry.key).internalPath;
      final Object fieldValue = entry.value;

      if (fieldValue is firestore.FieldValue && fieldValue.isDelete) {
        // Add it to the field mask, but don't add anything to updateData.
        context.addToFieldMask(fieldPath);
      } else {
        final FieldValue parsedValue =
            _parseData(fieldValue, context.childContextForField(fieldPath));
        if (parsedValue != null) {
          context.addToFieldMask(fieldPath);
          updateData = updateData.set(fieldPath, parsedValue);
        }
      }
    }

    return accumulator.toUpdateData(updateData);
  }

  /// Parses the update data from the update(field, value, field, value...)
  /// varargs call, accepting both strings and FieldPaths.
  UserDataParsedUpdateData parseUpdateDataFromList(
      List<Object> fieldsAndValues) {
    // fieldsAndValues.length and alternating types should already be validated
    // by collectUpdateArguments().
    final int length = fieldsAndValues.length;
    Assert.hardAssert(length.remainder(2) == 0,
        'Expected fieldAndValues to contain an even number of elements');

    final UserDataParseAccumulator accumulator =
        UserDataParseAccumulator(UserDataSource.update);
    final UserDataParseContext context = accumulator.rootContext;
    ObjectValue updateData = ObjectValue.empty;

    for (int i = 0; i < length; i += 2) {
      final Object fieldPath = fieldsAndValues[i];
      final Object fieldValue = fieldsAndValues[i + 1];

      Assert.hardAssert(
          fieldPath is String || fieldPath is firestore.FieldPath,
          'Expected argument to be String or FieldPath, but it was '
          '${fieldPath.runtimeType}.');

      FieldPath parsedField;

      if (fieldPath is String) {
        parsedField =
            firestore.FieldPath.fromDotSeparatedPath(fieldPath).internalPath;
      } else {
        parsedField = (fieldPath as firestore.FieldPath).internalPath;
      }

      if (fieldValue is firestore.FieldValue && fieldValue.isDelete) {
        // Add it to the field mask, but don't add anything to updateData.
        context.addToFieldMask(parsedField);
      } else {
        final FieldValue parsedValue =
            _parseData(fieldValue, context.childContextForField(parsedField));
        if (parsedValue != null) {
          context.addToFieldMask(parsedField);
          updateData = updateData.set(parsedField, parsedValue);
        }
      }
    }

    return accumulator.toUpdateData(updateData);
  }

  /// Parse a 'query value' (e.g. value in a where filter or a value in a cursor
  /// bound).
  FieldValue parseQueryValue(Object input) {
    final UserDataParseAccumulator accumulator =
        UserDataParseAccumulator(UserDataSource.argument);
    final FieldValue parsed = _parseData(input, accumulator.rootContext);

    Assert.hardAssert(parsed != null, 'Parsed data should not be null.');
    Assert.hardAssert(accumulator.fieldTransforms.isEmpty,
        'Field transforms should have been disallowed.');
    return parsed;
  }

  /// Internal helper for parsing user data.
  ///
  /// A [context] object representing the current path being parsed, the source
  /// of the data being parsed, etc. Returns parsed value, or null if the value
  /// was a FieldValue sentinel that should not be included in the resulting
  /// parsed data.
  FieldValue _parseData(Object input, UserDataParseContext context) {
    if (input is Map) {
      return _parseMap<dynamic, dynamic>(input, context);
    } else if (input is firestore.FieldValue) {
      // FieldValues usually parse into transforms (except FieldValue.delete())
      // in which case we do not want to include this field in our parsed data
      // (as doing so will overwrite the field directly prior to the transform
      // trying to transform it). So we don't add this location to
      // [context.fieldMask] and we return null as our parsing result.
      _parseSentinelFieldValue(input, context);
      return null;
    } else {
      // If the context path is null we are inside an array and we don't support
      // field mask paths more granular than the top-level array.
      if (context.path != null) {
        context.addToFieldMask(context.path);
      }

      if (input is List) {
        // TODO: Include the path containing the array in the error message.
        if (context.arrayElement) {
          throw context.createError('Nested arrays are not supported');
        }
        return _parseList<dynamic>(input, context);
      } else {
        return _parseScalarValue(input, context);
      }
    }
  }

  ObjectValue _parseMap<K, V>(Map<K, V> map, UserDataParseContext context) {
    final Map<String, FieldValue> result = <String, FieldValue>{};

    if (map.isEmpty) {
      if (context.path != null && context.path.isNotEmpty) {
        context.addToFieldMask(context.path);
      }

      return ObjectValue.empty;
    } else {
      for (MapEntry<K, V> entry in map.entries) {
        if (entry.key is! String) {
          throw context.createError(
              'Non-String Map key (${entry.value}) is not allowed');
        }
        final String key = entry.key as String;
        final FieldValue parsedValue =
            _parseData(entry.value, context.childContextForSegment(key));
        if (parsedValue != null) {
          result[key] = parsedValue;
        }
      }
    }
    return ObjectValue.fromMap(result);
  }

  ArrayValue _parseList<T>(List<T> list, UserDataParseContext context) {
    final List<FieldValue> result = List<FieldValue>(list.length);
    int entryIndex = 0;
    for (T entry in list) {
      FieldValue parsedEntry =
          _parseData(entry, context.childContextForArrayIndex(entryIndex));
      // Just include nulls in the array for fields being replaced with a
      // sentinel.
      parsedEntry ??= NullValue.nullValue();
      result[entryIndex] = parsedEntry;
      entryIndex++;
    }
    return ArrayValue.fromList(result);
  }

  /// 'Parses' the provided FieldValue, adding any necessary transforms to
  /// [context._fieldTransforms].
  void _parseSentinelFieldValue(
      firestore.FieldValue value, UserDataParseContext context) {
    // Sentinels are only supported with writes, and not within arrays.
    if (!context.isWrite) {
      throw context.createError(
          '${value.methodName}() can only be used with set() and update()');
    }
    if (context.path == null) {
      throw context.createError(
          '${value.methodName}() is not currently supported inside arrays');
    }

    if (value.isDelete) {
      if (context.dataSource == UserDataSource.mergeSet) {
        // No transform to add for a delete, but we need to add it to our
        // fieldMask so it gets deleted.
        context.addToFieldMask(context.path);
      } else if (context.dataSource == UserDataSource.update) {
        Assert.hardAssert(
            context.path.isNotEmpty,
            'FieldValue.delete() at the '
            'top level should have already been handled.');
        throw context.createError('FieldValue.delete() can only appear at the '
            'top level of your update data');
      } else {
        // We shouldn't encounter delete sentinels for queries or non-merge
        // [set()] calls.
        throw context.createError('FieldValue.delete() can only be used with '
            'update() and set() with SetOptions.merge()');
      }
    } else if (value.isServerTimestamp) {
      context.addToFieldTransforms(context.path, ServerTimestampOperation());
    } else if (value.isArrayUnion) {
      final List<FieldValue> parsedElements =
          _parseArrayTransformElements(value.elements);
      final ArrayTransformOperation arrayUnion =
          ArrayTransformOperationUnion(parsedElements);
      context.addToFieldTransforms(context.path, arrayUnion);
    } else if (value.isArrayRemove) {
      final List<FieldValue> parsedElements =
          _parseArrayTransformElements(value.elements);
      final ArrayTransformOperation arrayRemove =
          ArrayTransformOperationRemove(parsedElements);
      context.addToFieldTransforms(context.path, arrayRemove);
    } else {
      throw Assert.fail('Unknown FieldValue type: ${value.runtimeType}');
    }
  }

  /// Helper to parse a scalar value (i.e. not a Map or List)
  ///
  /// Returns the parsed value, or null if the value was a FieldValue sentinel
  /// that should not be included in the resulting parsed data.
  //p
  FieldValue _parseScalarValue(Object input, UserDataParseContext context) {
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
      // Firestore backend truncates precision down to microseconds. To ensure
      // offline mode works the same with regards to truncation, perform the
      // truncation immediately without waiting for the backend to do that.
      final int truncatedNanoseconds = timestamp.nanoseconds ~/ 1000 * 1000;
      return TimestampValue.valueOf(Timestamp(seconds, truncatedNanoseconds));
    } else if (input is GeoPoint) {
      return GeoPointValue.valueOf(input);
    } else if (input is Blob) {
      return BlobValue.valueOf(input);
    } else if (input is DocumentReference) {
      final DocumentReference ref = input;
      // TODO: Rework once pre-converter is ported to Android.
      if (ref.firestore != null) {
        final DatabaseId otherDb = ref.firestore.databaseId;
        if (otherDb != databaseId) {
          throw context.createError(
              'Document reference is for database ${otherDb.projectId}/${otherDb.databaseId} but should be for database ${databaseId.projectId}/${databaseId.databaseId}');
        }
      }
      return ReferenceValue.valueOf(databaseId, ref.key);
    } else {
      throw context.createError('Unsupported type: ${input.runtimeType}');
    }
  }

  List<FieldValue> _parseArrayTransformElements(List<Object> elements) {
    final UserDataParseAccumulator accumulator =
        UserDataParseAccumulator(UserDataSource.argument);
    final List<FieldValue> result = List<FieldValue>(elements.length);
    for (int i = 0; i < elements.length; i++) {
      final Object element = elements[i];
      // Although array transforms are used with writes, the actual elements
      // being unioned or removed are not considered writes since they cannot
      // contain any FieldValue sentinels, etc.
      final UserDataParseContext context = accumulator.rootContext;
      result[i] = _parseData(element, context.childContextForArrayIndex(i));
    }
    return result;
  }
}
