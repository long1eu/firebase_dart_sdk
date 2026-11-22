/// The checks and conversions every user value goes through at the API edge before it reaches Repo.
/// JS: `core/util/validation.ts` (`validateFirebaseDataArg`, `validatePriority`); Android:
/// `utilities/Validation.java`, `core/ServerValues.java` (the server value forms).
///
/// Package-internal: no public library exports this file.
library;

import 'package:firebase_database_dart/src/api/firebase_database_exception.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';

/// [value] with every number passed through [normalizeUserNumber] (so a `-0.0` is sent as 0 and an
/// integral `5.0` is stored as the `int` 5), as a fresh copy: maps become `Map<String, Object?>` and
/// lists `List<Object?>`.
Object? normalizeUserValue(Object? value) => switch (value) {
  final num n => normalizeUserNumber(n),
  final Map<Object?, Object?> m => <String, Object?>{
    for (final MapEntry<Object?, Object?> e in m.entries)
      '${e.key}': normalizeUserValue(e.value),
  },
  final List<Object?> l => <Object?>[
    for (final Object? e in l) normalizeUserValue(e),
  ],
  _ => value,
};

/// Throws an [ArgumentError] for a map anywhere in [data] that has a `.sv` key but is not exactly
/// `{'.sv': 'timestamp'}` or `{'.sv': {'increment': <finite number>}}`, so a server value the client
/// cannot resolve never reaches the write tree, the cache or the server.
void validateServerValues(
  String fnName,
  Object? data, [
  String argName = 'value',
]) {
  if (data is Map) {
    if (data.containsKey('.sv')) {
      if (!_isServerValue(data)) {
        throw ArgumentError(
          '$fnName failed: $argName argument contains an invalid server value '
          '($data). Only ServerValue.timestamp ({".sv": "timestamp"}) and '
          'ServerValue.increment ({".sv": {"increment": <number>}}) are allowed.',
        );
      }
      return;
    }
    for (final Object? child in data.values) {
      validateServerValues(fnName, child, argName);
    }
  } else if (data is List) {
    for (final Object? child in data) {
      validateServerValues(fnName, child, argName);
    }
  }
}

bool _isServerValue(Map<Object?, Object?> map) {
  if (map.length != 1) {
    return false;
  }
  final Object? op = map['.sv'];
  if (op == 'timestamp') {
    return true;
  }
  if (op is Map && op.length == 1) {
    final Object? delta = op['increment'];
    return delta is num && delta.isFinite;
  }
  return false;
}

/// Validates a value written at [path] by [fnName]: the JS data rules plus the server value forms.
void validateUserValue(String fnName, Object? value, Path path) {
  validateFirebaseDataArg(fnName, value, path);
  validateServerValues(fnName, value);
}

/// Validates a priority argument of [fnName]: the JS priority rules plus the server value forms.
void validateUserPriority(String fnName, Object? priority) {
  validatePriority(fnName, priority);
  validateServerValues(fnName, priority, 'priority');
}

/// Validates the map of an `update` at [path] by [fnName]: the JS merge rules (keys, overlapping
/// paths, `.priority` values) plus the server value forms.
void validateUserMerge(String fnName, Map<String, Object?> values, Path path) {
  validateFirebaseMergeDataArg(fnName, values, path);
  validateServerValues(fnName, values, 'values');
}

/// The node of a validated user [value], with [priority] when not null, numbers normalised.
Node userValueNode(Object? value, [Object? priority]) => nodeFromJson(
  normalizeUserValue(value),
  priority == null ? null : normalizeUserValue(priority),
);

/// Throws an [ArgumentError] when [path] ends in `.length` or `.keys`, which JS treats as read only.
void validateNotReadOnlyKey(String fnName, Path path) {
  final String? key = path.back?.name;
  if (key == '.length' || key == '.keys') {
    throw ArgumentError('$fnName failed: $key is a read-only object.');
  }
}

/// The public form of an error that crossed from the core: a [DatabaseError] or a
/// [ServerActionsException] becomes a [FirebaseDatabaseException]; anything else is returned as it
/// is.
Object toApiError(Object error) => switch (error) {
  final DatabaseError e => exceptionFromDatabaseError(e),
  final ServerActionsException e => exceptionFromServerStatus(
    e.status,
    e.reason,
  ),
  _ => error,
};
