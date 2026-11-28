import 'package:meta/meta.dart';

final RegExp _ttlPattern = RegExp(r'^([0-9]{1,9})(\.[0-9]{1,9})?s$');

/// The shortest lifetime accepted from the server: a shorter one would make every request an
/// exchange.
const int _minMilliseconds = 60 * 1000;

/// The longest lifetime kept: a longer one is cut to it.
const int _maxMilliseconds = 7 * 24 * 60 * 60 * 1000;

/// The lifetime in the `ttl` of an exchange response, or null when it must be refused.
///
/// [value] must be a string of the form `<1 to 9 digits>[.<1 to 9 digits>]s` (a protobuf duration,
/// ASCII digits only). Under 60 seconds gives null; over 7 days gives 7 days. Milliseconds are the
/// seconds times 1000 plus the first three fraction digits; further digits are dropped. The digits
/// are read as integers, the same on the VM, dart2js and dart2wasm.
@internal
Duration? parseTtl(Object? value) {
  if (value is! String) {
    return null;
  }
  final RegExpMatch? match = _ttlPattern.firstMatch(value);
  if (match == null) {
    return null;
  }
  final int seconds = int.parse(match.group(1)!);
  final String fraction = (match.group(2) ?? '.').substring(1);
  final String thousandths = fraction.padRight(3, '0').substring(0, 3);
  final int milliseconds = seconds * 1000 + int.parse(thousandths);
  if (milliseconds < _minMilliseconds) {
    return null;
  }
  if (milliseconds > _maxMilliseconds) {
    return const Duration(milliseconds: _maxMilliseconds);
  }
  return Duration(milliseconds: milliseconds);
}
