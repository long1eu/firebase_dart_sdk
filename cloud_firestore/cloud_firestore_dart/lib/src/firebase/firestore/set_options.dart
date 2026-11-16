// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:collection/collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';

/// Chooses whether a `set` call replaces the whole document or merges the
/// data into it.
///
/// Pass one to `set` of `DocumentReference`, `WriteBatch` or `Transaction`.
/// Without options, `set` replaces the document. With [merge] it changes only
/// the fields present in the data, and with [mergeFields] only the fields you
/// name. A merge creates the document if it does not exist.
///
/// ```dart
/// final DocumentReference<Map<String, Object?>> sf = firestore.doc('cities/SF');
///
/// // Keeps every other field of the document.
/// await sf.set(<String, Object?>{'capital': false}, const SetOptions(merge: true));
///
/// // Writes only `population`, even though `name` is in the data too.
/// await sf.set(
///   <String, Object?>{'name': 'San Francisco', 'population': 870000},
///   const SetOptions(mergeFields: <String>['population']),
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
/// `{mergeFields: [...]}` objects; this is FlutterFire's `SetOptions`.
class SetOptions {
  /// Options for a `set` call: [merge] merges the data into the document, and
  /// [mergeFields] merges only the fields it names. Give at most one of them;
  /// with neither, `set` replaces the whole document.
  ///
  /// Each entry of [mergeFields] is a [String] (a dot-separated field path, so
  /// `'address.city'` names `city` inside the map `address`) or a [FieldPath]
  /// (for a field name that contains a dot). The `set` call throws an
  /// [ArgumentError] if an entry is not a valid field path or if the data has
  /// no value for one of the fields.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').set(
  ///   <String, Object?>{
  ///     'stats.v2': <String, Object?>{'visits': 10},
  ///   },
  ///   SetOptions(mergeFields: <Object>[
  ///     FieldPath(<String>['stats.v2', 'visits']),
  ///   ]),
  /// );
  /// ```
  const SetOptions({bool merge = false, List<Object>? mergeFields})
    : assert(
        !(merge && mergeFields != null),
        "SetOptions cannot have both 'merge' and 'mergeFields'.",
      ),
      _merge = merge,
      _mergeFields = mergeFields;

  final bool _merge;
  final List<Object>? _mergeFields;

  /// Whether the data is merged into the existing document instead of
  /// replacing it: true with `merge: true` and with [mergeFields].
  bool get merge => _merge || _mergeFields != null;

  /// The fields to merge, or null to merge every field of the data (with
  /// [merge]) or to replace the document.
  ///
  /// Throws an [ArgumentError] if an entry is not a [String] or a [FieldPath],
  /// or is not a valid field path.
  List<FieldPath>? get mergeFields {
    final List<Object>? fields = _mergeFields;
    if (fields == null) {
      return null;
    }
    return List<FieldPath>.unmodifiable(<FieldPath>[
      for (final Object field in fields)
        if (field is FieldPath)
          field
        else if (field is String)
          FieldPath.fromString(field)
        else
          throw ArgumentError.value(
            field,
            'mergeFields',
            'must contain String or FieldPath values',
          ),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetOptions &&
          merge == other.merge &&
          const ListEquality<FieldPath>().equals(
            mergeFields,
            other.mergeFields,
          );

  @override
  int get hashCode =>
      Object.hash(merge, const ListEquality<FieldPath>().hash(mergeFields));

  @override
  String toString() =>
      'SetOptions(merge: $merge, mergeFields: ${mergeFields?.join(', ')})';
}

/// Members of [SetOptions] for the SDK itself. Not exported by the public libraries.
extension SetOptionsInternal on SetOptions {
  /// The fields to merge, or null to merge every field of the data (or none,
  /// for an overwrite).
  FieldMask? get fieldMask {
    final List<FieldPath>? fields = mergeFields;
    if (fields == null) {
      return null;
    }
    return FieldMask(
      fields.map((FieldPath field) => field.internalPath).toSet(),
    );
  }
}
