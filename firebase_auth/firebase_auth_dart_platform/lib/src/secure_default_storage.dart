import 'dart:async';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, InMemoryAuthStorage;
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart'
    show SecureAuthStorageException;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ServicesBinding;

/// Whether the line that says the sessions are kept in the fallback has been
/// printed in this process.
bool _fallbackAnnounced = false;

/// Whether the line that says the sessions are kept in memory, because the
/// marker places them in a secure store that cannot be used, has been printed
/// in this process.
bool _memoryAnnounced = false;

/// Lets the next fallback print its line again, for tests that check it.
@visibleForTesting
void resetFallbackAnnouncement() {
  _fallbackAnnounced = false;
  _memoryAnnounced = false;
}

/// Where the store stands for one [SecureDefaultStorage].
enum _Choice {
  /// The probe has not answered yet.
  undecided,

  /// The probe succeeded: every operation goes to the secure store.
  secure,

  /// The secure store is unavailable: the operations go to the fallback, or
  /// to memory for a session the marker places in the store.
  unavailable,
}

/// What the marker says about the session of one key.
enum SessionMark {
  /// The session lives in the secure store: it is never read from the session
  /// file again. Kept as `secure`.
  secure,

  /// A sign-out (or another write) did not reach the secure store: the next
  /// run that can open the store deletes the session there before anything
  /// reads it. Kept as `sign-out`.
  signOut,
}

/// The marker of the secure store: a small file next to the session file that
/// says, for each session key, whether its session lives in the secure store
/// ([SessionMark]). It never holds a secret.
///
/// The file is a JSON object from the session key (as `FirebaseUserAuth`
/// passes it) to `secure` or `sign-out`, kept by [file] (a `FileAuthStorage`
/// at `<session file>.secure`: written atomically and owner-only). A value
/// that is neither counts as `secure`. The marks of the keys already read are
/// cached for the life of the object.
class SecureStoreMarker {
  /// A marker kept in [file].
  SecureStoreMarker(this.file);

  /// The file of the marker.
  final AuthStorage file;

  final Map<String, SessionMark?> _marks = <String, SessionMark?>{};

  /// The mark of the session of [key]; null when it has none (the session, if
  /// any, is in the session file). A failed read of the file is thrown.
  Future<SessionMark?> markOf(String key) async {
    if (_marks.containsKey(key)) {
      return _marks[key];
    }
    final String? text = await file.read(key);
    final SessionMark? mark = switch (text) {
      null => null,
      'sign-out' => SessionMark.signOut,
      _ => SessionMark.secure,
    };
    return _marks[key] = mark;
  }

  /// Gives the session of [key] the mark [mark]. A failed write is thrown,
  /// and the mark is unchanged then.
  Future<void> mark(String key, SessionMark mark) async {
    if (_marks.containsKey(key) && _marks[key] == mark) {
      return;
    }
    await file.write(key, switch (mark) {
      SessionMark.secure => 'secure',
      SessionMark.signOut => 'sign-out',
    });
    _marks[key] = mark;
  }
}

/// The session file as the storage that `SecureAuthStorage` moves the
/// sessions from: deleting a session from it (after it moved, or after a
/// sign-out reached the store) marks it `secure` first, so that from then on
/// the file is never read for it, even when the store cannot be opened.
class MarkingFileStorage implements AuthStorage {
  /// The session file [file], marked in [marker].
  MarkingFileStorage(this.file, this.marker);

  /// The session file.
  final AuthStorage file;

  /// The marker of the secure store.
  final SecureStoreMarker marker;

  @override
  FutureOr<String?> read(String key) => file.read(key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await marker.mark(key, SessionMark.secure);
    }
    await file.write(key, value);
  }
}

