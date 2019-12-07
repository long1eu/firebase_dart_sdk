// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of firebase_auth;

class FirebaseAuthApi {
  FirebaseAuthApi({@required IdentitytoolkitApi gitkit})
      : assert(gitkit != null),
        _requester = gitkit.relyingparty {
    final RelyingpartyResourceApi a = gitkit.relyingparty;
  }

  final RelyingpartyResourceApi _requester;

  /// Calls the signUpNewUser endpoint, which is responsible anonymously signing up a user or signing in a user
  /// anonymously.
  Future<SignupNewUserResponse> signupNewUser(IdentitytoolkitRelyingpartySignupNewUserRequest request) {
    return _requester.signupNewUser(request);
  }

  /// Calls the getAccountInfo endpoint, which returns account info for a given account.
  Future<GetAccountInfoResponse> getAccountInfo(IdentitytoolkitRelyingpartyGetAccountInfoRequest request) {
    return _requester.getAccountInfo(request);
  }

  /// Calls the createAuthURI endpoint, which is responsible for creating the URI used by the IdP to authenticate the
  /// user.
  Future<CreateAuthUriResponse> createAuthUri(IdentitytoolkitRelyingpartyCreateAuthUriRequest request) {
    return _requester.createAuthUri(request);
  }

  Future<GetOobConfirmationCodeResponse> getOobConfirmationCode(Relyingparty request) {
    return _requester.getOobConfirmationCode(request);
  }

  Future<EmailLinkSigninResponse> emailLinkSignin(IdentitytoolkitRelyingpartyEmailLinkSigninRequest request) {
    return _requester.emailLinkSignin(request);
  }
}
