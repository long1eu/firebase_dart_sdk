// Golden listing of the exported public API (names, parameters, deprecations).
//
// A failing test means the public surface changed. Review the diff of
// test/unit/api/public_api.golden.txt; if the change is intended, regenerate it with
//
//     UPDATE_GOLDEN=1 dart test test/unit/api/public_api_golden_test.dart
//
// The listing is built with dart:mirrors from the `cloud_firestore_dart` barrel,
// so it works under `dart test` (JIT), not in AOT. Mirrors do not expose
// nullability, so `T` and `T?` look the same in the listing.

import 'dart:io';
import 'dart:mirrors';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

bool _isPublic(Symbol symbol) => !MirrorSystem.getName(symbol).startsWith('_');

String _name(Symbol symbol) => MirrorSystem.getName(symbol);

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
        members.add('  new $name${_params(d)}${_flags(d)}');
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

String describePublicApi() {
  final LibraryMirror barrel =
      currentMirrorSystem().findLibrary(#cloud_firestore_dart);
  final Map<String, List<String>> entries = <String, List<String>>{};
  for (final LibraryDependencyMirror dep in barrel.libraryDependencies) {
    if (!dep.isExport) {
      continue;
    }
    for (final DeclarationMirror d in dep.targetLibrary!.declarations.values) {
      if (!_isPublic(d.simpleName)) {
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
}
