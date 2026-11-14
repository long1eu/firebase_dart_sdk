// File created by
// Lung Razvan <long1eu>
// on 14/11/2026

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';

/// Returns the canonical string of [value], the part of the canonical id of a query that stands for a value (the JS
/// `canonifyValue` in `model/values.ts`).
///
/// The canonical id of a query is stored in the cache, so this string must never change for a value. It is built
/// here explicitly and does not use the `toString` of any value. The strings are the ones of the JS SDK; the values
/// that the backend stores as maps with a reserved key (vectors, the BSON types, pending server timestamps) are
/// written as those maps, as JS does.
String canonifyValue(FieldValue value) {
  if (value is NullValue) {
    return 'null';
  } else if (value is BoolValue) {
    return value.value ? 'true' : 'false';
  } else if (value is IntegerValue) {
    return _integer(value.value);
  } else if (value is DoubleValue) {
    return canonifyDouble(value.value);
  } else if (value is TimestampValue) {
    return _time(value.value.seconds, value.value.nanoseconds);
  } else if (value is StringValue) {
    return value.value;
  } else if (value is BlobValue) {
    final int subtype = value.value.subtype;
    if (subtype == 0) {
      return base64Encode(value.value.bytes);
    }
    // BSON binary data: the subtype is the first byte of the stored bytes.
    return _map(<String, String>{
      BsonKeys.binary: base64Encode(<int>[subtype, ...value.value.bytes]),
    });
  } else if (value is ReferenceValue) {
    return value.key.path.canonicalString;
  } else if (value is GeoPointValue) {
    return 'geo(${canonifyDouble(value.value.latitude)},'
        '${canonifyDouble(value.value.longitude)})';
  } else if (value is ArrayValue) {
    return '[${value.internalValue.map(canonifyValue).join(',')}]';
  } else if (value is ObjectValue) {
    // The entries of the map are sorted by key.
    return _map(<String, String>{
      for (final MapEntry<String, FieldValue> entry in value.internalValue)
        entry.key: canonifyValue(entry.value),
    });
  } else if (value is VectorFieldValue) {
    return _map(<String, String>{
      VectorFieldValue.typeKey: VectorFieldValue.vectorTypeValue,
      VectorFieldValue.vectorKey:
          '[${value.value.toArray().map(canonifyDouble).join(',')}]',
    });
  } else if (value is ServerTimestampValue) {
    final FieldValue? previous = value.previousFieldValue;
    return _map(<String, String>{
      '__local_write_time__': _time(
        value.localWriteTime.seconds,
        value.localWriteTime.nanoseconds,
      ),
      if (previous != null) '__previous_value__': canonifyValue(previous),
      '__type__': 'server_timestamp',
    });
  } else if (value is MinKeyValue) {
    return _map(<String, String>{BsonKeys.minKey: 'null'});
  } else if (value is MaxKeyValue) {
    return _map(<String, String>{BsonKeys.maxKey: 'null'});
  } else if (value is Int32FieldValue) {
    return _map(<String, String>{BsonKeys.int32: _integer(value.intValue)});
  } else if (value is Decimal128FieldValue) {
    return _map(<String, String>{BsonKeys.decimal128: value.value.stringValue});
  } else if (value is BsonObjectIdValue) {
    return _map(<String, String>{BsonKeys.objectId: value.value.value});
  } else if (value is BsonTimestampValue) {
    return _map(<String, String>{
      BsonKeys.timestamp: _map(<String, String>{
        BsonKeys.timestampIncrement: _integer(value.value.increment),
        BsonKeys.timestampSeconds: _integer(value.value.seconds),
      }),
    });
  } else if (value is RegexFieldValue) {
    return _map(<String, String>{
      BsonKeys.regex: _map(<String, String>{
        BsonKeys.regexOptions: value.value.options,
        BsonKeys.regexPattern: value.value.pattern,
      }),
    });
  } else if (value is InternalMaxValue) {
    return _map(<String, String>{'__type__': '__max__'});
  }
  throw ArgumentError('Invalid value type: ${value.runtimeType}');
}

/// The string of a number in JS (`'' + value`), which the JS SDK uses for doubles: a double without a fraction has no
/// `.0`, and -0 is `0`.
String canonifyDouble(double value) {
  if (value.isNaN) {
    return 'NaN';
  } else if (value.isInfinite) {
    return value.isNegative ? '-Infinity' : 'Infinity';
  } else if (value == 0) {
    return '0';
  }
  // Both languages print the shortest digits that read back as the same double, and switch to the exponent form
  // at the same magnitudes. Dart adds `.0` to a double without a fraction.
  final String text = '$value';
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

// The digits of an integer; an explicit radix keeps this independent of `int.toString()`.
String _integer(int value) => value.toRadixString(10);

String _time(int seconds, int nanos) =>
    'time(${_integer(seconds)},${_integer(nanos)})';

/// [entries] in the order of their keys, as `{key:value,...}`.
String _map(Map<String, String> entries) {
  final List<String> keys = entries.keys.toList()..sort();
  return '{${keys.map((String key) => '$key:${entries[key]}').join(',')}}';
}
