// The regular expressions of the backend are RE2 expressions. This file
// parses the RE2 syntax and matches with a Pike VM (Thompson's construction
// with submatch tracking), so matching takes time linear in the input for a
// given pattern, like RE2 itself, and never backtracks: a pattern such as
// `(a+)+b` can not freeze the client on hostile data.
//
// The semantics are RE2's, checked against the Enterprise emulator (the
// recorded results in emulator_results.golden.jsonl): leftmost-first matches
// (the match a backtracking engine finds), `.` is everything but a line feed,
// `\d`, `\w`, `\s` and `\b` are ASCII, a line feed is the only line break of
// `(?m)`, counted repetitions are capped at 1000, a lone `]` is a literal and
// assertions can be repeated. Flags are understood only at the start of the
// pattern (as the Dart RegExp translation this replaces did).

/// Thrown for a pattern RE2 rejects.
class InvalidPattern implements Exception {
  const InvalidPattern();
}

/// Thrown for a valid RE2 pattern that is not evaluated here: syntax this
/// file does not implement, or a pattern or an input too large to match
/// locally within [maxRe2Steps].
class UnsupportedPattern implements Exception {
  UnsupportedPattern(this.message);

  final String message;

  @override
  String toString() => 'UnsupportedPattern: $message';
}

/// The largest program (instructions) a pattern may compile to. RE2 limits
/// the size of its programs too; counted repetitions are capped at 1000.
const int maxRe2Instructions = 20000;

/// The most steps (an instruction run for one position) one match may take,
/// about the size of the program times the length of the input. Beyond it the
/// match is an [UnsupportedPattern], so the expression goes to the backend.
const int maxRe2Steps = 50000000;

const Map<String, String> _posixClasses = <String, String>{
  'alnum': '0-9A-Za-z',
  'alpha': 'A-Za-z',
  'ascii': '\x00-\x7F',
  'blank': '\t ',
  'cntrl': '\x00-\x1F\x7F',
  'digit': '0-9',
  'graph': '!-~',
  'lower': 'a-z',
  'print': ' -~',
  'punct': r'!-/:-@[-`{-~',
  'space': '\t\n\v\f\r ',
  'upper': 'A-Z',
  'word': '0-9A-Za-z_',
  'xdigit': '0-9A-Fa-f',
};

/// The ranges of a POSIX class body such as `0-9A-Za-z`.
List<int> _posixRanges(String body) {
  final List<int> ranges = <int>[];
  final List<int> units = body.codeUnits;
  for (int i = 0; i < units.length; i++) {
    if (i + 2 < units.length && units[i + 1] == 0x2d) {
      ranges
        ..add(units[i])
        ..add(units[i + 2]);
      i += 2;
    } else {
      ranges
        ..add(units[i])
        ..add(units[i]);
    }
  }
  return ranges;
}

const List<int> _digitRanges = <int>[0x30, 0x39];
const List<int> _wordRanges = <int>[
  0x30, 0x39, 0x41, 0x5a, 0x5f, 0x5f, 0x61, 0x7a, //
];

/// `\s` of RE2: `[\t\n\f\r ]` (no vertical tab, no Unicode spaces; the
/// emulator agrees).
const List<int> _spaceRanges = <int>[0x09, 0x0a, 0x0c, 0x0d, 0x20, 0x20];

bool _inRanges(List<int> ranges, int c) {
  for (int i = 0; i < ranges.length; i += 2) {
    if (c >= ranges[i] && c <= ranges[i + 1]) {
      return true;
    }
  }
  return false;
}

bool _isWord(int c) => _inRanges(_wordRanges, c);

/// The line breaks of `(?m)`: only a line feed, as in RE2 (the emulator
/// agrees).
bool _isLineTerminator(int c) => c == 0x0a;

final Map<int, int> _lowerCache = <int, int>{};
final Map<int, int> _upperCache = <int, int>{};

/// The simple lower case of [c] (itself when that is not one code point).
int _lower(int c) {
  if (c < 0x80) {
    return c >= 0x41 && c <= 0x5a ? c + 0x20 : c;
  }
  return _lowerCache[c] ??= _single(String.fromCharCode(c).toLowerCase(), c);
}

