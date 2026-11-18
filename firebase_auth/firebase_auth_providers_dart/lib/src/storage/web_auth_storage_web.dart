import 'package:web/web.dart' as web;

import '../auth_storage.dart';

/// An [AuthStorage] in the browser's `sessionStorage` or `localStorage` (the JS SDK's `browserSessionPersistence`
/// and `browserLocalPersistence`).
///
/// * [WebAuthStorage.session]: the session lasts as long as the tab (it survives reloads, not closing the tab);
///   other tabs do not share it.
/// * [WebAuthStorage.local]: the session survives closing the browser and is shared by the tabs of the origin.
///
/// **What the storage exposes.** It holds the refresh token of the signed-in user, which does not expire. Every
/// script that runs on the origin can read both storages: a cross-site scripting flaw, or a compromised
/// third-party script, gives the session away, and with `localStorage` the token stays on the device until the user
/// signs out. Use a strict Content Security Policy, load no script you do not trust, and prefer
/// [WebAuthStorage.session] (or `InMemoryAuthStorage`, signing in again on every visit) unless users expect to stay
/// signed in.
///
/// A storage that the browser refuses (for example with cookies blocked) throws from [read] and [write], so
/// `FirebaseUserAuth.forApp` fails: catch that and fall back to `InMemoryAuthStorage` if you want.
///
/// On the Dart VM the constructors throw an [UnsupportedError]: use `FileAuthStorage` there.
///
/// ```dart
/// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
///   app,
///   storage: WebAuthStorage.session(),
/// );
/// ```
class WebAuthStorage implements AuthStorage {
  /// The `sessionStorage` of the page. [prefix] goes before every key.
  WebAuthStorage.session({this.prefix = ''}) : _local = false;

  /// The `localStorage` of the origin. [prefix] goes before every key.
  WebAuthStorage.local({this.prefix = ''}) : _local = true;

  /// What goes before every key in the browser storage.
  final String prefix;

  final bool _local;

  web.Storage get _storage =>
      _local ? web.window.localStorage : web.window.sessionStorage;

  @override
  String? read(String key) => _storage.getItem('$prefix$key');

  @override
  void write(String key, String? value) {
    if (value == null) {
      _storage.removeItem('$prefix$key');
    } else {
      _storage.setItem('$prefix$key', value);
    }
  }
}
