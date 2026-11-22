// Lists the exported public API of the package from its source text.
//
// The other two database packages list their API with dart:mirrors (see
// firebase_database_dart/test/api/support/public_api_describer.dart). This
// package imports Flutter, which neither `flutter test` nor the plain Dart VM
// can combine with dart:mirrors, so the declarations are read from the source
// instead, parsed with package:analyzer (syntax only, nothing resolved): for
// each exported name, the header of the declaration and the header of each
// public member (up to its body, `=>`, `;` or field initializer), as the source
// tokens joined by single spaces, comments and `@override` left out,
// nullability and defaults kept. It reads `lib/` relative to the working
// directory (the package root).

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

/// The listing of the exports of `lib/<library>`, entries sorted by name.
///
/// Follows the `export` directives of the library to files of this package
/// (`package:<this package>/...` or relative URIs), one level deep. Throws a
/// [StateError] for an export of another package or for a `show` name that
/// has no public declaration in the exported file.
String listPublicApi(String library) {
  final CompilationUnit unit = _parse(
    File('lib/$library').readAsStringSync(),
    'lib/$library',
  );
  final List<ApiEntry> entries = <ApiEntry>[...apiEntriesOf(unit)];
  for (final ExportDirective export
      in unit.directives.whereType<ExportDirective>()) {
    final String uri = export.uri.stringValue!;
    final String path = _libPath(uri, library);
    final Set<String>? shown = _names<ShowCombinator>(export);
    final Set<String> hidden = _names<HideCombinator>(export) ?? <String>{};
    final List<ApiEntry> exported = apiEntriesOf(
      _parse(File(path).readAsStringSync(), path),
    ).where((ApiEntry e) => !hidden.contains(e.name)).toList();
    if (shown != null) {
      exported.retainWhere((ApiEntry e) => shown.contains(e.name));
      final Set<String> missing = shown.difference(
        exported.map((ApiEntry e) => e.name).toSet(),
      );
      if (missing.isNotEmpty) {
        throw StateError(
          'The lister found no public declaration of $missing in $uri. '
          'Check the `show` list of that export, or teach '
          'test/public_api_lister.dart that kind of declaration.',
        );
      }
    }
    entries.addAll(exported);
  }
  return formatApiEntries(entries);
}

/// The listing of the public declarations of the Dart library [source], as
/// [listPublicApi] writes them; [only], when given, keeps the named ones.
String listPublicApiOfSource(String source, {Set<String>? only}) {
  final List<ApiEntry> entries = apiEntriesOf(_parse(source, 'source.dart'));
  if (only != null) {
    entries.retainWhere((ApiEntry e) => only.contains(e.name));
  }
  return formatApiEntries(entries);
}

/// The listing of [entries]: sorted by name, each entry its header line, then
/// its member lines indented by two spaces and sorted. Checks each entry with
/// [checkApiEntry].
String formatApiEntries(List<ApiEntry> entries) {
  final List<ApiEntry> sorted = <ApiEntry>[...entries]
    ..sort((ApiEntry a, ApiEntry b) => a.name.compareTo(b.name));
  final StringBuffer out = StringBuffer();
  for (final ApiEntry entry in sorted) {
    checkApiEntry(entry);
    out.writeln(entry.header);
    for (final String member in <String>[...entry.members]..sort()) {
      out.writeln('  $member');
    }
  }
  return out.toString();
}

/// One public top-level declaration and the headers of its public members.
class ApiEntry {
  /// An entry; [publicMembersInSource] is what [checkApiEntry] compares
  /// [members] with.
  ApiEntry({
    required this.name,
    required this.header,
    this.members = const <String>[],
    this.publicMembersInSource = 0,
  });

  /// The declared name.
  final String name;

  /// The declaration up to its body (or up to `;`), on one line.
  final String header;

  /// The member headers, unsorted and without indentation.
  final List<String> members;

  /// How many public members (enum values included) the source body declares.
  final int publicMembersInSource;
}

