/// The digits of the longest string [parseBoundedInt] reads: 2^53 − 1 has 16 digits, so a longer
/// string is out of every allowed range. A 16-digit value above 2^53 − 1 may round on the web, but it
/// rounds to a value that still fails the range check.
const int _maxDigits = 16;

final RegExp _digits = RegExp(r'^[0-9]+$');

/// The integer [value] holds when it is within [min] to [max] (inclusive), else null.
///
/// [value] is a number from JSON or a string of ASCII digits. A number counts when it is finite and has
/// no fractional part (on the web every JSON number is a double, so `1.0` cannot be told from `1`); a
/// string counts when it is 1 to 16 ASCII digits. Fractions, exponents in strings, signs, hex,
/// whitespace, non-finite values and values out of range give null, on the VM and on the web alike.
int? parseBoundedInt(Object? value, {required int min, required int max}) {
  final int? parsed;
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) {
      return null;
    }
    if (value < -9007199254740991 || value > 9007199254740991) {
      return null;
    }
    parsed = value.toInt();
  } else if (value is String) {
    if (value.length > _maxDigits || !_digits.hasMatch(value)) {
      return null;
    }
    parsed = int.parse(value);
    if (parsed > 9007199254740991) {
      return null;
    }
  } else {
    return null;
  }
  if (parsed < min || parsed > max) {
    return null;
  }
  return parsed;
}
