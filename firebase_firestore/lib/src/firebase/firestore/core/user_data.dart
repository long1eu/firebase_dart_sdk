// File created by
// Lung Razvan <long1eu>
// on 15/10/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// Represents what type of API method provided the data being parsed; useful
/// for determining which error conditions apply during parsing and providing
/// better error messages.
class UserDataSource {
  final int _value;

  const UserDataSource._(this._value);

  /// The data comes from a regular Set operation, without merge.
  static const UserDataSource set = const UserDataSource._(0);

  /// The data comes from a Set operation with merge enabled.
  static const UserDataSource mergeSet = const UserDataSource._(1);

  /// The data comes from an Update operation.
  static const UserDataSource update = const UserDataSource._(2);

  /// Indicates the source is a where clause, cursor bound, arrayUnion()
  /// element, etc. Of note,  UserDataParseContext.isWrite() will return false.
  static const UserDataSource argument = const UserDataSource._(3);

  String get name => _stringValues[_value];

  static const List<UserDataSource> values = const <UserDataSource>[
    set,
    mergeSet,
    update,
    argument
  ];

  static const List<String> _stringValues = const <String>[
    'set',
    'mergeSet',
    'update',
    'argument'
  ];
}

/// A [context] object that wraps a [UserDataParseAccumulator] and refers to a specific
/// location in a user-supplied document. Instances are created and passed
/// around while traversing user data during parsing in order to conveniently
/// accumulate data in the [UserDataParseAccumulator].
class UserDataParseContext {
  final Pattern _reservedFieldRegex = RegExp('^__.*__\$');

  final UserDataParseAccumulator _accumulator;

  /// The current path being parsed.
  // TODO: path should never be null, but we don't support array paths right
  // now.
  final FieldPath path;

  /// Whether or not this context corresponds to an element of an array.
  final bool arrayElement;

  /// Initializes a [UserDataParseContext] with the given source and path.
  ///
  /// [accumulator] on which to add results. [path] within the object being
  /// parsed. This could be an empty path (in which case the context represents
  /// the root of the data being parsed), or a nonempty path (indicating the
  /// context represents a nested location within the data). [arrayElement]
  /// whether or not this context corresponds to an element of an array.
  ///
  /// * TODO: We don't support array paths right now, so path can be null to
  /// indicate the context represents any location within an array (in which
  /// case certain features will not work and errors will be somewhat
  /// compromised).
  UserDataParseContext._(this._accumulator, this.path, this.arrayElement);

  /// What type of API method provided the data being parsed; useful for
  /// determining which error conditions apply during parsing and providing
  /// better error messages.
  UserDataSource get dataSource => _accumulator.dataSource;

  /// Returns true for the non-query parse contexts (Set, MergeSet and Update).
  bool get isWrite {
    switch (_accumulator.dataSource) {
      case UserDataSource.set: // fall through
      case UserDataSource.mergeSet: // fall through
      case UserDataSource.update:
        return true;
      case UserDataSource.argument:
        return false;
      default:
        throw Assert.fail(
            'Unexpected case for UserDataSource: ${_accumulator.dataSource.name}');
    }
  }

  UserDataParseContext childContextForSegment(String fieldName) {
    final FieldPath childPath =
        path == null ? null : path.appendSegment(fieldName);
    final UserDataParseContext context = UserDataParseContext._(
        _accumulator, childPath, /*arrayElement:*/ false);
    context._validatePathSegment(fieldName);
    return context;
  }

  UserDataParseContext childContextForField(FieldPath fieldPath) {
    final FieldPath childPath =
        path == null ? null : path.appendField(fieldPath);
    final UserDataParseContext context = UserDataParseContext._(
        _accumulator, childPath, /*arrayElement:*/ false);
    context._validatePath();
    return context;
  }

  UserDataParseContext childContextForArrayIndex(int arrayIndex) {
    // TODO: We don't support array paths right now; so make path null.
    return UserDataParseContext._(
        _accumulator, /*path:*/ null, /*arrayElement:*/ true);
  }

  /// Adds the given [fieldPath] to the accumulated FieldMask.
  void addToFieldMask(FieldPath fieldPath) {
    _accumulator.addToFieldMask(fieldPath);
  }

  /// Adds a transformation for the given field path.
  void addToFieldTransforms(
      FieldPath fieldPath, TransformOperation transformOperation) {
    _accumulator.addToFieldTransforms(fieldPath, transformOperation);
  }

  /// Creates an error including the given reason and the current field path.
  Error createError(String reason) {
    final String fieldDescription =
        (path == null || path.isEmpty) ? '' : ' (found in field $path)';
    return ArgumentError('Invalid data. ' + reason + fieldDescription);
  }

  void _validatePath() {
    // TODO: Remove null check once we have proper paths for fields within
    // arrays.
    if (path == null) {
      return;
    }
    for (int i = 0; i < path.length; i++) {
      _validatePathSegment(path.getSegment(i));
    }
  }

  void _validatePathSegment(String segment) {
    if (isWrite && _reservedFieldRegex.allMatches(segment).isNotEmpty) {
      throw createError('Document fields cannot begin and end with __');
    }
  }
}

/// The result of parsing document data (e.g. for a setData call).
class UserDataParsedSetData {
  final ObjectValue _data;
  final FieldMask _fieldMask;
  final List<FieldTransform> _fieldTransforms;