/// The simple upper case of [c] (itself when that is not one code point).
int _upper(int c) {
  if (c < 0x80) {
    return c >= 0x61 && c <= 0x7a ? c - 0x20 : c;
  }
  return _upperCache[c] ??= _single(String.fromCharCode(c).toUpperCase(), c);
}

int _single(String text, int fallback) {
  final List<int> runes = text.runes.toList();
  return runes.length == 1 ? runes.single : fallback;
}

/// The case-folded form of [c]: what a case-insensitive comparison compares.
int _fold(int c) => _lower(_upper(c));

/// A set of code points: ranges, classes such as `\d` or `\pL`, negation.
class _CharSet {
  _CharSet({
    required this.ranges,
    required this.predicates,
    required this.negated,
    required this.ignoreCase,
  });

  /// Pairs of inclusive bounds.
  final List<int> ranges;

  /// More members: `\pL`, `\D`, ...
  final List<bool Function(int c)> predicates;
  final bool negated;
  final bool ignoreCase;

  bool _contains(int c) {
    if (_inRanges(ranges, c)) {
      return true;
    }
    for (final bool Function(int) predicate in predicates) {
      if (predicate(c)) {
        return true;
      }
    }
    return false;
  }

  bool matches(int c) {
    bool result = _contains(c);
    if (!result && ignoreCase) {
      final int lower = _lower(c);
      final int upper = _upper(c);
      final int fold = _fold(c);
      result =
          (lower != c && _contains(lower)) ||
          (upper != c && _contains(upper)) ||
          (fold != c && _contains(fold));
    }
    return result != negated;
  }
}

// ---- the syntax tree ----

sealed class _Node {}

/// One code point of a set.
class _Char extends _Node {
  _Char(this.set);

  final _CharSet set;
}

/// One literal code point.
class _Literal extends _Node {
  _Literal(this.rune, this.ignoreCase) : folded = _fold(rune);

  final int rune;
  final bool ignoreCase;
  final int folded;
}

class _Concat extends _Node {
  _Concat(this.nodes);

  final List<_Node> nodes;
}

class _Alternation extends _Node {
  _Alternation(this.nodes);

  final List<_Node> nodes;
}

class _Repeat extends _Node {
  _Repeat(this.node, this.min, this.max, this.greedy);

  final _Node node;
  final int min;

  /// -1 for no upper bound.
  final int max;
  final bool greedy;
}

class _Group extends _Node {
  _Group(this.node, this.index);

  final _Node node;
  final int index;
}

enum _AssertKind {
  textStart,
  textEnd,
  lineStart,
  lineEnd,
  wordBoundary,
  notWordBoundary,
}

class _Assert extends _Node {
  _Assert(this.kind);

  final _AssertKind kind;
}

// ---- the parser ----

class _Parser {
  _Parser(String pattern) : runes = pattern.runes.toList();

  final List<int> runes;
  int i = 0;
  bool ignoreCase = false;
  bool dotAll = false;
  bool multiLine = false;
  int groups = 0;
  final Map<String, int> names = <String, int>{};

  bool get atEnd => i >= runes.length;

  int peek([int offset = 0]) =>
      i + offset < runes.length ? runes[i + offset] : -1;

  _Node parse() {
    _flags();
    final _Node node = _alternation();
    if (!atEnd) {
      // An unmatched closing parenthesis.
      throw const InvalidPattern();
    }
    return node;
  }

