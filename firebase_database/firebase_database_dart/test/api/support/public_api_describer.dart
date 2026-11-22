// The generator of the public API goldens of the three database packages. It is
// the generator of cloud_firestore_dart (test/unit/api/public_api_golden_test.dart)
// copied, with the package name and the library as parameters: that file is a
// test of another package with its own name hard-coded, so it cannot be imported.
// Keep the two listings in the same format.
//
// The listing is built with dart:mirrors, so it works under `dart test` (JIT),
// not in AOT or under `flutter test`. Mirrors do not expose nullability, so `T`
// and `T?` look the same in the listing. Typedefs are not listed by mirrors; they
// are read from the source text (nullability kept), relative to the working
// directory, which is the package root under `dart test`.

import 'dart:io';
import 'dart:mirrors';

/// The type variables of the class in the parameters of a constructor, as
/// dart:mirrors prints them: `X0`, `C1X0`, `dart.core.Null.X0`.
final RegExp _classTypeVariable = RegExp(
  r'(?:dart\.core\.Null\.)?\b(?:C\d+)?X\d+\b',
);

/// The parameter list of a constructor with the type variables of its class
/// written as `dynamic`. Dart SDKs disagree about them: up to 3.12 mirrors
/// print the variable (`FirestoreDataConverter<X0> converter`) for every
/// constructor, 3.14 prints `dynamic` for factory constructors only. The
/// listing must not depend on the SDK that runs the test.
String _constructorParams(String params) =>
    params.replaceAll(_classTypeVariable, 'dynamic');

bool _isPublic(Symbol symbol) => !MirrorSystem.getName(symbol).startsWith('_');

final RegExp _typedef = RegExp(
  r'^typedef (\w+)(?:<[^=]*>)?\s*=\s*([^;]+);',
  multiLine: true,
);

/// The right-hand side of a typedef on one line, independent of how the
/// formatter laid it out (line breaks, trailing commas).
String _normalizeTypedef(String type) => type
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'([(\[{<]) '), (Match m) => m.group(1)!)
    .replaceAllMapped(RegExp(r',? ?([)\]}>])'), (Match m) => m.group(1)!)
    .trim();

String _name(Symbol symbol) => MirrorSystem.getName(symbol);

/// Whether the `show` / `hide` combinators of the export `dep` let `symbol`
/// through, so names hidden in the barrel do not appear in the listing.
///
/// Mirrors report `show A, B` as one combinator per name, so the shown names
/// are the union of all `show` combinators.
///
/// Mirrors list the members of an extension as library members named
/// `Extension.member`; they are exported when the extension is.
bool _isExportedBy(LibraryDependencyMirror dep, Symbol member) {
  final String name = MirrorSystem.getName(member);
  final Symbol symbol = name.contains('.')
      ? Symbol(name.substring(0, name.indexOf('.')))
      : member;
  final Iterable<CombinatorMirror> shows = dep.combinators.where(
    (CombinatorMirror c) => c.isShow,
  );
  if (shows.isNotEmpty &&
      !shows.any((CombinatorMirror c) => c.identifiers.contains(symbol))) {
    return false;
  }
  return !dep.combinators.any(
    (CombinatorMirror c) => c.isHide && c.identifiers.contains(symbol),
  );
}

String _type(TypeMirror type) {
  if (type is ClassMirror && type.typeArguments.isNotEmpty) {
    return '${_name(type.simpleName)}<${type.typeArguments.map(_type).join(', ')}>';
  }
  return _name(type.simpleName);
}

String _flags(DeclarationMirror mirror) {
  final StringBuffer buffer = StringBuffer();
  for (final InstanceMirror meta in mirror.metadata) {
    if (meta.reflectee is Deprecated) {
      buffer.write(' @deprecated');
    } else if (meta.reflectee.runtimeType.toString() == '_Internal') {
      buffer.write(' @internal');
    }
  }
  return buffer.toString();
}

