// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart'
    as firestore;
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_mutation.dart';
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

/**
 * Helper for parsing raw user input (provided via the API) into internal model classes.
 *
 * @hide
 */
class UserDataConverter {
  final DatabaseId databaseId;

  UserDataConverter(this.databaseId);

  /** Parse document data from a non-merge set() call. */
  ParsedDocumentData parseSetData(Map<String, Object> input) {
    _ParseContext context =
        new _ParseContext(UserDataSource.set, FieldPath.emptyPath);
    FieldValue parsed = _parseData(input, context);
    Assert.hardAssert(
        parsed is ObjectValue, "Parse result should be an object.");

    return new ParsedDocumentData(
      parsed as ObjectValue,
      /* fieldMask= */ null,
      context.fieldTransforms,
    );
  }

  /** Parse document data from a set() call with SetOptions.merge() set. */
  ParsedDocumentData parseMergeData(
      Map<String, Object> input, FieldMask fieldMask) {
    _ParseContext context =
        new _ParseContext(UserDataSource.mergeSet, FieldPath.emptyPath);
    FieldValue parsed = _parseData(input, context);
    Assert.hardAssert(
        parsed is ObjectValue, "Parse result should be an object.");

    List<FieldTransform> fieldTransforms;

    if (fieldMask == null) {
      fieldMask = FieldMask(context.fieldMask.toList());
      fieldTransforms = context.fieldTransforms;
    } else {
      // Verify that all elements specified in the field mask are part of the parsed context.
      for (FieldPath field in fieldMask.mask) {
        if (!context.contains(field)) {
          throw new ArgumentError(
              "Field '$field' is specified in your field mask but not in your input data.");
        }
      }

      fieldTransforms = [];

      for (FieldTransform parsedTransform in context.fieldTransforms) {
        if (fieldMask.covers(parsedTransform.fieldPath)) {
          fieldTransforms.add(parsedTransform);
        }
      }
    }

    return new ParsedDocumentData(
        parsed as ObjectValue, fieldMask, fieldTransforms);
  }

  /// Parse update data from an update() call.
  ParsedUpdateData parseUpdateData(Map<String, Object> data) {
    Assert.checkNotNull(data, "Provided update data must not be null.");
    List<FieldPath> fieldMaskPaths = [];
    ObjectValue updateData = ObjectValue.empty;

    _ParseContext context =
        new _ParseContext(UserDataSource.update, FieldPath.emptyPath);
    for (MapEntry<String, Object> entry in data.entries) {
      FieldPath fieldPath =
          firestore.FieldPath.fromDotSeparatedPath(entry.key).internalPath;
      Object fieldValue = entry.value;

      if (fieldValue is firestore.DeleteFieldValue) {
        // Add it to the field mask, but don't add anything to updateData.
        fieldMaskPaths.add(fieldPath);
      } else {
        FieldValue parsedValue =
            _parseData(fieldValue, context.childContextForField(fieldPath));
        if (parsedValue != null) {
          fieldMaskPaths.add(fieldPath);
          updateData = updateData.set(fieldPath, parsedValue);
        }
      }
    }

    FieldMask mask = FieldMask(fieldMaskPaths);
    return new ParsedUpdateData(
      updateData,
      mask,
      context.fieldTransforms,
    );
  }

  /**
   * Parses the update data from the update(field, value, field, value...) varargs call, accepting
   * both strings and FieldPaths.
   */
  ParsedUpdateData parseUpdateDataFromList(List<Object> fieldsAndValues) {
    _ParseContext context =
        new _ParseContext(UserDataSource.update, FieldPath.emptyPath);
    List<FieldPath> fieldMaskPaths = [];
    ObjectValue updateData = ObjectValue.empty;

    // fieldsAndValues.length and alternating types should already be validated by
    // Util.collectUpdateArguments().
    Assert.hardAssert(fieldsAndValues.length % 2 == 0,
        "Expected fieldAndValues to contain an even number of elements");

    Iterator<Object> iterator = fieldsAndValues.iterator;

    while (iterator.moveNext()) {
      Object fieldPath = iterator.current;
      Object fieldValue = iterator.current;

      Assert.hardAssert(fieldPath is String || fieldPath is firestore.FieldPath,
          "Expected argument to be String or FieldPath.");

      FieldPath parsedField;

      if (fieldPath is String) {
        parsedField =
            firestore.FieldPath.fromDotSeparatedPath(fieldPath).internalPath;
      } else {
        parsedField = (fieldPath as firestore.FieldPath).internalPath;
      }

      if (fieldValue is firestore.DeleteFieldValue) {
        // Add it to the field mask, but don't add anything to updateData.
        fieldMaskPaths.add(parsedField);
      } else {
        FieldValue parsedValue =
            _parseData(fieldValue, context.childContextForField(parsedField));
        if (parsedValue != null) {
          fieldMaskPaths.add(parsedField);
          updateData = updateData.set(parsedField, parsedValue);
        }
      }
    }

    FieldMask mask = FieldMask(fieldMaskPaths);
    return new ParsedUpdateData(updateData, mask, context.fieldTransforms);
  }

