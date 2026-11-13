import 'firebase_user_auth.dart';

/// The signed-in user of a [FirebaseUserAuth].
class AuthUser {
  /// Creates a user.
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
