// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// A [FieldPath] refers to a field in a document. The path may consist of a single field name
/// (referring to a top level field in the document), or a list of field names (referring to a
/// nested field in the document).
class FieldPath {
  const FieldPath(this.internalPath);

  factory FieldPath.fromSegments(List<String> segments) {
    return FieldPath(model.FieldPath.fromSegments(segments));
  }

  /// Creates a [FieldPath] from the provided field names. If more than one field name is provided,
  /// the path will point to a nested field in a document.
  ///
  /// [fieldNames] a list of field names.
  ///
  /// Return a FieldPath that points to a field location in a document.
  factory FieldPath.of(List<String> fieldNames) {
    checkArgument(fieldNames != null && fieldNames.isNotEmpty,
        'Invalid field path. Provided path must not be null or empty.');

    for (int i = 0; i < fieldNames.length; ++i) {
      checkArgument(fieldNames[i] != null && fieldNames[i].isNotEmpty,
          'Invalid field name at argument ${i + 1}. Field names must not be null or empty.');
    }

    return FieldPath.fromSegments(fieldNames);
  }

  /// Parses a field path string into a [FieldPath], treating dots as separators.
  factory FieldPath.fromDotSeparatedPath(String path) {
    checkNotNull(path, 'Provided field path must not be null.');
    checkArgument(!reserved.hasMatch(path),
        'Invalid field path ($path). Paths must not contain \'~\', \'*\', \'/\', \'[\', or \']\'');
    try {
      return FieldPath.of(path.split('.'));
    } on ArgumentError catch (_) {
      throw ArgumentError(
          'Invalid field path ($path). Paths must not be empty, begin with \'.\', end with \'.\', '
          'or contain \'..\'');
    }
  }

  /// Matches any characters in a field path string that are reserved.
  static final RegExp reserved = RegExp('[~*/\\[\\]]');

  final model.FieldPath internalPath;

  static final FieldPath documentIdInstance =
      FieldPath(model.FieldPath.keyPath);

  /// Returns a special sentinel [FieldPath] to refer to the id of a document. It can be used in
  /// queries to sort or filter by the document id.
  static FieldPath documentId() => documentIdInstance;

  @override
  String toString() {
    return internalPath.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldPath &&
          runtimeType == other.runtimeType &&
          internalPath == other.internalPath;

  @override
  int get hashCode => internalPath.hashCode * 31;
}
