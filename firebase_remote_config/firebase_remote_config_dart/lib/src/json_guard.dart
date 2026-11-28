import 'dart:convert';

/// The deepest nesting of arrays and objects the client decodes.
const int maxJsonDepth = 32;

/// True when [units] (bytes, or UTF-16 code units of a string) nest brackets outside JSON strings deeper
/// than [maxDepth].
///
/// It runs before decoding, so a hostile body cannot make the decoder recurse deeply.
bool exceedsJsonDepth(List<int> units, {int maxDepth = maxJsonDepth}) {
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (final int unit in units) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        inString = false;
      }
      continue;
    }
    if (unit == 0x22) {
      inString = true;
    } else if (unit == 0x5b || unit == 0x7b) {
      depth++;
      if (depth > maxDepth) {
        return true;
      }
    } else if (unit == 0x5d || unit == 0x7d) {
      depth--;
    }
  }
  return false;
}

/// Decodes [bytes] as strict UTF-8 JSON after the depth scan. Throws a [FormatException] for a body that
/// is too deep, not UTF-8 or not JSON.
Object? decodeGuardedBytes(List<int> bytes) {
  if (exceedsJsonDepth(bytes)) {
    throw const FormatException('The JSON nests deeper than 32 levels.');
  }
  return jsonDecode(utf8.decode(bytes));
}

/// Decodes [text] as JSON after the depth scan. Throws a [FormatException] for text that is too deep or
/// not JSON.
Object? decodeGuardedText(String text) {
  if (exceedsJsonDepth(text.codeUnits)) {
    throw const FormatException('The JSON nests deeper than 32 levels.');
  }
  return jsonDecode(text);
}

/// [value] as a JSON object, or null.
Map<String, Object?>? asObject(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  return null;
}

/// [value] as a JSON object of string to string, or null when it is not one or a value is not a string.
Map<String, String>? asStringMap(Object? value) {
  if (value is! Map<String, Object?>) {
    return null;
  }
  final Map<String, String> result = <String, String>{};
  for (final MapEntry<String, Object?> entry in value.entries) {
    final Object? text = entry.value;
    if (text is! String) {
      return null;
    }
    result[entry.key] = text;
  }
  return result;
}

/// [value] as a JSON array of strings, or null when it is not one or an element is not a string.
List<String>? asStringList(Object? value) {
  if (value is! List<Object?>) {
    return null;
  }
  final List<String> result = <String>[];
  for (final Object? element in value) {
    if (element is! String) {
      return null;
    }
    result.add(element);
  }
  return result;
}

/// True when [object] has no [key], or its value is a string.
bool isOptionalString(Map<String, Object?> object, String key) =>
    !object.containsKey(key) || object[key] is String;

/// True when [text] holds only ASCII digits and is not empty.
bool isDigits(String text) {
  if (text.isEmpty) {
    return false;
  }
  for (final int unit in text.codeUnits) {
    if (unit < 0x30 || unit > 0x39) {
      return false;
    }
  }
  return true;
}
