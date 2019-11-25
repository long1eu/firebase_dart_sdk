// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

/// Helper object that contains the result of a successful sign-in, link and reauthenticate action.
///
/// It contains references to a [FirebaseUser] instance and a [AdditionalUserInfo] instance.
class AuthResult {
  const AuthResult._(this.user, [this.additionalUserInfo, this.credential]);

  /// Returns the currently signed-in [FirebaseUser], or `null` if there isn't
  /// any (i.e. the user is signed out).
  final FirebaseUser user;

  /// Returns IDP-specific information for the user if the provider is one of
  /// Facebook, Github, Google, or Twitter.
  final AdditionalUserInfo additionalUserInfo;

  /// This property will be non-null after a successful sign-in via signInWithProvider:UIDelegate:.
  ///
  /// May be used to obtain the accessToken and/or IDToken pertaining to a recently signed-in user.
  // TODO(long1eu): refactor docs to better mach the Dart implementation
  final AuthCredential credential;

  @override
  String toString() {
    return (ToStringHelper(AuthResult)
          ..add('user', user)
          ..add('additionalUserInfo', additionalUserInfo)
          ..add('credential', credential))
        .toString();
  }
}
