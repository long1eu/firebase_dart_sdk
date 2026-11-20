import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, FileAuthStorage, InMemoryAuthStorage;

/// The file that keeps the sessions when the app passes no storage, or null
/// where there is no sensible default (Android, iOS: pass `storageFor` to
/// `FirebaseAuthDart.use`).
///
/// * Linux and other Unix systems: `$XDG_DATA_HOME` (or `~/.local/share`)
///   `/<executable>/firebase_auth_dart_platform/sessions.json`.
/// * macOS: `~/Library/Application Support/<executable>/...`.
/// * Windows: `%APPDATA%\<executable>\...`.
///
/// `<executable>` is the file name of the running program (without `.exe`): a
/// Flutter desktop app is built under the name of its project, so each app has
/// its own file. The file holds one session per Firebase app (keyed by API key
/// and app name) and is written owner-only by `FileAuthStorage`.
String? defaultSessionFile() {
  final Map<String, String> env = Platform.environment;
  String? base;
  if (Platform.isWindows) {
    base = env['APPDATA'];
  } else if (Platform.isAndroid || Platform.isIOS) {
    return null;
  } else {
    final String? home = env['HOME'];
    final String? xdg = env['XDG_DATA_HOME'];
    if (Platform.isMacOS) {
      base = home == null || home.isEmpty
          ? null
          : '$home/Library/Application Support';
    } else if (xdg != null && xdg.startsWith('/')) {
      // The XDG specification ignores a relative value.
      base = xdg;
    } else if (home != null && home.isNotEmpty) {
      base = '$home/.local/share';
    }
  }
  if (base == null || base.isEmpty) {
    return null;
  }
  return <String>[
    base,
    _executableName(),
    'firebase_auth_dart_platform',
    'sessions.json',
  ].join(Platform.pathSeparator);
}

/// A [FileAuthStorage] in [defaultSessionFile], or memory when there is none.
AuthStorage defaultFileStorage() {
  final String? file = defaultSessionFile();
  return file == null ? InMemoryAuthStorage() : FileAuthStorage(file);
}

String _executableName() {
  String name = Platform.resolvedExecutable.split(RegExp(r'[/\\]')).last;
  if (name.toLowerCase().endsWith('.exe')) {
    name = name.substring(0, name.length - 4);
  }
  return name.isEmpty ? 'flutter_app' : name;
}
