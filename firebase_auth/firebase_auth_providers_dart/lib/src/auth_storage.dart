import 'dart:async';

import 'firebase_user_auth.dart';

/// Where [FirebaseUserAuth] keeps the session of the signed-in user (its refresh token and the user record), so
/// that the user is still signed in after a restart.
///
/// The package has [InMemoryAuthStorage] (the default; forgets the session when the process ends),
/// `FileAuthStorage` (an owner-only file on the Dart VM), `WebAuthStorage` (`sessionStorage` or `localStorage`
/// in a browser), `IndexedDbAuthStorage` (IndexedDB in a browser) and `BestWebAuthStorage` (IndexedDB, else
/// `localStorage`, else memory, chosen once). An application that keeps secrets elsewhere implements this on top of
/// its own storage.
///
/// **The stored value is a credential.** It holds the refresh token of the user, which does not expire: whoever
/// reads it can get ID tokens and act as that user (read and write what the security rules allow the user) until
/// the user signs out, the account is disabled or the token is revoked. An implementation must keep it where the
/// platform keeps secrets, not in plain preferences or a world-readable file:
///
/// * Flutter on iOS, Android, macOS, Windows and Linux: a secure storage plugin such as `flutter_secure_storage`
///   (Keychain, Android Keystore, Windows Credential Manager, libsecret).
/// * A command line tool or a server: the system keychain or secret service, or a file readable only by its owner
///   (`FileAuthStorage`: mode 0600, in a directory of the user that others cannot write to).
/// * The web: `localStorage` and IndexedDB are readable by every script of the origin, so a cross-site scripting
///   flaw gives the session away; prefer [InMemoryAuthStorage] (sign in again on every visit) or
///   `WebAuthStorage.session`, and keep a strict Content Security Policy.
///
/// Delete the value ([write] with null) when the user signs out; [FirebaseUserAuth] does that itself.
///
/// [FirebaseUserAuth] calls [read] in [FirebaseUserAuth.restore] (and, for an
/// [ObservableAuthStorage], after a change made elsewhere and before it stores an update of the
/// signed-in user's session), and [write] after every sign-in, sign-out and change of the user or
/// of the refresh token, and waits for both. An exception they throw reaches the caller of the
/// operation. The value is a JSON object with a `version` (2 since 0.3; 0.2 wrote no version);
/// treat it as opaque.
///
/// ```dart
/// // Dart VM: a command line tool keeps its session in the user's configuration directory.
/// final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
///   app,
///   storage: FileAuthStorage('${Platform.environment['HOME']}/.config/my_tool/session.json'),
/// );
/// ```
abstract class AuthStorage {
  /// Constructor for subclasses.
  AuthStorage();

  /// Returns the value stored under [key], or null when there is none.
  FutureOr<String?> read(String key);

  /// Stores [value] under [key]; null removes it. The value is a credential (see [AuthStorage]).
  FutureOr<void> write(String key, String? value);
}

/// An [AuthStorage] that tells when a stored value was changed by someone else: another tab or
/// window of the browser (the JS SDK's `_addListener` and `_removeListener` of a persistence).
///
/// `WebAuthStorage`, `IndexedDbAuthStorage` and `BestWebAuthStorage` implement it.
/// [FirebaseUserAuth] listens to [changes] of its key while it uses the storage: when another tab
/// signs out, signs in another user or stores new tokens, it reads the stored session and takes it
/// over without writing it back, so that a sign-out in one tab is not undone by the next write of
/// another.
///
/// An implementation keeps the writes made through the object itself out of [changes], and reports
/// the changes of other tabs; whether it also reports those of another object in the same page
/// depends on the storage (see its documentation).
abstract interface class ObservableAuthStorage implements AuthStorage {
  /// Emits after the value under [key] was changed by someone else; the event carries no value:
  /// read it. It may also emit when the value was written again unchanged. The storage watches
  /// [key] only while the stream is listened to, and may end the stream when it is closed.
  Stream<void> changes(String key);
}

/// An [AuthStorage] that lives as long as the object: the default of [FirebaseUserAuth]. The user has to sign in
/// again after a restart.
///
/// One instance can be shared by several [FirebaseUserAuth]s in a process, so that a new instance restores the
/// session of an earlier one:
///
/// ```dart
/// final InMemoryAuthStorage storage = InMemoryAuthStorage();
/// final FirebaseUserAuth first = FirebaseUserAuth(apiKey: apiKey, storage: storage);
/// await first.signInAnonymously();
/// await first.dispose();
///
/// final FirebaseUserAuth second = FirebaseUserAuth(apiKey: apiKey, storage: storage);
/// await second.restore();
/// print(second.uid == first.uid); // true
/// ```
class InMemoryAuthStorage implements AuthStorage {
  /// Creates an empty storage.
  InMemoryAuthStorage();

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
