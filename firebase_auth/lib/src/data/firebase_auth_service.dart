// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of firebase_auth;

class FirebaseAuthService {
  const FirebaseAuthService({@required HttpService service})
      : assert(service != null),
        _service = service;

  final HttpService _service;

  Future<ExchangeCustomTokenResponse> signInWithCustomToken(ExchangeCustomTokenRequest request) async {
    final dynamic data = await _service.post(':signInWithCustomToken', request.json);
    return ExchangeCustomTokenResponse.fromJson(data);
  }

  /// Create a new email and password user
  ///
  ///
  /// If the email is not provided, an anonymous user will be created. Issues an HTTP POST request to the Auth
  /// signupNewUser endpoint.
  Future<BaseAuthResponse> signUp(BaseAuthRequest request) async {
    final dynamic data = await _service.post(':signUp', request.json);
    return BaseAuthResponse.fromJson(data);
  }

  /// Sign in a user with an email and password
  ///
  /// Makes an HTTP POST request to the Auth verifyPassword endpoint.
  Future<BaseAuthResponse> signIn(BaseAuthRequest request) async {
    final dynamic data = await _service.post(':signInWithPassword', request.json);
    return BaseAuthResponse.fromJson(data);
  }

  /// Sign in a user with an OAuth credential
  ///
  /// Issues an HTTP POST request to the Auth verifyAssertion endpoint.
  Future<OAuthResponse> signInWithIdp(OAuthRequest request) async {
    final dynamic data = await _service.post(':signInWithIdp', request.json);
    return OAuthResponse.fromJson(data);
  }

  /// Lookup all providers associated with a specified email
  ///
  /// Issues an HTTP POST request to the Auth createAuthUri endpoint.
  Future<CreateAuthUriResponse> createAuthUri(CreateAuthUriRequest request) async {
    final dynamic data = await _service.post(':createAuthUri', request.json);
    return CreateAuthUriResponse.fromJson(data);
  }

  /// Send a password reset or verification email. [locale] is the corresponding language code
  /// to the user's locale. Passing this will localize the email verification sent to the user.
  ///
  /// Issues an HTTP POST request to the Auth getOobConfirmationCode endpoint.
  Future<OobCodeResponse> sendOobCode(OobCodeRequest request) async {
    final dynamic data = await _service.post(
      ':sendOobCode',
      request.json,
      headers: <String, String>{
        if (_service.locale != null) 'X-Firebase-Locale': _service.locale,
      },
    );
    return OobCodeResponse.fromJson(data);
  }

  /// Verify or apply a password reset code
  ///
  /// Issues an HTTP POST request to the Auth resetPassword endpoint.
  /// see [ResetPasswordRequest]
  Future<ResetPasswordResponse> resetPassword(ResetPasswordRequest request) async {
    final dynamic data = await _service.post(':resetPassword', request.json);
    return ResetPasswordResponse.fromJson(data);
  }

  /// Perform various account updates:
  ///   - changeEmail
  ///   - changePassword
  ///   - updateProfile
  ///   - linkEmailAndPassword
  ///   - unlinkProvider
  ///   - confirmEmailVerification
  ///
  /// Issues an HTTP POST request to the Auth resetPassword endpoint.
  /// see [UpdateRequest] factory constructors
  Future<UpdateResponse> update(UpdateRequest request) async {
    final dynamic data = await _service.post(':update', request.json);
    return UpdateResponse.fromJson(data);
  }

  /// All the user information associated with the account
  ///
  /// Issues an HTTP POST request to the Auth getAccountInfo endpoint.
  Future<List<UserDataResponse>> lookup(String idToken) async {
    final dynamic data = await _service.post(':lookup', <String, dynamic>{'idToken': idToken});

    return List<Map<String, dynamic>>.from(data['users'])
        .map((Map<String, dynamic> json) => UserDataResponse.fromJson(json))
        .toList();
  }
}