  /// Flags at the start: `(?i)`, `(?s)`, `(?m)` and combinations.
  void _flags() {
    while (i + 2 < runes.length && runes[i] == 0x28 && runes[i + 1] == 0x3f) {
      int j = i + 2;
      bool negate = false;
      final List<void Function()> changes = <void Function()>[];
      bool valid = true;
      while (j < runes.length && runes[j] != 0x29 && runes[j] != 0x3a) {
        final bool value = !negate;
        switch (String.fromCharCode(runes[j])) {
          case '-':
            negate = true;
          case 'i':
            changes.add(() => ignoreCase = value);
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
        return;
      }
      for (final void Function() change in changes) {
        change();
      }
      i = j + 1;
    }
  }

  _Node _alternation() {
    final List<_Node> branches = <_Node>[_concatenation()];
    while (peek() == 0x7c /* | */ ) {
      i++;
      branches.add(_concatenation());
    }
    return branches.length == 1 ? branches.single : _Alternation(branches);
  }

  _Node _concatenation() {
    final List<_Node> nodes = <_Node>[];
    while (!atEnd && peek() != 0x7c && peek() != 0x29) {
      nodes.addAll(_repetition());
    }
    return nodes.length == 1 ? nodes.single : _Concat(nodes);
  }

  /// An atom with its quantifier. `\Q...\E` gives several atoms; only the
  /// last one is quantified.
  List<_Node> _repetition() {
    if (_isQuantifierStart()) {
      // Nothing to repeat.
      throw const InvalidPattern();
    }
    final List<_Node> atoms = _atom();
    if (atoms.isEmpty || !_isQuantifierStart()) {
      return atoms;
    }
    // RE2 also repeats an assertion (`^*`).
    final _Node last = atoms.removeLast();
    final (int min, int max) = _quantifier();
    bool greedy = true;
    if (peek() == 0x3f /* ? */ ) {
      greedy = false;
      i++;
    }
    if (_isQuantifierStart()) {
      // A possessive or a repeated quantifier.
      throw const InvalidPattern();
    }
    return <_Node>[...atoms, _Repeat(last, min, max, greedy)];
  }

  bool _isQuantifierStart() {
    final int c = peek();
    if (c == 0x2a || c == 0x2b || c == 0x3f) {
      return true;
    }
    return c == 0x7b && _countedRepetition() != null;
  }

  /// The bounds of `{n}`, `{n,}` or `{n,m}` at the current position, or null
  /// when the brace is a literal.
  (int, int, int)? _countedRepetition() {
    int j = i + 1;
    int start = j;
    while (j < runes.length && runes[j] >= 0x30 && runes[j] <= 0x39) {
      j++;
    }
    if (j == start || j >= runes.length) {
      return null;
    }
    final int min = _number(start, j);
    int max = min;
    if (runes[j] == 0x2c /* , */ ) {
      j++;
      start = j;
      while (j < runes.length && runes[j] >= 0x30 && runes[j] <= 0x39) {
        j++;
      }
      max = j == start ? -1 : _number(start, j);
    }
    if (j >= runes.length || runes[j] != 0x7d) {
      return null;
    }
    return (min, max, j + 1);
  }

  int _number(int start, int end) {
    if (end - start > 4) {
      // RE2 caps counted repetitions at 1000.
      throw const InvalidPattern();
    }
    return int.parse(String.fromCharCodes(runes.sublist(start, end)));
  }

  (int, int) _quantifier() {
    final int c = runes[i];
    if (c == 0x2a) {
      i++;
      return (0, -1);
    } else if (c == 0x2b) {
      i++;
      return (1, -1);
    } else if (c == 0x3f) {
      i++;
      return (0, 1);
    }
    final (int min, int max, int end) = _countedRepetition()!;
    if (min > 1000 || max > 1000 || (max >= 0 && max < min)) {
      throw const InvalidPattern();
    }
    i = end;
    return (min, max);
  }

  List<_Node> _atom() {
    final int c = runes[i];
    switch (c) {
      case 0x28: // (
        return <_Node>[_group()];
      case 0x5b: // [
        i++;
        return <_Node>[_Char(_class())];
      case 0x2e: // .
        i++;
        return <_Node>[
          _Char(
            _CharSet(
              ranges: dotAll
                  ? const <int>[0, 0x10ffff]
                  : const <int>[0x0a, 0x0a],
              predicates: const <bool Function(int)>[],
              negated: !dotAll,
              ignoreCase: false,
            ),
          ),
        ];
      case 0x5e: // ^
        i++;
        return <_Node>[
          _Assert(multiLine ? _AssertKind.lineStart : _AssertKind.textStart),
        ];
      case 0x24: // $
        i++;
        return <_Node>[
          _Assert(multiLine ? _AssertKind.lineEnd : _AssertKind.textEnd),
        ];
      case 0x5c: // \
        return _escape();
      default:
        i++;
        return <_Node>[_Literal(c, ignoreCase)];
    }
  }

  _Node _group() {
    i++; // (
    int? index;
    if (peek() == 0x3f /* ? */ ) {
      final int next = peek(1);
      if (next == 0x3a /* : */ ) {
        i += 2;
      } else if (next == 0x50 /* P */ && peek(2) == 0x3c /* < */ ) {
        i += 3;
        index = _name();
      } else if (next == 0x3c &&
          peek(2) != 0x3d /* = */ &&
          peek(2) != 0x21 /* ! */ ) {
        i += 2;
        index = _name();
      } else if (next == 0x3d || next == 0x21 || next == 0x3c || next == 0x3e) {
        // Lookaround and atomic groups.
        throw const InvalidPattern();
      } else {
        throw UnsupportedPattern('flags inside a pattern');
      }
    } else {
      index = ++groups;
    }
    final _Node node = _alternation();
    if (peek() != 0x29 /* ) */ ) {
      throw const InvalidPattern();
    }
    i++;
    return index == null ? node : _Group(node, index);
  }

  /// A group name up to `>`; registers the group.
  int _name() {
    final int start = i;
    while (!atEnd && runes[i] != 0x3e) {
      i++;
    }
    if (atEnd) {
      throw const InvalidPattern();
    }
    final String name = String.fromCharCodes(runes.sublist(start, i));
    i++;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name) ||
        names.containsKey(name)) {
      throw const InvalidPattern();
    }
    return names[name] = ++groups;
  }

  _CharSet _set(List<int> ranges, [List<bool Function(int)>? predicates]) =>
      _CharSet(
        ranges: ranges,
        predicates: predicates ?? const <bool Function(int)>[],
        negated: false,
        ignoreCase: ignoreCase,
      );

  _CharSet _negated(List<int> ranges) => _CharSet(
    ranges: ranges,
    predicates: const <bool Function(int)>[],
    negated: true,
    ignoreCase: false,
  );

  /// An escape outside a class.
  List<_Node> _escape() {
    if (i + 1 >= runes.length) {
      throw const InvalidPattern();
    }
    final int n = runes[i + 1];
    final String next = String.fromCharCode(n);
    i += 2;
    switch (next) {
      case 'Q':
        final List<_Node> literals = <_Node>[];
        while (!atEnd &&
            !(runes[i] == 0x5c &&
                i + 1 < runes.length &&
                runes[i + 1] == 0x45)) {
          literals.add(_Literal(runes[i], ignoreCase));
          i++;
        }
        i += 2;
        return literals;
      case 'z':
        return <_Node>[_Assert(_AssertKind.textEnd)];
      case 'A':
        return <_Node>[_Assert(_AssertKind.textStart)];
      case 'b':
        return <_Node>[_Assert(_AssertKind.wordBoundary)];
      case 'B':
        return <_Node>[_Assert(_AssertKind.notWordBoundary)];
      case 'd' || 'D' || 'w' || 'W' || 's' || 'S' || 'p' || 'P':
        i -= 2;
        return <_Node>[_Char(_classEscapeSet()!)];
      default:
        i -= 2;
        return <_Node>[_Literal(_escapedRune(inClass: false), ignoreCase)];
    }
  }

  /// `\d`, `\pL` and the like at the current position as a set, or null when
  /// the escape is not a class.
  _CharSet? _classEscapeSet() {
    final String next = String.fromCharCode(runes[i + 1]);
    switch (next) {
      case 'd':
        i += 2;
        return _set(_digitRanges);
      case 'D':
        i += 2;
        return _negated(_digitRanges);
      case 'w':
        i += 2;
        return _set(_wordRanges);
      case 'W':
        i += 2;
        return _negated(_wordRanges);
      case 's':
        i += 2;
        return _set(_spaceRanges);
      case 'S':
        i += 2;
        return _negated(_spaceRanges);
      case 'p' || 'P':
        i += 2;
        final String name;
        if (!atEnd && runes[i] != 0x7b) {
          name = String.fromCharCode(runes[i]);
          i++;
        } else {
          final int end = runes.indexOf(0x7d, i);
          if (end < 0) {
            throw const InvalidPattern();
          }
          name = String.fromCharCodes(runes.sublist(i + 1, end));
          i = end + 1;
        }
        final bool Function(int) property = _property(name);
        return _CharSet(
          ranges: const <int>[],
          predicates: <bool Function(int)>[property],
          negated: next == 'P',
          ignoreCase: ignoreCase,
        );
    }
    return null;
  }

  /// The code point of an escape that stands for one character.
  int _escapedRune({required bool inClass}) {
    final int n = runes[i + 1];
    final String next = String.fromCharCode(n);
    i += 2;
    switch (next) {
      case 'n':
        return 0x0a;
      case 'r':
        return 0x0d;
      case 't':
        return 0x09;
      case 'f':
        return 0x0c;
      case 'v':
        return 0x0b;
      case 'a':
        return 0x07;
      case 'b' when inClass:
        return 0x08;
      case '0':
        if (!atEnd && runes[i] >= 0x30 && runes[i] <= 0x39) {
          throw const InvalidPattern();
        }
        return 0;
      case 'x':
        if (!atEnd && runes[i] == 0x7b) {
          // \x{1F600}: any code point.
          final int end = runes.indexOf(0x7d, i);
          final String hex = end < 0
              ? ''
              : String.fromCharCodes(runes.sublist(i + 1, end));
          final int? code = RegExp(r'^[0-9A-Fa-f]{1,8}$').hasMatch(hex)
              ? int.parse(hex, radix: 16)
              : null;
          if (code == null || code > 0x10ffff) {
            throw const InvalidPattern();
          }
          i = end + 1;
          return code;
        }
        if (i + 2 > runes.length) {
          throw const InvalidPattern();
        }
        final String hex = String.fromCharCodes(runes.sublist(i, i + 2));
        if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(hex)) {
          throw const InvalidPattern();
        }
        i += 2;
        return int.parse(hex, radix: 16);
      case 'C':
        throw UnsupportedPattern(r'\C (a single byte)');
    }
    if (RegExp('[A-Za-z0-9]').hasMatch(next)) {
      // Backreferences and letter escapes RE2 does not have.
      throw const InvalidPattern();
    }
    // An escaped punctuation character is that character.
    return n;
  }

  /// A character class after its `[`.
  _CharSet _class() {
    bool negated = false;
    if (peek() == 0x5e /* ^ */ ) {
      negated = true;
      i++;
    }
    final List<int> ranges = <int>[];
    final List<bool Function(int)> predicates = <bool Function(int)>[];
    bool first = true;
    while (true) {
      if (atEnd) {
        throw const InvalidPattern();
      }
      final int c = runes[i];
      if (c == 0x5d /* ] */ && !first) {
        i++;
        break;
      }
      first = false;
      // [:name:]
      if (c == 0x5b && peek(1) == 0x3a) {
        final int end = runes.indexOf(0x5d, i + 2);
        if (end < 0 || runes[end - 1] != 0x3a) {
          throw const InvalidPattern();
        }
        final String name = String.fromCharCodes(runes.sublist(i + 2, end - 1));
        final bool negatedName = name.startsWith('^');
        final String? body =
            _posixClasses[negatedName ? name.substring(1) : name];
        if (body == null) {
          throw const InvalidPattern();
        } else if (negatedName) {
          throw UnsupportedPattern('[:$name:]');
        }
        ranges.addAll(_posixRanges(body));
        i = end + 1;
        continue;
      }
      if (c == 0x5c /* \ */ ) {
        if (i + 1 >= runes.length) {
          throw const InvalidPattern();
        }
        final int n = runes[i + 1];
        if (n == 0x51 /* Q */ ) {
          i += 2;
          while (!atEnd &&
              !(runes[i] == 0x5c &&
                  i + 1 < runes.length &&
                  runes[i + 1] == 0x45)) {
            ranges
              ..add(runes[i])
              ..add(runes[i]);
            i++;
          }
          i += 2;
          continue;
        }
        if ('zABE'.contains(String.fromCharCode(n))) {
          throw const InvalidPattern();
        }
        final _CharSet? set = _classEscapeSet();
        if (set != null) {
          if (peek() == 0x2d && peek(1) != 0x5d && peek(1) != -1) {
            // A class can not be the bound of a range.
            throw const InvalidPattern();
          }
          predicates.add(set.matches);
          continue;
        }
      }
      final int low = c == 0x5c ? _escapedRune(inClass: true) : _next();
      if (peek() == 0x2d /* - */ && peek(1) != 0x5d && peek(1) != -1) {
        i++;
        final int hc = runes[i];
        if (hc == 0x5c &&
            i + 1 < runes.length &&
            'dDwWsSpP'.contains(String.fromCharCode(runes[i + 1]))) {
          throw const InvalidPattern();
        }
        final int high = hc == 0x5c ? _escapedRune(inClass: true) : _next();
        if (high < low) {
          throw const InvalidPattern();
        }
        ranges
          ..add(low)
          ..add(high);
      } else {
        ranges
          ..add(low)
          ..add(low);
      }
    }
    return _CharSet(
      ranges: ranges,
      predicates: predicates,
      negated: negated,
      ignoreCase: ignoreCase,
    );
  }

  int _next() => runes[i++];
}

