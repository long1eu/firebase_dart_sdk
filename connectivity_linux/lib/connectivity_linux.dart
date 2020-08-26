import 'dart:async';

import 'package:connectivity_platform_interface/connectivity_platform_interface.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

/// The Linux implementation of the ConnectivityPlatform of the Connectivity plugin.
class ConnectivityLinux extends ConnectivityPlatform {
  ConnectivityLinux() : _networkManager = NetworkManager();

  final NetworkManager _networkManager;

  /// Factory method that initializes the connectivity plugin platform with an instance
  /// of the plugin for Linux.
  static void register() {
    ConnectivityPlatform.instance = ConnectivityLinux();
  }

  @override
  Future<ConnectivityResult> checkConnectivity() async {
    final NetworkManagerState state = await _networkManager.state();
    return _stateToResult(state);
  }

  @override
  Stream<ConnectivityResult> get onConnectivityChanged {
    return _networkManager.stateChanged.map(_stateToResult);
  }

  // Creates an "unsupported_operation" PlatformException for a given `method` name.
  Exception _unsupported(String method) {
    return PlatformException(
      code: 'UNSUPPORTED_OPERATION',
      message: '$method() is not supported on Linux.',
    );
  }

  /// Obtains the wifi name (SSID) of the connected network
  @override
  Future<String> getWifiName() {
    throw _unsupported('getWifiName');
  }

  /// Obtains the wifi BSSID of the connected network.
  @override
  Future<String> getWifiBSSID() {
    throw _unsupported('getWifiBSSID');
  }

  /// Obtains the IP address of the connected wifi network
  @override
  Future<String> getWifiIP() {
    throw _unsupported('getWifiIP');
  }

  /// Request to authorize the location service (Only on iOS).
  @override
  Future<LocationAuthorizationStatus> requestLocationServiceAuthorization({
    bool requestAlwaysLocationUsage = false,
  }) {
    throw _unsupported('requestLocationServiceAuthorization');
  }

  /// Get the current location service authorization (Only on iOS).
  @override
  Future<LocationAuthorizationStatus> getLocationServiceAuthorization() {
    throw _unsupported('getLocationServiceAuthorization');
  }

  ConnectivityResult _stateToResult(NetworkManagerState state) {
    return state == NetworkManagerState.connectedGlobal || state == NetworkManagerState.unknown
        ? ConnectivityResult.wifi
        : ConnectivityResult.none;
  }
}

/// Interface over DBus for NetworkManager.
///
/// This exposes the state() method and the `StateChanged` signal.
/// see [NetworkManager](https://developer.gnome.org/NetworkManager/stable/gdbus-org.freedesktop.NetworkManager.html)
class NetworkManager {
  NetworkManager() : _client = DBusClient.system() {
    _stateController = StreamController<NetworkManagerState>.broadcast(
      onListen: () async {
        await _stateController.addStream(state().asStream());
        _stateSubscription = await _client.subscribeSignals(
          _onData,
          path: DBusObjectPath('/org/freedesktop/NetworkManager'),
          sender: 'org.freedesktop.NetworkManager',
          interface: 'org.freedesktop.NetworkManager',
          member: 'StateChanged',
        );
      },
      onCancel: () {
        _client.unsubscribeSignals(_stateSubscription);
        _stateSubscription = null;
      },
    );
  }

  final DBusClient _client;
  StreamController<NetworkManagerState> _stateController;
  DBusSignalSubscription _stateSubscription;

