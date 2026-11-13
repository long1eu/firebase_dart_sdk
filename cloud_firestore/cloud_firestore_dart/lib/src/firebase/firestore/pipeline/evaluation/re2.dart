// The regular expressions of the backend are RE2 expressions; Dart has its
// own dialect. This file translates the first to the second, as far as that
// is possible.

/// Thrown for a pattern RE2 rejects.
class InvalidPattern implements Exception {
  const InvalidPattern();
}

/// Thrown for a valid RE2 pattern that has no Dart equivalent here.
class UnsupportedPattern implements Exception {
  UnsupportedPattern(this.message);

  final String message;
}

const Map<String, String> _posixClasses = <String, String>{
  'alnum': '0-9A-Za-z',
  'alpha': 'A-Za-z',
  'ascii': r'\x00-\x7F',
  'blank': r'\t ',
  'cntrl': r'\x00-\x1F\x7F',
  'digit': '0-9',
  'graph': '!-~',
  'lower': 'a-z',
  'print': ' -~',
  'punct': r'!-\/:-@\[-`{-~',
  'space': r'\t\n\v\f\r ',
  'upper': 'A-Z',
  'word': '0-9A-Za-z_',
  'xdigit': '0-9A-Fa-f',
};

final RegExp _letter = RegExp('[A-Za-z]');
final RegExp _repetition = RegExp(r'^\d+(,\d*)?$');

/// The characters a Dart regular expression in Unicode mode lets a backslash
/// escape as themselves.
const String _syntaxCharacters = r'^$\.*+?()[]{}|/';

String _literal(int rune, {required bool inClass}) {
  final String character = String.fromCharCode(rune);
  if (_syntaxCharacters.contains(character) || (inClass && character == '-')) {
    return '\\$character';
  }
  return character;
}