String _params(MethodMirror method) {
  final List<String> positional = <String>[];
  final List<String> optional = <String>[];
  final List<String> named = <String>[];
  for (final ParameterMirror p in method.parameters) {
    final String text = '${_type(p.type)} ${_name(p.simpleName)}';
    if (p.isNamed) {
      named.add(text);
    } else if (p.isOptional) {
      optional.add(text);
    } else {
      positional.add(text);
    }
  }
  final List<String> parts = <String>[
    ...positional,
    if (optional.isNotEmpty) '[${optional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ];
  return '(${parts.join(', ')})';
}

List<String> _describeClass(ClassMirror cls) {
  final String kind = cls.isEnum
      ? 'enum'
      : cls.isAbstract
      ? 'abstract class'
      : 'class';
  final String superclass =
      cls.superclass != null &&
          cls.superclass!.simpleName != #Object &&
          !cls.isEnum
      ? ' extends ${_type(cls.superclass!)}'
      : '';
  final List<String> lines = <String>[
    '$kind ${_name(cls.simpleName)}$superclass${_flags(cls)}',
  ];
  final List<String> members = <String>[];
  for (final DeclarationMirror d in cls.declarations.values) {
    if (!_isPublic(d.simpleName)) {
      continue;
    }
    if (d is MethodMirror) {
      final String isStatic = d.isStatic ? 'static ' : '';
      final String name = _name(d.simpleName);
      if (d.isConstructor) {
        // The simple name of a named constructor is `Class.name`, so a
        // private one (`Class._`) passes the check above.
        if (_name(d.constructorName).startsWith('_')) {
          continue;
        }
        members.add('  new $name${_constructorParams(_params(d))}${_flags(d)}');
      } else if (d.isGetter) {
        members.add(
          '  ${isStatic}get $name: ${_type(d.returnType)}${_flags(d)}',
        );
      } else if (d.isSetter) {
        members.add('  ${isStatic}set $name${_params(d)}${_flags(d)}');
      } else {
        members.add(
          '  $isStatic$name${_params(d)}: ${_type(d.returnType)}${_flags(d)}',
        );
      }
    } else if (d is VariableMirror) {
      members.add(
        '  ${d.isStatic ? 'static ' : ''}${d.isFinal ? 'final ' : ''}${_name(d.simpleName)}: ${_type(d.type)}${_flags(d)}',
      );
    }
  }
  members.sort();
  return <String>[...lines, ...members];
}

/// The API exported by the library file [library] of [package], for example
/// `describePublicApi('firebase_database_dart', 'testing.dart')`. The library
/// must be imported (directly or not) by the program that calls this, so that
/// the mirror system has loaded it. Libraries are found by their URI.
///
/// Unlike the generator of cloud_firestore_dart, an export of an exported
/// library is followed (with every `show` / `hide` on the way), because
/// `src/api/database_logger.dart` only re-exports the logger types.
String describePublicApi(String package, String library) {
  final LibraryMirror barrel =
      currentMirrorSystem().libraries[Uri.parse('package:$package/$library')]!;
  final Map<String, List<String>> entries = <String, List<String>>{};
  _collect(package, barrel, <LibraryDependencyMirror>[], entries);
  final List<String> names = entries.keys.toList()..sort();
  return '${names.expand((String n) => entries[n]!).join('\n')}\n';
}

/// Adds the exports of [library] to [entries]; [chain] are the exports that
/// led to it, each of which must let a name through.
void _collect(
  String package,
  LibraryMirror library,
  List<LibraryDependencyMirror> chain,
  Map<String, List<String>> entries,
) {
  bool passes(Symbol symbol) =>
      chain.every((LibraryDependencyMirror dep) => _isExportedBy(dep, symbol));
  if (chain.isNotEmpty) {
    for (final DeclarationMirror d in library.declarations.values) {
      if (!_isPublic(d.simpleName) || !passes(d.simpleName)) {
        continue;
      }
      final String name = _name(d.simpleName);
      if (d is ClassMirror) {
        entries[name] = _describeClass(d);
      } else if (d is TypedefMirror) {
        entries[name] = <String>[
          'typedef $name = ${_type(d.referent)}${_flags(d)}',
        ];
      } else if (d is MethodMirror) {
        entries[name] = <String>[
          '${d.isGetter ? 'get ' : ''}$name${d.isGetter ? '' : _params(d)}: ${_type(d.returnType)}${_flags(d)}',
        ];
      } else if (d is VariableMirror) {
        entries[name] = <String>['var $name: ${_type(d.type)}${_flags(d)}'];
      }
    }
    // dart:mirrors does not list typedefs in `declarations`, so they are read
    // from the source of the exported library (tests run in the package root).
    final List<String> segments = library.uri.pathSegments;
    if (segments.first == package) {
      final String source = File(
        'lib/${segments.skip(1).join('/')}',
      ).readAsStringSync();
      for (final RegExpMatch m in _typedef.allMatches(source)) {
        final String name = m.group(1)!;
        if (!name.startsWith('_') && passes(Symbol(name))) {
          entries[name] = <String>[
            'typedef $name = ${_normalizeTypedef(m.group(2)!)}',
          ];
        }
      }
    }
  }
  for (final LibraryDependencyMirror dep in library.libraryDependencies) {
    if (dep.isExport) {
      _collect(package, dep.targetLibrary!, <LibraryDependencyMirror>[
        ...chain,
        dep,
      ], entries);
    }
  }
}
