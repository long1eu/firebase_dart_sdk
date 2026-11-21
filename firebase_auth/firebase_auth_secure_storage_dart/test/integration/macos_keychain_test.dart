@TestOn('mac-os')
library;

import 'dart:io';

import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

/// The login keychain of the user running the test, through
/// Security.framework. Run from a desktop session (not SSH: the keychain is
/// locked there and macOS cannot prompt).
void main() {
  group('macOS login keychain', skip: integrationSkip(), () {
    defineStoreContract(
      open: (String service) => SecretStore.platform(service: service),
      inspect: (String service, String account, String secret) async {
        // `security` reads the legacy keychains only, so finding the item
        // proves it is a generic password of the login keychain, not of
        // the data-protection keychain.
        final ProcessResult result = await Process.run('security', <String>[
          'find-generic-password',
          '-s',
          service,
          '-a',
          account,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', contains('"genp"'));
      },
    );
  });
}