/// Throws a [StateError] when [entry] shows that the lister misread the
/// source: a line with no name in it, a header that does not name the entry,
/// or no member lines for a body that declares public members.
void checkApiEntry(ApiEntry entry) {
  for (final String line in <String>[entry.header, ...entry.members]) {
    if (!RegExp(r'[A-Za-z_$]').hasMatch(line)) {
      throw StateError(
        'The lister wrote "$line" under ${entry.name}, a line without a name: '
        'it misread the source. Fix test/public_api_lister.dart.',
      );
    }
  }
  final RegExp name = RegExp(
    '(^|[^\\w\$])${RegExp.escape(entry.name)}'
    '(\$|[^\\w\$])',
  );
  if (!name.hasMatch(entry.header)) {
    throw StateError(
      'The header "${entry.header}" does not name ${entry.name}: the lister '
      'misread the source. Fix test/public_api_lister.dart.',
    );
  }
  if (entry.members.isEmpty && entry.publicMembersInSource > 0) {
    throw StateError(
      '${entry.name} declares ${entry.publicMembersInSource} public members '
      'but the lister wrote none: it misread the source. Fix '
      'test/public_api_lister.dart.',
    );
  }
}

/// The entries of the public top-level declarations of [unit] (unnamed
/// extensions have no name to export and are left out).
List<ApiEntry> apiEntriesOf(CompilationUnit unit) {
  if (unit.directives.any((Directive d) => d is PartDirective)) {
    throw StateError(
      'The lister does not read `part` files. Teach '
      'test/public_api_lister.dart to follow them.',
    );
  }
  final List<ApiEntry> entries = <ApiEntry>[];
  for (final CompilationUnitMember d in unit.declarations) {
    final ApiEntry? entry = switch (d) {
      ClassDeclaration() => _container(d, d.namePart.typeName, d.body),
      MixinDeclaration() => _container(d, d.name, d.body),
      ExtensionDeclaration(:final Token name?) => _container(d, name, d.body),
      ExtensionTypeDeclaration() => _container(
        d,
        d.primaryConstructor.typeName,
        d.body,
      ),
      EnumDeclaration() => _enum(d),
      TypeAlias() when _public(d.name) => ApiEntry(
        name: d.name.lexeme,
        header: _header(d, d.semicolon),
      ),
      FunctionDeclaration() when _public(d.name) => ApiEntry(
        name: d.name.lexeme,
        header: _header(d, d.functionExpression.body.beginToken),
      ),
      _ => null,
    };
    if (entry != null) {
      entries.add(entry);
    } else if (d is TopLevelVariableDeclaration) {
      for (final (String name, String line) in _variables(d, d.variables)) {
        entries.add(ApiEntry(name: name, header: line));
      }
    }
  }
  return entries;
}

ApiEntry? _container(AnnotatedNode d, Token name, ClassBody body) {
  if (!_public(name)) {
    return null;
  }
  return ApiEntry(
    name: name.lexeme,
    header: _header(d, body.beginToken),
    members: _members(body.members),
    publicMembersInSource: _publicCount(body.members),
  );
}

ApiEntry? _enum(EnumDeclaration d) {
  final Token name = d.namePart.typeName;
  if (!_public(name)) {
    return null;
  }
  final List<EnumConstantDeclaration> values = d.body.constants;
  return ApiEntry(
    name: name.lexeme,
    header: _header(d, d.body.beginToken),
    members: <String>[
      for (final EnumConstantDeclaration v in values) v.name.lexeme,
      ..._members(d.body.members),
    ],
    publicMembersInSource: values.length + _publicCount(d.body.members),
  );
}

/// The header lines of the public members among [members].
List<String> _members(List<ClassMember> members) => <String>[
  for (final ClassMember m in members)
    ...switch (m) {
      MethodDeclaration() when _public(m.name) => <String>[
        _header(m, m.body.beginToken),
      ],
      ConstructorDeclaration() when _publicConstructor(m) => <String>[
        _header(m, m.body.beginToken),
      ],
      FieldDeclaration() => <String>[
        for (final (String _, String line) in _variables(m, m.fields)) line,
      ],
      _ => const <String>[],
    },
];

