// Security review: TLS can only be turned off for a host other than the
// production one, and that is enforced in every build mode (it used to be an
// `assert`, which release builds drop).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

void main() {
  group('sslEnabled: false with the production host', () {
    test('is rejected by the constructor with an ArgumentError', () {
      expect(() => FirestoreSettings(sslEnabled: false), throwsArgumentError);
      expect(
          () => FirestoreSettings(
              host: FirestoreSettings.defaultHost, sslEnabled: false),
          throwsArgumentError);
    });

    test('is rejected by copyWith', () {
      expect(() => FirestoreSettings().copyWith(sslEnabled: false),
          throwsArgumentError);
      // Emulator settings moved back to the production host must not keep
      // their plaintext setting.
      expect(
          () => FirestoreSettings()
              .withEmulator('127.0.0.1', 8080)
              .copyWith(host: FirestoreSettings.defaultHost),
          throwsArgumentError);
    });

    test('is rejected whatever the case or a trailing dot of the host', () {
      for (final String host in <String>[
        'FIRESTORE.googleapis.com',
        'firestore.googleapis.com.',
        ' firestore.googleapis.com',
      ]) {
        expect(() => FirestoreSettings(host: host, sslEnabled: false),
            throwsArgumentError,
            reason: host);
        expect(() => FirestoreSettings().withEmulator(host, 443),
            throwsArgumentError,
            reason: host);
        expect(
            () => FirestoreSettings().withEmulator(host, 443,
                mockUserToken: <String, Object?>{'sub': 'alice'}),
            throwsArgumentError,
            reason: host);
      }
    });
  });

  test('a host that is not a plain host name is rejected', () {
    // The web transport builds URLs from the host: 'good.example@evil.example'
    // would send every request, with its credentials, to evil.example.
    for (final String host in <String>[
      'firestore.googleapis.com@evil.example',
      'evil.example/firestore.googleapis.com',
      'evil.example?x=',
      'evil.example#',
      r'evil.example\@firestore.googleapis.com',
      'evil.example firestore.googleapis.com',
      'http://evil.example',
      '',
    ]) {
      expect(() => FirestoreSettings(host: host), throwsArgumentError,
          reason: host);
      expect(
          () => FirestoreSettings().copyWith(host: host), throwsArgumentError,
          reason: host);
      expect(() => FirestoreSettings().withEmulator(host, 8080),
          throwsArgumentError,
          reason: host);
    }
    // Host names, IPv4 and IPv6 literals are fine.
    for (final String host in <String>[
      'localhost',
      '10.0.2.2',
      '::1',
      '[::1]',
      'my-proxy.internal.example.com',
    ]) {
      expect(FirestoreSettings(host: host).host, host);
    }
  });

  test('TLS stays on by default and for a custom host', () {
    expect(FirestoreSettings().sslEnabled, isTrue);
    expect(FirestoreSettings(host: 'example.com').sslEnabled, isTrue);
    expect(
        FirestoreSettings().copyWith(host: 'example.com').sslEnabled, isTrue);
  });

  test('plaintext is possible for an explicitly configured other host', () {
    expect(FirestoreSettings(host: 'localhost', sslEnabled: false).sslEnabled,
        isFalse);
    expect(FirestoreSettings().withEmulator('localhost', 8080).sslEnabled,
        isFalse);
  });
}