/// The default storage of the sessions where the platform has a secure store:
/// the secure store, or [fallback] when that store is unavailable.
///
/// Before the first operation, a probe decides for the whole life of the
/// object (the default storage is one object per program): it writes a value
/// under [probeKey] in [direct], reads it back and deletes it. A read alone
/// cannot tell: a macOS build without the keychain entitlement reads a
/// missing key as null and fails only at the first write.
///
/// * The probe succeeds: every operation goes to the secure store from then
///   on, and its errors are thrown, so that a session that is stored but
///   cannot be read is never mistaken for no session. When the store becomes
///   unavailable later in the run, the error is thrown too: the shim's
///   `FallbackStorage` keeps a failed write in memory.
/// * A step of the probe fails with a [SecureAuthStorageException] whose
///   `isUnavailable` is true (no plugin, no Secret Service, a locked keyring,
///   a macOS build without the keychain entitlement, DPAPI refusing access on
///   Windows): the store is unavailable for the run, and nothing is written
///   to it. A session without a mark in [marker] goes to [fallback]; a
///   session with one is kept in memory (see below). One line per process
///   says each.
/// * Any other failure of the probe is thrown by the operation that waited
///   for it; the next operation probes again.
///
/// The [marker] (null where there is no session file) keeps, for each
/// session key, whether its session lives in the secure store:
///
/// * A session is marked `secure` before it is written to the store, and
///   before it is deleted from the session file after it moved (a crash
///   between the move and that delete leaves the mark, the store's copy and
///   the file's: the next read deletes the file's).
/// * A marked session is never read from or written to the session file. In
///   a run where the store cannot be used, it is kept in memory only, and a
///   write (a sign-out, or a sign-in to another account) marks it
///   `sign-out` and deletes it from the file.
/// * A write that fails in the store, or whose probe failed, marks a marked
///   session `sign-out` too (`FallbackStorage` then keeps it in memory).
/// * A session marked `sign-out` is deleted from the store, and from the
///   file, by the first read of the next run that can use the store, before
///   anything is read; it is then marked `secure`.
///
/// So the session the store holds never comes back after the user signed out
/// or signed in again in a run without it, and no refresh token of a session
/// that lives in the store is written to the file. A session without a mark
/// is moved from the file by [secure] as before.
///
/// The probe entry is deleted in every case where it may have been written.
/// Operations started while the probe runs wait for it. Without a services
/// binding (an app that uses Firebase before
/// `WidgetsFlutterBinding.ensureInitialized()`), no plugin can be called, so
/// the store counts as unavailable, without a probe.
class SecureDefaultStorage implements AuthStorage {
  /// A storage in [secure], or in [fallback] when [secure] is unavailable.
  ///
  /// [direct] is a storage in the same secure store and namespace as [secure]
  /// that touches nothing else (no `migrateFrom`). [fallbackFile] is the path
  /// of the file of [fallback] for the printed line; null when [fallback]
  /// keeps the sessions in memory. [marker] is the marker of the secure store
  /// next to that file, and then [secure] moves the sessions from a
  /// [MarkingFileStorage] of [fallback]; null when there is no file.
  SecureDefaultStorage({
    required this.secure,
    required this.direct,
    required this.fallback,
    required this.fallbackFile,
    this.marker,
  });

  /// The key of the probe entry in [direct].
  static const String probeKey = '.probe';

  /// The secure store, a `SecureAuthStorage` that moves the sessions from the
  /// session file.
  final AuthStorage secure;

  /// The secure store without the move: the probe writes, reads and deletes
  /// [probeKey] in it, and the sessions the marker places in the store are
  /// read and written in it.
  final AuthStorage direct;

  /// Where the sessions without a mark are kept when [secure] is unavailable.
  final AuthStorage fallback;

  /// The file of [fallback]; null when it is memory.
  final String? fallbackFile;

  /// The marker of the secure store; null when there is no session file.
  final SecureStoreMarker? marker;

  /// The marked sessions of a run where the store cannot be used.
  final InMemoryAuthStorage _memory = InMemoryAuthStorage();

  _Choice _choice = _Choice.undecided;
  Future<bool>? _deciding;
  String _reason = '';

  /// Whether the secure store was unavailable at the probe: the sessions go
  /// to [fallback], or to memory when they are marked.
  bool get usesFallback => _choice == _Choice.unavailable;

