/// The JSON value rules shared by both transports (spec 5.7): variables are checked before anything
/// is sent, results are normalised the same way on the VM and the web. No protobuf here.
library;

/// The largest integer a JSON number or a proto3 `Struct` double holds exactly: 2^53 − 1.
const int maxSafeInteger = 9007199254740991;

/// The deepest nesting of maps and lists in variables and results; the outermost map is depth 1.
const int maxDataDepth = 100;

/// [variables] checked against the value rules, as a fresh map.
///
/// Allowed values are `null`, `bool`, `int` within ±(2^53 − 1), finite `double`, `String`,
/// `List<Object?>` and `Map<String, Object?>`, nested at most [maxDataDepth] deep. Throws an
/// [ArgumentError] naming the path of the first value that breaks a rule
/// (`variables.items[3].count`), never the value.
Map<String, Object?> checkVariables(Map<Object?, Object?> variables) {
  return _checkedMap(variables, 'variables', 1);
}

Object? _checkedValue(Object? value, String path, int depth) {
  return switch (value) {
    null || bool() || String() => value,
    int() => _checkedInt(value, path),
    double() => _checkedDouble(value, path),
    Map<Object?, Object?>() => _checkedMap(value, path, depth),
    List<Object?>() => _checkedList(value, path, depth),
    _ => throw ArgumentError(
      'holds a ${value.runtimeType}; variables hold only null, bool, num, String, List and Map',
      path,
    ),
  };
}

int _checkedInt(int value, String path) {
  if (value > maxSafeInteger || value < -maxSafeInteger) {
    throw ArgumentError(
      'is an integer outside ±(2^53 − 1), which the server would round',
      path,
    );
  }
  return value;
}

double _checkedDouble(double value, String path) {
  if (!value.isFinite) {
    throw ArgumentError('is not a finite number', path);
  }
  return value;
}

Map<String, Object?> _checkedMap(
  Map<Object?, Object?> map,
  String path,
  int depth,
) {
  _checkDepth(path, depth);
  final Map<String, Object?> checked = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw ArgumentError('has a key that is not a String', path);
    }
    checked[key] = _checkedValue(entry.value, '$path.$key', depth + 1);
  }
  return checked;
}

List<Object?> _checkedList(List<Object?> list, String path, int depth) {
  _checkDepth(path, depth);
  final List<Object?> checked = <Object?>[];
  for (int i = 0; i < list.length; i++) {
    checked.add(_checkedValue(list[i], '$path[$i]', depth + 1));
  }
  return checked;
}

void _checkDepth(String path, int depth) {
  if (depth > maxDataDepth) {
    throw ArgumentError('nests deeper than $maxDataDepth levels', path);
  }
}

/// A result number as both transports hand it out: an `int` when [value] is integral and within
/// ±(2^53 − 1), else the `double`.
///
/// Throws a [FormatException] for a value that is not finite (the response is then
/// `invalid-response`).
num resultNumber(double value) {
  if (!value.isFinite) {
    throw const FormatException(
      'The response holds a number that is not finite.',
    );
  }
  if (value == value.truncateToDouble() && value.abs() <= maxSafeInteger) {
    return value.toInt();
  }
  return value;
}

/// A decoded JSON [data] object as a fresh `Map<String, Object?>`, with every integral double
/// within ±(2^53 − 1) turned into an `int` (spec 5.7 rule 4).
///
/// Throws a [FormatException] when it nests deeper than [maxDataDepth] or holds a value that is not
/// JSON.
Map<String, Object?> normalizedResult(Map<Object?, Object?> data) {
  return _normalizedMap(data, 1);
}

Object? _normalizedValue(Object? value, int depth) {
  return switch (value) {
    null || bool() || String() || int() => value,
    double() => resultNumber(value),
    Map<Object?, Object?>() => _normalizedMap(value, depth),
    List<Object?>() => _normalizedList(value, depth),
    _ => throw const FormatException(
      'The response holds a value that is not JSON.',
    ),
  };
}

Map<String, Object?> _normalizedMap(Map<Object?, Object?> map, int depth) {
  _checkResultDepth(depth);
  final Map<String, Object?> normalized = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw const FormatException(
        'The response holds a key that is not a string.',
      );
    }
    normalized[key] = _normalizedValue(entry.value, depth + 1);
  }
  return normalized;
}

List<Object?> _normalizedList(List<Object?> list, int depth) {
  _checkResultDepth(depth);
  return <Object?>[
    for (final Object? item in list) _normalizedValue(item, depth + 1),
  ];
}

void _checkResultDepth(int depth) {
  if (depth > maxDataDepth) {
    throw const FormatException('The response nests deeper than 100 levels.');
  }
}

/// A GraphQL error path from [raw]: each entry a `String` or an integral, non-negative number
/// within ±(2^53 − 1) (as an `int`). Anything else, including a [raw] that is not a list, gives
/// `[]`, and the error is kept (spec 5.7 rule 7).
List<Object> errorPathOf(Object? raw) {
  if (raw is! List<Object?>) {
    return const <Object>[];
  }
  final List<Object> path = <Object>[];
  for (final Object? entry in raw) {
    final Object? segment = switch (entry) {
      String() => entry,
      int() when entry >= 0 && entry <= maxSafeInteger => entry,
      double() when _isIndex(entry) => entry.toInt(),
      _ => null,
    };
    if (segment == null) {
      return const <Object>[];
    }
    path.add(segment);
  }
  return path;
}

bool _isIndex(double value) =>
    value.isFinite &&
    value >= 0 &&
    value <= maxSafeInteger &&
    value == value.truncateToDouble();

/// A deep copy of the JSON value [value]: fresh maps and lists, so that no two callers share one
/// (spec 5.7 rule 8).
Object? copyJson(Object? value) {
  return switch (value) {
    Map<Object?, Object?>() => <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key! as String: copyJson(entry.value),
    },
    List<Object?>() => <Object?>[
      for (final Object? item in value) copyJson(item),
    ],
    _ => value,
  };
}

/// A deep copy of the JSON object [data]; see [copyJson].
Map<String, Object?> copyJsonObject(Map<String, Object?> data) =>
    copyJson(data)! as Map<String, Object?>;
