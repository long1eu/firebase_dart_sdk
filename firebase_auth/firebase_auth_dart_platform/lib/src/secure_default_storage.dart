import 'dart:async';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage;
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart'
    show SecureAuthStorageException;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ServicesBinding;

/// Whether the line that says where the sessions are kept instead has been
/// printed in this process.
bool _fallbackAnnounced = false;

/// Lets the next fallback print its line again, for tests that check it.
@visibleForTesting
void resetFallbackAnnouncement() => _fallbackAnnounced = false;

/// Where the store stands for one [SecureDefaultStorage].
enum _Choice {
  /// The probe has not answered yet.
  undecided,

  /// The probe succeeded: every operation goes to the secure store.
  secure,

  /// The secure store is unavailable: every operation goes to the fallback.
  fallback,
}

/// The default storage of the sessions where the platform has a secure store:
/// the secure store, or [fallback] when that store is unavailable.
///
/// Before the first operation, a probe decides for the whole life of the
/// object (the default storage is one object per program): it writes a value
/// under [probeKey] in [probe], reads it back and deletes it. A read alone
/// cannot tell: a macOS build without the keychain entitlement reads a
/// missing key as null and fails only at the first write.
///
/// * The probe succeeds: every operation goes to [secure] from then on, and
///   its errors are thrown, so that a session that is stored but cannot be
///   read is never mistaken for no session. When the store becomes
///   unavailable later in the run, the error is thrown too: the shim's
///   `FallbackStorage` keeps a failed write in memory.
/// * A step of the probe fails with a [SecureAuthStorageException] whose
///   `isUnavailable` is true (no plugin, no Secret Service, a locked keyring,
///   a macOS build without the keychain entitlement): every operation goes to
///   [fallback], and one line per process says so. Nothing is written to the
///   secure store afterwards.
/// * Any other failure of the probe is thrown by the operation that waited
///   for it; the next operation probes again.
///
/// The probe entry is deleted in every case where it may have been written.
/// Operations started while the probe runs wait for it. Without a services
/// binding (an app that uses Firebase before
/// `WidgetsFlutterBinding.ensureInitialized()`), no plugin can be called, so
/// the store counts as unavailable, without a probe.
class SecureDefaultStorage implements AuthStorage {
  /// A storage in [secure], or in [fallback] when [secure] is unavailable.
  ///
  /// [probe] is a storage in the same secure store and namespace as [secure]
  /// that touches nothing else (no `migrateFrom`). [fallbackFile] is the path
  /// of the file of [fallback] for the printed line; null when [fallback]
  /// keeps the sessions in memory.
  SecureDefaultStorage({
    required this.secure,
    required this.probe,
    required this.fallback,
    required this.fallbackFile,
  });

  /// The key of the probe entry in [probe].
  static const String probeKey = '.probe';

  /// The secure store, a `SecureAuthStorage`.
  final AuthStorage secure;

  /// The storage the probe writes, reads and deletes [probeKey] in.
  final AuthStorage probe;

  /// Where the sessions are kept when [secure] is unavailable.
  final AuthStorage fallback;

  /// The file of [fallback]; null when it is memory.
  final String? fallbackFile;

  _Choice _choice = _Choice.undecided;
  Future<AuthStorage>? _deciding;

  /// Whether the operations go to [fallback]: the secure store was
  /// unavailable at the probe.
  bool get usesFallback => _choice == _Choice.fallback;

  @override
  Future<String?> read(String key) async => (await _chosen()).read(key);

  @override
  Future<void> write(String key, String? value) async =>
      (await _chosen()).write(key, value);

  Future<AuthStorage> _chosen() async {
    switch (_choice) {
      case _Choice.secure:
        return secure;
      case _Choice.fallback:
        return fallback;
      case _Choice.undecided:
        return _deciding ??= _decide().whenComplete(() => _deciding = null);
    }
  }

  Future<AuthStorage> _decide() async {
    if (!_hasServicesBinding()) {
      _useFallback(
        'no services binding: call WidgetsFlutterBinding.ensureInitialized() '
        'before the first use of Firebase',
      );
      return fallback;
    }
    try {
      await _probe();
    } on SecureAuthStorageException catch (e) {
      if (!e.isUnavailable) {
        rethrow;
      }
      _useFallback('$e');
      return fallback;
    }
    _choice = _Choice.secure;
    return secure;
  }

  Future<void> _probe() async {
    final String value = 'probe ${DateTime.now().microsecondsSinceEpoch}';
    // A failed write stores nothing: there is nothing to delete then.
    await probe.write(probeKey, value);
    try {
      final String? back = await probe.read(probeKey);
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
    await probe.write(probeKey, null);
  }

  /// Deletes the probe entry after its read failed. That failure is what the
  /// probe reports, so a failure here is printed, not thrown over it, unless
  /// it only repeats that the store is unavailable (the fallback line says
  /// so already).
  Future<void> _deleteProbeAfterFailure() async {
    try {
      await probe.write(probeKey, null);
    } on SecureAuthStorageException catch (e) {
      if (!e.isUnavailable) {
        debugPrint(
          'firebase_auth_dart_platform: the probe entry of the secure store '
          'could not be deleted ($e).',
        );
      }
    }
  }

  void _useFallback(String reason) {
    _choice = _Choice.fallback;
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
      '(${reason.replaceAll('\n', ' ')}); the sessions are kept $where '
      'instead.',
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
