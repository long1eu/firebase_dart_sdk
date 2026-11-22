/// Number rules shared by nodes, hashes, keys and query values. JS: `core/util/util.ts` (part:
/// `doubleToIEEE754String`, `tryParseInt`, `INTEGER_32_MIN/MAX`, `isInvalidJSONNumber`); Android:
/// `snapshot/LongNode.java`, `DoubleNode.java`, `core/utilities/Utilities.java` (part).
///
/// One rule on every platform: a value is an "integer" when it is integral and within the 53-bit
/// safe range, so hashes and ordering agree between the VM and the web. Nothing here relies on
/// `is int` or `is double`, which mean nothing on the web.
library;

import 'dart:typed_data';

/// The smallest 32-bit signed integer; integer-like keys must be at least this.
const int int32Min = -2147483648;

/// The largest 32-bit signed integer; integer-like keys must be at most this.
const int int32Max = 2147483647;

/// The largest integer a double represents exactly (2^53 - 1).
const int maxSafeInteger = 9007199254740991;

/// Whether [value] counts as an integer: integral and within plus or minus [maxSafeInteger].
bool isIntegral(num value) =>
    // The range check comes first: it is false for NaN and the infinities.
    value >= -maxSafeInteger && value <= maxSafeInteger && value % 1 == 0;

/// Returns [value] as an `int` when [isIntegral], otherwise as a `double`, identically on the VM
/// and the web.
///
/// This is the rule for values from the server and the cache: a negative zero stays the double
/// `-0.0` (its hash has the sign bit set, JS `util.ts` doubleToIEEE754String). Values the user
/// writes go through [normalizeUserNumber] instead.
num normalizeNumber(num value) {
  if (value == 0) {
    // 0, 0.0 or -0.0: keep the sign of a negative zero, as a double.
    return value.isNegative ? value.toDouble() : 0;
  }
  return isIntegral(value) ? value.toInt() : value.toDouble();
}

/// [normalizeNumber] for a value the user writes: a negative zero becomes `0`, so every platform
/// sends and stores `0` (JS `JSON.stringify(-0)` is `"0"`).
num normalizeUserNumber(num value) => value == 0 ? 0 : normalizeNumber(value);

/// Whether [value] is NaN or infinite, which JSON cannot carry.
bool isInvalidJsonNumber(Object? value) =>
    value is num && (value.isNaN || value.isInfinite);

final ByteData _ieeeScratch = ByteData(8);

const String _hexDigits = '0123456789abcdef';

/// The 16 hex characters of the IEEE 754 big-endian bits of [value], as the JS SDK hashes numbers.
String doubleToIeee754String(double value) {
  assert(!isInvalidJsonNumber(value), 'Invalid JSON number');
  _ieeeScratch.setFloat64(0, value);
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 8; i++) {
    final int byte = _ieeeScratch.getUint8(i);
    buffer
      ..write(_hexDigits[byte >> 4])
      ..write(_hexDigits[byte & 0xf]);
  }
  return buffer.toString();
}

/// Parses [key] as an integer-like key (`^-?(0*)\d{1,10}$` and within int32), or returns null.
///
/// Leading zeros and `-0` are integer-like, as in JS `tryParseInt` and Android
/// `Utilities.tryParseInt`.
int? tryParseIntKey(String key) {
  final int length = key.length;
  if (length == 0) {
    return null;
  }
  int i = 0;
  bool negative = false;
  if (key.codeUnitAt(0) == 0x2d /* - */ ) {
    if (length == 1) {
      return null;
    }
    negative = true;
    i = 1;
  }
  // `0*`: skip leading zeros, keeping at least one digit for `\d{1,10}`.
  while (i < length - 1 && key.codeUnitAt(i) == 0x30) {
    i++;
  }
  if (length - i > 10) {
    return null;
  }
  int value = 0;
  for (; i < length; i++) {
    final int digit = key.codeUnitAt(i) - 0x30;
    if (digit < 0 || digit > 9) {
      return null;
    }
    value = value * 10 + digit;
  }
  if (negative) {
    if (value == 0) {
      return 0;
    }
    value = -value;
    return value >= int32Min ? value : null;
  }
  return value <= int32Max ? value : null;
}

final RegExp _jsonNumber = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$');

/// Parses a JSON number as the server sends it, including the Java forms `1.0E21` and
/// `4.9E-324`, and normalises it with [normalizeNumber]; null when [text] is not a JSON number.
num? tryParseJsonNumber(String text) {
  if (!_jsonNumber.hasMatch(text)) {
    return null;
  }
  final double value = double.parse(text);
  if (value.isInfinite) {
    return null;
  }
  return normalizeNumber(value);
}
