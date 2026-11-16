// ServiceAccountKey and FirebaseUserAuth.emulatorOrigin. The key is a throwaway made by the test with openssl
// (nothing is committed, nothing real is read); the key tests are skipped without it.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

void main() {
  String? skip;
  try {
    if (Process.runSync('openssl', <String>['version']).exitCode != 0) {
      skip =
          '`openssl version` failed: the test needs openssl to make a throwaway key';
    }
  } on ProcessException {
    skip =
        'openssl is not installed: the test needs it to make a throwaway key';
  }

  group('ServiceAccountKey', () {
    late Directory temp;
    late Map<String, Object?> keyFile;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('auth_providers_sak_');
      ProcessResult result = Process.runSync('openssl', <String>[
        'genpkey',
        '-algorithm',
        'RSA',
        '-pkeyopt',
        'rsa_keygen_bits:2048',
        '-out',
        '${temp.path}/key.pem',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      result = Process.runSync('openssl', <String>[
        'pkey',
        '-in',
        '${temp.path}/key.pem',
        '-pubout',
        '-out',
        '${temp.path}/public.pem',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      keyFile = <String, Object?>{
        'type': 'service_account',
        'project_id': 'demo-test',
        'private_key_id': 'throwaway',
        'private_key': File('${temp.path}/key.pem').readAsStringSync(),
        'client_email': 'kit@demo-test.iam.gserviceaccount.com',
        'client_id': '1234567890',
      };
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('reads the fields of the key file, from a map or a string', () {
      for (final Object json in <Object>[keyFile, jsonEncode(keyFile)]) {
        final ServiceAccountKey key = ServiceAccountKey.fromJson(json);
        expect(key.clientEmail, 'kit@demo-test.iam.gserviceaccount.com');
        expect(key.projectId, 'demo-test');
        expect(key.privateKeyId, 'throwaway');
        expect(key.modulus.bitLength, 2048);
        expect(key.publicExponent, BigInt.from(65537));
        expect('$key', isNot(contains('PRIVATE')));
      }
    });

    test('signs RS256 signatures that openssl verifies', () {
      final ServiceAccountKey key = ServiceAccountKey.fromJson(keyFile);
      final List<int> data = utf8.encode('header.payload');
      File('${temp.path}/data.txt').writeAsBytesSync(data);
      File('${temp.path}/sig.bin').writeAsBytesSync(key.signRs256(data));
      final ProcessResult verify = Process.runSync('openssl', <String>[
        'dgst',
        '-sha256',
        '-verify',
        '${temp.path}/public.pem',
        '-signature',
        '${temp.path}/sig.bin',
        '${temp.path}/data.txt',
      ]);
      expect('${verify.stdout}', contains('Verified OK'));
    });

    test('something that is not a key file is rejected without quoting it', () {
      for (final Object bad in <Object>[
        <String, Object?>{},
        <String, Object?>{...keyFile, 'type': 'authorized_user'},
        'not json',
      ]) {
        expect(
          () => ServiceAccountKey.fromJson(bad),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '$e',
              'text',
              isNot(contains('PRIVATE KEY')),
            ),
          ),
        );
      }
    });
  }, skip: skip);

  test('emulatorOrigin checks the host like the constructor', () {
    expect(
      FirebaseUserAuth.emulatorOrigin('127.0.0.1:9099'),
      'http://127.0.0.1:9099',
    );
    expect(
      FirebaseUserAuth.emulatorOrigin('https://localhost:9099/'),
      'https://localhost:9099',
    );
    for (final String bad in <String>[
      'user@127.0.0.1:9099',
      '127.0.0.1:9099/path',
      '127.0.0.1:0',
      'identitytoolkit.googleapis.com',
    ]) {
      expect(() => FirebaseUserAuth.emulatorOrigin(bad), throwsArgumentError);
    }
  });
}
