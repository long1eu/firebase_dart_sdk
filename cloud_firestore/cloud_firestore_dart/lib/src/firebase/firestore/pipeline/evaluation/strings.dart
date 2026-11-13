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
  (List<FieldValue> v) => _string(v.map(_text).join()),
);

/// A predicate of two strings.
_Function _stringPredicate(bool Function(String value, String other) test) {
  return (_Call call) => _strict(call, <bool Function(FieldValue)?>[
    _isString,
    _isString,
  ], (List<FieldValue> v) => _bool(test(_text(v[0]), _text(v[1]))));
}

/// The regular expression of a `like` pattern: `%` is any text, `_` any
/// character, a backslash makes the next character literal.
RegExp _likeToRegExp(String like) {
  final StringBuffer pattern = StringBuffer('^');
  bool escape = false;
  for (final int rune in like.runes) {
    final String character = String.fromCharCode(rune);
    if (escape) {
      escape = false;
      pattern.write(RegExp.escape(character));
    } else if (character == r'\') {
      escape = true;
    } else if (character == '_') {
      pattern.write(r'[^\n]');
    } else if (character == '%') {
      pattern.write(r'[^\n]*');
    } else {
      pattern.write(RegExp.escape(character));
    }
  }
  if (escape) {
    throw const _EvaluationError();
  }
  pattern.write(r'$');
  return RegExp(pattern.toString(), unicode: true);
}

RegExp _regExp(String pattern, {bool anchored = false}) {
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

/// What a match stands for: the whole match, or the capturing group of a
/// pattern that has exactly one. More groups are an error.
FieldValue _matchValue(RegExpMatch match) {
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
    final RegExpMatch? match = _regExp(_text(v[1])).firstMatch(_text(v[0]));
    return match == null ? _null : EvaluateValue(_matchValue(match));
  },
);

EvaluateResult _regexFindAll(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isString, _isString],
  (List<FieldValue> v) => _list(
    _regExp(_text(v[1])).allMatches(_text(v[0])).map(_matchValue).toList(),
  ),
);

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
      first = false;
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
    (String value, String pattern) => _likeToRegExp(pattern).hasMatch(value),
  ),
  'regex_contains': _stringPredicate(
    (String value, String pattern) => _regExp(pattern).hasMatch(value),
  ),
  'regex_match': _stringPredicate(
    (String value, String pattern) =>
        _regExp(pattern, anchored: true).hasMatch(value),
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
