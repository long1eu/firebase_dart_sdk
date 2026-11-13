import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:rxdart/rxdart.dart';

/// Returns the connectivity the client should listen to, given the one of the
/// app (`PlatformDependencies.onNetworkConnected`). This platform has nothing
/// to add.
BehaviorSubject<bool> withPlatformConnectivity(
  BehaviorSubject<bool> onNetworkConnected,
) => onNetworkConnected;

/// This platform has no way to notice that the connectivity may have changed.
ConnectivityChangeDetector? createConnectivityChangeDetector() => null;