final Map<String, RegExp> _properties = <String, RegExp>{};

/// The test for the Unicode property [name] (`L`, `Lu`, `Letter`, ...), as
/// Dart knows it.
bool Function(int) _property(String name) {
  RegExp? property = _properties[name];
  if (property == null) {
    try {
      property = RegExp('^\\p{$name}\$', unicode: true);
    } on FormatException {
      throw const InvalidPattern();
    }
    _properties[name] = property;
  }
  final RegExp test = property;
  final Map<int, bool> cache = <int, bool>{};
  return (int c) => cache[c] ??= test.hasMatch(String.fromCharCode(c));
}

// ---- the program ----

const int _opChar = 0;
const int _opLiteral = 1;
const int _opSplit = 2;
const int _opJump = 3;
const int _opSave = 4;
const int _opAssert = 5;
const int _opMatch = 6;

class _Compiler {
  final List<int> op = <int>[];
  final List<int> x = <int>[];
  final List<int> y = <int>[];
  final List<Object?> data = <Object?>[];

  int emit(int code, [int a = 0, int b = 0, Object? value]) {
    if (op.length >= maxRe2Instructions) {
      throw UnsupportedPattern(
        'the pattern is too large to be matched locally',
      );
    }
    op.add(code);
    x.add(a);
    y.add(b);
    data.add(value);
    return op.length - 1;
  }

