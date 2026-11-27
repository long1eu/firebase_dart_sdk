/// Argument validation of keys, paths, priorities and data. JS: `core/util/validation.ts`;
/// Android: `core/utilities/Validation.java`, `core/ValidationPath.java` (data checks).
///
/// Failures throw [ArgumentError] with the JS message text.
///
/// Differences from JS, where Dart has no `undefined`: `optional` lets a null key, path or merge
/// map through (for data and priorities null is already valid). Data may only be null, `bool`,
/// `num`, `String`, `Map` with `String` keys and `List`; anything else is refused. A string with
/// an unpaired surrogate (value, key or path) is refused, because the server would store U+FFFD.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';

/// Characters a key may not contain.
final RegExp invalidKeyRegex = RegExp(r'[\[\].#$\/\u0000-\u001F\u007F]');

/// Characters a path may not contain.
final RegExp invalidPathRegex = RegExp(r'[\[\].#$\u0000-\u001F\u007F]');

/// The largest string leaf, in UTF-8 bytes.
const int maxLeafSize = 10 * 1024 * 1024;

final RegExp _infoPrefix = RegExp(r'^\/*\.info(\/|$)');

const String _invalidKeyHint =
    'Keys must be non-empty strings '
    'and can\'t contain ".", "#", "\$", "/", "[", or "]"';

String _errorPrefix(String fnName, String argName) =>
    '$fnName failed: $argName argument ';

/// Whether [text] contains a UTF-16 surrogate that is not part of a pair.
bool hasLoneSurrogate(String text) {
  final int length = text.length;
  for (int i = 0; i < length; i++) {
    final int c = text.codeUnitAt(i);
    if (c < 0xd800 || c > 0xdfff) {
      continue;
    }
    if (c <= 0xdbff && i + 1 < length) {
      final int next = text.codeUnitAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        i++;
        continue;
      }
    }
    return true;
  }
  return false;
}

/// Whether [key] is a non-empty string without invalid characters.
bool isValidKey(Object? key) =>
    key is String &&
    key.isNotEmpty &&
    !invalidKeyRegex.hasMatch(key) &&
    !hasLoneSurrogate(key);

/// Whether [pathString] is a valid path.
bool isValidPathString(String pathString) =>
    pathString.isNotEmpty &&
    !invalidPathRegex.hasMatch(pathString) &&
    !hasLoneSurrogate(pathString);

String _stripInfo(String pathString) =>
    pathString.isEmpty ? pathString : pathString.replaceFirst(_infoPrefix, '/');

/// Whether [pathString] is a valid path that may start with `.info`.
bool isValidRootPathString(String pathString) =>
    isValidPathString(_stripInfo(pathString));

/// Whether [priority] is null, a finite number, a string or a server value.
bool isValidPriority(Object? priority) =>
    priority == null ||
    priority is String ||
    (priority is num && !isInvalidJsonNumber(priority)) ||
    (priority is Map && priority.containsKey('.sv'));

/// Validates [data] for a write at [path] by [fnName].
///
/// [optional] has no effect: null is valid data.
void validateFirebaseDataArg(
  String fnName,
  Object? data,
  Path path, {
  bool optional = false,
}) {
  final String errorPrefix = _errorPrefix(fnName, 'value');
  validateFirebaseData(errorPrefix, data, ValidationPath(path, errorPrefix));
}

/// Validates [data] below [path], recursively.
void validateFirebaseData(
  String errorPrefix,
  Object? data,
  ValidationPath path,
) {
  if (data == null || data is bool) {
    return;
  }
  if (data is num) {
    if (isInvalidJsonNumber(data)) {
      throw ArgumentError(
        '${errorPrefix}contains $data ${path.toErrorString()}',
      );
    }
    return;
  }
  if (data is String) {
    // Check the size, avoiding the UTF-8 count when it cannot be too long.
    if (data.length > maxLeafSize / 3 && utf8Length(data) > maxLeafSize) {
      throw ArgumentError(
        '${errorPrefix}contains a string greater than $maxLeafSize utf8 bytes '
        "${path.toErrorString()} ('${data.substring(0, 50)}...')",
      );
    }
    if (hasLoneSurrogate(data)) {
      throw ArgumentError(
        '${errorPrefix}contains a string with an unpaired surrogate '
        '${path.toErrorString()}',
      );
    }
    return;
  }
  if (data is Function) {
    throw ArgumentError(
      '${errorPrefix}contains a function ${path.toErrorString()} '
      'with contents = $data',
    );
  }
  if (data is Map) {
    bool hasDotValue = false;
    bool hasActualChild = false;
    for (final MapEntry<Object?, Object?> entry in data.entries) {
      final Object? key = entry.key;
      if (key == '.value') {
        hasDotValue = true;
      } else if (key != '.priority' && key != '.sv') {
        hasActualChild = true;
        if (!isValidKey(key)) {
          throw ArgumentError(
            '$errorPrefix contains an invalid key ($key) '
            '${path.toErrorString()}.  $_invalidKeyHint',
          );
        }
      }
      path.push(key! as String);
      validateFirebaseData(errorPrefix, entry.value, path);
      path.pop();
    }
    if (hasDotValue && hasActualChild) {
      throw ArgumentError(
        '$errorPrefix contains ".value" child ${path.toErrorString()} '
        'in addition to actual children.',
      );
    }
    return;
  }
  if (data is List) {
    for (int i = 0; i < data.length; i++) {
      path.push('$i');
      validateFirebaseData(errorPrefix, data[i], path);
      path.pop();
    }
    return;
  }
  throw ArgumentError(
    '${errorPrefix}contains an unsupported type (${data.runtimeType}) '
    '${path.toErrorString()}',
  );
}

