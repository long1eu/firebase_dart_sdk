@TestOn('windows')
library;

import 'dart:io';

import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

/// Files encrypted with DPAPI in %LOCALAPPDATA%\<service>. Run in the
/// user's desktop session: over SSH DPAPI refuses access (no interactive
/// logon) and the tests fail with CryptProtectData status 5
/// (ERROR_ACCESS_DENIED).
void main() {
  group('Windows DPAPI', skip: integrationSkip(), () {
    String directoryOf(String service) =>
        '${Platform.environment['LOCALAPPDATA']}\\$service';

    defineStoreContract(
      open: (String service) => SecretStore.platform(service: service),
      cleanUp: (String service) async {
        final Directory dir = Directory(directoryOf(service));
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      },
      inspect: (String service, String account, String secret) async {
        final List<FileSystemEntity> files = Directory(
          directoryOf(service),
        ).listSync();
        expect(files, hasLength(1));
        final List<int> bytes = File(files.single.path).readAsBytesSync();
        expect(String.fromCharCodes(bytes), isNot(contains(secret)));
      },
    );
  });
}
