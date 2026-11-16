// Security review: TLS can only be turned off for a host other than the
// production one, and that is enforced in every build mode (it used to be an
// `assert`, which release builds drop).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

void main() {
  group('sslEnabled: false with the production host', () {
    test('is rejected by the constructor with an ArgumentError', () {
      expect(() => Settings(sslEnabled: false), throwsArgumentError);
      expect(
          () => Settings(
              host: Settings.defaultHost, sslEnabled: false),
          throwsArgumentError);
    });

    test('is rejected by copyWith', () {
      expect(() => Settings().copyWith(sslEnabled: false),
          throwsArgumentError);
      // Emulator settings moved back to the production host must not keep
      // their plaintext setting.
      expect(
          () => Settings()
              .withEmulator('127.0.0.1', 8080)
              .copyWith(host: Settings.defaultHost),
          throwsArgumentError);
    });

    test('is rejected whatever the case or a trailing dot of the host', () {
      for (final String host in <String>[
        'FIRESTORE.googleapis.com',
        'firestore.googleapis.com.',
        ' firestore.googleapis.com',
      ]) {
        expect(() => Settings(host: host, sslEnabled: false),
            throwsArgumentError,
            reason: host);
        expect(() => Settings().withEmulator(host, 443),
            throwsArgumentError,
            reason: host);
        expect(
            () => Settings().withEmulator(host, 443,
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
      expect(() => Settings(host: host), throwsArgumentError,
          reason: host);
      expect(
          () => Settings().copyWith(host: host), throwsArgumentError,
          reason: host);
      expect(() => Settings().withEmulator(host, 8080),
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
      expect(Settings(host: host).host, host);
    }
  });

  test('TLS stays on by default and for a custom host', () {
    expect(Settings().sslEnabled, isTrue);
    expect(Settings(host: 'example.com').sslEnabled, isTrue);
    expect(
        Settings().copyWith(host: 'example.com').sslEnabled, isTrue);
  });

  test('plaintext is possible for an explicitly configured other host', () {
    expect(Settings(host: 'localhost', sslEnabled: false).sslEnabled,
        isFalse);
    expect(Settings().withEmulator('localhost', 8080).sslEnabled,
        isFalse);
  });
}
