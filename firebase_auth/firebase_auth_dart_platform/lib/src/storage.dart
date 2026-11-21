import 'dart:async';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, FileAuthStorage, InMemoryAuthStorage;
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart'
    show SecureAuthStorage;
import 'package:flutter/foundation.dart';

import 'secure_default_storage.dart';
import 'storage_path_stub.dart'
    if (dart.library.io) 'storage_path_io.dart'
    as path;

export 'storage_path_stub.dart'
    if (dart.library.io) 'storage_path_io.dart'
    show defaultSessionFile, isFileSystemException, runningUnderFlutterTest;

AuthStorage? _defaultStorage;

/// The storage of the sessions when the app passes none: the secure store of
/// the platform ([secureDefaultStorage]), except on the web, where it is
/// memory.
///
/// One object for the whole program, shared by the instances of every app: it
/// holds one session per app, and one object writes them one at a time, so
/// that two apps do not overwrite each other's session.
AuthStorage defaultStorage() => _defaultStorage ??= kIsWeb
    ? path.defaultFileStorage()
    : secureDefaultStorage(path.defaultSessionFile());

/// A [SecureDefaultStorage]: a [SecureAuthStorage] that moves the sessions
/// found in [sessionFile] (see `defaultSessionFile`) into the secure store,
/// with that file (or memory when [sessionFile] is null) as the fallback for
/// a run where the secure store is unavailable. The probe uses a second
/// `SecureAuthStorage` in the same namespace, without `migrateFrom`, so that
/// deleting the probe entry never touches the file.
SecureDefaultStorage secureDefaultStorage(String? sessionFile) {
  final AuthStorage? file = sessionFile == null
      ? null
      : FileAuthStorage(sessionFile);
  return SecureDefaultStorage(
    secure: SecureAuthStorage(migrateFrom: file),
    probe: SecureAuthStorage(),
    fallback: file ?? InMemoryAuthStorage(),
    fallbackFile: sessionFile,
  );
}

/// The storage of the sessions of one auth instance: the storage of the app,
/// with memory behind it.
///
/// When a write to the storage of the app fails (the secure store refused it,
/// or the session file of the fallback cannot be written), the session is
/// kept in memory for the rest of the run, so that the sign-in still succeeds,
/// and the failure is printed once. A failed read is not caught: the restore
/// fails, the app starts signed out and the error reaches `authStateReady()`.
/// A secure store that is unavailable from the start never gets here: the
/// default storage ([SecureDefaultStorage]) moves to its fallback first.
///
/// The client itself rethrows a failed write (and stores the session again at
/// the next change); the official plugins never fail a sign-in because the
/// keychain or the preferences could not be written, so this package keeps
/// that behaviour here, in front of the client.
class FallbackStorage implements AuthStorage {
  FallbackStorage(this._persistent);

  final AuthStorage _persistent;
  final InMemoryAuthStorage _memory = InMemoryAuthStorage();

  /// Whether a write to [_persistent] failed: memory is used from then on.
  bool _persistentFailed = false;

  @override
  FutureOr<String?> read(String key) =>
      _persistentFailed ? _memory.read(key) : _persistent.read(key);

  @override
  FutureOr<void> write(String key, String? value) {
    if (_persistentFailed) {
      _memory.write(key, value);
      return null;
    }
    return _writePersistent(key, value);
  }

  Future<void> _writePersistent(String key, String? value) async {
    try {
      await _persistent.write(key, value);
    } on Exception catch (e) {
      _persistentFailed = true;
      _memory.write(key, value);
      debugPrint(
        'firebase_auth_dart_platform: the session could not be stored ($e); '
        'it is kept in memory until the program ends.',
      );
    }
  }
}
