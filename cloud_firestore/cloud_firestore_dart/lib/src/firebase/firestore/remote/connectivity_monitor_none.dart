import 'package:rxdart/rxdart.dart';

/// Returns the connectivity the client should listen to, given the one of the
/// app (`PlatformDependencies.onNetworkConnected`). This platform has nothing
/// to add.
BehaviorSubject<bool> withPlatformConnectivity(
  BehaviorSubject<bool> onNetworkConnected,
) => onNetworkConnected;
