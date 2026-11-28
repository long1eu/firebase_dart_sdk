/// The value encoding of the callable protocol: raw JSON in requests (§5.5), 64-bit wrappers
/// decoded in responses (§5.6).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions_dart/src/platform.dart';

/// The deepest nesting of lists and maps sent or read.
const int maxValueDepth = 512;

const String _int64Type = 'type.googleapis.com/google.protobuf.Int64Value';
const String _uint64Type = 'type.googleapis.com/google.protobuf.UInt64Value';

final RegExp _signedDigits = RegExp(r'^-?[0-9]{1,20}$');
final RegExp _unsignedDigits = RegExp(r'^[0-9]{1,20}$');
final BigInt _int64Min = BigInt.parse('-9223372036854775808');
final BigInt _int64Max = BigInt.parse('9223372036854775807');
final BigInt _jsSafeMax = BigInt.parse('9007199254740991');

/// The UTF-8 bytes of `{"data": <data encoded>}`, the body of every call (§5.4 rule 3).
///
/// Throws the [ArgumentError] of [encodeValue].
Uint8List encodeRequestBody(Object? data) {
  final StringBuffer out = StringBuffer('{"data":');
  _write(out, data, 'data', 0);
  out.write('}');
  return utf8.encode(out.toString());
}

/// The JSON text of [value] as the callable protocol sends it (§5.5).
///
/// Accepts `null`, `bool`, `String`, finite `num`, `List` and `Map` with `String` keys, nested at
/// most [maxValueDepth] levels. A whole `double` whose absolute value is below 1e21 (and `-0.0`)
/// is written as its integer digits, as `JSON.stringify` writes it, on every compiler; any other
/// number goes through `jsonEncode`. No 64-bit wrapper is ever written.
///
/// Throws an [ArgumentError] naming the path (`data.items[3].name`) and the type, never the value,
/// for anything else.
String encodeValue(Object? value) {
  final StringBuffer out = StringBuffer();
  _write(out, value, 'data', 0);
  return out.toString();
}

void _write(StringBuffer out, Object? value, String path, int depth) {
  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value ? 'true' : 'false');
    case String():
      out.write(jsonEncode(value));
    case num():
      out.write(_numberText(value, path));
    case List<Object?>():
      _writeList(out, value, path, _deeper(depth));
    case Map<Object?, Object?>():
      _writeMap(out, value, path, _deeper(depth));
    default:
      throw ArgumentError(
        'Cannot encode a ${value.runtimeType} at $path; use JSON types '
        '(null, bool, num, String, List, Map<String, …>).',
      );
  }
}

/// Non-finite numbers are refused first: on dart2js an infinity passes `is int`.
String _numberText(num value, String path) {
  if (value.isNaN || value.isInfinite) {
    throw ArgumentError('Cannot encode a non-finite number at $path.');
  }
  // On dart2js a whole number is also a double, so this branch covers every whole number there,
  // and -0.0 too (jsonEncode would write "-0.0"). BigInt gives the exact digits of a whole double.
  if (value is double &&
      value == value.truncateToDouble() &&
      value.abs() < 1e21) {
    return BigInt.from(value).toString();
  }
  return jsonEncode(value);
}

int _deeper(int depth) {
  final int next = depth + 1;
  if (next > maxValueDepth) {
    throw ArgumentError('Data is nested more than $maxValueDepth levels deep.');
  }
  return next;
}

void _writeList(StringBuffer out, List<Object?> list, String path, int depth) {
  out.write('[');
  for (int index = 0; index < list.length; index++) {
    if (index > 0) {
      out.write(',');
    }
    _write(out, list[index], '$path[$index]', depth);
  }
  out.write(']');
}

void _writeMap(
  StringBuffer out,
  Map<Object?, Object?> map,
  String path,
  int depth,
) {
  out.write('{');
  bool first = true;
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw ArgumentError('Map keys must be strings at $path.');
    }
    if (!first) {
      out.write(',');
    }
    first = false;
    out
      ..write(jsonEncode(key))
      ..write(':');
    _write(out, entry.value, '$path.$key', depth);
  }
  out.write('}');
}

/// A value of a response the decoder refuses (§5.6 rule 4); mapped to `internal`, "Response
/// contains an invalid value.".
final class InvalidValueException implements Exception {
  /// The value is invalid.
  const InvalidValueException();

  @override
  String toString() => 'InvalidValueException';
}

/// [value], as `jsonDecode` gave it, with every 64-bit wrapper replaced by its `int` (§5.6 rules
/// 3-4).
///
/// Maps become `Map<String, Object?>` and lists `List<Object?>`; a map whose `@type` is not one of
/// the two wrapper types stays a map. Numbers keep the type `jsonDecode` gave them. The caller has
/// already bounded the nesting (`exceedsJsonDepth`).
///
/// Throws [InvalidValueException] for a wrapper whose `value` is not a decimal string within the
/// range the platform holds exactly, and for a map key that is not a string.
Object? decodeValue(Object? value) {
  switch (value) {
    case Map<Object?, Object?>():
      final Object? type = value['@type'];
      if (type == _int64Type || type == _uint64Type) {
        return _unwrap(value['value'], unsigned: type == _uint64Type);
      }
      return _decodeMap(value);
    case List<Object?>():
      return <Object?>[
        for (final Object? element in value) decodeValue(element),
      ];
    default:
      return value;
  }
}

Map<String, Object?> _decodeMap(Map<Object?, Object?> map) {
  final Map<String, Object?> decoded = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw const InvalidValueException();
    }
    decoded[key] = decodeValue(entry.value);
  }
  return decoded;
}

/// UInt64Value must be at most 2^63 − 1, because a Dart `int` is signed; on dart2js both types
/// must be within ±(2^53 − 1). Parsed through [BigInt] so the rule is the same on every compiler.
int _unwrap(Object? text, {required bool unsigned}) {
  final RegExp pattern = unsigned ? _unsignedDigits : _signedDigits;
  if (text is! String || !pattern.hasMatch(text)) {
    throw const InvalidValueException();
  }
  final BigInt number = BigInt.parse(text);
  if (number < _int64Min || number > _int64Max) {
    throw const InvalidValueException();
  }
  if (jsNumbers && number.abs() > _jsSafeMax) {
    throw const InvalidValueException();
  }
  return number.toInt();
}
