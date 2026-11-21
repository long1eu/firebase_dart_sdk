@TestOn('linux')
library;

import 'dart:io';

import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

/// The Secret Service of the session, through libsecret. Needs
/// libsecret-1-0, a D-Bus session bus and an unlocked keyring; see the
/// README for a headless run with dbus-run-session and gnome-keyring-daemon.
void main() {
  group('Linux Secret Service', skip: integrationSkip(), () {
    defineStoreContract(
      open: (String service) => SecretStore.platform(service: service),
      inspect: (String service, String account, String secret) async {
        // secret-tool (libsecret-tools) is optional: it proves the item has
        // the attributes the README names.
        final ProcessResult result;
        try {
          result = await Process.run('secret-tool', <String>[
            'lookup',
            'service',
            service,
            'account',
            account,
          ]);
        } on ProcessException {
          printOnFailure(
            'secret-tool is not installed; attributes not checked',
          );
          return;
        }
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}'.trim(), secret);
      },
    );

    test('without a Secret Service the error says unavailable', () async {
      // A session bus address that does not exist makes libsecret fail to
      // connect, in a child process so this process keeps its bus.
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'test/integration/linux_no_bus.dart'],
        environment: <String, String>{
          'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/nonexistent/bus',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect('${result.stdout}', contains('isUnavailable=true'));
    });
  });
}
