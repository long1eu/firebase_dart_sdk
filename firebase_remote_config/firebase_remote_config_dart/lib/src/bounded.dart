/// The largest integer that the VM, dart2js and dart2wasm all represent exactly: 2^53 − 1.
const int maxSafeInteger = 9007199254740991;

/// The largest millisecond count, either side of the epoch, that [DateTime] accepts: 8.64e15.
///
/// Every stored time is read with this bound, so building its [DateTime] cannot throw.
const int maxDateMillis = 8640000000000000;

/// Reads an integer from the server or from a store, the same way on the VM, dart2js and dart2wasm.
///
/// Returns the value when [value] is a JSON number with no fractional part, or a string of ASCII digits,
/// within [min] and [max] (inclusive); returns null for anything else: fractions, signs, hex,
/// whitespace, an empty string, non-finite numbers, values out of range and other types.
///
/// A JSON number is checked by value, not by its text: `1.0` and `1e3` decode to the same number as `1`
/// and `1000` on the web, so they are accepted on every platform. [min] and [max] must be within
/// ±[maxSafeInteger].
int? parseBoundedInt(Object? value, {required int min, required int max}) {
  if (value is String) {
    return _parseDigits(value, min, max);
  }
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) {
      return null;
    }
    if (value < min || value > max) {
      return null;
    }
    return value.toInt();
  }
  return null;
}

int? _parseDigits(String text, int min, int max) {
  // 2^53 − 1 has 16 digits; a longer string is out of every allowed range.
  if (text.isEmpty || text.length > 16) {
    return null;
  }
  for (final int unit in text.codeUnits) {
    if (unit < 0x30 || unit > 0x39) {
      return null;
    }
  }
  final int? parsed = int.tryParse(text);
  if (parsed == null || parsed < min || parsed > max) {
    return null;
  }
  return parsed;
}
