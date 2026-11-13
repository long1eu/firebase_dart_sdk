/// The signed-in user of a [FirebaseUserAuth].
class AuthUser {
  /// Creates a user.
  const AuthUser({required this.uid, this.email, this.isAnonymous = false});

  /// The id of the user.
  final String uid;

  /// The email address of the user, when the account has one.
  final String? email;

  /// Whether the user signed in anonymously.
  final bool isAnonymous;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          uid == other.uid &&
          email == other.email &&
          isAnonymous == other.isAnonymous;

  @override
  int get hashCode => Object.hash(uid, email, isAnonymous);

  @override
  String toString() => 'AuthUser(uid: $uid, isAnonymous: $isAnonymous)';
}
