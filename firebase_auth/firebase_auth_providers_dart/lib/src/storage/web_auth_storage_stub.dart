import '../auth_storage.dart';

/// An [AuthStorage] in the browser's `sessionStorage` ([WebAuthStorage.session]) or `localStorage`
/// ([WebAuthStorage.local]), the JS SDK's `browserSessionPersistence` and `browserLocalPersistence`. It needs a
/// browser: on the Dart VM the constructors throw an [UnsupportedError]; use `FileAuthStorage` there.
///
/// Both storages are readable by every script of the origin: a cross-site scripting flaw gives the refresh token
/// (which does not expire) away. See the documentation of the web implementation.
class WebAuthStorage implements AuthStorage {
  /// The `sessionStorage` of the page: the session lasts as long as the tab. [prefix] goes before every key. Throws
  /// an [UnsupportedError] on this platform.
  WebAuthStorage.session({this.prefix = ''}) {
    throw UnsupportedError('WebAuthStorage needs a browser.');
  }

  /// The `localStorage` of the origin: the session survives closing the browser. [prefix] goes before every key.
  /// Throws an [UnsupportedError] on this platform.
  WebAuthStorage.local({this.prefix = ''}) {
    throw UnsupportedError('WebAuthStorage needs a browser.');
  }

  /// What goes before every key in the browser storage.
  final String prefix;

  @override
  String? read(String key) => throw UnsupportedError('No browser');

  @override
  void write(String key, String? value) => throw UnsupportedError('No browser');
}
