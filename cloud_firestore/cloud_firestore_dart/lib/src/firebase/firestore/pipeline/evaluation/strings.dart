part of 'expression_evaluator.dart';

// ---- strings and bytes ----
//
// Positions and lengths of strings count Unicode code points, not the UTF-16
// code units of a Dart string.

List<int> _runes(String text) => text.runes.toList();

EvaluateResult _charLength(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isString],
  (List<FieldValue> v) => _int(_text(v[0]).runes.length),
);

EvaluateResult _byteLength(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isStringOrBytes],
  (List<FieldValue> v) => _int(
    v[0] is StringValue ? utf8.encode(_text(v[0])).length : _blob(v[0]).length,
  ),
);

EvaluateResult _length(_Call call) =>
    _strict(call, <bool Function(FieldValue)?>[null], (List<FieldValue> v) {
      final FieldValue value = v[0];
      return switch (value) {
        StringValue() => _int(value.value.runes.length),
        BlobValue() => _int(value.value.bytes.length),
        ArrayValue() => _int(value.internalValue.length),
        VectorFieldValue() => _int(value.internalValue.length),
        ObjectValue() => _int(value.internalValue.length),
        _ => _error,
      };
    });

bool _isAsciiUpper(int byte) => byte >= 0x41 && byte <= 0x5a;
bool _isAsciiLower(int byte) => byte >= 0x61 && byte <= 0x7a;

bool _isCased(int rune) {
  final String character = String.fromCharCode(rune);
  return character.toLowerCase() != character ||
      character.toUpperCase() != character;
}

/// Lower case with the two rules `String.toLowerCase` of the Dart VM does not
/// have: a capital I with a dot keeps its dot, and a capital sigma at the end
/// of a word becomes a final sigma.
String _lowerCase(String text) {
  if (!text.contains('\u0130') && !text.contains('\u03a3')) {
    return text.toLowerCase();
  }
  final List<int> runes = text.runes.toList();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < runes.length; i++) {
    final int rune = runes[i];
    if (rune == 0x0130) {
      buffer.write('i\u0307');
    } else if (rune == 0x03a3) {
      final bool afterLetter = i > 0 && _isCased(runes[i - 1]);
      final bool beforeLetter = i + 1 < runes.length && _isCased(runes[i + 1]);
      buffer.write(afterLetter && !beforeLetter ? '\u03c2' : '\u03c3');
    } else {
      buffer.write(String.fromCharCode(rune).toLowerCase());
    }
  }
  return buffer.toString();
}

EvaluateResult _toLower(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isStringOrBytes],
  (List<FieldValue> v) => v[0] is StringValue
      ? _string(_lowerCase(_text(v[0])))
      : _bytes(<int>[
          for (final int b in _blob(v[0])) _isAsciiUpper(b) ? b + 0x20 : b,
        ]),
);

