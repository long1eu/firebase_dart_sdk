part of 'expression_evaluator.dart';

// ---- maps ----

Map<String, FieldValue> _entries(FieldValue map) => <String, FieldValue>{
  for (final MapEntry<String, FieldValue> entry
      in (map as ObjectValue).internalValue)
    entry.key: entry.value,
};

/// `map_get(map, key)`: a key that is not in the map has no value.
EvaluateResult _mapGet(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isMap, _isString],
  (List<FieldValue> v) {
    final FieldValue? value = (v[0] as ObjectValue).internalValue[_text(v[1])];
    return value == null ? _unset : EvaluateValue(value);
  },
);

/// `get_field(value, key)`: like `map_get`, but a value that is not a map
/// simply has no such field.
EvaluateResult _getField(_Call call) {
  if (call.length != 2) {
    return _error;
  }
  final EvaluateResult map = call.arg(0);
  final EvaluateResult key = call.arg(1);
  if (map.isError || key.isError) {
    return _error;
  }
  final FieldValue? keyValue = key.value;
  if (_isNull(keyValue)) {
    return _null;
  } else if (keyValue is! StringValue) {
    return _error;
  }
  final FieldValue? mapValue = map.value;
  if (mapValue is! ObjectValue) {
    return _unset;
  }
  final FieldValue? value = mapValue.internalValue[keyValue.value];
  return value == null ? _unset : EvaluateValue(value);
}

/// `map_keys`, `map_values` and `map_entries`, in the order of the keys.
_Function _mapParts(FieldValue Function(String key, FieldValue value) part) {
  return (_Call call) => _strict(call, <bool Function(FieldValue)?>[_isMap], (
    List<FieldValue> v,
  ) {
    final List<MapEntry<String, FieldValue>> entries =
        _entries(v[0]).entries.toList()..sort(
          (MapEntry<String, FieldValue> a, MapEntry<String, FieldValue> b) =>
              compareUtf8Strings(a.key, b.key),
        );
    return _list(<FieldValue>[
      for (final MapEntry<String, FieldValue> entry in entries)
        part(entry.key, entry.value),
    ]);
  });
}

EvaluateResult _mapMerge(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isMap],
  min: 2,
  (List<FieldValue> v) => EvaluateValue(
    ObjectValue.fromMap(<String, FieldValue>{
      for (final FieldValue map in v) ..._entries(map),
    }),
  ),
);

EvaluateResult _mapRemove(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isMap, _isString],
  (List<FieldValue> v) =>
      EvaluateValue(ObjectValue.fromMap(_entries(v[0])..remove(_text(v[1])))),
);

/// `map_set(map, key, value)`: the map with the value under the key. A
/// value that is missing removes the key. Like `get_field`, anything that is
/// not a map has no fields to set: the result is missing too.
EvaluateResult _mapSet(_Call call) {
  if (call.length != 3) {
    return _error;
  }
  final EvaluateResult mapResult = call.arg(0);
  if (mapResult.isError) {
    return _error;
  }
  final FieldValue? map = mapResult.value;
  if (map is! ObjectValue) {
    return _unset;
  }
  final EvaluateResult keyResult = call.arg(1);
  final EvaluateResult valueResult = call.arg(2);
  if (keyResult.isError || valueResult.isError) {
    return _error;
  }
  final FieldValue? key = keyResult.value;
  if (_isNull(key)) {
    return _null;
  } else if (key is! StringValue) {
    return _error;
  }
  final Map<String, FieldValue> entries = _entries(map);
  final FieldValue? value = valueResult.value;
  if (value == null) {
    entries.remove(key.value);
  } else {
    entries[key.value] = value;
  }
  return EvaluateValue(ObjectValue.fromMap(entries));
}

final Map<String, _Function> _mapFunctions = <String, _Function>{
  'map_get': _mapGet,
  'get_field': _getField,
  'map_keys': _mapParts(
    (String key, FieldValue value) => StringValue.valueOf(key),
  ),
  'map_values': _mapParts((String key, FieldValue value) => value),
  'map_entries': _mapParts(
    (String key, FieldValue value) => ObjectValue.fromMap(<String, FieldValue>{
      'k': StringValue.valueOf(key),
      'v': value,
    }),
  ),
  'map_merge': _mapMerge,
  'map_remove': _mapRemove,
  'map_set': _mapSet,
};
