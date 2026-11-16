// RS256 verification and the X.509 reader: keys made in Dart, one known vector (a certificate and a token that
// openssl signed once; the private key was discarded), and openssl cross-checks when openssl is installed.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_admin_dart/src/auth/jwt.dart';
import 'package:firebase_admin_dart/src/auth/rsa.dart';
import 'package:test/test.dart';

import 'support.dart';

// Made with `openssl req -x509 -newkey rsa:2048 -subj /CN=test-vector`; the token is the RS256 signature by
// `openssl dgst -sha256 -sign` of its first two segments. The private key was deleted right after.
const String _vectorCertificate = '''
-----BEGIN CERTIFICATE-----
MIICqDCCAZACCQCRsPymdmJZkTANBgkqhkiG9w0BAQsFADAWMRQwEgYDVQQDDAt0
ZXN0LXZlY3RvcjAeFw0yNjExMTYwNTQzNTFaFw0zNjExMTMwNTQzNTFaMBYxFDAS
BgNVBAMMC3Rlc3QtdmVjdG9yMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
AQEAv0s5xGVhzIgDPKZff6e6C/U/mgyCJpdkKXx6erfIBnVuV7AruhdnlalBbfdL
kBhliSRI/OEU7F/6tbB5h1+hcLp3WKlJfl1Y7kNBG0hvmJo5kJM0mBGJp/gNGTkP
zbASwVtd4e2TsyCaiCt01BDwWK/lkojWw0QGYdmXXqTjuKvoMd+KeM58GtSykzFn
9K82qMJB0cOVkVFT37m+TNptW9YxAXXUiGbu7o1Av3tRKuJdptEm8++9eU3Ryqrm
pIR90aHYugeUJ7LTCwdr5OheFkrS5E8sfsyIZKVpOukKxnIZZtx5jFbNfbOC8zDP
+fh55EWmWlvRloAeF2GF7AGiwQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAC/bwy
LBQQGkPmx+I0oLK6gWoSNpx1dngcWh4OFg/aRK9LIjWzORxvOZ/29OVXl/4J2YWx
UII2taaaC4V1tGSYfK1X1nYsUEcY0zD/JxSENajBSOmkrr5Bg5wt9UDZGjdgC1Kf
9U8DqX/DzYj0DQH+RwCFDq1vJHh9KB1yv2Sm1UQ9ZfI28/JYjk+F1NJq0H45Vjbq
f/pomEv6hynZWS4zDrT04baSyEj68GxaIax4PMhL+fQdylpG7XuM+Sigb38NQA1p
8rbbPiUWeS4/1udsqOMUQDXGW9xZUdl8I+2sJTjL1rpBa2F5HjpzLwsTUsmqcL1l
uy2r8sFiaixcx1MR
-----END CERTIFICATE-----
''';

const String vectorToken =
    'eyJhbGciOiJSUzI1NiIsImtpZCI6InZlY3Rvci1raWQiLCJ0eXAiOiJKV1QifQ.'
    'eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vZGVtby10ZXN0IiwiYXVkIjoiZGVtby10ZXN0IiwiYXV0aF90aW1lIjoxNzkw'
    'MDAwMDAwLCJ1c2VyX2lkIjoidmVjdG9yLXVzZXIiLCJzdWIiOiJ2ZWN0b3ItdXNlciIsImlhdCI6MTc5MDAwMDAwMCwiZXhwIjoxNzkwMDAzNjAw'
    'LCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7fSwic2lnbl9pbl9wcm92aWRlciI6ImN1c3RvbSJ9fQ.'
    'BIkWxmqKFxUAXjXMI0L5D625iR0rBq7S8OUcFvZeTGma-oV40rNZL7htbotuPbrKxTiEg_q4fJwYVmJ8zZYf34aY_DCs5WTDI4sVXITFIxgSeHiQ'
    'MMqE0NXDM246ucqGD1R6H00SpLQO078N-R4jBP-yegx3knkTFIfGxFTPWtP89m3gQem_tyIkjLxZ-0cbSv6b3LfUQxeGY6SqIXNlS-WXrGvbYiKW'
    'c8AiPmL4O6LFoV2AkHChu_FF-Y1LQih2neoSZENL8DKFUnstqq9e6AcAGQc4FAGXoY5BtHlDxvemcNsSDD1dLOwOXVhyCRcxPQ6fvkxsedB5g0_z'
    'M4iVog';

/// The certificate of [vectorToken].
String get vectorCertificate => _vectorCertificate;

bool _verifies(RsaPublicKey key, String token) {
  final List<String> parts = token.split('.');
  return key.verifyRs256(
    ascii.encode('${parts[0]}.${parts[1]}'),
    decodeSegment(parts[2]),
  );
}

