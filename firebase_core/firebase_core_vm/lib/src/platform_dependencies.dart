// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart';
import 'package:rxdart/rxdart.dart';

/// This class should provide services that Firebase depends on and are platform
/// specific.
class PlatformDependencies with LocalStoreMixin implements LocalStorage {
  /// A storage box that can save key/value pair that persists restarts.
  ///
  /// It is recommended that you use an encrypted box.
  @override
  Box<String> get box => null;

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

  /// Used by Firebase services when a network call is made and the user is
  /// allowed to add their own headers
  HeaderBuilder get headersBuilder => null;

  /// Used by Firebase services to persist various data (eg. user session)
  LocalStorage get storage => this;

  /// Firebase services will use this to generate authorization headers
  ///
  /// If you are planing to also use FirebaseAuth you don't need to worry about
  /// this field. Firebase Auth SDK automatically registers as
  /// [InternalTokenProvider] if null is set.
  InternalTokenProvider get authProvider => null;
}

// todo(long1eu): implement a version of this that supports `userAccessGroup` on iOS
/// Local persistence interface to store key/value pairs
abstract class LocalStorage {
  const LocalStorage();

  Future<LocalStorage> getStore(String key);

  /// Returns all the keys saved by this store
  Set<String> get keys;

  /// Gets the values at [key], or null if none found.
  dynamic get(String key);

  /// Saves the value at [key].
  ///
  /// When a null value is provided the implementation should remove the value if one exists.
  Future<void> set(String key, dynamic value);
}

/// Signature used to retrieved platform specific headers for every request made
/// by Firebase services.
typedef HeaderBuilder = Future<Map<String, String>> Function();

mixin LocalStoreMixin implements LocalStorage {
  Box<String> get box;

  LocalStorage _store;

  LocalStorage get store {
    if (_store != null) {
      return _store;
    }
    if (box != null) {
      _store = _HiveLocalStorage(box);
    } else {
      _store = _MemoryLocalStorage();
    }
    return _store;
  }

  @override
  Future<LocalStorage> getStore(String key) => store.getStore(key);

  @override
  Set<String> get keys => store.keys;

  @override
  String get(String key) => store.get(key);

  @override
  Future<void> set(String key, dynamic value) => store.set(key, value);
}

class _MemoryLocalStorage implements LocalStorage {
  _MemoryLocalStorage([Map<String, dynamic> map]) : _map = map ?? <String, dynamic>{};

  final Map<String, dynamic> _map;

  @override
  Future<LocalStorage> getStore(String key) {
    return Future<LocalStorage>.value(_MemoryLocalStorage());
  }

  @override
  Set<String> get keys {
    return _map.keys.toSet();
  }

  @override
  dynamic get(String key) {
    return _map[key];
  }

  @override
  Future<void> set(String key, dynamic value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }
}

class _HiveLocalStorage implements LocalStorage {
  _HiveLocalStorage(Box<dynamic> box) : _box = box ?? <String, dynamic>{};

  final Box<dynamic> _box;

  @override
  Future<LocalStorage> getStore(String key) async {
    final String name = basenameWithoutExtension(_box.path);
    final Box<dynamic> box = await Hive.openBox<dynamic>('$name-$key');
    return _HiveLocalStorage(box);
  }

  @override
  Set<String> get keys => _box.keys.toSet();

  @override
  dynamic get(String key) => _box.get(key);

  @override
  Future<void> set(String key, dynamic value) async {
    if (value == null) {
      await _box.delete(key);
    } else {
      await _box.put(key, value);
    }
  }
}
