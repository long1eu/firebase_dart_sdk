import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../auth_storage.dart';

/// An [AuthStorage] in a file that only its owner can read (Dart VM: command line tools, servers, Flutter desktop).
///
/// The file holds a JSON object of the stored values, one per key, so several `FirebaseUserAuth` instances (apps,
/// projects) can share it. It is written atomically: a new file is created next to it, made readable and writable
/// by its owner only, checked, filled, and renamed over the old one. A secret never sits in a file other users can
/// read, not even for a moment.
///
/// * Linux and macOS: the file gets mode 0600 (`chmod`, run as a process, because `dart:io` cannot set
///   permissions), and a directory this class creates gets 0700. The mode is checked before anything is written:
///   when it is not owner-only (for example `chmod` is missing), [write] throws a [FileSystemException] and stores
///   nothing. Put the file in a directory of the user (for example `~/.config/<app>/`).
/// * Windows: files have no POSIX mode; a new file inherits the access control list of its directory. A directory
///   in the user's profile (`%APPDATA%\<app>` or `%LOCALAPPDATA%\<app>`) is readable by the user, administrators
///   and SYSTEM only, which is what this class relies on: it does not change ACLs. Do not use a shared directory
///   such as `C:\ProgramData` or a temporary directory.
/// * Android and iOS: the app's private directory (from `path_provider`'s `getApplicationSupportDirectory`) is
///   protected by the platform sandbox; no `chmod` runs there. Prefer the platform keystore through a secure storage
///   plugin when the device may be shared or backed up.
///
/// **What the file exposes.** It holds the refresh token of the signed-in user, which does not expire: anyone who
/// can read the file can act as that user (whatever the security rules allow the user) until the user signs out,
/// the account is disabled or its tokens are revoked. Owner-only permissions protect it from other users of the
/// machine, not from other programs of the same user, from backups, or from root. Keep it out of version control
/// and out of container images; on a shared or untrusted machine prefer the system keychain.
///
/// ```dart
/// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
///   app,
///   storage: FileAuthStorage('${Platform.environment['HOME']}/.config/my_tool/session.json'),
/// );
/// ```
class FileAuthStorage implements AuthStorage {
  /// A storage in the file at [path]. Nothing is read or created until it is used.
  FileAuthStorage(this.path);

  /// The path of the file.
  final String path;

  Future<void> _last = Future<void>.value();

  static final Random _random = Random.secure();

  @override
  Future<String?> read(String key) async {
    await _last;
    return (await _readAll())[key];
  }

  @override
  Future<void> write(String key, String? value) {
    // One write at a time, in order: each one reads what the previous one wrote.
    final Future<void> next = _last
        .catchError((Object _) {})
        .then((_) => _write(key, value));
    _last = next.catchError((Object _) {});
    return next;
  }

  Future<Map<String, String>> _readAll() async {
    final File file = File(path);
    if (!file.existsSync()) {
      return <String, String>{};
    }
    final String text = await file.readAsString();
    if (text.trim().isEmpty) {
      return <String, String>{};
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      // Not a file of this class: treated as empty, and replaced at the next write.
      return <String, String>{};
    }
    return <String, String>{
      if (json is Map)
        for (final MapEntry<Object?, Object?> e in json.entries)
          if (e.key is String && e.value is String)
            e.key! as String: e.value! as String,
    };
  }

  Future<void> _write(String key, String? value) async {
    final Map<String, String> all = await _readAll();
    if (value == null) {
      all.remove(key);
    } else {
      all[key] = value;
    }
    final File file = File(path);
    if (all.isEmpty) {
      if (file.existsSync()) {
        await file.delete();
      }
      return;
    }
    final Directory directory = file.parent;
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      await _restrict(directory.path, '700');
    }
    final File temporary = File(
      '$path.${pid}_${_random.nextInt(1 << 32).toRadixString(16)}.tmp',
    );
    await temporary.create(exclusive: true);
    try {
      await _restrict(temporary.path, '600');
      _checkOwnerOnly(temporary);
      await temporary.writeAsString(jsonEncode(all), flush: true);
      await temporary.rename(path);
    } on Object {
      if (temporary.existsSync()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  static bool get _posix => Platform.isLinux || Platform.isMacOS;

  /// `chmod <mode> <path>` on Linux and macOS.
  static Future<void> _restrict(String path, String mode) async {
    if (!_posix) {
      return;
    }
    final ProcessResult result;
    try {
      result = await Process.run('chmod', <String>[mode, path]);
    } on ProcessException catch (e) {
      throw FileSystemException(
        'Could not run chmod to make the file readable by its owner only: ${e.message}',
        path,
      );
    }
    if (result.exitCode != 0) {
      throw FileSystemException(
        'chmod $mode failed: ${result.stderr}'.trim(),
        path,
      );
    }
  }

  /// Throws when [file] can be read or written by others than its owner (Linux and macOS).
  static void _checkOwnerOnly(File file) {
    if (!_posix) {
      return;
    }
    final int mode = file.statSync().mode;
    if (mode & 0x3f != 0) {
      throw FileSystemException(
        'The file is accessible to other users (mode ${(mode & 0x1ff).toRadixString(8)}); nothing was written',
        file.path,
      );
    }
  }
}