void main() {
  final TestKey key = TestKey();
  final TestKey other = TestKey();

  group('RsaPublicKey', () {
    test('reads the key of a certificate', () {
      final RsaPublicKey parsed = RsaPublicKey.fromCertificatePem(
        key.certificatePem,
      );
      expect(parsed.modulus, key.n);
      expect(parsed.exponent, key.e);
    });

    test('verifies a signature of the matching key only', () {
      final List<int> data = utf8.encode('header.payload');
      final RsaPublicKey public = RsaPublicKey(key.n, key.e);
      expect(public.verifyRs256(data, key.sign(data)), isTrue);
      expect(
        public.verifyRs256(utf8.encode('header.payloaD'), key.sign(data)),
        isFalse,
      );
      expect(public.verifyRs256(data, other.sign(data)), isFalse);
      final List<int> flipped = key.sign(data)..[10] ^= 1;
      expect(public.verifyRs256(data, flipped), isFalse);
      expect(public.verifyRs256(data, key.sign(data).sublist(1)), isFalse);
      expect(public.verifyRs256(data, bytesOf(key.n, key.length)), isFalse);
    });

    test('the known vector verifies, and fails once changed', () {
      final RsaPublicKey public = RsaPublicKey.fromCertificatePem(
        vectorCertificate,
      );
      expect(public.modulus.bitLength, 2048);
      expect(public.exponent, BigInt.from(65537));
      expect(_verifies(public, vectorToken), isTrue);
      final List<String> parts = vectorToken.split('.');
      final String otherPayload =
          '${parts[0]}.${segment(<String, Object?>{'sub': 'someone-else'})}.${parts[2]}';
      expect(_verifies(public, otherPayload), isFalse);
      expect(_verifies(RsaPublicKey(key.n, key.e), vectorToken), isFalse);
    });

    test('refuses what is not a certificate with an RSA key', () {
      for (final String bad in <String>[
        '',
        'not pem',
        '-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----',
        pem('CERTIFICATE', <int>[0x30, 0x03, 0x02, 0x01, 0x01]),
        pem('CERTIFICATE', <int>[0x30, 0x84, 0x7f, 0xff, 0xff, 0xff]),
        pem('CERTIFICATE', derSequence(<List<int>>[derInteger(BigInt.one)])),
      ]) {
        expect(
          () => RsaPublicKey.fromCertificatePem(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    final String? skip = opensslSkip();

    test(
      'openssl agrees with the keys, signatures and certificates the tests make',
      () {
        final Directory temp = Directory.systemTemp.createTempSync(
          'admin_rsa_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        final List<int> data = utf8.encode('header.payload');
        File('${temp.path}/public.pem').writeAsStringSync(key.publicKeyPem);
        File('${temp.path}/data').writeAsBytesSync(data);
        File('${temp.path}/sig').writeAsBytesSync(key.sign(data));
        final ProcessResult result = Process.runSync('openssl', <String>[
          'dgst', '-sha256', '-verify', '${temp.path}/public.pem', //
          '-signature', '${temp.path}/sig', '${temp.path}/data',
        ]);
        expect('${result.stdout}', contains('Verified OK'));
        // And the test certificate is a DER openssl can read.
        File('${temp.path}/cert.pem').writeAsStringSync(key.certificatePem);
        final ProcessResult cert = Process.runSync('openssl', <String>[
          'x509', '-in', '${temp.path}/cert.pem', '-noout', '-modulus', //
        ]);
        expect(
          '${cert.stdout}'.trim().toLowerCase(),
          'modulus=${key.n.toRadixString(16)}',
        );
      },
      skip: skip,
    );

    test(
      'verifies a token that openssl signed now, with a certificate openssl made',
      () {
        final Directory temp = Directory.systemTemp.createTempSync(
          'admin_rsa_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        final ProcessResult made = Process.runSync('openssl', <String>[
          'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
          '-subj',
          '/CN=throwaway',
          '-keyout',
          '${temp.path}/key.pem',
          '-out',
          '${temp.path}/cert.pem',
        ]);
        expect(made.exitCode, 0, reason: '${made.stderr}');
        final String input =
            '${segment(<String, Object?>{'alg': 'RS256', 'kid': 'k'})}.${segment(<String, Object?>{'q': '???~~~'})}';
        File('${temp.path}/input').writeAsStringSync(input);
        final ProcessResult signed = Process.runSync('openssl', <String>[
          'dgst', '-sha256', '-sign', '${temp.path}/key.pem', //
          '-out', '${temp.path}/sig', '${temp.path}/input',
        ]);
        expect(signed.exitCode, 0, reason: '${signed.stderr}');
        final String token =
            '$input.${b64url(File('${temp.path}/sig').readAsBytesSync())}';
        final RsaPublicKey public = RsaPublicKey.fromCertificatePem(
          File('${temp.path}/cert.pem').readAsStringSync(),
        );
        expect(_verifies(public, token), isTrue);
        expect(_verifies(RsaPublicKey(key.n, key.e), token), isFalse);
      },
      skip: skip,
    );
  });

  group('JWT segments', () {
    test('base64url without padding only', () {
      expect(base64UrlNoPadding(<int>[0xfb, 0xff]), '-_8');
      expect(decodeSegment('-_8'), <int>[0xfb, 0xff]);
      for (final String bad in <String>['+/8', '-_8=', 'a b', 'abcde']) {
        expect(() => decodeSegment(bad), throwsFormatException, reason: bad);
      }
      expect(
        () => decodeJsonSegment(b64url(utf8.encode('[1]'))),
        throwsFormatException,
      );
    });
  });
}
