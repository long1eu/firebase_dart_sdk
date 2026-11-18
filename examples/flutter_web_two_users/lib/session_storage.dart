import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:web/web.dart' as web;

/// Keeps the session of a FirebaseUserAuth (its refresh token) in the
/// sessionStorage of the tab: it survives a reload and is gone when the tab
/// is closed. Any script of the origin can read it; see the documentation of
/// [AuthStorage] before keeping a session in a browser.
class SessionAuthStorage implements AuthStorage {
  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      web.window.sessionStorage.removeItem(key);
    } else {
      web.window.sessionStorage.setItem(key, value);
    }
  }
}
