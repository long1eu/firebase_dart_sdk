// Finds the public members of a package's public libraries whose signatures
// name a type of the package that no public library exports. Used by
// test/api/public_api_type_reachability_test.dart. Built with dart:mirrors, so
// it runs under `dart test` (JIT) only, like public_api_describer.dart.
//
// Rules:
// - Reachable types: every class, mixin and enum exported by any of the given
//   libraries (the union). A type exported by one public library counts as
//   reachable from all of them.
// - Checked: every public declaration that the libraries export (classes,
//   enums, mixins, top-level functions, getters, setters and variables,
//   extension members, typedefs) and, for classes, every public member they
//   declare (constructors, methods, getters, setters, fields, static or not),
//   their supertypes, mixins and interfaces, and the bounds of their type
//   parameters. Instance members inherited from a supertype of the package that
//   is not reachable are checked under the exported class; members of reachable
//   supertypes are checked under their own name, members of other packages and
//   of dart: libraries are not checked.
// - Skipped: declarations annotated `@internal` or `@visibleForTesting`
//   (package:meta); the analyzer warns on their use outside the package.
//   `@protected` and `@visibleForOverriding` members are checked, because
//   subclasses outside the package see them.
// - Fine: types of dart: libraries, of other packages, type variables,
//   dynamic, void, Never, and reachable types. Typedefs are transparent: the
//   types they expand to are checked, not the name of the alias.
//
// Known limits of dart:mirrors:
// - Record types are reported as `Record` (dart:core), so the types of record
//   fields are not checked. Today `ImmutableTree.findRootMostValueAndPath`
//   and `findRootMostMatchingPathAndValue` return the record typedef
//   `PathAndValue<T>` = `({Path path, T value})`; its fields are not seen
//   (Path is exported, so nothing is missed there).
// - An extension type is seen as its representation type, so an unexported
//   extension type in a signature is not reported.
// - Nullability is not visible; it does not change which types are named.
// - The type parameters of generic methods and their bounds are not visible.
// - Typedefs are not listed by mirrors. Exported typedefs are found in the
//   source text of the exported library (not of its part files) and their
//   targets are checked by resolving each identifier against the imports of
//   that library, so a prefixed name (`p.Type`) is not checked, and an
//   `@internal` on a typedef is not seen.
// - The `on` type of an extension is not visible except as the receiver
//   parameter of its members, and an `@internal` on the extension itself is
//   not seen (its members are checked unless each is annotated).

import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'public_api_describer.dart' show isExportedBy;

/// The sorted findings for the public libraries [libraries] (label to URI, for
/// example `'storage_engine.dart'` to `package:firebase_database_dart/...`) of
/// the package whose libraries have URIs that start with [ownPrefix].
///
/// A finding reads `library: Owner.member names Type (declared in uri)`. The
/// member is `new` for an unnamed constructor, `x=` for a setter, and
/// `(extends)`, `(with)`, `(implements)` or `<T>` (bound of `T`) for the
/// declaration of a class. A top-level declaration has no owner. The URI is
/// printed as is for `package:` URIs and relative to [ownPrefix] otherwise.
///
/// Every library must be loaded by the program (imported directly or not).
List<String> findUnexportedTypes({
  required Map<String, Uri> libraries,
  required String ownPrefix,
}) {
  final List<(String, DeclarationMirror)> exports =
      <(String, DeclarationMirror)>[];
  final List<_Typedef> typedefs = <_Typedef>[];
  libraries.forEach((String label, Uri uri) {
    final LibraryMirror? barrel = currentMirrorSystem().libraries[uri];
    if (barrel == null) {
      throw StateError('$uri is not loaded: import it in the test file.');
    }
    _collectExports(
      label,
      barrel,
      <LibraryDependencyMirror>[],
      ownPrefix,
      exports,
      typedefs,
    );
  });
  final _Checker checker = _Checker(ownPrefix, <String>{
    for (final (String _, DeclarationMirror d) in exports)
      if (d is ClassMirror) _key(d),
  });
  for (final (String library, DeclarationMirror d) in exports) {
    checker.checkDeclaration(library, d);
  }
  typedefs.forEach(checker.checkTypedef);
  return checker.findings.toList()..sort();
}

/// An exported typedef, read from the source of the library that declares it.
class _Typedef {
  _Typedef(this.library, this.owner, this.name, this.target);

  final String library;
  final LibraryMirror owner;
  final String name;
  final String target;
}

final RegExp _typedefSource = RegExp(
  r'^typedef (\w+)(?:<[^=]*>)?\s*=\s*([^;]+);',
  multiLine: true,
);

String _name(Symbol symbol) => MirrorSystem.getName(symbol);

bool _isPublic(Symbol symbol) => !_name(symbol).startsWith('_');

