/// Number rules shared by nodes, hashes, keys and query values. JS: `core/util/util.ts` (part:
/// `doubleToIEEE754String`, `tryParseInt`, `INTEGER_32_MIN/MAX`, `isInvalidJSONNumber`); Android:
/// `snapshot/LongNode.java`, `DoubleNode.java`, `core/utilities/Utilities.java` (part).
///
/// The server keeps the number it was given, so the client does too: an `int` stays an `int`
/// (the VM and wasm keep all 64 bits); a `double` that is integral and within the 53-bit safe
/// range reads as an `int`; negative zero, fractions and larger doubles stay doubles. Hashes go
/// through the double form on every platform. On the web every number is a double, so `is int`
/// alone decides nothing here.
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

/// The stored form of [value]: an `int` is returned as it is, also beyond [maxSafeInteger] (the
/// server stores 64-bit integers exactly); a `double` becomes an `int` when [isIntegral] and not
/// negative zero; every other `double` is returned as it is.
///
/// This is the rule for values from the server and the cache: a negative zero stays the double
/// `-0.0` (its hash has the sign bit set, JS `util.ts` doubleToIEEE754String). Values the user
/// writes go through [normalizeUserNumber] instead.
num normalizeNumber(num value) {
  // False on the VM and wasm for an int; true for every number on the web.
  if (value is! double) {
    return value;
  }
  if (value == 0) {
    // 0.0 or -0.0: keep the sign of a negative zero, as a double.
    return value.isNegative ? value : 0;
  }
  return isIntegral(value) ? value.toInt() : value;
}

/// [normalizeNumber] for a value the user writes: a negative zero becomes `0`, so every platform
/// sends and stores `0` (JS `JSON.stringify(-0)` is `"0"`).
num normalizeUserNumber(num value) => value == 0 ? 0 : normalizeNumber(value);

/// Compares two stored numbers as the server orders them: exactly, also beyond [maxSafeInteger]
/// (measured: orderByValue separates 9007199254740992 and 9007199254740993). Negative zero equals
/// zero. Returns -1, 0 or 1.
///
/// On the VM and wasm two ints are compared as ints, and an int against a double without
/// rounding the int. On the web every number is a double, so such values compare as equal there.
int compareNumbers(num a, num b) {
  if (a is int && b is int) {
    return a < b ? -1 : (a == b ? 0 : 1);
  }
  if (a is int) {
    return _compareIntToDouble(a, b.toDouble());
  }
  if (b is int) {
    return -_compareIntToDouble(b, a.toDouble());
  }
  return a < b ? -1 : (a == b ? 0 : 1);
}

int _compareIntToDouble(int i, double d) {
  final double rounded = i.toDouble();
  if (rounded != d) {
    return rounded < d ? -1 : 1;
  }
  // Equal after rounding: decide on the exact integers. 2^63 and beyond is above every int.
  if (d >= 9223372036854775808.0) {
    return -1;
  }
  final int exact = d.toInt();
  return i < exact ? -1 : (i == exact ? 0 : 1);
}

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

final RegExp _fractionOrExponent = RegExp('[.eE]');

final RegExp _jsonNumber = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$');

/// Parses a JSON number as the server sends it, including the Java forms `1.0E21` and
/// `4.9E-324`, and normalises it with [normalizeNumber]; null when [text] is not a JSON number.
num? tryParseJsonNumber(String text) {
  if (!_jsonNumber.hasMatch(text)) {
    return null;
  }
  if (!text.contains(_fractionOrExponent)) {
    // Integer form: exact on the VM up to 64 bits; larger values fall through to a double.
    final int? integer = int.tryParse(text);
    // "-0" goes on to the double path, which keeps the sign.
    if (integer != null && integer != 0) {
      return normalizeNumber(integer);
    }
  }
  final double value = double.parse(text);
  if (value.isInfinite) {
    return null;
  }
  return normalizeNumber(value);
}
