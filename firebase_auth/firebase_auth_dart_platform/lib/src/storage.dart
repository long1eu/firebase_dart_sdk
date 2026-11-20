import 'dart:async';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, InMemoryAuthStorage;

import 'storage_path_stub.dart'
    if (dart.library.io) 'storage_path_io.dart'
    as path;

export 'storage_path_stub.dart'
    if (dart.library.io) 'storage_path_io.dart'
    show defaultSessionFile;

/// The storage of the sessions when the app passes none: the file of
/// [path.defaultSessionFile], or memory where there is no file system.
AuthStorage defaultStorage() => path.defaultFileStorage();

/// The storage of one auth instance: the storage of the app, or memory after
/// `setPersistence(Persistence.NONE)`.
class SwitchableStorage implements AuthStorage {
  SwitchableStorage(this._persistent);

  final AuthStorage _persistent;
  final InMemoryAuthStorage _memory = InMemoryAuthStorage();
  bool _inMemory = false;

  AuthStorage get _current => _inMemory ? _memory : _persistent;

  @override
  FutureOr<String?> read(String key) => _current.read(key);

  @override
  FutureOr<void> write(String key, String? value) => _current.write(key, value);

  /// Moves the value of [key] to memory ([inMemory]) or back to the storage of
  /// the app, and removes it where it was, as the JS SDK does when the
  /// persistence changes.
  Future<void> setInMemory(bool inMemory, String key) async {
    if (inMemory == _inMemory) {
      return;
    }
    final AuthStorage from = _current;
    final AuthStorage to = inMemory ? _memory : _persistent;
    final String? value = await from.read(key);
    await to.write(key, value);
    _inMemory = inMemory;
    await from.write(key, null);
  }
}
