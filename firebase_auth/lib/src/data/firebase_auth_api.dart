// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of firebase_auth;

class FirebaseAuthApi {
  const FirebaseAuthApi({@required FirebaseAuthService firebaseAuthService})
      : assert(firebaseAuthService != null),
        _firebaseAuthService = firebaseAuthService;

  final FirebaseAuthService _firebaseAuthService;

  /// Calls the signUpNewUser endpoint, which is responsible anonymously signing up a user or signing in a user
  /// anonymously.
  Future<BaseAuthResponse> signUpNewUser(BaseAuthRequest request) {
    return _firebaseAuthService.signUp(request);
  }

  /// Calls the getAccountInfo endpoint, which returns account info for a given account.
  Future<List<UserDataResponse>> getAccountInfo(String firebaseAccessToken) {
    return _firebaseAuthService.lookup(firebaseAccessToken);
  }

  /// Calls the createAuthURI endpoint, which is responsible for creating the URI used by the IdP to authenticate the
  /// user.
  Future<CreateAuthUriResponse> createAuthUri(CreateAuthUriRequest request) {
    return _firebaseAuthService.createAuthUri(request);
  }
}