  /// Parse a "query value" (e.g. value in a where filter or a value in a cursor
  /// bound).
  FieldValue parseQueryValue(Object input) {
    _ParseContext context =
        new _ParseContext(UserDataSource.argument, FieldPath.emptyPath);
    FieldValue parsed = _parseData(input, context);
    Assert.hardAssert(parsed != null, 'Parsed data should not be null.');
    Assert.hardAssert(context.fieldTransforms.isEmpty,
        'Field transforms should have been disallowed.');
    return parsed;
  }

  /// Converts a POJO into a Map, throwing appropriate errors if it wasn't
  /// actually a proper POJO.
  /// TODO find a way to implement this without using reflection
  Map<String, Object> convertPOJO(Object pojo) {
    Assert.checkNotNull(pojo, 'Provided data must not be null.');
    String reason =
        'Invalid data. Data must be a Map<String, Object> or a suitable POJO object, but it was';

    // Check Array before calling CustomClassMapper since it'll give you a confusing message
    // to use List instead, which also won't work.
    if (pojo is List) {
      throw new ArgumentError(reason + "$reason a List");
    }

    Object converted = CustomClassMapper.convertToPlainJavaTypes(pojo);
    if (converted is! Map) {
      throw new ArgumentError('$reason of type: ${pojo.runtimeType}');
    }

    Map<String, Object> map = converted;
    return map;
  }

  /// Internal helper for parsing user data.
  ///
  /// A [context] object representing the current path being parsed, the source
  /// of the data being parsed, etc. Returns parsed value, or null if the value
  /// was a FieldValue sentinel that should not be included in the resulting
  /// parsed data.
  FieldValue _parseData(Object input, _ParseContext context) {
    if (input is Map) {
      return _parseMap(input, context);
    } else if (input is firestore.FieldValue) {
      // FieldValues usually parse into transforms (except FieldValue.delete())
      // in which case we do not want to include this field in our parsed data
      // (as doing so will overwrite the field directly prior to the transform
      // trying to transform it). So we don't add this location to
      // [context.fieldMask] and we return null as our parsing result.
      this._parseSentinelFieldValue(input, context);
      return null;
    } else {
      // If [context.path] is null we are inside an array and we don't support
      // field mask paths more granular than the top-level array.
      if (context.path != null) {
        context.fieldMask.add(context.path);
      }

      if (input is List) {
        // TODO: Include the path containing the array in the error message.
        if (context.arrayElement) {
          throw context.createError('Nested arrays are not supported');
        }
        return _parseList(input, context);
      } else {
        return _parseScalarValue(input, context);
      }
    }
  }

  ObjectValue _parseMap<K, V>(Map<K, V> map, _ParseContext context) {
    Map<String, FieldValue> result = <String, FieldValue>{};
    for (MapEntry<K, V> entry in map.entries) {
      if (entry.key is! String) {
        throw context
            .createError('Non-String Map key (${entry.value}) is not allowed');
      }
      String key = entry.key as String;
      FieldValue parsedValue =
          _parseData(entry.key, context.childContextForName(key));
      if (parsedValue != null) {
        result[key] = parsedValue;
      }
    }
    return ObjectValue.fromMap(result);
  }

  ArrayValue _parseList<T>(List<T> list, _ParseContext context) {
    List<FieldValue> result = new List(list.length);
    int entryIndex = 0;
    for (T entry in list) {
      FieldValue parsedEntry =
          _parseData(entry, context.childContextForArray(entryIndex));
      if (parsedEntry == null) {
        // Just include nulls in the array for fields being replaced with a
        // sentinel.
        parsedEntry = NullValue.nullValue();
      }
      result.add(parsedEntry);
      entryIndex++;
    }
    return ArrayValue.fromList(result);
  }