  /// The overall networking state as determined by the NetworkManager daemon,
  /// based on the state of network devices under its management.
  ///
  /// [state()](https://developer.gnome.org/NetworkManager/stable/gdbus-org.freedesktop.NetworkManager.html#gdbus-method-org-freedesktop-NetworkManager.state)
  Future<NetworkManagerState> state() async {
    final DBusMethodResponse result = await _client.callMethod(
      path: DBusObjectPath('/org/freedesktop/NetworkManager'),
      destination: 'org.freedesktop.NetworkManager',
      interface: 'org.freedesktop.NetworkManager',
      member: 'state',
    );

    if (result is DBusMethodErrorResponse) {
      return Future<NetworkManagerState>.error(
          StateError('${result.errorName}, ${result.values.join(',')}'), StackTrace.current);
    }
    final DBusUint32 rawValue = result.returnValues.first;
    return NetworkManagerState.valueOf(rawValue.value);
  }

  /// Emits the the NetworkManage's state when ever it changes.
  ///
  /// [StateChanged](https://developer.gnome.org/NetworkManager/stable/gdbus-org.freedesktop.NetworkManager.html#gdbus-signal-org-freedesktop-NetworkManager.StateChanged)
  Stream<NetworkManagerState> get stateChanged => _stateController.stream;

  void _onData(DBusObjectPath path, String interface, String member, List<DBusValue> values) {
    if (values.length == 1 && values[0].signature == const DBusSignature('u')) {
      final DBusUint32 rawValue = values.first;
      _stateController.add(NetworkManagerState.valueOf(rawValue.value));
    }
  }
}

/// Values that indicate the current overall network state.
class NetworkManagerState {
  const NetworkManagerState._(this._i, this._value);

  final int _i;
  final int _value;

  /// Networking state is unknown.
  ///
  /// This indicates a daemon error that makes it unable to reasonably assess the state.
  /// In such event the applications are expected to assume Internet connectivity might
  /// be present and not disable controls that require network access. The graphical shells
  /// may hide the network accessibility indicator altogether since no meaningful status
  /// indication can be provided.
  static const NetworkManagerState unknown = NetworkManagerState._(0, 0);

  /// Networking is not enabled, the system is being suspended or resumed from suspend.
  static const NetworkManagerState asleep = NetworkManagerState._(1, 10);

  /// There is no active network connection. The graphical shell should indicate no
  /// network connectivity and the applications should not attempt to access the network.
  static const NetworkManagerState disconnected = NetworkManagerState._(2, 20);

  /// Network connections are being cleaned up. The applications should tear down their
  /// network sessions.
  static const NetworkManagerState disconnecting = NetworkManagerState._(3, 30);

  /// A network connection is being started The graphical shell should indicate the
  /// network is being connected while the applications should still make no attempts
  /// to connect the network.
  static const NetworkManagerState connecting = NetworkManagerState._(4, 40);

  /// There is only local IPv4 and/or IPv6 connectivity, but no default route to access
  /// the Internet. The graphical shell should indicate no network connectivity.
  static const NetworkManagerState connectedLocal = NetworkManagerState._(5, 50);

  /// There is only site-wide IPv4 and/or IPv6 connectivity. This means a default route
  /// is available, but the Internet connectivity check did not succeed. The graphical
  /// shell should indicate limited network connectivity.
  static const NetworkManagerState connectedSite = NetworkManagerState._(6, 60);

  /// There is global IPv4 and/or IPv6 Internet connectivity This means the Internet
  /// connectivity check succeeded, the graphical shell should indicate full network
  /// connectivity.
  static const NetworkManagerState connectedGlobal = NetworkManagerState._(7, 70);

  static const List<NetworkManagerState> values = <NetworkManagerState>[
    unknown,
    asleep,
    disconnected,
    disconnecting,
    connecting,
    connectedLocal,
    connectedSite,
    connectedGlobal,
  ];

  static const List<String> _names = <String>[
    'unknown',
    'asleep',
    'disconnected',
    'disconnecting',
    'connecting',
    'connectedLocal',
    'connectedSite',
    'connectedGlobal',
  ];

  static NetworkManagerState valueOf(int value) {
    return values.firstWhere((NetworkManagerState state) => state._value == value);
  }

  @override
  String toString() {
    return 'NetworkManagerState.${_names[_i]}';
  }
}
