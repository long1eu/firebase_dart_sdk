// Unit tests of FirebaseUserAuth.emulatorConfig and AuthEmulatorOptions, with a fake HTTP client.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String apiKey = 'test-api-key';

void main() {
  late List<http.Request> requests;

  setUp(() => requests = <http.Request>[]);

  FirebaseUserAuth create(
    String? emulatorHost, {
    AuthEmulatorOptions options = const AuthEmulatorOptions(),
  }) {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: apiKey,
      emulatorHost: emulatorHost,
      emulatorOptions: options,
      httpClient: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response('{"error":{"code":400,"message":"X"}}', 400);
      }),
    );
    addTearDown(auth.dispose);
    return auth;
  }

  /// The lines printed (where `Log` writes) while [body] runs.
  List<String> printedBy(void Function() body) {
    final List<String> printed = <String>[];
    runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
            printed.add(line),
      ),
    );
    return printed;
  }

  test('emulatorConfig is null for the real service', () {
    expect(create(null).emulatorConfig, isNull);
  });

  test('emulatorConfig splits the emulator host like the JS SDK', () {
    for (final (String given, AuthEmulatorConfig expected)
        in <(String, AuthEmulatorConfig)>[
          (
            '127.0.0.1:9099',
            const AuthEmulatorConfig(
              protocol: 'http',
              host: '127.0.0.1',
              port: 9099,
            ),
          ),
          (
            'http://localhost:9099/',
            const AuthEmulatorConfig(
              protocol: 'http',
              host: 'localhost',
              port: 9099,
            ),
          ),
          (
            'HTTPS://Auth.Internal:8443',
            const AuthEmulatorConfig(
              protocol: 'https',
              host: 'Auth.Internal',
              port: 8443,
            ),
          ),
          (
            '[::1]:9099',
            const AuthEmulatorConfig(
              protocol: 'http',
              host: '[::1]',
              port: 9099,
            ),
          ),
          (
            'https://[::1]',
            const AuthEmulatorConfig(protocol: 'https', host: '[::1]'),
          ),
          (
            'auth-emulator',
            const AuthEmulatorConfig(protocol: 'http', host: 'auth-emulator'),
          ),
        ]) {
      expect(create(given).emulatorConfig, expected, reason: given);
    }
  });

  test('the requests go to the origin of emulatorConfig', () async {
    for (final (String given, String origin) in <(String, String)>[
      ('https://[::1]', 'https://[::1]'),
      ('localhost:09099', 'http://localhost:9099'),
    ]) {
      requests.clear();
      await expectLater(
        create(given).signInAnonymously(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(
        requests.single.url.toString(),
        '$origin/identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
        reason: given,
      );
    }
  });

  test('emulatorConfig carries the options', () {
    const AuthEmulatorOptions quiet = AuthEmulatorOptions(
      disableWarnings: true,
    );
    expect(
      create('127.0.0.1:9099').emulatorConfig!.options.disableWarnings,
      isFalse,
    );
    expect(
      create('127.0.0.1:9099', options: quiet).emulatorConfig!.options,
      quiet,
    );
  });

  test('disableWarnings leaves out the warning for a remote emulator', () {
    expect(printedBy(() => create('10.0.0.5:9099')), hasLength(1));
    expect(
      printedBy(
        () => create(
          '10.0.0.5:9099',
          options: const AuthEmulatorOptions(disableWarnings: true),
        ),
      ),
      isEmpty,
    );
  });

  test('forApp passes the emulator options on', () async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: apiKey,
        appId: '1:1:web:1',
        projectId: 'demo',
      ),
      name: 'emulator-config-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(app.delete);
    late Future<FirebaseUserAuth> pending;
    final List<String> printed = printedBy(() {
      pending = FirebaseUserAuth.forApp(
        app,
        emulatorHost: '10.0.0.5:9099',
        emulatorOptions: const AuthEmulatorOptions(disableWarnings: true),
        httpClient: MockClient((http.Request request) async {
          throw StateError('no request expected');
        }),
      );
    });
    final FirebaseUserAuth auth = await pending;
    addTearDown(auth.dispose);
    expect(printed, isEmpty);
    expect(
      auth.emulatorConfig,
      const AuthEmulatorConfig(
        protocol: 'http',
        host: '10.0.0.5',
        port: 9099,
        options: AuthEmulatorOptions(disableWarnings: true),
      ),
    );
  });

  test('a scheme other than http or https is an ArgumentError', () {
    for (final String host in <String>[
      'ftp://127.0.0.1:9099',
      'ws://localhost:9099',
    ]) {
      expect(
        () => create(host),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('invalid-emulator-scheme'),
          ),
        ),
        reason: host,
      );
      expect(
        () => FirebaseUserAuth.emulatorOrigin(host),
        throwsArgumentError,
        reason: host,
      );
    }
  });
}