  @override
  Future<String?> read(String key) async {
    final bool usable = await _decide();
    final SessionMark? mark = await marker?.markOf(key);
    if (!usable) {
      if (mark == null) {
        _announceFallback();
        return fallback.read(key);
      }
      _announceMemory();
      return _memory.read(key);
    }
    switch (mark) {
      case null:
        return secure.read(key);
      case SessionMark.signOut:
        await direct.write(key, null);
        await _deleteFromFile(key);
        await marker!.mark(key, SessionMark.secure);
        return null;
      case SessionMark.secure:
        final String? value = await direct.read(key);
        await _deleteFromFile(key);
        return value;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    final bool usable;
    try {
      usable = await _decide();
    } on Exception {
      await _signOutLaterIfMarked(key);
      rethrow;
    }
    final SecureStoreMarker? marker = this.marker;
    final SessionMark? mark = await marker?.markOf(key);
    if (!usable) {
      if (marker == null || mark == null) {
        _announceFallback();
        return fallback.write(key, value);
      }
      _announceMemory();
      _memory.write(key, value);
      await _signOutLater(marker, key);
      return;
    }
    try {
      await _writeSecure(key, value, mark);
    } on Exception {
      await _signOutLaterIfMarked(key);
      rethrow;
    }
  }

  Future<void> _writeSecure(
    String key,
    String? value,
    SessionMark? mark,
  ) async {
    final SecureStoreMarker? marker = this.marker;
    if (marker == null || value == null) {
      // A sign-out through [secure] deletes the session from the file too,
      // marking it first (MarkingFileStorage).
      return secure.write(key, value);
    }
    await marker.mark(key, SessionMark.secure);
    await direct.write(key, value);
    if (mark != SessionMark.secure) {
      await _deleteFromFile(key);
    }
  }

  /// Marks the session of [key] `sign-out` when it has a mark; a failure is
  /// printed, because the caller rethrows the error that brought it here.
  Future<void> _signOutLaterIfMarked(String key) async {
    final SecureStoreMarker? marker = this.marker;
    if (marker == null) {
      return;
    }
    try {
      if (await marker.markOf(key) != null) {
        await _signOutLater(marker, key);
      }
    } on Exception catch (e) {
      debugPrint(
        'firebase_auth_dart_platform: the sign-out of "$key" could not be '
        'recorded in the marker of the secure store ($e); the session the '
        'store holds may come back at the next start.',
      );
    }
  }

  Future<void> _signOutLater(SecureStoreMarker marker, String key) async {
    await marker.mark(key, SessionMark.signOut);
    await _deleteFromFile(key);
  }

  /// Deletes the session of [key] from the session file, where a marked
  /// session must not be. A failure is printed: the file is never read for a
  /// marked session, so nothing is restored from it.
  Future<void> _deleteFromFile(String key) async {
    if (marker == null) {
      return;
    }
    try {
      if (await fallback.read(key) != null) {
        await fallback.write(key, null);
      }
    } on Exception catch (e) {
      debugPrint(
        'firebase_auth_dart_platform: the session "$key" could not be '
        'deleted from $fallbackFile ($e); it is no longer read from there.',
      );
    }
  }

  /// Whether the secure store can be used in this run; probes it first.
  Future<bool> _decide() async {
    switch (_choice) {
      case _Choice.secure:
        return true;
      case _Choice.unavailable:
        return false;
      case _Choice.undecided:
        return _deciding ??= _probeOnce().whenComplete(() => _deciding = null);
    }
  }

  Future<bool> _probeOnce() async {
    if (!_hasServicesBinding()) {
      _unavailable(
        'no services binding: call WidgetsFlutterBinding.ensureInitialized() '
        'before the first use of Firebase',
      );
      return false;
    }
    try {
      await _probe();
    } on SecureAuthStorageException catch (e) {
      if (!e.isUnavailable) {
        rethrow;
      }
      _unavailable('$e');
      return false;
    }
    _choice = _Choice.secure;
    return true;
  }

  Future<void> _probe() async {
    final String value = 'probe ${DateTime.now().microsecondsSinceEpoch}';
    // A failed write stores nothing: there is nothing to delete then.
    await direct.write(probeKey, value);
    try {
      final String? back = await direct.read(probeKey);
      if (back != value) {
        throw SecureAuthStorageException(
          platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
          operation: 'read',
          cause: Exception(
            'the probe value read back from the secure store differs from '
            'the one written',
          ),
        );
      }
    } on Exception {
      await _deleteProbeAfterFailure();
      rethrow;
    }
    await direct.write(probeKey, null);
  }

  /// Deletes the probe entry after its read failed. That failure is what the
  /// probe reports, so a failure here is printed, not thrown over it, unless
  /// it only repeats that the store is unavailable (the fallback line says
  /// so already).
  Future<void> _deleteProbeAfterFailure() async {
    try {
      await direct.write(probeKey, null);
    } on SecureAuthStorageException catch (e) {
      if (!e.isUnavailable) {
        debugPrint(
          'firebase_auth_dart_platform: the probe entry of the secure store '
          'could not be deleted ($e).',
        );
      }
    }
  }

  void _unavailable(String reason) {
    _choice = _Choice.unavailable;
    _reason = reason.replaceAll('\n', ' ');
  }

  void _announceFallback() {
    if (_fallbackAnnounced) {
      return;
    }
    _fallbackAnnounced = true;
    final String? file = fallbackFile;
    final String where = file == null
        ? 'in memory until the program ends'
        : 'in $file';
    debugPrint(
      'firebase_auth_dart_platform: the secure store is unavailable '
      '($_reason); the sessions are kept $where instead.',
    );
  }

  void _announceMemory() {
    if (_memoryAnnounced) {
      return;
    }
    _memoryAnnounced = true;
    debugPrint(
      'firebase_auth_dart_platform: the secure store is unavailable '
      '($_reason); the sessions it holds are not used in this run: they are '
      'kept in memory until the program ends, and a sign-out is completed in '
      'the store at the next start that can open it.',
    );
  }

  /// Whether a services binding exists, through which the plugin is called.
  ///
  /// `ServicesBinding.instance` has no nullable form: without a binding it
  /// throws a `FlutterError` in debug builds and a `TypeError` (a null check)
  /// in release builds, both `Error`s.
  static bool _hasServicesBinding() {
    try {
      return identical(ServicesBinding.instance, ServicesBinding.instance);
    } on Error {
      return false;
    }
  }
}
