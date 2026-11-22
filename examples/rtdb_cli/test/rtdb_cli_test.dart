import 'package:rtdb_cli/parsing.dart';
import 'package:test/test.dart';

void main() {
  group('host and path', () {
    test('parseHostPort', () {
      expect(parseHostPort('127.0.0.1:9000'), (host: '127.0.0.1', port: 9000));
      expect(parseHostPort('[::1]:9000'), (host: '[::1]', port: 9000));
      expect(() => parseHostPort('localhost'), throwsA(isA<UsageError>()));
      expect(() => parseHostPort('h:99999'), throwsA(isA<UsageError>()));
    });

    test('normalizePath', () {
      expect(normalizePath('/a/b/'), 'a/b');
      expect(normalizePath('/'), '');
      expect(() => normalizePath('a//b'), throwsA(isA<UsageError>()));
      expect(() => normalizePath('a.b'), throwsA(isA<UsageError>()));
    });
  });

  group('JSON', () {
    test('parseJsonValue', () {
      expect(parseJsonValue('{"a":[1,2]}'), {
        'a': [1, 2],
      });
      expect(parseJsonValue('"x"'), 'x');
      expect(parseJsonValue('null'), isNull);
      expect(() => parseJsonValue('{a:1}'), throwsA(isA<UsageError>()));
    });

    test('parseJsonObject', () {
      expect(parseJsonObject('{"a/b":1}'), {'a/b': 1});
      expect(() => parseJsonObject('[1]'), throwsA(isA<UsageError>()));
    });

    test('encodeJson', () {
      expect(encodeJson({'a': 1}, compact: true), '{"a":1}');
      expect(encodeJson({'a': 1}), '{\n  "a": 1\n}');
    });

    test('parseBound', () {
      expect(parseBound('5'), 5);
      expect(parseBound('true'), true);
      expect(parseBound('"7"'), '7');
      expect(parseBound('alice'), 'alice');
      expect(parseBound('[1]'), '[1]');
    });
  });

  group('parseQuerySpec', () {
    test('no flags is a plain query', () {
      expect(parseQuerySpec().isPlain, isTrue);
    });

    test('combines order, bounds and limit', () {
      final QuerySpec spec = parseQuerySpec(
        orderByChild: 'age',
        startAt: '18',
        endAt: '65',
        limitToLast: '10',
      );
      expect(spec.orderBy, OrderBy.child);
      expect(spec.orderByChild, 'age');
      expect(spec.startAt, 18);
      expect(spec.endAt, 65);
      expect(spec.limitToLast, 10);
      expect(spec.isPlain, isFalse);
    });

    test('keeps an explicit null bound', () {
      final QuerySpec spec = parseQuerySpec(orderByChild: 'x', equalTo: 'null');
      expect(spec.hasEqualTo, isTrue);
      expect(spec.equalTo, isNull);
    });

    test('refuses what the database refuses', () {
      expect(
        () => parseQuerySpec(orderByKey: true, orderByValue: true),
        throwsA(isA<UsageError>()),
      );
      expect(
        () => parseQuerySpec(limitToFirst: '1', limitToLast: '1'),
        throwsA(isA<UsageError>()),
      );
      expect(
        () => parseQuerySpec(equalTo: '1', startAt: '0'),
        throwsA(isA<UsageError>()),
      );
      expect(
        () => parseQuerySpec(limitToFirst: '0'),
        throwsA(isA<UsageError>()),
      );
      expect(
        () => parseQuerySpec(orderByKey: true, startAt: '5'),
        throwsA(isA<UsageError>()),
      );
    });
  });

  group('resolveTarget', () {
    test('refuses without emulator and without a database URL', () {
      expect(() => resolveTarget(), throwsA(isA<ConfigurationError>()));
      expect(
        () => resolveTarget(project: 'prod'),
        throwsA(isA<ConfigurationError>()),
      );
    });

    test('the flag wins over the environment', () {
      final DatabaseTarget t = resolveTarget(
        emulator: '127.0.0.1:9000',
        environment: {'FIREBASE_DATABASE_EMULATOR_HOST': 'other:1'},
      );
      expect(t.emulatorHost, '127.0.0.1:9000');
      expect(t.projectId, 'demo-example');
      expect(t.databaseUrl, isNull);
    });

    test('the environment alone is enough', () {
      final DatabaseTarget t = resolveTarget(
        environment: {'FIREBASE_DATABASE_EMULATOR_HOST': 'localhost:9000'},
      );
      expect(t.emulatorHost, 'localhost:9000');
    });

    test('an explicit URL names the project', () {
      final DatabaseTarget t = resolveTarget(
        databaseUrl: 'https://my-app-default-rtdb.firebaseio.com',
      );
      expect(t.emulatorHost, isNull);
      expect(t.projectId, 'my-app');
    });

    test('a bad emulator or URL is a usage error', () {
      expect(() => resolveTarget(emulator: 'nope'), throwsA(isA<UsageError>()));
      expect(
        () => resolveTarget(databaseUrl: 'not a url'),
        throwsA(isA<UsageError>()),
      );
    });
  });
}