/// How many of [members] have a public name (an unnamed constructor counts).
int _publicCount(List<ClassMember> members) => members
    .where(
      (ClassMember m) => switch (m) {
        MethodDeclaration() => _public(m.name),
        ConstructorDeclaration() => _publicConstructor(m),
        FieldDeclaration() => m.fields.variables.any(
          (VariableDeclaration v) => _public(v.name),
        ),
        _ => false,
      },
    )
    .length;

bool _publicConstructor(ConstructorDeclaration c) {
  final Token? name = c.name;
  return name == null || _public(name);
}

/// The name and the line of each public variable of [list], declared by [d]:
/// annotations, modifiers and type, then the name (the initializer left out).
List<(String, String)> _variables(
  AnnotatedNode d,
  VariableDeclarationList list,
) {
  final String prefix = _header(d, list.variables.first.name);
  return <(String, String)>[
    for (final VariableDeclaration v in list.variables)
      if (_public(v.name))
        (
          v.name.lexeme,
          prefix.isEmpty ? v.name.lexeme : '$prefix ${v.name.lexeme}',
        ),
  ];
}

/// The text of [node] from its first annotation up to [end] (excluded), on
/// one line; `@override` is left out.
String _header(AnnotatedNode node, Token end) {
  final LineInfo lines = (node.root as CompilationUnit).lineInfo;
  return <String>[
    for (final Annotation a in node.metadata)
      if (!(a.name.name == 'override' && a.arguments == null))
        _tokens(a.beginToken, a.endToken.next!, lines),
    _tokens(node.firstTokenAfterCommentAndMetadata, end, lines),
  ].where((String part) => part.isNotEmpty).join(' ');
}

const Set<String> _openers = <String>{'(', '[', '{', '<'};
const Set<String> _closers = <String>{')', ']', '}', '>'};

/// The tokens from [from] up to [end] (excluded), joined by one space where
/// the source has whitespace or a comment between them. Inside brackets the
/// space is dropped (`(\n  a,\n  b,\n)` is `(a, b)`), and so is a trailing
/// comma; for `<` and `>` only when the source breaks the line there, since
/// they are also operators.
String _tokens(Token from, Token end, LineInfo lines) {
  final StringBuffer out = StringBuffer();
  for (Token t = from; t != end && !t.isEof; t = t.next!) {
    final Token next = t.next!;
    final bool closes = _closers.contains(next.lexeme);
    if (t.type == TokenType.COMMA && closes) {
      continue;
    }
    out.write(t.lexeme);
    if (next == end || next.offset <= t.end) {
      continue;
    }
    final bool angle = t.lexeme == '<' || next.lexeme == '>';
    final bool lineBreak =
        lines.getLocation(next.offset).lineNumber !=
        lines.getLocation(t.end).lineNumber;
    final bool bracket = _openers.contains(t.lexeme) || closes;
    if (!bracket || (angle && !lineBreak)) {
      out.write(' ');
    }
  }
  return out.toString();
}

bool _public(Token name) => !name.lexeme.startsWith('_');

CompilationUnit _parse(String source, String path) =>
    parseString(content: source, path: path).unit;

/// The path of the file that the URI of an export of `lib/<library>` names.
String _libPath(String uri, String library) {
  final String pubspec = File('pubspec.yaml').readAsStringSync();
  final String package = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!;
  if (uri.startsWith('package:$package/')) {
    return 'lib/${uri.substring('package:$package/'.length)}';
  }
  if (!uri.contains(':')) {
    return Uri.file('lib/$library').resolve(uri).toFilePath();
  }
  throw StateError(
    'The lister does not follow the export of $uri (not this package). Teach '
    'test/public_api_lister.dart to list it if it belongs in the golden.',
  );
}

/// The names of the combinators of type [T] of [export], null without any.
Set<String>? _names<T extends Combinator>(ExportDirective export) {
  final List<T> combinators = export.combinators.whereType<T>().toList();
  if (combinators.isEmpty) {
    return null;
  }
  return <String>{
    for (final T c in combinators)
      ...switch (c) {
        ShowCombinator() => c.shownNames,
        HideCombinator() => c.hiddenNames,
      }.map((SimpleIdentifier n) => n.name),
  };
}
