import 'dart:async';

/// Where [FirebaseUserAuth] keeps the session of the signed-in user (its refresh token), so that the user is still
/// signed in after a restart.
///
/// The default, [InMemoryAuthStorage], forgets it when the process ends. An application that wants the session to
/// survive implements this on top of its own storage.
///
/// **The stored value is a credential.** It holds the refresh token of the user, which does not expire: whoever
/// reads it can get ID tokens and act as that user (read and write what the security rules allow the user) until
/// the user signs out, the account is disabled or the token is revoked. An implementation must keep it where the
/// platform keeps secrets, not in plain preferences or a world-readable file:
///
/// * Flutter on iOS, Android, macOS, Windows and Linux: a secure storage plugin such as `flutter_secure_storage`
///   (Keychain, Android Keystore, Windows Credential Manager, libsecret).
/// * A command line tool or a server: the system keychain or secret service, or a file readable only by its owner
///   (mode 0600 in a directory with mode 0700).
/// * The web: `localStorage` and IndexedDB are readable by every script of the origin, so a cross-site scripting
///   flaw gives the session away; prefer [InMemoryAuthStorage] (sign in again on every visit) or
///   `sessionStorage`, and keep a strict Content Security Policy.
///
/// Delete the value ([write] with null) when the user signs out; [FirebaseUserAuth] does that itself.
abstract class AuthStorage {
  /// Returns the value stored under [key], or null.
  FutureOr<String?> read(String key);

  /// Stores [value] under [key]; null removes it.
  FutureOr<void> write(String key, String? value);
}

/// An [AuthStorage] that lives as long as the object.
class InMemoryAuthStorage implements AuthStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