/// The characters whose upper case is more than one character (the
/// unconditional mappings of Unicode's SpecialCasing.txt). `String.toUpperCase`
/// of the Dart VM leaves them as they are.
final Map<int, String> _specialUpperCase = <int, String>{
  0x00df: 'SS',
  0x0149: '\u02bcN',
  0x01f0: 'J\u030c',
  0x0390: '\u0399\u0308\u0301',
  0x03b0: '\u03a5\u0308\u0301',
  0x0587: '\u0535\u0552',
  0x1e96: 'H\u0331',
  0x1e97: 'T\u0308',
  0x1e98: 'W\u030a',
  0x1e99: 'Y\u030a',
  0x1e9a: 'A\u02be',
  0x1f50: '\u03a5\u0313',
  0x1f52: '\u03a5\u0313\u0300',
  0x1f54: '\u03a5\u0313\u0301',
  0x1f56: '\u03a5\u0313\u0342',
  for (int i = 0; i < 16; i++)
    0x1f80 + i: '${String.fromCharCode(0x1f08 + i % 8)}\u0399',
  for (int i = 0; i < 16; i++)
    0x1f90 + i: '${String.fromCharCode(0x1f28 + i % 8)}\u0399',
  for (int i = 0; i < 16; i++)
    0x1fa0 + i: '${String.fromCharCode(0x1f68 + i % 8)}\u0399',
  0x1fb2: '\u1fba\u0399',
  0x1fb3: '\u0391\u0399',
  0x1fb4: '\u0386\u0399',
  0x1fb6: '\u0391\u0342',
  0x1fb7: '\u0391\u0342\u0399',
  0x1fbc: '\u0391\u0399',
  0x1fc2: '\u1fca\u0399',
  0x1fc3: '\u0397\u0399',
  0x1fc4: '\u0389\u0399',
  0x1fc6: '\u0397\u0342',
  0x1fc7: '\u0397\u0342\u0399',
  0x1fcc: '\u0397\u0399',
  0x1fd2: '\u0399\u0308\u0300',
  0x1fd3: '\u0399\u0308\u0301',
  0x1fd6: '\u0399\u0342',
  0x1fd7: '\u0399\u0308\u0342',
  0x1fe2: '\u03a5\u0308\u0300',
  0x1fe3: '\u03a5\u0308\u0301',
  0x1fe4: '\u03a1\u0313',
  0x1fe6: '\u03a5\u0342',
  0x1fe7: '\u03a5\u0308\u0342',
  0x1ff2: '\u1ffa\u0399',
  0x1ff3: '\u03a9\u0399',
  0x1ff4: '\u038f\u0399',
  0x1ff6: '\u03a9\u0342',
  0x1ff7: '\u03a9\u0342\u0399',
  0x1ffc: '\u03a9\u0399',
  0xfb00: 'FF',
  0xfb01: 'FI',
  0xfb02: 'FL',
  0xfb03: 'FFI',
  0xfb04: 'FFL',
  0xfb05: 'ST',
  0xfb06: 'ST',
  0xfb13: '\u0544\u0546',
  0xfb14: '\u0544\u0535',
  0xfb15: '\u0544\u053b',
  0xfb16: '\u054e\u0546',
  0xfb17: '\u0544\u053d',
};

String _upperCase(String text) {
  final String upper = text.toUpperCase();
  if (!upper.runes.any(_specialUpperCase.containsKey)) {
    return upper;
  }
  final StringBuffer buffer = StringBuffer();
  for (final int rune in upper.runes) {
    buffer.write(_specialUpperCase[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}

EvaluateResult _toUpper(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isStringOrBytes],
  (List<FieldValue> v) => v[0] is StringValue
      ? _string(_upperCase(_text(v[0])))
      : _bytes(<int>[
          for (final int b in _blob(v[0])) _isAsciiLower(b) ? b - 0x20 : b,
        ]),
);

bool _isAsciiSpace(int byte) => byte == 0x20 || (byte >= 0x09 && byte <= 0x0d);

/// `trim`, `ltrim` and `rtrim`, of whitespace or of the characters (bytes)
/// of a second argument.
_Function _trim({required bool left, required bool right}) {
  List<int> trimList(List<int> units, bool Function(int) remove) {
    int start = 0;
    int end = units.length;
    if (left) {
      while (start < end && remove(units[start])) {
        start++;
      }
    }
    if (right) {
      while (end > start && remove(units[end - 1])) {
        end--;
      }
    }
    return units.sublist(start, end);
  }

  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isStringOrBytes, _isStringOrBytes],
    min: 1,
    max: 2,
    (List<FieldValue> v) {
      final FieldValue value = v[0];
      if (v.length == 2 && v[1].runtimeType != value.runtimeType) {
        throw const _EvaluationError();
      }
      if (value is StringValue) {
        if (v.length == 1) {
          final String text = value.value;
          return _string(
            left && right
                ? text.trim()
                : (left ? text.trimLeft() : text.trimRight()),
          );
        }
        final Set<int> characters = _text(v[1]).runes.toSet();
        return _string(
          String.fromCharCodes(
            trimList(_runes(value.value), characters.contains),
          ),
        );
      }
      final Set<int>? bytes = v.length == 2 ? _blob(v[1]).toSet() : null;
      return _bytes(trimList(_blob(value), bytes?.contains ?? _isAsciiSpace));
    },
  );
}

/// `reverse` (strings, bytes and arrays) and `string_reverse` (strings and
/// bytes).
_Function _reverse({required bool arrays}) {
  return (_Call call) =>
      _strict(call, <bool Function(FieldValue)?>[null], (List<FieldValue> v) {
        final FieldValue value = v[0];
        if (value is StringValue) {
          return _string(String.fromCharCodes(_runes(value.value).reversed));
        } else if (value is BlobValue) {
          return _bytes(value.value.bytes.reversed.toList());
        } else if (arrays && value is ArrayValue) {
          return _list(value.internalValue.reversed.toList());
        }
        return _error;
      });
}

