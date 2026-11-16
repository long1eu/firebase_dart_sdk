// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// A [FieldPath] refers to a field in a document. The path may consist of a single field name
/// (referring to a top level field in the document), or a list of field names (referring to a
/// nested field in the document).
///
/// Methods that take a field name as a `String` split it on dots. Use a [FieldPath] when a field
/// name itself contains a dot or another character that a dotted path cannot hold
/// (`~ * / [ ]`), and [documentId] to filter or sort by the document id.
///
/// ```dart
/// final FieldPath nested = FieldPath(['address', 'city']); // same as 'address.city'
/// final FieldPath dotted = FieldPath(['version.1']); // one field named "version.1"
///
/// final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
///     .collection('cities')
///     .where(nested, isEqualTo: 'San Francisco')
///     .orderBy(dotted)
///     .get();
/// ```
class FieldPath {
  /// Implementation detail of the SDK; not part of the supported API. Use [FieldPath.new] or
  /// [FieldPath.fromString].
  const FieldPath._(this._internalPath);

  /// Creates a [FieldPath] from the provided field names. If more than one field name is provided,
  /// the path will point to a nested field in a document.
  ///
  /// [fieldNames] a list of field names.
  ///
  /// Return a FieldPath that points to a field location in a document. Throws an [ArgumentError]
  /// if [fieldNames] is empty or one of the names is empty.
  factory FieldPath(List<String> fieldNames) {
    checkArgument(
      fieldNames.isNotEmpty,
      'Invalid field path. Provided path must not be null or empty.',
    );

    for (int i = 0; i < fieldNames.length; ++i) {
      checkArgument(
        fieldNames[i].isNotEmpty,
        'Invalid field name at argument ${i + 1}. Field names must not be null or empty.',
      );
    }

    return FieldPath._(model.FieldPath.fromSegments(fieldNames));
  }

  /// Parses a field path string into a [FieldPath], treating dots as separators.
  ///
  /// Throws an [ArgumentError] if [path] is empty, starts or ends with a dot, contains `..`, or
  /// contains one of `~ * / [ ]`; use [FieldPath.new] for such names.
  factory FieldPath.fromString(String path) {
    checkNotNull(path, 'Provided field path must not be null.');
    checkArgument(
      !_reserved.hasMatch(path),
      "Invalid field path ($path). Paths must not contain '~', '*', '/', '[', "
      "or ']'. Use FieldPath() for field names that contain them.",
    );
    try {
      return FieldPath(path.split('.'));
    } on ArgumentError catch (_) {
      throw ArgumentError(
        'Invalid field path ($path). Paths must not be empty, begin with \'.\', end with \'.\', '
        'or contain \'..\'',
      );
    }
  }

  /// Matches any characters in a field path string that are reserved.
  static final RegExp _reserved = RegExp('[~*/\\[\\]]');

  final model.FieldPath _internalPath;

  static final FieldPath _documentIdInstance = FieldPath._(
    model.FieldPath.keyPath,
  );

  /// A special sentinel [FieldPath] to refer to the id of a document. It can be
  /// used in queries to sort or filter by the document id. This is `documentId()` of the JS SDK.
  ///
  /// In a filter on a collection the value is a document id or a `DocumentReference`; on a
  /// collection group it is a full document path.
  ///
  /// ```dart
  /// final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
  ///     .collection('cities')
  ///     .where(FieldPath.documentId, whereIn: ['SF', 'LA'])
  ///     .get();
  /// ```
  ///
  /// A getter named `documentId` (the official spelling) cannot exist next to
  /// the method [documentId] until that method is removed.
  static FieldPath get documentId => _documentIdInstance;

  /// The field names of this path, one per nesting level: `['address', 'city']` for
  /// `'address.city'`.
  List<String> get components => List<String>.unmodifiable(<String>[
    for (int i = 0; i < _internalPath.length; i++) _internalPath.getSegment(i),
  ]);

  @override
  String toString() {
    return _internalPath.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldPath &&
          runtimeType == other.runtimeType &&
          _internalPath == other.internalPath;

  @override
  int get hashCode => _internalPath.hashCode * 31;
}

/// Members of [FieldPath] for the SDK itself. Not exported by the public libraries.
extension FieldPathInternal on FieldPath {
  /// The model path this public path wraps.
  model.FieldPath get internalPath => _internalPath;

  /// Wraps the model path [path].
  static FieldPath create(model.FieldPath path) => FieldPath._(path);

  /// Matches any characters in a field path string that are reserved.
  static RegExp get reserved => FieldPath._reserved;

  /// The path of the document id, as [FieldPath.documentId].
  static FieldPath get documentIdInstance => FieldPath._documentIdInstance;

  /// [FieldPath.fromString] for the [path] argument of the public
  /// method [methodName]: an invalid path fails with an [ArgumentError] that
  /// names the method, like the JS SDK (`Function where() called with invalid
  /// data. Invalid field path (a..b). ...`), and [documentPath] when given.
  static FieldPath fromArgument(
    String methodName,
    String path, {
    String? documentPath,
  }) {
    try {
      return FieldPath.fromString(path);
    } on ArgumentError catch (e) {
      final String found = documentPath == null
          ? ''
          : ' (found in document $documentPath)';
      throw ArgumentError(
        'Function $methodName() called with invalid data. ${e.message}$found',
      );
    }
  }
}