/// Validates that no path of [mergePaths] is a prefix of another.
///
/// Unlike JS, [mergePaths] is not sorted in place.
void validateFirebaseMergePaths(String errorPrefix, List<Path> mergePaths) {
  for (final Path curPath in mergePaths) {
    final List<String> keys = curPath.toStringList();
    for (int j = 0; j < keys.length; j++) {
      if (keys[j] == '.priority' && j == keys.length - 1) {
        // .priority is OK.
      } else if (!isValidKey(keys[j])) {
        throw ArgumentError(
          '${errorPrefix}contains an invalid key (${keys[j]}) in path '
          '$curPath. $_invalidKeyHint',
        );
      }
    }
  }

  // Sorting puts an ancestor right before its descendants.
  final List<Path> sorted = List<Path>.of(mergePaths)..sort();
  Path? prevPath;
  for (final Path curPath in sorted) {
    if (prevPath != null && prevPath.contains(curPath)) {
      throw ArgumentError(
        '${errorPrefix}contains a path $prevPath that is ancestor of another '
        'path $curPath',
      );
    }
    prevPath = curPath;
  }
}

/// The longest key [_locationKeyError] prints whole; a longer one is cut to this many characters.
const int _maxPrintedLocationKey = 20;

/// The error for the merge key [key] that names the location itself, with a hint for [value]:
/// `remove()` for null, `set()` otherwise. [key] is only slashes or empty; a key longer than
/// [_maxPrintedLocationKey] characters is printed cut, with its length.
ArgumentError _locationKeyError(String errorPrefix, String key, Object? value) {
  final String shown = key.length <= _maxPrintedLocationKey
      ? '"$key"'
      : '"${key.substring(0, _maxPrintedLocationKey)}..." (${key.length} characters)';
  final String hint = value == null
      ? 'Use remove() to delete the location'
      : 'Use set() to replace the location';
  return ArgumentError(
    '${errorPrefix}contains the key $shown, which names the location itself, not a child below '
    'it. $hint, or name the children to write.',
  );
}

/// Validates the argument of `update` at [path]. A key that parses to the empty path (`''`, or only
/// slashes such as `'/'` and `'//'`) is refused: it would name [path] itself.
void validateFirebaseMergeDataArg(
  String fnName,
  Object? data,
  Path path, {
  bool optional = false,
}) {
  if (optional && data == null) {
    return;
  }

  final String errorPrefix = _errorPrefix(fnName, 'values');
  if (data is! Map) {
    throw ArgumentError(
      '$errorPrefix must be an object containing the children to replace.',
    );
  }

  final List<Path> mergePaths = <Path>[];
  for (final MapEntry<Object?, Object?> entry in data.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw ArgumentError(
        '${errorPrefix}contains an invalid key ($key) in path $path. '
        '$_invalidKeyHint',
      );
    }
    final Path curPath = Path(key);
    if (curPath.isEmpty) {
      throw _locationKeyError(errorPrefix, key, entry.value);
    }
    validateFirebaseData(
      errorPrefix,
      entry.value,
      ValidationPath(path.childPath(curPath), errorPrefix),
    );
    if (curPath.back?.name == '.priority') {
      if (!isValidPriority(entry.value)) {
        throw ArgumentError(
          "${errorPrefix}contains an invalid value for '$curPath', which must "
          'be a valid Firebase priority (a string, finite number, server '
          'value, or null).',
        );
      }
    } else {
      validateNoPriorityWithoutValue(
        errorPrefix,
        entry.value,
        path.childPath(curPath),
      );
    }
    mergePaths.add(curPath);
  }
  validateFirebaseMergePaths(errorPrefix, mergePaths);
}

