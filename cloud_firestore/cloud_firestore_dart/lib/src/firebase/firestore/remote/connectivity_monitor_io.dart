import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:rxdart/rxdart.dart';

/// Returns the connectivity the client should listen to, given the one of the
/// app (`PlatformDependencies.onNetworkConnected`). `dart:io` has no
/// reachability events to add to it; see [createConnectivityChangeDetector]
/// for what this platform does instead.
BehaviorSubject<bool> withPlatformConnectivity(
  BehaviorSubject<bool> onNetworkConnected,
) => onNetworkConnected;

/// A detector that watches the addresses of the network interfaces of the
/// machine (`NetworkInterface.list`).
ConnectivityChangeDetector? createConnectivityChangeDetector() {
  return ConnectivityChangeDetector(listAddresses: listInterfaceAddresses);
}

/// The addresses of every interface except the loopback, as
/// `<interface>/<address>`.
Future<Set<String>> listInterfaceAddresses() async {
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    includeLinkLocal: true,
    type: InternetAddressType.any,
  );
  return <String>{
    for (final NetworkInterface interface in interfaces)
      for (final InternetAddress address in interface.addresses)
        '${interface.name}/${address.address}',
  };
}