/// `substring(value, position, [length])`. A negative position counts from
/// the end.
EvaluateResult _substring(_Call call) => _strict(
  call,
  // The value is checked in the body: a position or length of the wrong type
  // is an error, then a null argument makes the result null, and only then
  // a value that is not a string or bytes is an error.
  <bool Function(FieldValue)?>[null, _isInteger, _isInteger],
  min: 2,
  max: 3,
  (List<FieldValue> v) {
    if (!_isStringOrBytes(v[0])) {
      throw const _EvaluationError();
    }
    final List<int> units = v[0] is StringValue
        ? _runes(_text(v[0]))
        : _blob(v[0]);
    int start = _integer(v[1]);
    final int? length = v.length > 2 ? _integer(v[2]) : null;
    if (length != null && length < 0) {
      throw const _EvaluationError();
    }
    if (start < 0) {
      start = math.max(0, units.length + start);
    }
    if (start >= units.length) {
      return v[0] is StringValue ? _string('') : _bytes(const <int>[]);
    }
    final int end = length == null || length > units.length - start
        ? units.length
        : start + length;
    final List<int> part = units.sublist(start, end);
    return v[0] is StringValue
        ? _string(String.fromCharCodes(part))
        : _bytes(part);
  },
);

/// Evaluates arguments that have to be all strings, all bytes or all arrays
/// for `concat`.
EvaluateResult _mismatchedTypesAreErrors(
  _Call call,
  EvaluateResult Function(List<FieldValue> values) body,
) {
  // The typed check happens before the null check: concat('a', 1, null) is
  // an error, not null.
  final List<EvaluateResult> results = call.evalAll();
  if (results.any((EvaluateResult r) => r.isError)) {
    return _error;
  }
  Type? type;
  bool hasNull = false;
  final List<FieldValue> values = <FieldValue>[];
  for (final EvaluateResult result in results) {
    final FieldValue? value = result.value;
    if (_isNull(value)) {
      hasNull = true;
      continue;
    }
    if (value is! StringValue && value is! BlobValue && value is! ArrayValue) {
      return _error;
    }
    type ??= value.runtimeType;
    if (value.runtimeType != type) {
      return _error;
    }
    values.add(value!);
  }
  return hasNull ? _null : body(values);
}

/// `concat` of strings, of bytes or of arrays.
EvaluateResult _concat(_Call call) {
  if (call.length < 2) {
    return _error;
  }
  return _mismatchedTypesAreErrors(call, (List<FieldValue> v) {
    checkLocalValueSize(
      v.fold(0, (int size, FieldValue e) => size + _sizeOf(e)),
      'concat',
    );
    if (v[0] is StringValue) {
      return _string(v.map(_text).join());
    } else if (v[0] is BlobValue) {
      return _bytes(<int>[for (final FieldValue e in v) ..._blob(e)]);
    }
    return _list(<FieldValue>[for (final FieldValue e in v) ..._elements(e)]);
  });
}

EvaluateResult _stringConcat(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isString],
  min: 1,
  (List<FieldValue> v) {
    checkLocalValueSize(
      v.fold(0, (int size, FieldValue e) => size + _text(e).length),
      'string_concat',
    );
    return _string(v.map(_text).join());
  },
);

/// The size of a string, bytes or array value for [checkLocalValueSize].
int _sizeOf(FieldValue value) => switch (value) {
  StringValue() => value.value.length,
  BlobValue() => value.value.bytes.length,
  ArrayValue() => value.internalValue.length,
  _ => 1,
};

/// A predicate of two strings.
_Function _stringPredicate(bool Function(String value, String other) test) {
  return (_Call call) => _strict(call, <bool Function(FieldValue)?>[
    _isString,
    _isString,
  ], (List<FieldValue> v) => _bool(test(_text(v[0]), _text(v[1]))));
}

