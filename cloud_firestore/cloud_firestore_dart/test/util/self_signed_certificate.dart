// A self-signed certificate and its key, made by the test that needs them with
// the `openssl` command line tool. Nothing is checked in: the files live in a
// temporary directory until [SelfSignedCertificate.delete].

import 'dart:io';

/// A self-signed server certificate for a test server.
class SelfSignedCertificate {
  SelfSignedCertificate._(this._directory);

  /// Why no certificate can be made on this machine (openssl is missing), or
  /// null. Use it as the `skip` reason of the tests that need one.
  static final String? unavailableReason = _unavailableReason();

  static String? _unavailableReason() {
    try {
      if (Process.runSync('openssl', <String>['version']).exitCode != 0) {
        return '`openssl version` failed: the test needs openssl to make a '
            'certificate';
      }
    } on ProcessException {
      return 'openssl is not installed: the test needs it to make a '
          'self-signed certificate';
    }
    return null;
  }

  /// Makes a certificate for [name] (and the IP addresses in [ips]) that is
  /// valid for two days. Throws a [StateError] when openssl fails.
  factory SelfSignedCertificate.create(
    String name, {
    List<String> ips = const <String>[],
  }) {
    final Directory directory =
        Directory.systemTemp.createTempSync('firestore_test_tls_');
    final SelfSignedCertificate result = SelfSignedCertificate._(directory);
    final ProcessResult process = Process.runSync('openssl', <String>[
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
      '-keyout', result.keyPath,
      '-out', result.certificatePath,
      '-subj', '/CN=$name',
      '-addext',
      'subjectAltName=${<String>[
        'DNS:$name',
        for (final String ip in ips) 'IP:$ip'
      ].join(',')}',
      // The platform verifier (macOS) only accepts a server certificate with this extension.
      '-addext', 'extendedKeyUsage=serverAuth',
    ]);
    if (process.exitCode != 0) {
      directory.deleteSync(recursive: true);
      throw StateError('openssl failed: ${process.stderr}');
    }
    return result;
  }

  final Directory _directory;

  String get certificatePath => '${_directory.path}/cert.pem';

  String get keyPath => '${_directory.path}/key.pem';

  /// The certificate, PEM encoded.
  List<int> get certificate => File(certificatePath).readAsBytesSync();

  /// The private key, PEM encoded.
  List<int> get privateKey => File(keyPath).readAsBytesSync();

  /// Deletes the files.
  void delete() {
    if (_directory.existsSync()) {
      _directory.deleteSync(recursive: true);
    }
  }
}