  int get pc => op.length;

  void compile(_Node node) {
    switch (node) {
      case _Char():
        emit(_opChar, 0, 0, node.set);
      case _Literal():
        emit(_opLiteral, node.rune, node.ignoreCase ? 1 : 0, node.folded);
      case _Concat():
        for (final _Node child in node.nodes) {
          compile(child);
        }
      case _Alternation():
        final List<int> jumps = <int>[];
        for (int k = 0; k < node.nodes.length; k++) {
          if (k < node.nodes.length - 1) {
            final int split = emit(_opSplit);
            x[split] = pc;
            compile(node.nodes[k]);
            jumps.add(emit(_opJump));
            y[split] = pc;
          } else {
            compile(node.nodes[k]);
          }
        }
        for (final int jump in jumps) {
          x[jump] = pc;
        }
      case _Group():
        emit(_opSave, node.index * 2);
        compile(node.node);
        emit(_opSave, node.index * 2 + 1);
      case _Assert():
        emit(_opAssert, node.kind.index);
      case _Repeat():
        _repeat(node);
    }
  }

  void _setSplit(int split, int body, int exit, bool greedy) {
    x[split] = greedy ? body : exit;
    y[split] = greedy ? exit : body;
  }

  void _repeat(_Repeat node) {
    for (int k = 0; k < node.min; k++) {
      compile(node.node);
    }
    if (node.max < 0) {
      // x* as (x+)?, as RE2 does: an iteration that matches the empty string
      // still sets the groups in it, and the loop can not spin.
      final int split = emit(_opSplit);
      final int body = pc;
      compile(node.node);
      final int again = emit(_opSplit);
      _setSplit(again, body, pc, node.greedy);
      _setSplit(split, body, pc, node.greedy);
      return;
    }
    // (x(x(x)?)?)? for the optional copies.
    final List<int> splits = <int>[];
    for (int k = node.min; k < node.max; k++) {
      final int split = emit(_opSplit);
      splits.add(split);
      x[split] = pc; // body follows; the exit is set below
      compile(node.node);
    }
    for (final int split in splits) {
      _setSplit(split, split + 1, pc, node.greedy);
    }
  }
}

