// Golden listing of the exported public API (names, parameters, deprecations).
//
// A failing test means the public surface changed. Review the diff of
// test/unit/api/public_api.golden.txt; if the change is intended, regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart
//
// The listing is built with dart:mirrors from the `cloud_firestore_dart` barrel,
// so it works under `dart test` (JIT), not in AOT. Mirrors do not expose
// nullability, so `T` and `T?` look the same in the listing. Typedefs are not
// listed by mirrors; they are read from the source text (nullability kept).

import 'dart:io';
import 'dart:mirrors';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
// Loaded so that the lite library can be found by the mirror system.
// ignore: unused_import
import 'package:cloud_firestore_dart/lite.dart' as lite;
// Loaded so that the pipelines library can be found by the mirror system.
// ignore: unused_import
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:test/test.dart';

/// The type variables of the class in the parameters of a constructor, as
/// dart:mirrors prints them: `X0`, `C1X0`, `dart.core.Null.X0`.
final RegExp _classTypeVariable =
    RegExp(r'(?:dart\.core\.Null\.)?\b(?:C\d+)?X\d+\b');

/// The parameter list of a constructor with the type variables of its class
/// written as `dynamic`. Dart SDKs disagree about them: up to 3.12 mirrors
/// print the variable (`FirestoreDataConverter<X0> converter`) for every
/// constructor, 3.14 prints `dynamic` for factory constructors only. The
/// listing must not depend on the SDK that runs the test.
String _constructorParams(String params) =>
    params.replaceAll(_classTypeVariable, 'dynamic');

bool _isPublic(Symbol symbol) => !MirrorSystem.getName(symbol).startsWith('_');

final RegExp _typedef =
    RegExp(r'^typedef (\w+)(?:<[^=]*>)?\s*=\s*([^;]+);', multiLine: true);

/// The right-hand side of a typedef on one line, independent of how the
/// formatter laid it out (line breaks, trailing commas).
String _normalizeTypedef(String type) => type
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'([(\[{<]) '), (Match m) => m.group(1)!)
    .replaceAllMapped(RegExp(r',? ?([)\]}>])'), (Match m) => m.group(1)!)
    .trim();

String _name(Symbol symbol) => MirrorSystem.getName(symbol);

/// Whether the `show` / `hide` combinators of the export [dep] let [symbol]
/// through, so names hidden in the barrel do not appear in the listing.
///
/// Mirrors report `show A, B` as one combinator per name, so the shown names
/// are the union of all `show` combinators.
///
/// Mirrors list the members of an extension as library members named
/// `Extension.member`; they are exported when the extension is.
bool _isExportedBy(LibraryDependencyMirror dep, Symbol member) {
  final String name = MirrorSystem.getName(member);
  final Symbol symbol =
      name.contains('.') ? Symbol(name.substring(0, name.indexOf('.'))) : member;
  final Iterable<CombinatorMirror> shows =
      dep.combinators.where((CombinatorMirror c) => c.isShow);
  if (shows.isNotEmpty &&
      !shows.any((CombinatorMirror c) => c.identifiers.contains(symbol))) {
    return false;
  }
  return !dep.combinators
      .any((CombinatorMirror c) => c.isHide && c.identifiers.contains(symbol));
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
  final String superclass = cls.superclass != null &&
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
        members.add(
            '  new $name${_constructorParams(_params(d))}${_flags(d)}');
      } else if (d.isGetter) {
        members
            .add('  ${isStatic}get $name: ${_type(d.returnType)}${_flags(d)}');
      } else if (d.isSetter) {
        members.add('  ${isStatic}set $name${_params(d)}${_flags(d)}');
      } else {
        members.add(
            '  $isStatic$name${_params(d)}: ${_type(d.returnType)}${_flags(d)}');
      }
    } else if (d is VariableMirror) {
      members.add(
          '  ${d.isStatic ? 'static ' : ''}${d.isFinal ? 'final ' : ''}${_name(d.simpleName)}: ${_type(d.type)}${_flags(d)}');
    }
  }
  members.sort();
  return <String>[...lines, ...members];
}

