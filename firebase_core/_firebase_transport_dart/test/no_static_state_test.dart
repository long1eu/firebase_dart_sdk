@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// The top-level and static variables of [source] that hold state, as `name (line)` texts.
List<String> mutableStateOf(String source, String path) {
  final CompilationUnit unit = parseString(content: source, path: path).unit;
  final _StateFinder finder = _StateFinder(unit);
  unit.accept(finder);
  return finder.found;
}

final class _StateFinder extends RecursiveAstVisitor<void> {
  _StateFinder(this._unit);

  final CompilationUnit _unit;
  final List<String> found = <String>[];

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    _check(node.variables);
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isStatic) {
      _check(node.fields);
    }
    super.visitFieldDeclaration(node);
  }

  void _check(VariableDeclarationList list) {
    if (list.isConst) {
      return;
    }
    for (final VariableDeclaration variable in list.variables) {
      final Expression? initializer = variable.initializer;
      final bool allowed =
          list.isFinal &&
          !list.isLate &&
          initializer != null &&
          _isAllowed(initializer);
      if (!allowed) {
        final int line = _unit.lineInfo.getLocation(variable.offset).lineNumber;
        found.add('${variable.name.lexeme} (line $line)');
      }
    }
  }
}

bool _isAllowed(Expression expression) {
  if (_isConstant(expression)) {
    return true;
  }
  if (expression is InstanceCreationExpression) {
    final String name = expression.constructorName.type.name.lexeme;
    return expression.isConst ||
        (name == 'RegExp' && _allLiteral(expression.argumentList));
  }
  if (expression is MethodInvocation) {
    final Expression? target = expression.target;
    if (target == null) {
      return expression.methodName.name == 'RegExp' &&
          _allLiteral(expression.argumentList);
    }
    return target is SimpleIdentifier &&
        target.name == 'Uri' &&
        expression.methodName.name == 'parse' &&
        _allLiteral(expression.argumentList);
  }
  return false;
}

bool _isConstant(Expression expression) {
  if (expression is SimpleStringLiteral ||
      expression is IntegerLiteral ||
      expression is DoubleLiteral ||
      expression is BooleanLiteral ||
      expression is NullLiteral) {
    return true;
  }
  if (expression is AdjacentStrings) {
    return expression.strings.every(_isConstant);
  }
  if (expression is TypedLiteral) {
    return expression.isConst;
  }
  return false;
}

bool _allLiteral(ArgumentList arguments) =>
    arguments.arguments.isNotEmpty &&
    arguments.arguments.every((Object a) => a is Expression && _isConstant(a));

void main() {
  test('no file under lib/ holds mutable top-level or static state', () {
    final List<File> files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final List<String> offenders = <String>[];
    for (final File file in files) {
      for (final String found in mutableStateOf(
        file.readAsStringSync(),
        file.path,
      )) {
        offenders.add('${file.path}: $found');
      }
    }
    expect(offenders, isEmpty);
  });

  group('the detector', () {
    test('flags a non-final top-level variable', () {
      expect(mutableStateOf('int counter = 0;', 'a.dart'), hasLength(1));
    });

    test(
      'flags a final top-level variable with a non-constant initializer',
      () {
        expect(
          mutableStateOf('final List<int> cache = <int>[];', 'a.dart'),
          hasLength(1),
        );
        expect(
          mutableStateOf('final Map<String, int> m = {};', 'a.dart'),
          hasLength(1),
        );
      },
    );

    test('flags a static field that is not final or not constant', () {
      expect(
        mutableStateOf('class A { static int n = 0; }', 'a.dart'),
        hasLength(1),
      );
      expect(
        mutableStateOf('class A { static final x = Foo(); }', 'a.dart'),
        hasLength(1),
      );
      expect(
        mutableStateOf('class A { static late final int x; }', 'a.dart'),
        hasLength(1),
      );
    });

    test('flags a RegExp or Uri.parse of something that is not a literal', () {
      expect(
        mutableStateOf('final r = RegExp(pattern);', 'a.dart'),
        hasLength(1),
      );
      expect(
        mutableStateOf('final u = Uri.parse(text);', 'a.dart'),
        hasLength(1),
      );
    });

    test('passes const, literal finals, RegExp and Uri.parse of literals', () {
      expect(mutableStateOf('const int a = 1;', 'a.dart'), isEmpty);
      expect(mutableStateOf('final int a = 1;', 'a.dart'), isEmpty);
      expect(mutableStateOf("final r = RegExp(r'^a+\$');", 'a.dart'), isEmpty);
      expect(
        mutableStateOf("final u = Uri.parse('https://a.b/');", 'a.dart'),
        isEmpty,
      );
      expect(mutableStateOf('final l = const <int>[1];', 'a.dart'), isEmpty);
      expect(
        mutableStateOf('class A { static const String s = "x"; }', 'a.dart'),
        isEmpty,
      );
    });

    test('passes static methods and instance fields', () {
      expect(
        mutableStateOf('class A { static int f() => 1; int x = 0; }', 'a.dart'),
        isEmpty,
      );
    });
  });
}