/// A match of an [Re2] in a string. Positions are UTF-16 indices.
class Re2Match {
  Re2Match(this.input, this._captures, this._names);

  final String input;
  final List<int> _captures;
  final Map<String, int> _names;

  int get start => _captures[0];

  int get end => _captures[1];

  /// The number of capturing groups of the pattern.
  int get groupCount => _captures.length ~/ 2 - 1;

  /// The text of the group [index] (0 is the whole match), or null if it did
  /// not take part in the match.
  String? group(int index) {
    final int s = _captures[2 * index];
    final int e = _captures[2 * index + 1];
    return s < 0 || e < 0 ? null : input.substring(s, e);
  }

  String? namedGroup(String name) {
    final int? index = _names[name];
    if (index == null) {
      throw ArgumentError.value(name, 'name', 'Not a capture group name');
    }
    return group(index);
  }
}

/// A compiled RE2 pattern.
class Re2 {
  Re2._(this._compiler, this.groupCount, this._names);

  final _Compiler _compiler;

  /// The number of capturing groups.
  final int groupCount;
  final Map<String, int> _names;

  /// Whether the pattern matches anywhere in [input].
  bool hasMatch(String input) => firstMatch(input) != null;

  /// The leftmost match at or after [start], the one a backtracking engine
  /// would find.
  Re2Match? firstMatch(String input, [int start = 0]) =>
      _run(input, start, anchored: false);