/// Whether [value] matches the `like` [pattern]: `%` is any text, `_` any
/// character, a backslash makes the next character literal. Neither `%` nor
/// `_` matches a line feed (what the backend does). Characters are code
/// points.
///
/// A direct matcher, not a regular expression: every line feed of the value
/// has to be matched by a literal line feed of the pattern, so both are split
/// at them; inside a line, the pieces between `%` are found left to right,
/// each at its first occurrence. That takes O(n·m) time at worst (n and m the
/// lengths), O(n) for a pattern without `_` in its pieces.
bool _like(String value, String pattern) {
  // The tokens of the pattern: a code point, or -1 for `_`, -2 for `%`.
  final List<int> tokens = <int>[];
  bool escape = false;
  for (final int rune in pattern.runes) {
    if (escape) {
      escape = false;
      tokens.add(rune);
    } else if (rune == 0x5c /* \ */ ) {
      escape = true;
    } else if (rune == 0x5f /* _ */ ) {
      tokens.add(_likeAny);
    } else if (rune == 0x25 /* % */ ) {
      tokens.add(_likeText);
    } else {
      tokens.add(rune);
    }
  }
  if (escape) {
    throw const _EvaluationError();
  }
  final List<int> text = value.runes.toList();
  final List<List<int>> patternLines = _splitAt(tokens, 0x0a);
  final List<List<int>> textLines = _splitAt(text, 0x0a);
  if (patternLines.length != textLines.length) {
    return false;
  }
  for (int i = 0; i < textLines.length; i++) {
    if (!_likeLine(textLines[i], patternLines[i])) {
      return false;
    }
  }
  return true;
}

const int _likeAny = -1;
const int _likeText = -2;

List<List<int>> _splitAt(List<int> values, int separator) {
  final List<List<int>> parts = <List<int>>[<int>[]];
  for (final int value in values) {
    if (value == separator) {
      parts.add(<int>[]);
    } else {
      parts.last.add(value);
    }
  }
  return parts;
}

/// [text] (without line feeds) against [tokens] (without line feeds).
bool _likeLine(List<int> text, List<int> tokens) {
  final List<List<int>> pieces = _splitAt(tokens, _likeText);
  bool matchesAt(List<int> piece, int at) {
    for (int k = 0; k < piece.length; k++) {
      if (piece[k] != _likeAny && piece[k] != text[at + k]) {
        return false;
      }
    }
    return true;
  }

  if (pieces.length == 1) {
    return text.length == pieces.single.length && matchesAt(pieces.single, 0);
  }
  final List<int> first = pieces.first;
  final List<int> last = pieces.last;
  if (first.length + last.length > text.length ||
      !matchesAt(first, 0) ||
      !matchesAt(last, text.length - last.length)) {
    return false;
  }
  int position = first.length;
  final int end = text.length - last.length;
  for (int p = 1; p < pieces.length - 1; p++) {
    final List<int> piece = pieces[p];
    int at = position;
    while (at + piece.length <= end && !matchesAt(piece, at)) {
      at++;
    }
    if (at + piece.length > end) {
      return false;
    }
    position = at + piece.length;
  }
  return true;
}

Re2 _regExp(String pattern, {bool anchored = false}) {
  try {
    return compileRe2(pattern, anchored: anchored);
  } on InvalidPattern {
    throw const _EvaluationError();
  } on UnsupportedPattern catch (e) {
    throw UnsupportedExpression(
      'The regular expression can not be evaluated locally: ${e.message}',
    );
  }
}

/// Runs [match], turning a match too costly for the local matcher into an
/// [UnsupportedExpression].
T _matching<T>(T Function() match) {
  try {
    return match();
  } on UnsupportedPattern catch (e) {
    throw UnsupportedExpression(
      'The regular expression can not be evaluated locally: ${e.message}',
    );
  }
}

/// What a match stands for: the whole match, or the capturing group of a
/// pattern that has exactly one. More groups are an error.
FieldValue _matchValue(Re2Match match) {
  if (match.groupCount == 0) {
    return StringValue.valueOf(match.group(0)!);
  } else if (match.groupCount == 1) {
    final String? group = match.group(1);
    return group == null ? NullValue.nullValue() : StringValue.valueOf(group);
  }
  throw const _EvaluationError();
}

EvaluateResult _regexFind(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isString, _isString],
  (List<FieldValue> v) {
    final Re2 re2 = _regExp(_text(v[1]));
    final Re2Match? match = _matching(() => re2.firstMatch(_text(v[0])));
    return match == null ? _null : EvaluateValue(_matchValue(match));
  },
);

