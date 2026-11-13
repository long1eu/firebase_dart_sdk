// The connectivity detector of the VM against a real change of the network interfaces: a dummy interface is added
// and removed with `ip` (iproute2). Needs Linux and the right to change the interfaces (root with CAP_NET_ADMIN, for
// example a container started with `--cap-add NET_ADMIN`), so it runs only when FIRESTORE_TEST_NET_ADMIN=1.
// tool/linux/run_in_container.sh sets it.

@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_monitor_io.dart'
    as io;
import 'package:test/test.dart';

const String interfaceName = 'fsdummy0';
const String address = '10.213.77.1';

Future<void> ip(List<String> args) async {
  final ProcessResult result = await Process.run('ip', args);
  if (result.exitCode != 0) {
    fail('ip ${args.join(' ')}: ${result.stderr}');
  }
}

Future<void> removeInterface() async {
  await Process.run('ip', <String>['link', 'delete', interfaceName]);
}

void main() {
  final bool enabled = Platform.environment['FIRESTORE_TEST_NET_ADMIN'] == '1';

  test(
    'an address that appears on a new interface is a hint, its removal is not',
    () async {
      await removeInterface();
      addTearDown(removeInterface);

      final ConnectivityChangeDetector detector = ConnectivityChangeDetector(
        listAddresses: io.listInterfaceAddresses,
        pollInterval: const Duration(milliseconds: 200),
        minSignalInterval: Duration.zero,
      );
      addTearDown(detector.dispose);
      final StreamController<void> signals = StreamController<void>.broadcast();
      detector.onChange = () => signals.add(null);
      int count = 0;
      signals.stream.listen((_) => count++);

      detector.start();
      // Let the baseline be read and a few polls pass: nothing changed yet.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(count, 0);

      final Future<void> signal = signals.stream.first;
      await ip(<String>['link', 'add', interfaceName, 'type', 'dummy']);
      await ip(<String>['addr', 'add', '$address/32', 'dev', interfaceName]);
      await ip(<String>['link', 'set', interfaceName, 'up']);
      await signal.timeout(const Duration(seconds: 10));
      expect(
        await io.listInterfaceAddresses(),
        contains('$interfaceName/$address'),
      );

      final int before = count;
      await removeInterface();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(
        await io.listInterfaceAddresses(),
        isNot(contains('$interfaceName/$address')),
      );
      expect(count, before, reason: 'an address that went away is no hint');
    },
    skip: enabled
        ? false
        : 'Changes the network interfaces: needs root with CAP_NET_ADMIN '
              'and FIRESTORE_TEST_NET_ADMIN=1 (tool/linux/run_in_container.sh).',
  );
}