String _key(ClassMirror type) {
  final ClassMirror declaration = type.originalDeclaration as ClassMirror;
  return '${(declaration.owner! as LibraryMirror).uri}'
      '#${_name(declaration.simpleName)}';
}

/// Whether [d] carries `@internal` or `@visibleForTesting`.
bool _isSkipped(DeclarationMirror d) => d.metadata.any((InstanceMirror m) {
  final String type = m.reflectee.runtimeType.toString();
  return type == '_Internal' || type == '_VisibleForTesting';
});

bool _isMixinApplication(ClassMirror c) =>
    c.mixin.originalDeclaration != c.originalDeclaration;

/// Adds the exports of [library] to [exports] and [typedefs]; [chain] are the
/// exports that led to it, each of which must let a name through.
void _collectExports(
  String label,
  LibraryMirror library,
  List<LibraryDependencyMirror> chain,
  String ownPrefix,
  List<(String, DeclarationMirror)> exports,
  List<_Typedef> typedefs,
) {
  bool passes(Symbol symbol) =>
      chain.every((LibraryDependencyMirror dep) => isExportedBy(dep, symbol));
  for (final DeclarationMirror d in library.declarations.values) {
    if (_isPublic(d.simpleName) && passes(d.simpleName)) {
      exports.add((label, d));
    }
  }
  if (library.uri.toString().startsWith(ownPrefix)) {
    final Uri file = library.uri.scheme == 'package'
        ? Isolate.resolvePackageUriSync(library.uri)!
        : library.uri;
    final String source = File.fromUri(file).readAsStringSync();
    for (final RegExpMatch m in _typedefSource.allMatches(source)) {
      final String name = m.group(1)!;
      if (!name.startsWith('_') && passes(Symbol(name))) {
        typedefs.add(_Typedef(label, library, name, m.group(2)!));
      }
    }
  }
  for (final LibraryDependencyMirror dep in library.libraryDependencies) {
    if (dep.isExport && dep.targetLibrary != null) {
      _collectExports(
        label,
        dep.targetLibrary!,
        <LibraryDependencyMirror>[...chain, dep],
        ownPrefix,
        exports,
        typedefs,
      );
    }
  }
}

/// The public declarations that importing [library] makes visible.
Map<String, DeclarationMirror> _namespace(LibraryMirror library) {
  final Map<String, DeclarationMirror> names = <String, DeclarationMirror>{
    for (final DeclarationMirror d in library.declarations.values)
      if (_isPublic(d.simpleName)) _name(d.simpleName): d,
  };
  for (final LibraryDependencyMirror dep in library.libraryDependencies) {
    if (dep.isExport && dep.targetLibrary != null) {
      _namespace(dep.targetLibrary!).forEach((String n, DeclarationMirror d) {
        if (isExportedBy(dep, Symbol(n))) {
          names.putIfAbsent(n, () => d);
        }
      });
    }
  }
  return names;
}

class _Checker {
  _Checker(this.ownPrefix, this.reachable);

  final String ownPrefix;

  /// The keys ([_key]) of the exported classes, enums and mixins.
  final Set<String> reachable;

  final Set<String> findings = <String>{};

  bool _isOwn(LibraryMirror library) =>
      library.uri.toString().startsWith(ownPrefix);

  String _where(Uri uri) {
    final String text = uri.toString();
    return uri.scheme == 'package' || !text.startsWith(ownPrefix)
        ? text
        : text.substring(ownPrefix.length);
  }

  void checkDeclaration(String library, DeclarationMirror d) {
    if (_isSkipped(d)) {
      return;
    }
    if (d is ClassMirror) {
      _checkClass(library, d);
    } else if (d is MethodMirror) {
      _checkMethod(library, _name(d.simpleName), d);
    } else if (d is VariableMirror) {
      _checkType(library, _name(d.simpleName), d.type);
    }
  }

  /// Checks the classes that the identifiers of an exported typedef's target
  /// name, resolved in the scope of the library that declares it.
  void checkTypedef(_Typedef typedef) {
    final Map<String, DeclarationMirror> scope = <String, DeclarationMirror>{};
    for (final LibraryDependencyMirror dep
        in typedef.owner.libraryDependencies) {
      if (dep.isImport && dep.prefix == null && dep.targetLibrary != null) {
        _namespace(dep.targetLibrary!).forEach((String n, DeclarationMirror d) {
          if (isExportedBy(dep, Symbol(n))) {
            scope[n] = d;
          }
        });
      }
    }
    scope.addAll(_namespace(typedef.owner));
    for (final RegExpMatch m in RegExp(
      r'(?<![.\w])[A-Za-z_]\w*',
    ).allMatches(typedef.target)) {
      final DeclarationMirror? d = scope[m.group(0)];
      if (d is ClassMirror) {
        _checkType(typedef.library, typedef.name, d);
      }
    }
  }