  /// The match that starts exactly at [start], if any.
  Re2Match? matchAsPrefix(String input, [int start = 0]) =>
      _run(input, start, anchored: true);

  Re2Match? _run(String input, int start, {required bool anchored}) {
    final List<int> op = _compiler.op;
    final List<int> xs = _compiler.x;
    final List<int> ys = _compiler.y;
    final List<Object?> data = _compiler.data;
    final int slots = (groupCount + 1) * 2;
    final int length = input.length;
    final int size = op.length;

    // Threads of the current and of the next position, in priority order;
    // `onList` marks the instructions already on a list for its position.
    List<int> currentPcs = <int>[];
    List<List<int>> currentCaps = <List<int>>[];
    List<int> nextPcs = <int>[];
    List<List<int>> nextCaps = <List<int>>[];
    final List<int> mark = List<int>.filled(size, -1);
    // The generation of the current list; the next list has the one after.
    int generation = 1;
    List<int>? matched;
    int steps = 0;

    // The code points around the position: for assertions.
    int previous(int position) {
      if (position <= 0) {
        return -1;
      }
      final int unit = input.codeUnitAt(position - 1);
      if (unit >= 0xdc00 &&
          unit <= 0xdfff &&
          position >= 2 &&
          _isHigh(input.codeUnitAt(position - 2))) {
        return 0x10000 +
            ((input.codeUnitAt(position - 2) - 0xd800) << 10) +
            (unit - 0xdc00);
      }
      return unit;
    }

    int at(int position) {
      if (position >= length) {
        return -1;
      }
      final int unit = input.codeUnitAt(position);
      if (_isHigh(unit) && position + 1 < length) {
        final int low = input.codeUnitAt(position + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          return 0x10000 + ((unit - 0xd800) << 10) + (low - 0xdc00);
        }
      }
      return unit;
    }

    bool holds(int kind, int position) {
      switch (_AssertKind.values[kind]) {
        case _AssertKind.textStart:
          return position == 0;
        case _AssertKind.textEnd:
          return position == length;
        case _AssertKind.lineStart:
          final int p = previous(position);
          return p < 0 || _isLineTerminator(p);
        case _AssertKind.lineEnd:
          final int c = at(position);
          return c < 0 || _isLineTerminator(c);
        case _AssertKind.wordBoundary:
          final int p = previous(position);
          final int c = at(position);
          return (p >= 0 && _isWord(p)) != (c >= 0 && _isWord(c));
        case _AssertKind.notWordBoundary:
          final int p = previous(position);
          final int c = at(position);
          return (p >= 0 && _isWord(p)) == (c >= 0 && _isWord(c));
      }
    }

    // Follows jumps, splits, saves and assertions from [pc] and adds the
    // threads that wait for a character (or match) to the list, in priority
    // order.
    final List<int> stackPcs = <int>[];
    final List<List<int>> stackCaps = <List<int>>[];
    void add(
      List<int> pcs,
      List<List<int>> caps,
      int pc0,
      List<int> caps0,
      int position,
    ) {
      stackPcs.add(pc0);
      stackCaps.add(caps0);
      while (stackPcs.isNotEmpty) {
        final int pc = stackPcs.removeLast();
        final List<int> c = stackCaps.removeLast();
        if (mark[pc] == generation) {
          continue;
        }
        mark[pc] = generation;
        steps++;
        switch (op[pc]) {
          case _opJump:
            stackPcs.add(xs[pc]);
            stackCaps.add(c);
          case _opSplit:
            // The second target is pushed first so the first runs first.
            stackPcs
              ..add(ys[pc])
              ..add(xs[pc]);
            stackCaps
              ..add(c)
              ..add(c);
          case _opSave:
            final List<int> copy = List<int>.of(c);
            copy[xs[pc]] = position;
            stackPcs.add(pc + 1);
            stackCaps.add(copy);
          case _opAssert:
            if (holds(xs[pc], position)) {
              stackPcs.add(pc + 1);
              stackCaps.add(c);
            }
          default:
            pcs.add(pc);
            caps.add(c);
        }
      }
    }

    int position = start;
    while (true) {
      if (matched == null && (!anchored || position == start)) {
        // A new thread starting here, with the lowest priority.
        final List<int> caps = List<int>.filled(slots, -1);
        caps[0] = position;
        add(currentPcs, currentCaps, 0, caps, position);
      }
      if (currentPcs.isEmpty) {
        if (matched != null || anchored || position >= length) {
          break;
        }
        // No thread here: a match can only start further on.
        position += at(position) > 0xffff ? 2 : 1;
        generation++;
        continue;
      }
      if (steps > maxRe2Steps) {
        throw UnsupportedPattern(
          'the input is too long for this pattern to be matched locally',
        );
      }
      final int c = at(position);
      final int width = c > 0xffff ? 2 : 1;
      generation++;
      for (int t = 0; t < currentPcs.length; t++) {
        final int pc = currentPcs[t];
        final List<int> caps = currentCaps[t];
        steps++;
        switch (op[pc]) {
          case _opMatch:
            final List<int> result = List<int>.of(caps);
            result[1] = position;
            matched = result;
            // Lower priority threads are cut off.
            t = currentPcs.length;
          case _opChar:
            if (c >= 0 && (data[pc]! as _CharSet).matches(c)) {
              add(nextPcs, nextCaps, pc + 1, caps, position + width);
            }
          case _opLiteral:
            if (c >= 0 &&
                (c == xs[pc] ||
                    (ys[pc] == 1 && _fold(c) == (data[pc]! as int)))) {
              add(nextPcs, nextCaps, pc + 1, caps, position + width);
            }
        }
      }
      if (c < 0) {
        break;
      }
      position += width;
      final List<int> swapPcs = currentPcs;
      final List<List<int>> swapCaps = currentCaps;
      currentPcs = nextPcs;
      currentCaps = nextCaps;
      nextPcs = swapPcs..clear();
      nextCaps = swapCaps..clear();
      if (matched != null && currentPcs.isEmpty) {
        break;
      }
    }
    final List<int>? result = matched;
    return result == null ? null : Re2Match(input, result, _names);
  }
}

bool _isHigh(int unit) => unit >= 0xd800 && unit <= 0xdbff;

/// Compiles the RE2 [pattern].
///
/// Like RE2, a pattern has no backreferences and no lookaround (a pattern
/// with them is an [InvalidPattern]), `.` matches everything but a line
/// feed, and `\d`, `\w` and `\b` are about ASCII only.
///
/// Flags are only understood at the very start of the pattern (`(?i)`,
/// `(?s)`, `(?m)` and combinations): `a(?i)b` and `(?i:a)b` are an
/// [UnsupportedPattern].
///
/// With [anchored] the pattern has to match the whole input.
Re2 compileRe2(String pattern, {bool anchored = false}) {
  final _Parser parser = _Parser(pattern);
  final _Node node = parser.parse();
  final _Compiler compiler = _Compiler();
  compiler.compile(
    _Concat(<_Node>[
      if (anchored) _Assert(_AssertKind.textStart),
      node,
      if (anchored) _Assert(_AssertKind.textEnd),
    ]),
  );
  compiler
    ..emit(_opSave, 1)
    ..emit(_opMatch);
  return Re2._(compiler, parser.groups, Map<String, int>.of(parser.names));
}