String describePublicApi([Symbol library = #cloud_firestore_dart]) {
  final LibraryMirror barrel = currentMirrorSystem().findLibrary(library);
  final Map<String, List<String>> entries = <String, List<String>>{};
  for (final LibraryDependencyMirror dep in barrel.libraryDependencies) {
    if (!dep.isExport) {
      continue;
    }
    for (final DeclarationMirror d in dep.targetLibrary!.declarations.values) {
      if (!_isPublic(d.simpleName) || !_isExportedBy(dep, d.simpleName)) {
        continue;
      }
      final String name = _name(d.simpleName);
      if (d is ClassMirror) {
        entries[name] = _describeClass(d);
      } else if (d is TypedefMirror) {
        entries[name] = <String>[
          'typedef $name = ${_type(d.referent)}${_flags(d)}'
        ];
      } else if (d is MethodMirror) {
        entries[name] = <String>[
          '${d.isGetter ? 'get ' : ''}$name${d.isGetter ? '' : _params(d)}: ${_type(d.returnType)}${_flags(d)}'
        ];
      } else if (d is VariableMirror) {
        entries[name] = <String>['var $name: ${_type(d.type)}${_flags(d)}'];
      }
    }
    // dart:mirrors does not list typedefs in `declarations`, so they are read
    // from the source of the exported library (tests run in the package root).
    final String source =
        File('lib/${dep.targetLibrary!.uri.pathSegments.skip(1).join('/')}')
            .readAsStringSync();
    for (final RegExpMatch m in _typedef.allMatches(source)) {
      final String name = m.group(1)!;
      if (name.startsWith('_') || !_isExportedBy(dep, Symbol(name))) {
        continue;
      }
      entries[name] = <String>[
        'typedef $name = ${_normalizeTypedef(m.group(2)!)}'
      ];
    }
  }
  final List<String> names = entries.keys.toList()..sort();
  return '${names.expand((String n) => entries[n]!).join('\n')}\n';
}

void main() {
  test('exported public API matches the golden listing', () {
    final File golden = File('test/unit/api/public_api.golden.txt');
    final String actual = describePublicApi();
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync(actual);
      return;
    }
    expect(golden.existsSync(), isTrue,
        reason: 'Missing golden file. Run with UPDATE_GOLDEN=1.');
    expect(actual, golden.readAsStringSync(),
        reason: 'The public API changed. If intended, regenerate with '
            'UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart '
            'and review the diff of test/unit/api/public_api.golden.txt.');
  });

  test('exported pipelines API matches the golden listing', () {
    final File golden = File('test/unit/api/pipelines_api.golden.txt');
    final String actual = describePublicApi(#cloud_firestore_dart.pipelines);
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync(actual);
      return;
    }
    expect(golden.existsSync(), isTrue,
        reason: 'Missing golden file. Run with UPDATE_GOLDEN=1.');
    expect(actual, golden.readAsStringSync(),
        reason: 'The pipelines API changed. If intended, regenerate with '
            'UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart '
            'and review the diff of test/unit/api/pipelines_api.golden.txt.');
  });

  test('exported Firestore Lite API matches the golden listing', () {
    final File golden = File('test/unit/api/lite_api.golden.txt');
    final String actual = describePublicApi(#cloud_firestore_dart.lite);
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync(actual);
      return;
    }
    expect(golden.existsSync(), isTrue,
        reason: 'Missing golden file. Run with UPDATE_GOLDEN=1.');
    expect(actual, golden.readAsStringSync(),
        reason: 'The Firestore Lite API changed. If intended, regenerate with '
            'UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart '
            'and review the diff of test/unit/api/lite_api.golden.txt.');
  });
}