/// Compiles the RE2 [pattern] to a Dart [RegExp] that matches the same
/// strings.
///
/// Like RE2, the result has no backreferences and no lookaround (a pattern
/// with them is an [InvalidPattern]), `.` matches everything but a line
/// feed, and `\d`, `\w`, `\s` and `\b` are about ASCII only.
///
/// Flags are only understood at the very start of the pattern (`(?i)`,
/// `(?s)`, `(?m)` and combinations): Dart can not switch them inside a
/// pattern, so `a(?i)b` and `(?i:a)b` are an [UnsupportedPattern].
RegExp compileRe2(String pattern, {bool anchored = false}) {
  final List<int> runes = pattern.runes.toList();
  int i = 0;
  bool caseInsensitive = false;
  bool dotAll = false;
  bool multiLine = false;

  // Flags at the start.
  while (i + 2 < runes.length &&
      runes[i] == 0x28 /* ( */ &&
      runes[i + 1] == 0x3f /* ? */ ) {
    int j = i + 2;
    bool negate = false;
    final List<void Function()> changes = <void Function()>[];
    bool valid = true;
    while (j < runes.length && runes[j] != 0x29 && runes[j] != 0x3a) {
      final String flag = String.fromCharCode(runes[j]);
      final bool value = !negate;
      switch (flag) {
        case '-':
          negate = true;
        case 'i':
          changes.add(() => caseInsensitive = value);
        case 's':
          changes.add(() => dotAll = value);
        case 'm':
          changes.add(() => multiLine = value);
        default:
          valid = false;
      }
      j++;
    }
    if (!valid || j >= runes.length || runes[j] != 0x29 || j == i + 2) {
      break;
    }
    for (final void Function() change in changes) {
      change();
    }
    i = j + 1;
  }

  final StringBuffer out = StringBuffer();
  bool inClass = false;
  // Whether the last thing written was a quantifier (a second `+` would
  // make it possessive, which RE2 does not have).
  bool quantified = false;
  while (i < runes.length) {
    final int c = runes[i];
    final String ch = String.fromCharCode(c);
    if (ch == r'\') {
      if (i + 1 >= runes.length) {
        throw const InvalidPattern();
      }
      final int n = runes[i + 1];
      final String next = String.fromCharCode(n);
      i += 2;
      quantified = false;
      if ('123456789k'.contains(next)) {
        // Backreferences.
        throw const InvalidPattern();
      } else if (next == 'Q') {
        // A literal up to \E.
        while (i < runes.length &&
            !(runes[i] == 0x5c &&
                i + 1 < runes.length &&
                runes[i + 1] == 0x45)) {
          out.write(_literal(runes[i], inClass: inClass));
          i++;
        }
        i += 2;
      } else if (next == 'z') {
        out.write(multiLine ? r'(?![\s\S])' : r'$');
      } else if (next == 'A') {
        out.write(multiLine ? r'(?<![\s\S])' : '^');
      } else if (next == 'p' || next == 'P') {
        // \pL is \p{L}.
        if (i < runes.length && runes[i] != 0x7b) {
          out.write('\\$next{${String.fromCharCode(runes[i])}}');
          i++;
        } else {
          final int end = runes.indexOf(0x7d, i);
          if (end < 0) {
            throw const InvalidPattern();
          }
          out.write(
            '\\$next${String.fromCharCodes(runes.sublist(i, end + 1))}',
          );
          i = end + 1;
        }
      } else if (next == 'C') {
        throw UnsupportedPattern(r'\C (a single byte)');
      } else if (next == 'a') {
        out.write(r'\x07');
      } else if ('dDwWsSbBnrtfvx0'.contains(next)) {
        out.write('\\$next');
      } else if (_letter.hasMatch(next)) {
        // RE2 has no other letter escapes.
        throw const InvalidPattern();
      } else {
        // An escaped punctuation character is that character.
        out.write(_literal(n, inClass: inClass));
      }
      continue;
    }
    if (inClass) {
      if (ch == '[' && i + 1 < runes.length && runes[i + 1] == 0x3a) {
        // [:name:] or [:^name:]
        final int end = runes.indexOf(0x5d, i + 2);
        if (end < 0 || runes[end - 1] != 0x3a) {
          throw const InvalidPattern();
        }
        final String name = String.fromCharCodes(runes.sublist(i + 2, end - 1));
        final bool negated = name.startsWith('^');
        final String? ranges =
            _posixClasses[negated ? name.substring(1) : name];
        if (ranges == null) {
          throw const InvalidPattern();
        } else if (negated) {
          throw UnsupportedPattern('[:$name:]');
        }
        out.write(ranges);
        i = end + 1;
        continue;
      }
      if (ch == ']') {
        inClass = false;
        quantified = false;
      }
      out.write(ch == '[' ? r'\[' : ch);
      i++;
      continue;
    }
    switch (ch) {
      case '[':
        inClass = true;
        out.write('[');
        i++;
        // A caret and a closing bracket right after the opening one.
        if (i < runes.length && runes[i] == 0x5e) {
          out.write('^');
          i++;
        }
        if (i < runes.length && runes[i] == 0x5d) {
          out.write(r'\]');
          i++;
        }
        quantified = false;
      case '.':
        out.write(dotAll ? r'[\s\S]' : r'[^\n]');
        i++;
        quantified = false;
      case '(':
        quantified = false;
        if (i + 1 < runes.length && runes[i + 1] == 0x3f) {
          final String rest = String.fromCharCodes(
            runes.sublist(i + 2, (i + 4).clamp(0, runes.length)),
          );
          if (rest.startsWith(':')) {
            out.write('(?:');
            i += 3;
          } else if (rest.startsWith('P<')) {
            out.write('(?<');
            i += 4;
          } else if (rest.startsWith('<') &&
              !rest.startsWith('<=') &&
              !rest.startsWith('<!')) {
            out.write('(?<');
            i += 3;
          } else if (rest.startsWith('=') ||
              rest.startsWith('!') ||
              rest.startsWith('<') ||
              rest.startsWith('>')) {
            // Lookaround and atomic groups.
            throw const InvalidPattern();
          } else {
            throw UnsupportedPattern('flags inside a pattern');
          }
        } else {
          out.write('(');
          i++;
        }
      case '*' || '+' || '?':
        if (quantified && ch != '?') {
          // A possessive quantifier, or a repeated one.
          throw const InvalidPattern();
        }
        out.write(ch);
        i++;
        // A `?` after a quantifier makes it lazy and ends it.
        quantified = !quantified;
      case '{':
        final int end = runes.indexOf(0x7d, i);
        final String body = end < 0
            ? ''
            : String.fromCharCodes(runes.sublist(i + 1, end));
        if (_repetition.hasMatch(body)) {
          out.write('{$body}');
          i = end + 1;
          quantified = true;
        } else {
          // Not a repetition: RE2 reads the brace as itself.
          out.write(r'\{');
          i++;
          quantified = false;
        }
      case '}':
        out.write(r'\}');
        i++;
        quantified = false;
      default:
        out.write(ch);
        i++;
        quantified = false;
    }
  }
  if (inClass) {
    throw const InvalidPattern();
  }
  // The whole string, also when ^ and $ match at line breaks.
  final String source = anchored
      ? '(?<![\\s\\S])(?:$out)(?![\\s\\S])'
      : out.toString();
  try {
    return RegExp(
      source,
      unicode: true,
      caseSensitive: !caseInsensitive,
      multiLine: multiLine,
    );
  } on FormatException {
    throw const InvalidPattern();
  }
}
