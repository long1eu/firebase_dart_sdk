import 'package:firebase_remote_config_dart/src/value.dart';

/// The most custom signals after a merge (`JS-RC/constants.ts:19-21`).
const int maxSignals = 100;

/// The longest key of a custom signal, in characters.
const int maxSignalKeyLength = 250;

/// The longest string value of a custom signal, in characters.
const int maxSignalValueLength = 500;

/// Checks the changes given to `setCustomSignals` and renders their values as text.
///
/// A null value stays null (it removes the key). Throws an [ArgumentError] naming the limit and the
/// position of the entry in [changes], never its text: for a key that is empty or longer than
/// [maxSignalKeyLength], a value that is not a `String`, `int` or finite `double`, or a string longer
/// than [maxSignalValueLength].
Map<String, String?> normalizeSignalChanges(Map<String, Object?> changes) {
  final Map<String, String?> result = <String, String?>{};
  int position = 0;
  for (final MapEntry<String, Object?> entry in changes.entries) {
    final String key = entry.key;
    if (key.isEmpty || key.length > maxSignalKeyLength) {
      throw ArgumentError(
        'The custom signal at position $position has a key that is not 1-$maxSignalKeyLength '
        'characters long.',
      );
    }
    result[key] = _render(entry.value, position);
    position++;
  }
  return result;
}

String? _render(Object? value, int position) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    if (value.length > maxSignalValueLength) {
      throw ArgumentError(
        'The custom signal at position $position has a string value longer than '
        '$maxSignalValueLength characters.',
      );
    }
    return value;
  }
  if (value is num && value.isFinite) {
    return renderNumber(value);
  }
  throw ArgumentError(
    'The custom signal at position $position has a value that is not a String, an int or a finite '
    'double.',
  );
}

/// [current] with [changes] applied: a null value removes its key, others replace or add.
Map<String, String> mergeSignals(
  Map<String, String> current,
  Map<String, String?> changes,
) {
  final Map<String, String> merged = Map<String, String>.of(current);
  for (final MapEntry<String, String?> entry in changes.entries) {
    final String? value = entry.value;
    if (value == null) {
      merged.remove(entry.key);
    } else {
      merged[entry.key] = value;
    }
  }
  return merged;
}

/// True when [signals] respects every limit of 5.8.
bool withinSignalLimits(Map<String, String> signals) {
  if (signals.length > maxSignals) {
    return false;
  }
  for (final MapEntry<String, String> entry in signals.entries) {
    if (entry.key.isEmpty ||
        entry.key.length > maxSignalKeyLength ||
        entry.value.length > maxSignalValueLength) {
      return false;
    }
  }
  return true;
}