EvaluateResult _regexFindAll(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isString, _isString],
  (List<FieldValue> v) => _list(
    _matching(
      () => _allMatches(_regExp(_text(v[1])), _text(v[0])),
    ).map(_matchValue).toList(),
  ),
);

bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

/// The matches of [regExp] in [input] as the backend finds them.
///
/// The backend (Java) steps over the input in UTF-16 code units: after an
/// empty match right before a character outside the BMP it tries again
/// between the two halves of that character, where an empty match counts
/// once more (`regex_find_all('😀', '')` has three matches). A Dart regular
/// expression in Unicode mode never starts there, so that position is tried
/// on a copy of the input whose two halves are replaced by two characters of
/// the same kind (neither letters, digits, spaces nor line breaks).
List<Re2Match> _allMatches(Re2 regExp, String input) {
  final List<Re2Match> matches = <Re2Match>[];
  int position = 0;
  while (position <= input.length) {
    if (position > 0 &&
        position < input.length &&
        _isHighSurrogate(input.codeUnitAt(position - 1)) &&
        _isLowSurrogate(input.codeUnitAt(position))) {
      final String halves = input.replaceRange(
        position - 1,
        position + 1,
        '\u{e000}\u{e001}',
      );
      final Re2Match? match = regExp.matchAsPrefix(halves, position);
      if (match != null) {
        if (match.end != match.start) {
          throw UnsupportedExpression(
            'A match of half a character outside the BMP',
          );
        }
        matches.add(match);
      }
      position++;
      continue;
    }
    final Re2Match? match = regExp.firstMatch(input, position);
    if (match == null) {
      break;
    }
    matches.add(match);
    position = match.end == match.start ? match.end + 1 : match.end;
  }
  return matches;
}

/// Whether [regExp] (compiled anchored) matches all of [input].
bool _matchesAll(Re2 regExp, String input) =>
    _matching(() => regExp.matchAsPrefix(input) != null);

