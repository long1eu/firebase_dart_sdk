import 'firebase_user_auth.dart';

/// The signed-in user of a [FirebaseUserAuth]: [FirebaseUserAuth.currentUser], the result of a sign-in, and the
/// events of [FirebaseUserAuth.userChanges()].
///
/// An immutable snapshot: a change (a [FirebaseUserAuth.updateProfile], a [FirebaseUserAuth.reload]) produces a new
/// object. Two users are equal when all their fields are. [toString] shows only [uid] and [isAnonymous].
///
/// ```dart
/// final AuthUser user = await auth.signInAnonymously();
/// print('${user.uid} anonymous: ${user.isAnonymous}'); // anonymous: true
/// auth.userChanges().listen((AuthUser? user) => print(user?.email ?? 'signed out'));
/// ```
class AuthUser {
  /// Creates a user. [FirebaseUserAuth] creates them; you need this only for tests.
  const AuthUser({
    required this.uid,
    this.email,
    this.isAnonymous = false,
    this.emailVerified = false,
    this.displayName,
    this.photoUrl,
  });

  /// The id of the user.
  final String uid;

  /// The email address of the user, when the account has one.
  final String? email;

  /// Whether the user signed in anonymously (and has not added an email address and a password since).
  final bool isAnonymous;

  /// Whether the email address was verified. Up to date after a sign-in and after [FirebaseUserAuth.reload].
  final bool emailVerified;

  /// The display name of the user, when it has one.
  final String? displayName;

  /// The URL of the photo of the user, when it has one.
  final String? photoUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          uid == other.uid &&
          email == other.email &&
          isAnonymous == other.isAnonymous &&
          emailVerified == other.emailVerified &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl;

  @override
  int get hashCode => Object.hash(
    uid,
    email,
    isAnonymous,
    emailVerified,
    displayName,
    photoUrl,
  );

  @override
  String toString() => 'AuthUser(uid: $uid, isAnonymous: $isAnonymous)';
}
