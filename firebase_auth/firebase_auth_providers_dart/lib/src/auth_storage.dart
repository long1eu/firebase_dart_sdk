import 'dart:async';

/// Where [FirebaseUserAuth] keeps the session of the signed-in user (its refresh token), so that the user is still
/// signed in after a restart.
///
/// The default, [InMemoryAuthStorage], forgets it when the process ends. An application that wants the session to
/// survive implements this on top of its own storage (a file, the keychain, `localStorage`, ...). The value is a
/// credential: store it accordingly.
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
