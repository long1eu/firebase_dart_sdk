// Validation of lib/src/core/util/validation.dart (JS core/util/validation.ts).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:test/test.dart';

Matcher _argumentError(String part) => throwsA(
  isA<ArgumentError>().having(
    (ArgumentError e) => e.message,
    'message',
    contains(part),
  ),
);

void main() {
  test('isValidKey', () {
    expect(isValidKey('a'), isTrue);
    expect(isValidKey('-Nabc'), isTrue);
    expect(isValidKey('\u{1F600}'), isTrue);
    for (final String bad in <String>[
      '',
      'a.b',
      'a#',
      r'a$',
      'a/b',
      '[',
      ']',
      '\u0000',
      '\u001f',
      '\u007f',
    ]) {
      expect(isValidKey(bad), isFalse, reason: bad);
    }
    expect(isValidKey(null), isFalse);
    expect(isValidKey(1), isFalse);
  });

  test('isValidPathString', () {
    expect(isValidPathString('a/b'), isTrue);
    expect(isValidPathString('/'), isTrue);
    expect(isValidPathString(''), isFalse);
    expect(isValidPathString('a.b'), isFalse);
    expect(isValidPathString('.info'), isFalse);
  });

  test('isValidRootPathString allows a leading .info', () {
    expect(isValidRootPathString('.info'), isTrue);
    expect(isValidRootPathString('/.info/connected'), isTrue);
    expect(isValidRootPathString('//.info'), isTrue);
    expect(isValidRootPathString('.infox'), isFalse);
    expect(isValidRootPathString('a/.info'), isFalse);
  });

  test('lone surrogates are refused in keys, paths and values', () {
    expect(isValidKey('a\uD800'), isFalse);
    expect(isValidKey('\uDC00a'), isFalse);
    expect(isValidKey('\uDE00\uD83D'), isFalse);
    expect(isValidPathString('a/\uD800'), isFalse);
    expect(hasLoneSurrogate('\u{1F600}'), isFalse);
    expect(hasLoneSurrogate('ok'), isFalse);
    expect(
      () => validateFirebaseDataArg('set', 'x\uD800', Path('/a')),
      _argumentError('unpaired surrogate'),
    );
    expect(
      () => validateFirebaseDataArg('set', <String, Object?>{
        '\uD800': 1,
      }, Path('/a')),
      _argumentError('invalid key'),
    );
    expect(() => validateKey('child', 'key', 'a\uDBFF'), throwsArgumentError);
    expect(
      () => validatePriority('setPriority', '\uD800'),
      throwsArgumentError,
    );
  });

  test('isValidPriority', () {
    expect(isValidPriority(null), isTrue);
    expect(isValidPriority('p'), isTrue);
    expect(isValidPriority(1.5), isTrue);
    expect(isValidPriority(<String, Object?>{'.sv': 'timestamp'}), isTrue);
    expect(isValidPriority(double.nan), isFalse);
    expect(isValidPriority(double.infinity), isFalse);
    expect(isValidPriority(true), isFalse);
    expect(isValidPriority(<String, Object?>{'a': 1}), isFalse);
  });

  group('validateFirebaseData', () {
    test('accepts JSON values', () {
      validateFirebaseDataArg('set', null, Path('/a'));
      validateFirebaseDataArg('set', true, Path('/a'));
      validateFirebaseDataArg('set', 1.5, Path('/a'));
      validateFirebaseDataArg('set', 'text', Path('/a'));
      validateFirebaseDataArg('set', <Object?>[1, null, 'x'], Path('/a'));
      validateFirebaseDataArg('set', <String, Object?>{
        'a': <String, Object?>{'.value': 1, '.priority': 2},
        'b': <String, Object?>{'.sv': 'timestamp'},
      }, Path('/a'));
    });

    test('refuses NaN and infinities with the path', () {
      expect(
        () => validateFirebaseDataArg('set', <String, Object?>{
          'a': <String, Object?>{'b': double.nan},
        }, Path('/x')),
        _argumentError(
          "set failed: value argument contains NaN in property 'x.a.b'",
        ),
      );
      expect(
        () => validateFirebaseDataArg('set', double.infinity, Path('/x')),
        _argumentError('contains Infinity'),
      );
    });

    test('refuses invalid keys', () {
      expect(
        () => validateFirebaseDataArg('set', <String, Object?>{
          'a.b': 1,
        }, Path('/x')),
        _argumentError('contains an invalid key (a.b)'),
      );
      expect(
        () => validateFirebaseDataArg('set', <Object?, Object?>{
          1: 1,
        }, Path('/x')),
        _argumentError('contains an invalid key (1)'),
      );
    });

    test('refuses .value next to actual children', () {
      expect(
        () => validateFirebaseDataArg('set', <String, Object?>{
          '.value': 1,
          'a': 2,
        }, Path('/x')),
        _argumentError('contains ".value" child'),
      );
    });

    test('refuses functions and other types', () {
      expect(
        () => validateFirebaseDataArg('set', () {}, Path('/x')),
        _argumentError('contains a function'),
      );
      expect(
        () => validateFirebaseDataArg('set', DateTime(2020), Path('/x')),
        _argumentError('unsupported type'),
      );
    });

    test('refuses depth over 32 (and cycles)', () {
      Object? data = 1;
      for (int i = 0; i < 33; i++) {
        data = <String, Object?>{'a': data};
      }
      expect(
        () => validateFirebaseDataArg('set', data, Path.empty),
        _argumentError('maximum depth'),
      );
      final List<Object?> cycle = <Object?>[];
      cycle.add(cycle);
      expect(
        () => validateFirebaseDataArg('set', cycle, Path.empty),
        _argumentError('maximum depth'),
      );
    });

    test('refuses a key path over 768 bytes', () {
      expect(
        () => validateFirebaseDataArg('set', <String, Object?>{
          'b' * 800: 1,
        }, Path('/a')),
        _argumentError('has a key path longer than 768 bytes'),
      );
    });

    test('refuses a string over 10 MB of UTF-8', () {
      validateFirebaseDataArg('set', 'a' * maxLeafSize, Path('/a'));
      expect(
        () => validateFirebaseDataArg(
          'set',
          'é' * (maxLeafSize ~/ 2 + 1),
          Path('/a'),
        ),
        _argumentError('contains a string greater than 10485760 utf8 bytes'),
      );
    });
  });

  group('merges', () {
    test('accepts a map of paths', () {
      validateFirebaseMergeDataArg('update', <String, Object?>{
        'a/b': 1,
        'c': null,
        'd/.priority': 3,
      }, Path('/x'));
    });

    test('refuses non-maps', () {
      expect(
        () => validateFirebaseMergeDataArg('update', <Object?>[1], Path('/x')),
        _argumentError('must be an object'),
      );
      expect(
        () => validateFirebaseMergeDataArg('update', null, Path('/x')),
        throwsArgumentError,
      );
      validateFirebaseMergeDataArg('update', null, Path('/x'), optional: true);
    });

    test('refuses an ancestor of another path', () {
      expect(
        () => validateFirebaseMergeDataArg('update', <String, Object?>{
          'a/b': 1,
          'a': 2,
        }, Path('/x')),
        _argumentError(
          'contains a path /a that is ancestor of another path /a/b',
        ),
      );
    });

    test('refuses a key that names the location itself', () {
      for (final String key in <String>['', '/', '//']) {
        expect(
          () => validateFirebaseMergeDataArg('update', <String, Object?>{
            key: 1,
          }, Path('/x')),
          _argumentError(
            'contains the key "$key", which names the location itself',
          ),
          reason: key,
        );
      }
      expect(
        () => validateFirebaseMergeDataArg('update', <String, Object?>{
          '': null,
        }, Path('/x')),
        _argumentError('Use remove() to delete the location'),
      );
      validateFirebaseMergeDataArg('update', <String, Object?>{
        '.priority': 1,
        'a//b/': 2,
      }, Path('/x'));
    });

    test('refuses an invalid priority', () {
      expect(
        () => validateFirebaseMergeDataArg('update', <String, Object?>{
          'a/.priority': true,
        }, Path('/x')),
        _argumentError("invalid value for '/a/.priority'"),
      );
    });

    test(
      'validateFirebaseMergePaths refuses .priority in the middle and does not sort its input',
      () {
        expect(
          () =>
              validateFirebaseMergePaths('p ', <Path>[Path('/a/.priority/b')]),
          _argumentError(
            'contains an invalid key (.priority) in path /a/.priority/b',
          ),
        );
        final List<Path> paths = List<Path>.unmodifiable(<Path>[
          Path('/b'),
          Path('/a'),
        ]);
        validateFirebaseMergePaths('p ', paths);
      },
    );
  });

  test('validatePriority', () {
    validatePriority('setPriority', null);
    validatePriority('setPriority', 'a');
    validatePriority('setPriority', 1);
    expect(
      () => validatePriority('setPriority', double.nan),
      _argumentError('is NaN, but must be'),
    );
    expect(
      () => validatePriority('setPriority', true),
      _argumentError('must be a valid Firebase priority'),
    );
  });

  test('validateKey and validatePathString', () {
    validateKey('child', 'key', 'a');
    validateKey('child', 'key', null, optional: true);
    expect(() => validateKey('child', 'key', null), throwsArgumentError);
    expect(
      () => validateKey('child', 'key', 'a/b'),
      _argumentError('was an invalid key = "a/b"'),
    );
    validatePathString('child', 'path', 'a/b');
    validatePathString('child', 'path', null, optional: true);
    expect(
      () => validatePathString('child', 'path', 'a#'),
      _argumentError('was an invalid path = "a#"'),
    );
    validateRootPathString('ref', 'path', '/.info/connected');
    expect(
      () => validateRootPathString('ref', 'path', '/a/.info'),
      throwsArgumentError,
    );
  });

  test('validateWritablePath', () {
    validateWritablePath('set', Path('/a/.info'));
    expect(
      () => validateWritablePath('set', Path('/.info/connected')),
      _argumentError("set failed = Can't modify data under /.info/"),
    );
  });
}