  void _checkClass(String library, ClassMirror cls) {
    final String owner = _name(cls.simpleName);
    for (final TypeVariableMirror v in cls.typeVariables) {
      _checkType(library, '$owner<${_name(v.simpleName)}>', v.upperBound);
    }
    ClassMirror? superclass = cls.superclass;
    while (superclass != null && _isMixinApplication(superclass)) {
      _checkType(library, '$owner (with)', superclass.mixin);
      superclass = superclass.superclass;
    }
    if (superclass != null) {
      _checkType(library, '$owner (extends)', superclass);
    }
    for (final ClassMirror i in cls.superinterfaces) {
      _checkType(library, '$owner (implements)', i);
    }
    for (final DeclarationMirror d in cls.declarations.values) {
      if (!_isPublic(d.simpleName) || _isSkipped(d)) {
        continue;
      }
      if (d is MethodMirror) {
        if (d.isConstructor) {
          // The simple name of a named constructor is `Class.name`, so a
          // private one (`Class._`) passes the check above.
          final String name = _name(d.constructorName);
          if (!name.startsWith('_')) {
            _checkMethod(library, '$owner.${name.isEmpty ? 'new' : name}', d);
          }
        } else {
          _checkMethod(library, '$owner.${_name(d.simpleName)}', d);
        }
      } else if (d is VariableMirror) {
        _checkType(library, '$owner.${_name(d.simpleName)}', d.type);
      }
    }
    _checkInherited(library, owner, cls);
  }

  /// Checks the instance members that [cls] inherits from supertypes of the
  /// package that are not reachable, nearest supertype first.
  void _checkInherited(String library, String owner, ClassMirror cls) {
    final Set<Symbol> seen = cls.declarations.keys.toSet();
    final Set<String> visited = <String>{};
    final List<ClassMirror> queue = <ClassMirror>[
      ?cls.superclass,
      ...cls.superinterfaces,
    ];
    while (queue.isNotEmpty) {
      final ClassMirror type = queue.removeAt(0);
      if (_isMixinApplication(type)) {
        queue.addAll(<ClassMirror>[type.mixin, ?type.superclass]);
        continue;
      }
      final ClassMirror s = type.originalDeclaration as ClassMirror;
      if (!visited.add(_key(s)) ||
          !_isOwn(s.owner! as LibraryMirror) ||
          reachable.contains(_key(s))) {
        continue;
      }
      for (final DeclarationMirror d in s.declarations.values) {
        final bool isStatic =
            (d is MethodMirror && (d.isStatic || d.isConstructor)) ||
            (d is VariableMirror && d.isStatic);
        if (!_isPublic(d.simpleName) ||
            _isSkipped(d) ||
            isStatic ||
            !seen.add(d.simpleName)) {
          continue;
        }
        final String member = '$owner.${_name(d.simpleName)}';
        if (d is MethodMirror) {
          _checkMethod(library, member, d);
        } else if (d is VariableMirror) {
          _checkType(library, member, d.type);
        }
      }
      queue.addAll(<ClassMirror>[?s.superclass, ...s.superinterfaces]);
    }
  }

  void _checkMethod(String library, String member, MethodMirror method) {
    if (!method.isConstructor) {
      _checkType(library, member, method.returnType);
    }
    for (final ParameterMirror p in method.parameters) {
      _checkType(library, member, p.type);
    }
  }

  void _checkType(String library, String member, TypeMirror type) {
    for (final ClassMirror c in _namedClasses(type)) {
      final DeclarationMirror? owner = c.owner;
      if (owner is! LibraryMirror ||
          !_isOwn(owner) ||
          reachable.contains(_key(c))) {
        continue;
      }
      findings.add(
        '$library: $member names ${_name(c.simpleName)} '
        '(declared in ${_where(owner.uri)})',
      );
    }
  }
}

/// The class declarations that [type] names: itself, its type arguments, and
/// the return and parameter types of function types, recursively.
Iterable<ClassMirror> _namedClasses(TypeMirror type) sync* {
  if (type is TypeVariableMirror) {
    return;
  }
  if (type is TypedefMirror) {
    yield* _namedClasses(type.referent);
    return;
  }
  if (type is FunctionTypeMirror) {
    yield* _namedClasses(type.returnType);
    for (final ParameterMirror p in type.parameters) {
      yield* _namedClasses(p.type);
    }
    return;
  }
  if (type is ClassMirror) {
    yield type.originalDeclaration as ClassMirror;
    for (final TypeMirror argument in type.typeArguments) {
      yield* _namedClasses(argument);
    }
  }
  // dynamic, void and Never are plain TypeMirrors with no owner.
}