/// Throws an [ArgumentError] when [data], written at [path] by a merge, is or contains (at any
/// depth, a list element or a `.value` included) an object with a non-null `.priority` and no
/// value: no non-null `.value` and no child that holds a value once nulls and empty objects are
/// dropped. Not in JS or Android.
///
/// A merge sends the caller's JSON as it is, and the server answers such an object with a control
/// error that names no request, so the write's Future would never complete (decisions section
/// 11). An object that ends up empty with no priority, or with `.priority: null`, is a removal and
/// is accepted. `set` and transactions are not checked: they send the parsed node, in which such
/// an object is empty and left out.
void validateNoPriorityWithoutValue(
  String errorPrefix,
  Object? data,
  Path path,
) {
  _holdsValue(errorPrefix, data, path);
}

/// Whether [data] holds a value once nulls and empty objects are dropped; throws as
/// [validateNoPriorityWithoutValue] does. Every child is checked, also after one holds a value.
bool _holdsValue(String errorPrefix, Object? data, Path path) {
  if (data == null) {
    return false;
  }
  if (data is List) {
    bool holds = false;
    for (int i = 0; i < data.length; i++) {
      final Path child = path.child(ChildKey('$i'));
      holds = _holdsValue(errorPrefix, data[i], child) || holds;
    }
    return holds;
  }
  if (data is! Map) {
    return true;
  }
  if (data.containsKey('.sv')) {
    // A server value is a leaf (checked by validateServerValues). The loop below would reach the same
    // answer through the '.sv' key; this branch says it outright and never descends into the placeholder.
    return true;
  }
  bool holds = false;
  for (final MapEntry<Object?, Object?> entry in data.entries) {
    final Object? key = entry.key;
    if (key == '.value') {
      holds = _holdsValue(errorPrefix, entry.value, path) || holds;
    } else if (key is String && key != '.priority') {
      final Path child = path.child(ChildKey(key));
      holds = _holdsValue(errorPrefix, entry.value, child) || holds;
    }
  }
  if (!holds && data['.priority'] != null) {
    throw ArgumentError(
      "${errorPrefix}contains an object at '$path' with a priority and no "
      'value (only nulls or empty objects), which the server never answers. '
      'Remove the child with null, or give it a value with its priority '
      "({'.value': <value>, '.priority': <priority>}); to change the "
      "priority of an existing child, write '<child>/.priority'.",
    );
  }
  return holds;
}

/// Validates a priority argument.
///
/// [optional] has no effect: null is a valid priority.
void validatePriority(
  String fnName,
  Object? priority, {
  bool optional = false,
}) {
  if (isInvalidJsonNumber(priority)) {
    throw ArgumentError(
      '${_errorPrefix(fnName, 'priority')}is $priority, but must be a valid '
      'Firebase priority (a string, finite number, server value, or null).',
    );
  }
  if (!isValidPriority(priority)) {
    throw ArgumentError(
      '${_errorPrefix(fnName, 'priority')}must be a valid Firebase priority '
      '(a string, finite number, server value, or null).',
    );
  }
  if (priority is String && hasLoneSurrogate(priority)) {
    throw ArgumentError(
      '${_errorPrefix(fnName, 'priority')}contains a string with an unpaired '
      'surrogate.',
    );
  }
}

/// Validates a key argument named [argumentName].
void validateKey(
  String fnName,
  String argumentName,
  String? key, {
  bool optional = false,
}) {
  if (optional && key == null) {
    return;
  }
  if (!isValidKey(key)) {
    throw ArgumentError(
      '${_errorPrefix(fnName, argumentName)}was an invalid key = "$key".  '
      'Firebase keys must be non-empty strings and '
      'can\'t contain ".", "#", "\$", "/", "[", or "]").',
    );
  }
}

/// Validates a path argument named [argumentName].
void validatePathString(
  String fnName,
  String argumentName,
  String? pathString, {
  bool optional = false,
}) {
  if (optional && pathString == null) {
    return;
  }
  if (pathString == null || !isValidPathString(pathString)) {
    throw ArgumentError(
      '${_errorPrefix(fnName, argumentName)}was an invalid path = '
      '"$pathString". Paths must be non-empty strings and '
      'can\'t contain ".", "#", "\$", "[", or "]"',
    );
  }
}

/// Validates a root path argument (may start with `.info`).
void validateRootPathString(
  String fnName,
  String argumentName,
  String? pathString, {
  bool optional = false,
}) {
  validatePathString(
    fnName,
    argumentName,
    pathString == null ? null : _stripInfo(pathString),
    optional: optional,
  );
}

/// Throws if [path] is under `.info`, which cannot be written.
void validateWritablePath(String fnName, Path path) {
  if (path.front?.name == '.info') {
    throw ArgumentError("$fnName failed = Can't modify data under /.info/");
  }
}
