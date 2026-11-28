import 'dart:convert';

/// The default deepest nesting of arrays and objects the decoders accept.
const int maxJsonDepth = 32;

/// True when [units] nest brackets outside JSON strings deeper than [maxDepth].
///
/// [units] are the bytes of UTF-8 JSON, or the UTF-16 code units of a JSON string: the scan looks
/// only at ASCII brackets, quotes and backslashes, which are the same in both. It runs before
/// decoding, so a hostile body cannot make the decoder recurse deeply. [maxDepth] must not be
/// negative.
bool exceedsJsonDepth(List<int> units, {int maxDepth = maxJsonDepth}) {
  assert(maxDepth >= 0, 'maxDepth must not be negative');
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

/// Decodes [bytes] as strict UTF-8 JSON after the depth scan.
///
/// Throws `FormatException('The JSON nests deeper than <maxDepth> levels.')` past [maxDepth], and
/// the decoder's [FormatException] for bytes that are not UTF-8 or not JSON.
Object? decodeGuardedBytes(List<int> bytes, {int maxDepth = maxJsonDepth}) {
  if (exceedsJsonDepth(bytes, maxDepth: maxDepth)) {
    throw _tooDeep(maxDepth);
  }
  return jsonDecode(utf8.decode(bytes));
}

/// Decodes [text] as JSON after the depth scan.
///
/// Throws `FormatException('The JSON nests deeper than <maxDepth> levels.')` past [maxDepth], and
/// the decoder's [FormatException] for text that is not JSON.
Object? decodeGuardedText(String text, {int maxDepth = maxJsonDepth}) {
  if (exceedsJsonDepth(text.codeUnits, maxDepth: maxDepth)) {
    throw _tooDeep(maxDepth);
  }
  return jsonDecode(text);
}

FormatException _tooDeep(int maxDepth) =>
    FormatException('The JSON nests deeper than $maxDepth levels.');
