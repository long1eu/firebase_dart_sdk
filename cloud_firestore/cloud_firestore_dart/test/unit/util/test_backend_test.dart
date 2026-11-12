// Tests of the environment handling of the integration test backends
// (test/util/test_backend.dart). No network and no credentials are used.

import 'package:grpc/grpc.dart' show BaseAuthenticator;
import 'package:test/test.dart';

import '../../util/test_backend.dart';

class _FakeAuthenticator extends BaseAuthenticator {
  _FakeAuthenticator(this.header);

  final String? header;
  int calls = 0;

  @override
  Future<void> authenticate(Map<String, String> metadata, String uri) async {
    calls++;
    expect(uri, 'https://firestore.googleapis.com/');
    if (header != null) {
      metadata['authorization'] = header!;
    }
  }

  @override
  Future<void> obtainAccessCredentials(String uri) async {}
}

void main() {
  group('EmulatorAddress', () {
    test('parses host and port', () {
      final EmulatorAddress address = EmulatorAddress.parse('127.0.0.1:8181');
      expect(address.host, '127.0.0.1');
      expect(address.port, 8181);
      expect(address.toString(), '127.0.0.1:8181');
    });

    test('defaults the port', () {
      expect(EmulatorAddress.parse('localhost').port, 8080);
      expect(EmulatorAddress.parse('localhost', defaultPort: 8181).port, 8181);
    });

    test('rejects a port that is not a number', () {
      expect(() => EmulatorAddress.parse('localhost:abc'),
          throwsA(isA<FormatException>()));
    });
  });

  group('TestBackend', () {
    test('nothing is configured by default', () {
      final TestBackend backend = TestBackend(<String, String>{});
      expect(backend.emulatorHost, isNull);
      expect(backend.enterpriseEmulatorHost, isNull);
      expect(backend.usesRealProject, isFalse);
      expect(backend.realDatabaseId, isNull);
      expect(backend.enterpriseEmulatorSkipReason,
          contains('FIRESTORE_ENTERPRISE_EMULATOR_HOST is not set'));
    });

    test('empty and blank values count as unset', () {
      final TestBackend backend = TestBackend(<String, String>{
        'FIRESTORE_EMULATOR_HOST': '',
        'FIRESTORE_ENTERPRISE_EMULATOR_HOST': '  ',
        'FIRESTORE_TEST_PROJECT_ID': '',
      });
      expect(backend.emulatorHost, isNull);
      expect(backend.enterpriseEmulatorHost, isNull);
      expect(backend.usesRealProject, isFalse);
    });

    test('the two emulators are independent', () {
      final TestBackend backend = TestBackend(<String, String>{
        'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
        'FIRESTORE_ENTERPRISE_EMULATOR_HOST': '127.0.0.1:8181',
      });
      expect(backend.emulatorHost, '127.0.0.1:8080');
      expect(backend.enterpriseEmulatorHost, '127.0.0.1:8181');
      expect(backend.enterpriseEmulatorSkipReason, isNull);

      expect(
          TestBackend(<String, String>{
            'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
          }).enterpriseEmulatorHost,
          isNull);
    });

    test('a real project is opt-in with the project id', () {
      final TestBackend backend = TestBackend(<String, String>{
        'FIRESTORE_TEST_PROJECT_ID': 'my-project',
        'FIRESTORE_TEST_DATABASE_ID': 'my-db',
      });
      expect(backend.usesRealProject, isTrue);
      expect(backend.realProjectId, 'my-project');
      expect(backend.realDatabaseId, 'my-db');
    });

    test('credentials alone do not select a real project', () {
      final TestBackend backend = TestBackend(<String, String>{
        'GOOGLE_APPLICATION_CREDENTIALS': '/does/not/matter.json',
      });
      expect(backend.usesRealProject, isFalse);
    });

    test('the emulator wins over a real project', () {
      final TestBackend backend = TestBackend(<String, String>{
        'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
        'FIRESTORE_TEST_PROJECT_ID': 'my-project',
        'FIRESTORE_TEST_DATABASE_ID': 'my-db',
      });
      expect(backend.usesRealProject, isFalse);
      expect(backend.realDatabaseId, isNull);
    });
  });

  group('edition of the emulator', () {
    test('is Standard by default', () {
      expect(TestBackend(<String, String>{}).isEnterpriseEdition, isFalse);
      final TestBackend backend = TestBackend(<String, String>{
        'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
        'FIRESTORE_ENTERPRISE_EMULATOR_HOST': '127.0.0.1:8181',
      });
      expect(backend.isEnterpriseEdition, isFalse);
      expect(backend.skipOnEnterprise('x'), isNull);
    });

    test('is Enterprise when both variables name the same emulator', () {
      final TestBackend backend = TestBackend(<String, String>{
        'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8181',
        'FIRESTORE_ENTERPRISE_EMULATOR_HOST': '127.0.0.1:8181',
      });
      expect(backend.isEnterpriseEdition, isTrue);
      expect(backend.skipOnEnterprise('sums differ'),
          'Enterprise edition: sums differ');
    });

    test('FIRESTORE_EMULATOR_EDITION decides when it is set', () {
      expect(
          TestBackend(<String, String>{
            'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8181',
            'FIRESTORE_EMULATOR_EDITION': 'Enterprise',
          }).isEnterpriseEdition,
          isTrue);
      expect(
          TestBackend(<String, String>{
            'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8181',
            'FIRESTORE_ENTERPRISE_EMULATOR_HOST': '127.0.0.1:8181',
            'FIRESTORE_EMULATOR_EDITION': 'standard',
          }).isEnterpriseEdition,
          isFalse);
      expect(
          () => TestBackend(<String, String>{
                'FIRESTORE_EMULATOR_EDITION': 'premium',
              }).isEnterpriseEdition,
          throwsArgumentError);
    });
  });

  group('ApplicationDefaultTokenSource', () {
    test('returns the bearer token and resolves the credentials once',
        () async {
      int created = 0;
      final _FakeAuthenticator authenticator = _FakeAuthenticator('Bearer abc');
      final ApplicationDefaultTokenSource source =
          ApplicationDefaultTokenSource(
              createAuthenticator: (List<String> scopes) async {
        created++;
        expect(scopes, <String>['https://www.googleapis.com/auth/datastore']);
        return authenticator;
      });

      expect(created, 0, reason: 'credentials are resolved lazily');
      expect(await source.token, 'abc');
      expect(await source.token, 'abc');
      expect(created, 1);
      expect(authenticator.calls, 2);

      source.invalidate();
      expect(await source.token, 'abc');
      expect(created, 2);
    });

    test('fails when no bearer token is produced', () async {
      for (final String? header in <String?>[null, 'Basic abc']) {
        final ApplicationDefaultTokenSource source =
            ApplicationDefaultTokenSource(
                createAuthenticator: (List<String> _) async =>
                    _FakeAuthenticator(header));
        await expectLater(source.token, throwsA(isA<StateError>()));
      }
    });
  });
}