  /// "Parses" the provided FieldValue, adding any necessary transforms to
  /// [context.fieldTransforms].
  void _parseSentinelFieldValue(
      firestore.FieldValue value, _ParseContext context) {
    // Sentinels are only supported with writes, and not within arrays.
    if (!_isWrite(context.dataSource)) {
      throw context.createError(
          '${value.methodName}() can only be used with set() and update()');
    }
    if (context.path == null) {
      throw context.createError(
          '${value.methodName}() is not currently supported inside arrays');
    }

    if (value is firestore.DeleteFieldValue) {
      if (context.dataSource == UserDataSource.mergeSet) {
        // No transform to add for a delete, but we need to add it to our
        // fieldMask so it gets deleted.
        context.fieldMask.add(context.path);
      } else if (context.dataSource == UserDataSource.update) {
        Assert.hardAssert(context.path.isNotEmpty,
            'FieldValue.delete() at the top level should have already been handled.');
        throw context.createError(
            'FieldValue.delete() can only appear at the top level of your update data');
      } else {
        // We shouldn't encounter delete sentinels for queries or non-merge
        // [set()] calls.
        throw context.createError(
            'FieldValue.delete() can only be used with update() and set() with SetOptions.merge()');
      }
    } else if (value is firestore.ServerTimestampFieldValue) {
      context.fieldTransforms.add(new FieldTransform(
        context.path,
        ServerTimestampOperation(),
      ));
    } else if (value is firestore.ArrayUnionFieldValue) {
      List<FieldValue> parsedElements =
          _parseArrayTransformElements(value.elements);
      ArrayTransformOperation arrayUnion =
          ArrayTransformOperationUnion(parsedElements);
      context.fieldTransforms.add(new FieldTransform(context.path, arrayUnion));
    } else if (value is firestore.ArrayRemoveFieldValue) {
      List<FieldValue> parsedElements =
          _parseArrayTransformElements(value.elements);
      ArrayTransformOperation arrayRemove =
          ArrayTransformOperationRemove(parsedElements);
      context.fieldTransforms
          .add(new FieldTransform(context.path, arrayRemove));
    } else {
      throw Assert.fail("Unknown FieldValue type: ${value.runtimeType}");
    }
  }

  /// Helper to parse a scalar value (i.e. not a Map or List)
  ///
  /// Returns the parsed value, or null if the value was a FieldValue sentinel
  /// that should not be included in the resulting parsed data.
  //p
  FieldValue _parseScalarValue(Object input, _ParseContext context) {
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
      Timestamp timestamp = input;
      int seconds = timestamp.seconds;
      // Firestore backend truncates precision down to microseconds. To ensure
      // offline mode works the same with regards to truncation, perform the
      // truncation immediately without waiting for the backend to do that.
      final int truncatedNanoseconds = timestamp.nanoseconds ~/ 1000 * 1000;
      return TimestampValue.valueOf(
          new Timestamp(seconds, truncatedNanoseconds));
    } else if (input is GeoPoint) {
      return GeoPointValue.valueOf(input);
    } else if (input is Blob) {
      return BlobValue.valueOf(input);
    } else if (input is DocumentReference) {
      DocumentReference ref = input;
      // TODO: Rework once pre-converter is ported to Android.
      if (ref.firestore != null) {
        DatabaseId otherDb = ref.firestore.databaseId;
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
    List<FieldValue> result = List(elements.length);
    for (int i = 0; i < elements.length; i++) {
      Object element = elements[i];
      // Although array transforms are used with writes, the actual elements
      // being unioned or removed are not considered writes since they cannot
      // contain any FieldValue sentinels, etc.
      _ParseContext context =
          new _ParseContext(UserDataSource.argument, FieldPath.emptyPath);
      result.add(_parseData(element, context.childContextForArray(i)));
    }
    return result;
  }
}

/// The result of parsing document data (e.g. for a setData call).
class ParsedDocumentData {
  final ObjectValue _data;
  final FieldMask _fieldMask;
  final List<FieldTransform> _fieldTransforms;

  ParsedDocumentData(this._data, this._fieldMask, this._fieldTransforms);

  List<Mutation> toMutationList(DocumentKey key, Precondition precondition) {
    List<Mutation> mutations = <Mutation>[];
    if (_fieldMask != null) {
      mutations.add(PatchMutation(key, _data, _fieldMask, precondition));
    } else {
      mutations.add(SetMutation(key, _data, precondition));
    }
    if (!_fieldTransforms.isEmpty) {
      mutations.add(new TransformMutation(key, _fieldTransforms));
    }
    return mutations;
  }
}

/// The result of parsing "update" data (i.e. for an updateData call).
class ParsedUpdateData {
  final ObjectValue _data;
  final FieldMask _fieldMask;
  final List<FieldTransform> _fieldTransforms;

  const ParsedUpdateData(this._data, this._fieldMask, this._fieldTransforms);

  List<Mutation> toMutationList(DocumentKey key, Precondition precondition) {
    final List<Mutation> mutations = [];
    mutations.add(new PatchMutation(key, _data, _fieldMask, precondition));
    if (!_fieldTransforms.isEmpty) {
      mutations.add(new TransformMutation(key, _fieldTransforms));
    }
    return mutations;
  }
}

/// Represents what type of API method provided the data being parsed; useful
/// for determining which error conditions apply during parsing and providing
/// better error messages.
enum UserDataSource {
  set,
  mergeSet,
  update,

