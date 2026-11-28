// Ported from FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/any_value.dart. Apache License 2.0; see NOTICE.

/// A value of the GraphQL `Any` type: any JSON value.
class AnyValue {
  /// Wraps [value].
  AnyValue(this.value);

  /// Wraps the decoded JSON value [json], unchanged.
  AnyValue.fromJson(dynamic json) : value = json;

  /// The wrapped value.
  dynamic value;

  /// The value as a JSON value: booleans, numbers and strings as they are, lists and maps
  /// converted element by element, any other object through its `toJson()` when it has one, and
  /// otherwise unchanged.
  dynamic toJson() {
    final dynamic current = value;
    if (current is bool || current is num || current is String) {
      return current;
    }
    if (current is List) {
      return current.map((dynamic e) => AnyValue(e).toJson()).toList();
    }
    if (current is Map) {
      return convertMap(current as Map<String, dynamic>);
    }
    try {
      return current.toJson();
    } on NoSuchMethodError {
      return current;
    }
  }
}

/// [map] with every value that is not a string converted by [AnyValue.toJson].
Map<String, dynamic> convertMap(Map<String, dynamic> map) {
  return map.map((String key, dynamic value) {
    if (value is String) {
      return MapEntry<String, dynamic>(key, value);
    }
    return MapEntry<String, dynamic>(key, AnyValue(value).toJson());
  });
}

/// Serializes [v] through its `toJson()`.
dynamic defaultSerializer(dynamic v) => v.toJson();
