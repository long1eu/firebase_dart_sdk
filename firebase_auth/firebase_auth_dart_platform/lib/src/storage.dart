import 'dart:async';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show Persistence;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show
        AuthStorage,
        BestWebAuthStorage,
        FileAuthStorage,
        InMemoryAuthStorage,
        ObservableAuthStorage,
        WebAuthStorage;
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
/// the platform ([secureDefaultStorage]), except on the web, where it is the
/// best storage of the browser ([BestWebAuthStorage]: IndexedDB, else
/// `localStorage`, else memory).
///
/// One object for the whole program, shared by the instances of every app: it
/// holds one session per app, and one object writes them one at a time, so
/// that two apps do not overwrite each other's session.
AuthStorage defaultStorage() =>
    _defaultStorage ??= defaultStorageFor(web: kIsWeb);

/// What [defaultStorage] creates: [webStorage] (by default a
/// [BestWebAuthStorage]) when [web] is true, else [secureDefaultStorage] in
/// the default session file. Nothing is read or written here.
@visibleForTesting
AuthStorage defaultStorageFor({
  required bool web,
  AuthStorage Function() webStorage = BestWebAuthStorage.new,
}) => web ? webStorage() : secureDefaultStorage(path.defaultSessionFile());

/// The storage `setPersistence(persistence)` moves the session to.
///
/// * [Persistence.NONE]: [memory].
/// * [Persistence.LOCAL] and [Persistence.INDEXED_DB]: [persistent], the
///   storage of the app (`storageFor` of `FirebaseAuthDart.use`, else
///   [defaultStorage]; on the web by default IndexedDB, else `localStorage`,
///   else memory).
/// * [Persistence.SESSION]: [session], the `sessionStorage` of the tab (see
///   [sessionStorageFor]), or [memory] when there is none: outside a browser,
///   the nearest thing, and on the web with `storageFor`, so that an app that
///   chose its own storage never gets the session written elsewhere.
AuthStorage storageForPersistence(
  Persistence persistence, {
  required AuthStorage persistent,
  required AuthStorage memory,
  required AuthStorage? session,
}) => switch (persistence) {
  Persistence.NONE => memory,
  Persistence.LOCAL || Persistence.INDEXED_DB => persistent,
  Persistence.SESSION => session ?? memory,
};

/// Where [Persistence.SESSION] keeps the session of an app: on the web ([web])
/// when the app passed no `storageFor` ([customStorage] false), the
/// `sessionStorage` of the tab ([sessionStorage], by default
/// `WebAuthStorage.session`) with memory behind it. Null otherwise, and
/// [sessionStorage] is not called.
FallbackStorage? sessionStorageFor({
  required bool web,
  required bool customStorage,
  AuthStorage Function() sessionStorage = WebAuthStorage.session,
}) => web && !customStorage ? FallbackStorage(sessionStorage()) : null;

/// The storage the client of an app starts on, and restores from: [session]
/// when it holds a session under [key] (the app set [Persistence.SESSION]
/// before the tab was reloaded), else [persistent].
///
/// [session] is read synchronously, before the client exists; a read that is
/// asynchronous or throws (a browser that refuses `sessionStorage`) counts as
/// nothing stored there. A later `setPersistence(SESSION)` then finds the
/// client on [session] already and moves nothing, so the copy survives.
AuthStorage initialStorage({
  required AuthStorage persistent,
  required AuthStorage? session,
  required String key,
}) {
  if (session == null) {
    return persistent;
  }
  final FutureOr<String?> stored;
  try {
    stored = session.read(key);
  } on Object {
    // sessionStorage refused: there is nothing to restore from it.
    return persistent;
  }
  if (stored is Future<String?>) {
    stored.ignore();
    return persistent;
  }
  return stored == null ? persistent : session;
}

/// A [SecureDefaultStorage]: a [SecureAuthStorage] that moves the sessions
/// found in [sessionFile] (see `defaultSessionFile`) into the secure store,
/// with that file (or memory when [sessionFile] is null) as the fallback for
/// a run where the secure store is unavailable, and the marker of the secure
/// store at `<sessionFile>.secure`. A second `SecureAuthStorage` in the same
/// namespace, without `migrateFrom`, serves the probe and the sessions the
/// marker places in the store, so that it never touches the file.
SecureDefaultStorage secureDefaultStorage(String? sessionFile) {
  if (sessionFile == null) {
    return SecureDefaultStorage(
      secure: SecureAuthStorage(),
      direct: SecureAuthStorage(),
      fallback: InMemoryAuthStorage(),
      fallbackFile: null,
    );
  }
  final FileAuthStorage file = FileAuthStorage(sessionFile);
  final SecureStoreMarker marker = SecureStoreMarker(
    FileAuthStorage('$sessionFile.secure'),
  );
  return SecureDefaultStorage(
    secure: SecureAuthStorage(migrateFrom: MarkingFileStorage(file, marker)),
    direct: SecureAuthStorage(),
    fallback: file,
    fallbackFile: sessionFile,
    marker: marker,
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
///
/// [changes] passes on the changes that other tabs make to the storage of
/// the app when it reports them (the web storages), so that the client
/// follows a sign-out or a sign-in made in another tab; once memory is in use
/// they are ignored.
class FallbackStorage implements ObservableAuthStorage {
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

  @override
  Stream<void> changes(String key) {
    final AuthStorage persistent = _persistent;
    if (persistent is! ObservableAuthStorage) {
      return const Stream<void>.empty();
    }
    return persistent.changes(key).where((_) => !_persistentFailed);
  }
}
