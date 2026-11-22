// Lists the exported public API of the package from its source text.
//
// The other two database packages list their API with dart:mirrors (see
// firebase_database_dart/test/api/support/public_api_describer.dart). This package
// imports Flutter, which neither `flutter test` nor the plain Dart VM can combine
// with dart:mirrors, so the declarations are read from the source instead: for
// each exported name, the header of the declaration and the header of each public
// member (up to its body, `=>` or initializer), whitespace normalized, nullability
// and defaults kept. Only dart:io is used, so a plain `dart` program can run it.
// It reads `lib/` relative to the working directory (the package root).

import 'dart:io';

/// The listing of the exports of `lib/<library>`, entries sorted by name.
String listPublicApi(String library) {
  final String barrelText = File(
    'lib/$library',
  ).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
  final Map<String, List<String>> entries = <String, List<String>>{};
  // Names the barrel declares itself.
  _collect(_stripped(barrelText), null, entries);
  // Names it exports from `src`.
  final RegExp export = RegExp(
    r'''export\s+'package:[\w]+/(src/[\w/]+\.dart)'\s+show\s+([^;]+);''',
  );
  for (final RegExpMatch m in export.allMatches(barrelText)) {
    final String source = _stripped(
      File('lib/${m.group(1)}').readAsStringSync(),
    );
    final Set<String> names = m
        .group(2)!
        .split(',')
        .map((String n) => n.trim())
        .toSet();
    _collect(source, names, entries);
  }
  final List<String> names = entries.keys.toList()..sort();
  return '${names.expand((String n) => entries[n]!).join('\n')}\n';
}

final RegExp _declaration = RegExp(
  r'^(?:(?:abstract|base|final|sealed|interface|mixin) +)*(class|enum|mixin|typedef) +(\w+)',
  multiLine: true,
);

void _collect(
  String source,
  Set<String>? only,
  Map<String, List<String>> entries,
) {
  for (final RegExpMatch m in _declaration.allMatches(source)) {
    final String name = m.group(2)!;
    if (name.startsWith('_') || (only != null && !only.contains(name))) {
      continue;
    }
    final int start = m.start;
    if (m.group(1) == 'typedef') {
      entries[name] = <String>[
        _oneLine(source.substring(start, source.indexOf(';', start))),
      ];
      continue;
    }
    final int open = source.indexOf('{', start);
    final int close = _matching(source, open);
    entries[name] = <String>[
      _oneLine(source.substring(start, open)),
      ..._members(source.substring(open + 1, close)),
    ];
  }
}

/// The headers of the public members of a class body, sorted.
List<String> _members(String body) {
  final List<String> members = <String>[];
  final StringBuffer statement = StringBuffer();
  int depth = 0;
  bool skipping = false; // after `=>` or a field initializer, up to the `;`
  for (int i = 0; i < body.length; i++) {
    final String c = body[i];
    if (depth == 0 && !skipping && body.startsWith('=>', i)) {
      skipping = true;
    } else if (depth == 0 &&
        !skipping &&
        c == '=' &&
        _atInitializer(statement.toString())) {
      skipping = true;
    }
    if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
    }
    final bool blockEnds = c == '}' && depth == 0 && !skipping;
    final bool hasBlock =
        c == '{' &&
        depth == 1 &&
        !skipping &&
        !_inParameters(statement.toString());
    if (hasBlock) {
      // The body of a method: skip it, then the member is complete.
      i = _matching(body, i);
      depth = 0;
      _add(members, statement.toString());
      statement.clear();
      continue;
    }
    if (c == ';' && depth == 0) {
      _add(members, statement.toString());
      statement.clear();
      skipping = false;
    } else if (!skipping && !blockEnds) {
      statement.write(c);
    }
  }
  _add(members, statement.toString());
  members.sort();
  return members;
}

/// Whether `=` here starts an initializer (parentheses of the statement are closed).
bool _atInitializer(String text) =>
    '('.allMatches(text).length == ')'.allMatches(text).length;

/// Whether a `{` after [text] opens the named parameters (a `(` is still open).
bool _inParameters(String text) =>
    '('.allMatches(text).length > ')'.allMatches(text).length;

void _add(List<String> members, String raw) {
  String text = _oneLine(raw)
      .replaceAll(RegExp(r'^@override '), '')
      .replaceAll(RegExp(r' async\*?$'), '');
  if (text.isEmpty) {
    return;
  }
  final String head = text.split(RegExp(r'[(=]')).first.trim();
  if (head.split(RegExp(r'[ .]')).any((String part) => part.startsWith('_'))) {
    return;
  }
  members.add('  $text');
}

/// [source] without comments and with string literals emptied, so that braces
/// and semicolons in them do not count.
String _stripped(String source) => source
    .replaceAll(RegExp(r'//[^\n]*'), '')
    .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''")
    .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

String _oneLine(String text) => text
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'([(\[{<]) '), (Match m) => m.group(1)!)
    .replaceAllMapped(RegExp(r',? ?([)\]}>])'), (Match m) => m.group(1)!)
    .trim();

/// The index of the brace that closes the one at [open].
int _matching(String text, int open) {
  int depth = 0;
  for (int i = open; i < text.length; i++) {
    if (text[i] == '{') {
      depth++;
    } else if (text[i] == '}' && --depth == 0) {
      return i;
    }
  }
  throw StateError('Unbalanced braces after offset $open.');
}
