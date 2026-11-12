import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/emulator_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/firestore.pbgrpc.dart'
    show FirestoreServiceBase;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

Map<String, Object?> decodePart(String part) {
  final String padded = part.padRight((part.length + 3) ~/ 4 * 4, '=');
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, Object?>;
}

Future<Map<String, String>> metadataOf(
    EmulatorCredentialsProvider provider) async {
  final ChannelOptionsProvider options = ChannelOptionsProvider(
    databaseId: DatabaseId.forDatabase('p', 'd'),
    credentialsProvider: provider,
  );
  final Map<String, String> metadata = <String, String>{};
  for (final MetadataProvider p in options.callOptions.metadataProviders) {
    await p(metadata, 'uri');
  }
  return metadata;
}

/// A Firestore service whose methods are never reached: the interceptor of
/// the test server records the metadata of each call and rejects it.
class FakeFirestoreService extends FirestoreServiceBase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const GrpcError.unimplemented();
}

FirebaseApp newApp(String name) => FirebaseApp.withOptions(
      const FirebaseOptions(
          apiKey: 'key', applicationId: 'appId', projectId: 'my-project'),
      dependencies: null,
      name: name,
    );

void main() {
  group('createMockUserToken', () {
    // Port of packages/util/test/emulator.test.ts.
    test('creates a well-formed JWT', () {
      final String token = createMockUserToken(
          <String, Object?>{'user_id': 'alice'}, 'my-project');
      final List<String> parts = token.split('.');
      expect(parts, hasLength(3));
      expect(decodePart(parts[0]),
          <String, Object?>{'alg': 'none', 'type': 'JWT'});
      // We add an 'iat' field.
      expect(decodePart(parts[1]), <String, Object?>{
        'iss': 'https://securetoken.google.com/my-project',
        'aud': 'my-project',
        'iat': 0,
        'exp': 3600,
        'auth_time': 0,
        'sub': 'alice',
        'user_id': 'alice',
        'firebase': <String, Object?>{
          'sign_in_provider': 'custom',
          'identities': <String, Object?>{},
        },
      });
      // Unsecured JWTs have an empty signature.
      expect(parts[2], isEmpty);
      // base64url without padding.
      expect(token, isNot(contains('=')));
      expect(token, isNot(contains('+')));
      expect(token, isNot(contains('/')));
    });

    test('is the same string as the JS SDK', () {
      // The JS SDK encodes the JSON of the header with base64url and drops the padding.
      expect(
          createMockUserToken(<String, Object?>{'sub': 'alice'}, 'p')
              .split('.')
              .first,
          'eyJhbGciOiJub25lIiwidHlwZSI6IkpXVCJ9');
    });

    test('rejects "uid" field with error', () {
      expect(
          () => createMockUserToken(<String, Object?>{'uid': 'alice'}),
          throwsA(isA<ArgumentError>().having(
              (ArgumentError e) => e.message,
              'message',
              'The "uid" field is no longer supported by mockUserToken. Please '
                  'use "sub" instead for Firebase Auth User ID.')));
    });

    test('requires sub or user_id', () {
      expect(
          () => createMockUserToken(<String, Object?>{'email': 'a@b.c'}),
          throwsA(isA<ArgumentError>().having(
              (ArgumentError e) => e.message,
              'message',
              "mockUserToken must contain 'sub' or 'user_id' field!")));
    });

    test('given claims override the defaults', () {
      final String token = createMockUserToken(<String, Object?>{
        'sub': 'alice',
        'iat': 100,
        'email': 'alice@example.com',
        'firebase': <String, Object?>{'sign_in_provider': 'password'},
      });
      final Map<String, Object?> claims = decodePart(token.split('.')[1]);
      expect(claims['iss'], 'https://securetoken.google.com/demo-project');
      expect(claims['aud'], 'demo-project');
      expect(claims['iat'], 100);
      expect(claims['exp'], 3700);
      expect(claims['auth_time'], 100);
      expect(claims['email'], 'alice@example.com');
      expect(claims['firebase'],
          <String, Object?>{'sign_in_provider': 'password'});
    });
  });

  group('EmulatorCredentialsProvider', () {
    test('a string token is sent as is for the mock user', () async {
      final EmulatorCredentialsProvider provider =
          EmulatorCredentialsProvider.forMockUserToken('my-token', 'p');
      expect(await provider.token, 'my-token');
      expect(await provider.onChange.first, const User('mock-user'));
      expect(await metadataOf(provider),
          containsPair('Authorization', 'Bearer my-token'));
    });

    test('claims are encoded and the user is their sub', () async {
      final EmulatorCredentialsProvider provider =
          EmulatorCredentialsProvider.forMockUserToken(
              <String, Object?>{'sub': 'foobar'}, 'my-project');
      final String expected =
          createMockUserToken(<String, Object?>{'sub': 'foobar'}, 'my-project');
      expect(await provider.token, expected);
      expect(await provider.onChange.first, const User('foobar'));
      expect(await metadataOf(provider),
          containsPair('Authorization', 'Bearer $expected'));
    });

    test('user_id is the user when there is no sub', () async {
      final EmulatorCredentialsProvider provider =
          EmulatorCredentialsProvider.forMockUserToken(
              <String, Object?>{'user_id': 'bob'}, null);
      expect(await provider.onChange.first, const User('bob'));
    });
  });

  group('FirestoreSettings.mockUserToken', () {
    test('withEmulator sets it', () {
      final FirestoreSettings settings = FirestoreSettings()
          .withEmulator('127.0.0.1', 8080, mockUserToken: 'my-token');
      expect(settings.host, '127.0.0.1');
      expect(settings.port, 8080);
      expect(settings.sslEnabled, isFalse);
      expect(settings.mockUserToken, 'my-token');
    });

    test('withEmulator without a token clears it, copyWith keeps it', () {
      final FirestoreSettings settings = FirestoreSettings()
          .withEmulator('127.0.0.1', 8080, mockUserToken: 'my-token');
      expect(settings.withEmulator('127.0.0.1', 8080).mockUserToken, isNull);
      expect(
          settings
              .copyWith(cacheSettings: const MemoryCacheSettings())
              .mockUserToken,
          'my-token');
    });

    test('equality compares the claims', () {
      FirestoreSettings withClaims() =>
          FirestoreSettings().withEmulator('127.0.0.1', 8080,
              mockUserToken: <String, Object?>{'sub': 'alice'});
      expect(withClaims(), withClaims());
      expect(withClaims().hashCode, withClaims().hashCode);
      expect(
          withClaims(),
          isNot(FirestoreSettings().withEmulator('127.0.0.1', 8080,
              mockUserToken: <String, Object?>{'sub': 'bob'})));
      expect(withClaims(),
          isNot(FirestoreSettings().withEmulator('127.0.0.1', 8080)));
    });

    test('rejects invalid tokens when the settings are created', () {
      expect(
          () => FirestoreSettings().withEmulator('127.0.0.1', 8080,
              mockUserToken: <String, Object?>{'uid': 'alice'}),
          throwsArgumentError);
      expect(
          () => FirestoreSettings().withEmulator('127.0.0.1', 8080,
              mockUserToken: <String, Object?>{'email': 'a@b.c'}),
          throwsArgumentError);
      expect(
          () => FirestoreSettings()
              .withEmulator('127.0.0.1', 8080, mockUserToken: 42),
          throwsArgumentError);
    });

    test('is rejected when the settings stop pointing at the emulator', () {
      // The unsigned token must never reach a production host.
      final FirestoreSettings settings = FirestoreSettings()
          .withEmulator('127.0.0.1', 8080, mockUserToken: 'my-token');
      expect(
          () => settings.copyWith(
              host: FirestoreSettings.defaultHost, port: 443, sslEnabled: true),
          throwsArgumentError);
      expect(() => settings.copyWith(host: 'example.com'), throwsArgumentError);
      expect(() => settings.copyWith(port: 9090), throwsArgumentError);
      expect(() => settings.copyWith(sslEnabled: true), throwsArgumentError);
      // The same emulator is fine.
      expect(
          settings
              .copyWith(host: '127.0.0.1', port: 8080, sslEnabled: false)
              .mockUserToken,
          'my-token');
    });

    test('withEmulator rejects the production host', () {
      expect(
          () => FirestoreSettings().withEmulator(
              FirestoreSettings.defaultHost, 443,
              mockUserToken: 'my-token'),
          throwsArgumentError);
      expect(
          () => FirestoreSettings()
              .withEmulator(FirestoreSettings.defaultHost, 443),
          throwsArgumentError);
    });

    test('settings without withEmulator never have a token', () {
      expect(FirestoreSettings().mockUserToken, isNull);
      expect(
          FirestoreSettings(host: '127.0.0.1', port: 8080, sslEnabled: false)
              .mockUserToken,
          isNull);
      // Emulator settings that moved to another host are plain settings again.
      final FirestoreSettings moved = FirestoreSettings()
          .withEmulator('127.0.0.1', 8080)
          .copyWith(host: 'example.com', port: 443, sslEnabled: true);
      expect(moved.mockUserToken, isNull);
      expect(moved, FirestoreSettings(host: 'example.com'));
    });

    test('toString does not print the token', () {
      final FirestoreSettings settings = FirestoreSettings()
          .withEmulator('127.0.0.1', 8080, mockUserToken: 'secret-token');
      expect(settings.toString(), isNot(contains('secret-token')));
    });
  });

  group('requests', () {
    late Server server;
    late List<Map<String, String>> calls;

    setUp(() async {
      calls = <Map<String, String>>[];
      server = Server.create(
        services: <Service>[FakeFirestoreService()],
        interceptors: <Interceptor>[
          (ServiceCall call, ServiceMethod<dynamic, dynamic> method) {
            calls.add(Map<String, String>.of(call.clientMetadata!));
            return const GrpcError.permissionDenied(
                'rejected by the test server');
          },
        ],
      );
      await server.serve(address: '127.0.0.1', port: 0);
    });

    tearDown(() => server.shutdown());

    Future<void> getFromServer(
        FirestoreSettings settings, String appName) async {
      final FirebaseApp app = newApp(appName);
      addTearDown(app.delete);
      final Firestore firestore = await Firestore.instanceFor(
          app: app,
          settings:
              settings.copyWith(cacheSettings: const MemoryCacheSettings()));
      addTearDown(firestore.terminate);
      await expectLater(firestore.doc('col/doc').get(Source.server),
          throwsA(isA<FirestoreError>()));
    }

    test('send the mock user token as the bearer token', () async {
      await getFromServer(
          FirestoreSettings().withEmulator('127.0.0.1', server.port!,
              mockUserToken: <String, Object?>{'sub': 'alice'}),
          'mockUserTokenClaims');

      final String expected =
          createMockUserToken(<String, Object?>{'sub': 'alice'}, 'my-project');
      expect(calls, isNotEmpty);
      for (final Map<String, String> metadata in calls) {
        expect(metadata['authorization'], 'Bearer $expected');
      }
    });

    test('send no authorization header without a mock user token', () async {
      await getFromServer(
          FirestoreSettings().withEmulator('127.0.0.1', server.port!),
          'mockUserTokenNone');

      expect(calls, isNotEmpty);
      for (final Map<String, String> metadata in calls) {
        expect(metadata.containsKey('authorization'), isFalse);
      }
    });
  });
}