  /// Indicates the source is a where clause, cursor bound, arrayUnion()
  /// element, etc. Of note, isWrite(Argument) will return false.
  argument
}

/// A "context" object passed around while parsing user data.
class _ParseContext {
  final RegExp reservedFieldRegex = RegExp("^__.*__\$");

  /// The current path being parsed.
  /// TODO: path should never be null, but we don't support array paths right now.
  final FieldPath path;

  /// Whether or not this context corresponds to an element of an array.
  final bool arrayElement;

  /// What type of API method provided the data being parsed; useful for
  /// determining which error conditions apply during parsing and providing
  /// better error messages.
  final UserDataSource dataSource;

  /// Accumulates a list of field transforms found while parsing the data.
  final List<FieldTransform> fieldTransforms;

  /// Accumulates a list of the field paths found while parsing the data.
  final SplayTreeSet<FieldPath> fieldMask;

  /// Initializes a ParseContext with the given source and path.
  ///
  /// [dataSource] Indicates what kind of API method this data came from.
  /// [path] A path within the object being parsed. This could be an empty path
  /// (in which case the context represents the root of the data being parsed),
  /// or a nonempty path (indicating the context represents a nested location
  /// within the data).
  ///
  ///   * TODO: We don't support array paths right now, so path can be null to
  ///   indicate the context represents any location within an array (in which
  ///   case certain features will not work and errors will be somewhat
  ///   compromised).
  ///
  /// [arrayElement] Whether or not this context corresponds to an element of an
  /// array.
  /// [fieldTransforms] A mutable list of field transforms encountered while
  /// parsing the data.
  /// [fieldMask] A mutable list of field paths encountered while parsing the
  /// data.
  _ParseContext._(
    this.dataSource,
    this.path,
    this.arrayElement,
    this.fieldTransforms,
    this.fieldMask,
  ) {
    _validatePath();
  }

  factory _ParseContext(UserDataSource dataSource, FieldPath path) {
    return _ParseContext._(
      dataSource,
      path,
      /*arrayElement:*/ false,
      [],
      new SplayTreeSet(),
    );
  }

  _ParseContext childContextForName(String fieldName) {
    FieldPath childPath = path == null ? null : path.appendSegment(fieldName);
    _ParseContext context = new _ParseContext._(
      dataSource,
      childPath,
      /*arrayElement:*/ false,
      fieldTransforms,
      fieldMask,
    );
    context._validatePathSegment(fieldName);
    return context;
  }

  _ParseContext childContextForField(FieldPath fieldPath) {
    FieldPath childPath = path == null ? null : path.appendPath(fieldPath);
    _ParseContext context = new _ParseContext._(
      dataSource,
      childPath,
      /*arrayElement:*/ false,
      fieldTransforms,
      fieldMask,
    );
    context._validatePath();
    return context;
  }

  _ParseContext childContextForArray(int arrayIndex) {
    // TODO: We don't support array paths right now; so make path null.
    return new _ParseContext._(
      dataSource,
      /*path:*/ null,
      /*arrayElement:*/ true,
      fieldTransforms,
      fieldMask,
    );
  }

  /// Creates an error including the given reason and the current field path.
  StateError createError(String reason) {
    String fieldDescription = (this.path == null || this.path.isEmpty)
        ? ''
        : ' (found in field $path)';
    return new StateError('Invalid data. $reason $fieldDescription');
  }

  /// Returns 'true' if 'fieldPath' was traversed when creating this context.
  bool contains(FieldPath fieldPath) {
    for (FieldPath field in fieldMask) {
      if (fieldPath.isPrefixOf(field)) {
        return true;
      }
    }

    for (FieldTransform fieldTransform in fieldTransforms) {
      if (fieldPath.isPrefixOf(fieldTransform.fieldPath)) {
        return true;
      }
    }

    return false;
  }

  void _validatePath() {
    // TODO: Remove null check once we have proper paths for fields within arrays.
    if (this.path == null) {
      return;
    }
    for (int i = 0; i < this.path.length; i++) {
      this._validatePathSegment(this.path.getSegment(i));
    }
  }

  void _validatePathSegment(String segment) {
    if (_isWrite(dataSource) && reservedFieldRegex.hasMatch(segment)) {
      throw this.createError('Document fields cannot begin and end with __');
    }
  }
}

bool _isWrite(UserDataSource dataSource) {
  switch (dataSource) {
    case UserDataSource.set: // fall through
    case UserDataSource.mergeSet: // fall through
    case UserDataSource.update:
      return true;
    case UserDataSource.argument:
      return false;
    default:
      throw Assert.fail('Unexpected case for UserDataSource: $dataSource');
  }
}