  UserDataParsedSetData(this._data, this._fieldMask, this._fieldTransforms);

  List<Mutation> toMutationList(DocumentKey key, Precondition precondition) {
    final List<Mutation> mutations = <Mutation>[];
    if (_fieldMask != null) {
      mutations.add(PatchMutation(key, _data, _fieldMask, precondition));
    } else {
      mutations.add(SetMutation(key, _data, precondition));
    }
    if (_fieldTransforms.isNotEmpty) {
      mutations.add(TransformMutation(key, _fieldTransforms));
    }
    return mutations;
  }
}

/// The result of parsing 'update' data (i.e. for an updateData call).
class UserDataParsedUpdateData {
  final ObjectValue _data;

  final FieldMask _fieldMask;

  final List<FieldTransform> fieldTransforms;

  UserDataParsedUpdateData(this._data, this._fieldMask, this.fieldTransforms);

  List<Mutation> toMutationList(DocumentKey key, Precondition precondition) {
    final List<Mutation> mutations = <Mutation>[];
    mutations.add(PatchMutation(key, _data, _fieldMask, precondition));
    if (fieldTransforms.isNotEmpty) {
      mutations.add(TransformMutation(key, fieldTransforms));
    }
    return mutations;
  }
}

/// Accumulates the side-effect results of parsing user input. These include:
///
/// <ul>
/// <li>The field mask naming all the fields that have values.
/// <li>The transform operations that must be applied in the batch to implement
/// server-generated behavior. In the wire protocol these are encoded separately
/// from the Value.
/// </ul>
class UserDataParseAccumulator {
  /// What type of API method provided the data being parsed; useful for
  /// determining which error conditions apply during parsing and providing
  /// better error messages.
  final UserDataSource dataSource;

  /// Accumulates a list of the field paths found while parsing the data.
  final SplayTreeSet<FieldPath> _fieldMask;

  /// Accumulates a list of field transforms found while parsing the data.

  final List<FieldTransform> fieldTransforms;

  /// [dataSource] indicates what kind of API method this data came from.
  UserDataParseAccumulator(this.dataSource)
      : _fieldMask = SplayTreeSet<FieldPath>(),
        fieldTransforms = <FieldTransform>[];

  /// Returns a new [UserDataParseContext] representing the root of a user
  /// document.
  UserDataParseContext get rootContext {
    return UserDataParseContext._(
        this, FieldPath.emptyPath, /*arrayElement:*/ false);
  }

  /// Returns [true] if the given [fieldPath] was encountered in the current
  /// document.
  bool contains(FieldPath fieldPath) {
    for (FieldPath field in _fieldMask) {
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

  /// Adds the given [fieldPath] to the accumulated [FieldMask].
  void addToFieldMask(FieldPath fieldPath) {
    _fieldMask.add(fieldPath);
  }

  /// Adds a transformation for the given field path.
  void addToFieldTransforms(
      FieldPath fieldPath, TransformOperation transformOperation) {
    fieldTransforms.add(FieldTransform(fieldPath, transformOperation));
  }

  /// Wraps the given [data] and (Optional) [userFieldMask[ along with any
  /// accumulated transforms that are covered by the given field mask into a
  /// [UserDataParsedSetData] that represents a user-issued merge.
  ///
  /// [data] represents the converted user values and the (Optional)
  /// [userFieldMask] is the user-supplied field mask that masks out any changes
  /// that have been accumulated so far.
  ///
  /// Returns [UserDataParsedSetData] that wraps the contents of this
  /// [UserDataParseAccumulator]. (Optional) The field mask in the result will
  /// be the [userFieldMask] and only transforms that are covered by the mask
  /// will be included.
  UserDataParsedSetData toMergeData(ObjectValue data,
      [FieldMask userFieldMask]) {
    if (userFieldMask == null) {
      return UserDataParsedSetData(data, FieldMask(_fieldMask.toList()),
          fieldTransforms.toList(growable: false));
    }

    final List<FieldTransform> coveredFieldTransforms = <FieldTransform>[];

    for (FieldTransform parsedTransform in fieldTransforms) {
      if (userFieldMask.covers(parsedTransform.fieldPath)) {
        coveredFieldTransforms.add(parsedTransform);
      }
    }

    return UserDataParsedSetData(
      data,
      userFieldMask,
      coveredFieldTransforms.toList(growable: false),
    );
  }

  /// Wraps the given [data] along with any accumulated transforms into a
  /// [UserDataParsedSetData] that represents a user-issued Set.
  ///
  /// Return [UserDataParsedSetData] that wraps the contents of this
  /// [UserDataParseAccumulator].
  UserDataParsedSetData toSetData(ObjectValue data) {
    return UserDataParsedSetData(
      data,
      /*fieldMask:*/ null,
      fieldTransforms.toList(growable: false),
    );
  }

  /// Wraps the given [data] along with any accumulated field mask and
  /// transforms into a [UserDataParsedUpdateData] that represents a user-issued
  /// Update.
  ///
  /// Returns [UserDataParsedSetData] that wraps the contents of this
  /// [UserDataParseAccumulator].
  UserDataParsedUpdateData toUpdateData(ObjectValue data) {
    return UserDataParsedUpdateData(
      data,
      FieldMask(_fieldMask.toList()),
      fieldTransforms.toList(growable: false),
    );
  }
}
