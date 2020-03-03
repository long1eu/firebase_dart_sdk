// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:rxdart/rxdart.dart';

/// This class should provide services that Firebase depends on and are platform
/// specific.
class PlatformDependencies extends LocalStorage {
  PlatformDependencies();

  final Map<String, String> _map = <String, String>{};

  /// This stream should emit true then the app enters in background and false
  /// otherwise
  BehaviorSubject<bool> get onBackgroundChanged {
    return BehaviorSubject<bool>.seeded(false);
  }

  /// This stream should emit true when there is an internet connection and
  /// false otherwise
  BehaviorSubject<bool> get onNetworkConnected {
    return BehaviorSubject<bool>.seeded(true);
  }

  /// Used by Firebase services when a network call is made and the user are
  /// allowed to add their own headers
  HeaderBuilder get headersBuilder => null;

  /// Used by Firebase services to persist various data (eg. user session)
  ///
  /// If you don't want that an in memory implementation should be used.
  LocalStorage get storage => this;

  /// Firebase services will use this to generate authorization headers
  ///
  /// If you are planing to also use FirebaseAuth you don't need to worry about
  /// this field. Firebase Auth SDK automatically registers as
  /// [InternalTokenProvider] if none is set.
  InternalTokenProvider get authProvider => null;

  @override
  String get(String key) {
    return _map[key];
  }

  @override
  Future<void> set(String key, String value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }
}

/// Local persistence interface to store key/value pairs
abstract class LocalStorage {
  /// Gets the values at [key], or null if none found.
  String get(String key);

  /// Saves the value at [key].
  ///
  /// When a null value is provided the implementation should remove the value.
  Future<void> set(String key, String value);
}

/// Signature used to retrieved platform specific headers for every request made
/// by Firebase services.
typedef HeaderBuilder = Map<String, String> Function();
