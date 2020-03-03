// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:rxdart/rxdart.dart';

/// This class should hold services that Firebase depends on and are platform specific.
abstract class PlatformDependencies {
  const PlatformDependencies();

  /// This stream should emit true then the app enters in background and false otherwise
  BehaviorSubject<bool> get onBackgroundChanged;

  /// This stream should emit true when there is an internet connection and false otherwise
  BehaviorSubject<bool> get onNetworkConnected;

  HeaderBuilder get headersBuilder;

  LocalStorage get storage;

  InternalTokenProvider get authProvider;
}

abstract class LocalStorage {
  String get(String key);

  Future<void> set(String key, String value);
}

/// Signature used to retrieved platform specific headers for every request made by Firebase services.
typedef HeaderBuilder = Map<String, String> Function();
