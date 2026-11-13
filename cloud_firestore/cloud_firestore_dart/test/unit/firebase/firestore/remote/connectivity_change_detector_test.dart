// The built-in connectivity detector of the VM: it only gives hints that the
// connectivity may be back, from the addresses of the network interfaces and
// from jumps of the wall clock.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_monitor.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_monitor_io.dart'
    as io;
import 'package:test/test.dart';

import '../../../../util/fake_timers.dart';

void main() {
  const Duration poll = Duration(seconds: 2);

  late FakeTimers timers;
  late Set<String> addresses;
  late int listCalls;
  late int signals;
  late ConnectivityChangeDetector detector;

  setUp(() {
    timers = FakeTimers();
    addresses = <String>{'en0/192.168.1.20'};
    listCalls = 0;
    signals = 0;
    detector = ConnectivityChangeDetector(
      listAddresses: () async {
        listCalls++;
        return Set<String>.of(addresses);
      },
      pollInterval: poll,
      now: () => timers.now,
      createTimer: timers.create,
    )..onChange = () => signals++;
  });

  test('has no timer and reads nothing until it is started', () async {
    await pumpEventQueue();
    expect(detector.isRunning, isFalse);
    expect(timers.timers, isEmpty);
    expect(listCalls, 0);
  });

  test('signals when an address appears', () async {
    addresses = <String>{};
    detector.start();
    await pumpEventQueue();
    await timers.elapse(poll);
    expect(signals, 0);

    // Wi-Fi is back.
    addresses = <String>{'en0/192.168.1.20'};
    await timers.elapse(poll);
    expect(signals, 1);
  });

  test('signals when an address changes', () async {
    detector.start();
    await pumpEventQueue();

    // Another network: the old address is gone and a new one is there.
    addresses = <String>{'en0/10.0.0.7'};
    await timers.elapse(poll);
    expect(signals, 1);
  });

  test('signals when an interface is added (a VPN came up)', () async {
    detector.start();
    await pumpEventQueue();
    addresses = <String>{'en0/192.168.1.20', 'utun4/10.8.0.2'};
    await timers.elapse(poll);
    expect(signals, 1);
  });

  test('does not signal while nothing changes', () async {
    detector.start();
    await pumpEventQueue();
    for (int i = 0; i < 20; i++) {
      await timers.elapse(poll);
    }
    expect(signals, 0);
    // It keeps one timer, not one per poll.
    expect(timers.active, 1);
  });

  test('does not signal when an address goes away', () async {
    addresses = <String>{'en0/192.168.1.20', 'utun4/10.8.0.2'};
    detector.start();
    await pumpEventQueue();

    addresses = <String>{'en0/192.168.1.20'};
    await timers.elapse(poll);
    addresses = <String>{};
    await timers.elapse(poll);
    expect(signals, 0);
  });

  test('takes the addresses at start as the baseline', () async {
    detector.start();
    await pumpEventQueue();
    await timers.elapse(poll);
    expect(signals, 0, reason: 'the address was already there');

    // After a stop, the next start does not compare with the old baseline.
    detector.stop();
    addresses = <String>{'en0/10.0.0.7'};
    detector.start();
    await pumpEventQueue();
    await timers.elapse(poll);
    expect(signals, 0);
  });

  test(
    'signals when the clock jumps ahead of the timer (wake from sleep)',
    () async {
      detector.start();
      await pumpEventQueue();
      await timers.elapse(poll);
      expect(signals, 0);

      // The machine slept for an hour: the timer fires once, an hour late.
      await timers.elapse(const Duration(hours: 1));
      expect(signals, 1);

      // A poll that is a little late (a busy isolate) is not a wake-up.
      await timers.elapse(const Duration(seconds: 10));
      await timers.elapse(poll + const Duration(seconds: 5));
      expect(signals, 1);
    },
  );

  test('does not signal more often than minSignalInterval', () async {
    detector.start();
    await pumpEventQueue();
    for (int i = 0; i < 2; i++) {
      // A flapping interface: a new address at every poll.
      addresses = <String>{'en0/10.0.0.$i'};
      await timers.elapse(poll);
    }
    expect(signals, 1);

    addresses = <String>{'en0/10.0.1.1'};
    await timers.elapse(poll);
    addresses = <String>{'en0/10.0.1.2'};
    await timers.elapse(poll);
    // 8 seconds after the first signal, more than the 5 seconds between two.
    expect(signals, 2);
  });

  test('stop cancels the timer and a poll in flight does not signal', () async {
    final Completer<Set<String>> slowList = Completer<Set<String>>();
    int calls = 0;
    detector = ConnectivityChangeDetector(
      listAddresses: () {
        calls++;
        // The baseline is read right away, the first poll hangs.
        return calls == 1
            ? Future<Set<String>>.value(<String>{})
            : slowList.future;
      },
      pollInterval: poll,
      now: () => timers.now,
      createTimer: timers.create,
    )..onChange = () => signals++;

    detector.start();
    await pumpEventQueue();
    await timers.elapse(poll);
    expect(calls, 2);

    detector.stop();
    expect(detector.isRunning, isFalse);
    expect(timers.active, 0);

    slowList.complete(<String>{'en0/192.168.1.20'});
    await pumpEventQueue();
    expect(signals, 0);
    await timers.elapse(const Duration(minutes: 1));
    expect(calls, 2, reason: 'nothing polls after stop');
  });

  test('start twice keeps one timer', () async {
    detector
      ..start()
      ..start();
    await pumpEventQueue();
    expect(timers.active, 1);
  });

  test('dispose stops it for good', () async {
    detector.start();
    await pumpEventQueue();
    detector.dispose();
    expect(timers.active, 0);

    detector.start();
    expect(detector.isRunning, isFalse);
    expect(detector.isDisposed, isTrue);
    expect(timers.active, 0);
  });

  test('an interface list that cannot be read is not a signal', () async {
    bool fail = false;
    detector = ConnectivityChangeDetector(
      listAddresses: () async {
        if (fail) {
          throw StateError('no interfaces for you');
        }
        return <String>{'en0/192.168.1.20'};
      },
      pollInterval: poll,
      now: () => timers.now,
      createTimer: timers.create,
    )..onChange = () => signals++;
    detector.start();
    await pumpEventQueue();

    fail = true;
    await timers.elapse(poll);
    fail = false;
    await timers.elapse(poll);
    expect(signals, 0, reason: 'the same address as before the failure');
    expect(detector.isRunning, isTrue);
  });

  group('on this platform', () {
    test('the detector reads the real interfaces', () async {
      final Set<String> addresses = await io.listInterfaceAddresses();
      // Every entry is `<interface>/<address>`. A machine without any network
      // has none, which is fine.
      for (final String address in addresses) {
        expect(address, matches(RegExp(r'^[^/]+/.+$')));
        expect(address, isNot(contains('127.0.0.1')));
      }
      // Reading twice in a row gives the same set, so an idle machine does not
      // produce signals.
      expect(await io.listInterfaceAddresses(), addresses);
    });

    test('a detector is created, with real timers, and stops', () async {
      final ConnectivityChangeDetector? real =
          createConnectivityChangeDetector();
      expect(real, isNotNull);
      int realSignals = 0;
      real!.onChange = () => realSignals++;
      real.start();
      expect(real.isRunning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      real.dispose();
      expect(real.isRunning, isFalse);
      expect(realSignals, 0);
    });
  });
}