/// The index of the first occurrence of [search] in [units] at or after
/// [from], or -1.
int _indexOf(List<int> units, List<int> search, [int from = 0]) {
  for (int i = from; i + search.length <= units.length; i++) {
    bool match = true;
    for (int j = 0; j < search.length; j++) {
      if (units[i + j] != search[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

/// The code points of a string or the bytes of a blob, and how to make a
/// value of the same type again.
(List<int>, FieldValue Function(List<int>)) _units(FieldValue value) {
  if (value is StringValue) {
    return (
      _runes(value.value),
      (List<int> units) => StringValue.valueOf(String.fromCharCodes(units)),
    );
  }
  return (
    _blob(value),
    (List<int> units) => BlobValue.valueOf(Blob(Uint8List.fromList(units))),
  );
}

/// Arguments that are all strings or all bytes.
EvaluateResult _sameKind(
  _Call call,
  int count,
  EvaluateResult Function(List<FieldValue> values) body,
) => _strict(
  call,
  List<bool Function(FieldValue)?>.filled(count, _isStringOrBytes),
  (List<FieldValue> v) {
    if (v.any((FieldValue e) => e.runtimeType != v[0].runtimeType)) {
      throw const _EvaluationError();
    }
    return body(v);
  },
);

EvaluateResult _split(_Call call) => _sameKind(call, 2, (List<FieldValue> v) {
  final (List<int> units, FieldValue Function(List<int>) make) = _units(v[0]);
  final List<int> delimiter = _units(v[1]).$1;
  final List<FieldValue> parts = <FieldValue>[];
  if (delimiter.isEmpty) {
    // An empty delimiter splits between all the characters.
    for (final int unit in units) {
      parts.add(make(<int>[unit]));
    }
    return _list(parts);
  }
  int start = 0;
  while (true) {
    final int index = _indexOf(units, delimiter, start);
    if (index < 0) {
      parts.add(make(units.sublist(start)));
      break;
    }
    parts.add(make(units.sublist(start, index)));
    start = index + delimiter.length;
  }
  return _list(parts);
});

/// `join(array, delimiter)`: the elements that are not null, joined. They
/// have to be of the type of the delimiter.
EvaluateResult _join(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isArray, _isStringOrBytes],
  (List<FieldValue> v) {
    final (List<int> delimiter, FieldValue Function(List<int>) make) = _units(
      v[1],
    );
    final List<int> result = <int>[];
    bool first = true;
    for (final FieldValue element in _elements(v[0])) {
      if (element is NullValue) {
        continue;
      }
      if (element.runtimeType != v[1].runtimeType) {
        throw const _EvaluationError();
      }
      if (!first) {
        result.addAll(delimiter);
      }
      result.addAll(_units(element).$1);
      checkLocalValueSize(result.length, 'join');
      first = false;
    }
    if (v[1] is BlobValue) {
      // Bytes joined are a string: the bytes read as UTF-8, a malformed
      // sequence as U+FFFD (what the backend returns, unlike the Android SDK,
      // which returns bytes).
      return EvaluateValue(
        StringValue.valueOf(utf8.decode(result, allowMalformed: true)),
      );
    }
    return EvaluateValue(make(result));
  },
);

_Function _replace({required bool all}) {
  return (_Call call) => _sameKind(call, 3, (List<FieldValue> v) {
    final (List<int> units, FieldValue Function(List<int>) make) = _units(v[0]);
    final List<int> find = _units(v[1]).$1;
    final List<int> replacement = _units(v[2]).$1;
    if (find.isEmpty) {
      return EvaluateValue(v[0]);
    }
    final List<int> result = <int>[];
    int start = 0;
    while (true) {
      final int index = _indexOf(units, find, start);
      if (index < 0) {
        break;
      }
      result
        ..addAll(units.sublist(start, index))
        ..addAll(replacement);
      checkLocalValueSize(result.length, call.name);
      start = index + find.length;
      if (!all) {
        break;
      }
    }
    result.addAll(units.sublist(start));
    return EvaluateValue(make(result));
  });
}

/// The largest result of `string_repeat`, in bytes.
const int _maxRepeatedSize = 1024 * 1024;

EvaluateResult _stringRepeat(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isStringOrBytes, _isInteger],
  (List<FieldValue> v) {
    final int count = _integer(v[1]);
    if (count < 0) {
      throw const _EvaluationError();
    }
    final (List<int> units, FieldValue Function(List<int>) make) = _units(v[0]);
    // The result may have at most 1 MiB (of UTF-8 for a string); repeating
    // nothing gives nothing however often.
    final int size = v[0] is StringValue
        ? utf8.encode((v[0] as StringValue).value).length
        : units.length;
    if (size == 0) {
      return EvaluateValue(make(const <int>[]));
    }
    if (count > _maxRepeatedSize ~/ size) {
      throw const _EvaluationError();
    }
    return EvaluateValue(make(<int>[for (int i = 0; i < count; i++) ...units]));
  },
);

EvaluateResult _stringIndexOf(_Call call) => _sameKind(
  call,
  2,
  (List<FieldValue> v) => _int(_indexOf(_units(v[0]).$1, _units(v[1]).$1)),
);

final Map<String, _Function> _stringFunctions = <String, _Function>{
  'char_length': _charLength,
  'byte_length': _byteLength,
  'length': _length,
  'to_lower': _toLower,
  'to_upper': _toUpper,
  'trim': _trim(left: true, right: true),
  'ltrim': _trim(left: true, right: false),
  'rtrim': _trim(left: false, right: true),
  'reverse': _reverse(arrays: true),
  'string_reverse': _reverse(arrays: false),
  'substring': _substring,
  'concat': _concat,
  'string_concat': _stringConcat,
  'starts_with': _stringPredicate(
    (String value, String prefix) => value.startsWith(prefix),
  ),
  'ends_with': _stringPredicate(
    (String value, String suffix) => value.endsWith(suffix),
  ),
  'string_contains': _stringPredicate(
    (String value, String substring) => value.contains(substring),
  ),
  'like': _stringPredicate(
    (String value, String pattern) => _like(value, pattern),
  ),
  'regex_contains': _stringPredicate((String value, String pattern) {
    final Re2 re2 = _regExp(pattern);
    return _matching(() => re2.hasMatch(value));
  }),
  'regex_match': _stringPredicate(
    (String value, String pattern) =>
        _matchesAll(_regExp(pattern, anchored: true), value),
  ),
  'regex_find': _regexFind,
  'regex_find_all': _regexFindAll,
  'split': _split,
  'join': _join,
  'string_replace_all': _replace(all: true),
  'string_replace_one': _replace(all: false),
  'string_repeat': _stringRepeat,
  'string_index_of': _stringIndexOf,
};
