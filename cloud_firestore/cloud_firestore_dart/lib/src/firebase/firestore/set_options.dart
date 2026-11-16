// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';

/// Chooses whether a `set` call replaces the whole document or merges the
/// data into it.
///
/// Pass one to `set` of `DocumentReference`, `WriteBatch` or `Transaction`.
/// Without options, `set` replaces the document ([overwrite]). With
/// [mergeAllFields] it changes only the fields present in the data, and with
/// [SetOptions.mergeFields] or [SetOptions.mergeFieldPaths] only the fields
/// you name. A merge creates the document if it does not exist.
///
/// ```dart
/// final DocumentReference<Map<String, Object?>> sf = firestore.doc('cities/SF');
///
/// // Keeps every other field of the document.
/// await sf.set(<String, Object?>{'capital': false}, SetOptions.mergeAllFields);
///
/// // Writes only `population`, even though `name` is in the data too.
/// await sf.set(
///   <String, Object?>{'name': 'San Francisco', 'population': 870000},
///   SetOptions.mergeFields(<String>['population']),
/// );
/// ```
///
/// In a merge, nested maps are merged too: `{'address': {'city': 'SF'}}`
/// changes `address.city` and keeps the other fields of `address`. A merge
/// accepts [FieldValue.delete] to remove a field, which an overwrite does
/// not.
///
/// When the reference has a converter, `FirestoreDataConverter.toFirestore`
/// receives these options. In the JS SDK these are the `{merge: true}` and
/// `{mergeFields: [...]}` objects.
class SetOptions {
  const SetOptions._(this.merge, this._fieldMask)
    : assert(
        _fieldMask != null && merge,
        'Cannot specify a fieldMask for non-merge sets()',
      );

  const SetOptions._overwrite() : merge = false, _fieldMask = null;

  const SetOptions._mergeAll() : merge = true, _fieldMask = null;

  /// Merges only the fields named in [fields]; every other field of the data
  /// is ignored, and every other field of the document is kept.
  ///
  /// Each entry of [fields] is a dot-separated field path, so `'address.city'`
  /// names `city` inside the map `address`. Use [SetOptions.mergeFieldPaths]
  /// when a field name contains a dot.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').set(
  ///   <String, Object?>{'name': 'San Francisco', 'population': 870000},
  ///   SetOptions.mergeFields(<String>['population']),
  /// );
  /// ```
  ///
  /// Throws an [ArgumentError] if an entry of [fields] is not a valid field
  /// path. The `set` call throws an [ArgumentError] if the data has no value
  /// for one of [fields].
  factory SetOptions.mergeFields(List<String> fields) {
    final Set<model.FieldPath> fieldPaths = fields
        .map((String field) => FieldPath.fromString(field).internalPath)
        .toSet();
    return SetOptions._(true, FieldMask(fieldPaths));
  }

  /// Merges only the fields named in [fields], given as [FieldPath]s; every
  /// other field of the data is ignored, and every other field of the
  /// document is kept.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').set(
  ///   <String, Object?>{
  ///     'stats.v2': <String, Object?>{'visits': 10},
  ///   },
  ///   SetOptions.mergeFieldPaths(<FieldPath>[
  ///     FieldPath.of(<String>['stats.v2', 'visits']),
  ///   ]),
  /// );
  /// ```
  ///
  /// The `set` call throws an [ArgumentError] if the data has no value for one
  /// of [fields].
  factory SetOptions.mergeFieldPaths(List<FieldPath> fields) {
    final Set<model.FieldPath> fieldPaths = fields
        .map((FieldPath field) => field.internalPath)
        .toSet();
    return SetOptions._(true, FieldMask(fieldPaths));
  }

  /// Replaces the whole document with the data: fields that are not in the
  /// data are removed. The default when no options are given.
  static const SetOptions overwrite = SetOptions._overwrite();

  /// Merges the data into the document: only the fields present in the data
  /// are written, nested maps are merged, and the other fields of the
  /// document are kept. The JS SDK's `{merge: true}`.
  ///
  /// ```dart
  /// await firestore
  ///     .doc('cities/SF')
  ///     .set(<String, Object?>{'capital': false}, SetOptions.mergeAllFields);
  /// ```
  static const SetOptions mergeAllFields = SetOptions._mergeAll();

  /// Whether the data is merged into the existing document instead of
  /// replacing it: false only for [overwrite].
  final bool merge;

  final FieldMask? _fieldMask;
}

/// Members of [SetOptions] for the SDK itself. Not exported by the public libraries.
extension SetOptionsInternal on SetOptions {
  /// The fields to merge, or null to merge every field of the data (or none,
  /// for an overwrite).
  FieldMask? get fieldMask => _fieldMask;
}
