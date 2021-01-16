// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth_vm;

/// The maximum wait time before attempting to retry auto refreshing tokens after a failed attempt.
///
/// This is the upper limit of the exponential backoff used for retrying token refresh.
const Duration _kMaxWaitTimeForBackoff = Duration(minutes: 16);

/// The amount of time before the token expires that proactive refresh should be attempted.
const Duration _kTokenRefreshHeadStart = Duration(minutes: 5);

// ignore_for_file: prefer_constructors_over_static_methods
class FirebaseAuth implements InternalTokenProvider {
  FirebaseAuth._(this.app, this._firebaseAuthApi, this._apiKeyClient, this._userStorage);

  factory FirebaseAuth.getInstance(FirebaseApp app) {
    if (_instances.containsKey(app.name)) {
      return _instances[app.name];
    }
    _authStateChangedControllers[app.name] = StreamController<FirebaseUser>.broadcast();
    final UserStorage userStorage = UserStorage(localStorage: app.storage, appName: app.name);

    // init the identity toolkit client
    final ApiKeyClient apiKeyClient = ApiKeyClient(app.options.apiKey, app.headersBuilder, locale: userStorage.locale);
    final FirebaseAuthApi firebaseAuthApi = FirebaseAuthApi(client: apiKeyClient);

    final FirebaseAuth auth = FirebaseAuth._(app, firebaseAuthApi, apiKeyClient, userStorage);
    _instances[app.name] = auth;

    final FirebaseUser user = userStorage.getUser(auth);
    auth
      .._updateCurrentUser(user, saveToDisk: false)
      .._lastNotifiedUserToken = user?._rawAccessToken;
    if (app.authProvider == app) {
      app.authProvider = auth;
    }

    app.onDeleteApp.first.then(auth._onDelete);
    return auth;
  }

  /// The auth object for the default Firebase app.
  ///
  /// The default Firebase app must have already been configured or an exception will be raised.
  static FirebaseAuth get instance {
    if (_instances.containsKey(FirebaseApp.instance.name)) {
      return _instances[FirebaseApp.instance.name];
    } else {
      final FirebaseAuth auth = FirebaseAuth.getInstance(FirebaseApp.instance);
      _instances[FirebaseApp.instance.name] = auth;
      return auth;
    }
  }

  Future<void> _onDelete(String appName) async {
    if (_instances.containsKey(appName)) {
      _instances.remove(appName);
      await _backgroundChangedSub?.cancel();
      await _authStateChangedControllers[appName]?.close();
    }
  }

  /// The [FirebaseApp] object that this auth object is connected to.
  final FirebaseApp app;

  final FirebaseAuthApi _firebaseAuthApi;
  final UserStorage _userStorage;
  final ApiKeyClient _apiKeyClient;

  StreamSubscription<bool> _backgroundChangedSub;
  bool _isAppInBackground;

  FirebaseUser _currentUser;
  String _lastNotifiedUserToken;
  bool _autoRefreshTokens = false;
  bool _autoRefreshScheduled = false;

  static final Map<String, FirebaseAuth> _instances = <String, FirebaseAuth>{};
  static final Map<String, StreamController<FirebaseUser>> _authStateChangedControllers =
      <String, StreamController<FirebaseUser>>{};

  /// The current user language code.
  String get languageCode => _userStorage.locale;

  /// Set the current user language code.
  ///
  /// The string used to set this property must be a language code that follows BCP 47.
  set languageCode(String languageCode) {
    _userStorage.locale = languageCode;
    _apiKeyClient.locale = languageCode;
  }

  /// Gets the cached current user, or null if there is none.
  FirebaseUser get currentUser => _currentUser;

  /// Receive [FirebaseUser] each time the user signIn or signOut
  Stream<FirebaseUser> get onAuthStateChanged {
    return _authStateChangedControllers[app.name].stream;
  }

  /// Returns a list of sign-in methods that can be used to sign in a given user (identified by its main email address).
  ///
  /// This method is useful when you support multiple authentication mechanisms if you want to implement an email-first
  /// authentication flow.
  ///
  /// An empty `List` is returned if the user could not be found. A null list indicates that the user has an account,
  /// but there are no providers registered. This can happen if the user unlinked all providers. The user can regain
  /// access to his account by resetting the password. When the reset flow completes successful the
  /// [ProviderType.password] is linked to his account.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidEmail] - If the [email] address is malformed.
  Future<List<String>> fetchSignInMethodsForEmail(String email) async {
    assert(email != null);

    final IdentitytoolkitRelyingpartyCreateAuthUriRequest request = IdentitytoolkitRelyingpartyCreateAuthUriRequest()
      ..identifier = email
      ..continueUri = 'http://www.google.com/';

    final CreateAuthUriResponse response = await _firebaseAuthApi.createAuthUri(request);

    return response.registered ? response.allProviders?.toList() : <String>[];
  }

  /// Signs in a user with the given email address and password.
  ///
  /// If successful, it also signs the user in into the app and updates the [onAuthStateChanged] stream.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.operationNotAllowed] - Indicates that email and password accounts are not enabled. Enable
  ///       them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///   * [FirebaseAuthError.wrongPassword] - Indicates the user's [password] is wrong.
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is invalid.
  Future<AuthResult> signInWithEmailAndPassword({@required String email, @required String password}) {
    assert(email != null);
    assert(password != null);
    final AuthCredential credential = EmailAuthProvider.credential(email: email, password: password);
    return _signInAndRetrieveData(credential);
  }

  /// Signs in using an email address and email sign-in link.
  ///
  /// Errors:
  ///  * [FirebaseAuthError.operationNotAllowed] - Indicates that email and email sign-in link accounts are not enabled.
  ///       Enable them in the Auth section of the Firebase console.
  ///  * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///  * [FirebaseAuthError.invalidEmail] - Indicates the email address is invalid.
  Future<AuthResult> signInWithEmailAndLink({@required String email, @required String link}) async {
    assert(email != null);
    assert(link != null);

    final EmailPasswordAuthCredential credential = EmailAuthProvider.credentialWithLink(email: email, link: link);
    return _signInAndRetrieveData(credential);
  }

  /// Asynchronously signs in to Firebase with the given 3rd-party credentials (e.g. a Facebook login Access Token, a
  /// Google ID Token/Access Token pair, etc.) and returns additional identity provider data.
  ///
  /// If successful, it also signs the user in into the app and updates the [onAuthStateChanged] stream.
  ///
  /// If the user doesn't have an account already, one will be created automatically.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidCredential] - Indicates the supplied credential is invalid. This could happen if it
  ///       has expired or it is malformed.
  ///   * [FirebaseAuthError.operationNotAllowed] - Indicates that email and password accounts are not enabled. Enable
  ///       them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///   * [FirebaseAuthError.accountExistsWithDifferentCredential] - Indicates the email asserted by the credential
  ///       (e.g. the email in a Facebook access token) is already in use by an existing account, that cannot be
  ///       authenticated with this sign-in method. Call [fetchSignInMethodsForEmail] for this user’s email and then
  ///       prompt them to sign in with any of the sign-in providers returned. This error will only be thrown if the
  ///       "One account per email address" setting is enabled in the Firebase console, under Auth settings.
  ///   * [FirebaseAuthError.wrongPassword] - Indicates the user's [password] is wrong.
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is invalid.
  ///   * [FirebaseAuthError.missingVerificationID] - Indicates that the phone auth credential was created with an empty
  ///       verification ID.
  ///   * [FirebaseAuthError.missingVerificationCode] - Indicates that the phone auth credential was created with an
  ///       empty verification code.
  ///   * [FirebaseAuthError.invalidVerificationID] - Indicates that the phone auth credential was created with an
  ///       invalid verification ID.
  ///   * [FirebaseAuthError.invalidVerificationCode] - Indicates that the phone auth credential was created with an
  ///       invalid verification code.
  ///   * [FirebaseAuthError.sessionExpired] - Indicates that the SMS code has expired.
  Future<AuthResult> signInWithCredential(AuthCredential credential) async {
    assert(credential != null);
    return _signInAndRetrieveData(credential);
  }

  /// Asynchronously creates and becomes an anonymous user.
  ///
  /// If there is already an anonymous user signed in, that user will be returned instead. If there is any other
  /// existing user signed in, that user will be signed out.
  ///
  /// Errors:
  ///   • [FirebaseAuthError.operationNotAllowed] - Indicates that Anonymous accounts are not enabled.
  Future<AuthResult> signInAnonymously() async {
    if (_currentUser != null && _currentUser.isAnonymous) {
      return _ensureUserPersistence(AuthResult._(_currentUser));
    }

    final IdentitytoolkitRelyingpartySignupNewUserRequest request = IdentitytoolkitRelyingpartySignupNewUserRequest();
    final SignupNewUserResponse response = await _firebaseAuthApi.signupNewUser(request);

    final FirebaseUser user = await _completeSignInWithAccessToken(
      response.idToken,
      int.parse(response.expiresIn),
      response.refreshToken,
      anonymous: true,
    );

    return AuthResult._(user, AdditionalUserInfo.newAnonymous());
  }

  /// Tries to sign in a user with a given Custom Token [token].
  ///
  /// If successful, it also signs the user in into the app and updates the [onAuthStateChanged] stream.
  ///
  /// Use this method after you retrieve a Firebase Auth Custom Token from your server.
  ///
  /// If the user identified by the [uid] specified in the token doesn't have an account already, one will be created
  /// automatically.
  ///
  /// Read how to use Custom Token authentication and the cases where it is useful in
  /// [the guides](https://firebase.google.com/docs/auth/android/custom-auth).
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidCustomToken] - Indicates a validation error with the custom token.
  ///   * [FirebaseAuthError.customTokenMismatch] - Indicates the service account and the API key belong to different
  ///       projects. Also ensure your app's SHA1 is correct in the Firebase console.
  Future<AuthResult> signInWithCustomToken(String token) async {
    assert(token != null);

    final IdentitytoolkitRelyingpartyVerifyCustomTokenRequest request =
        IdentitytoolkitRelyingpartyVerifyCustomTokenRequest()..token = token;

    final VerifyCustomTokenResponse response = await _firebaseAuthApi._requester.verifyCustomToken(request);

    final String expiresIn = response.expiresIn ?? '3600';
    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(expiresIn), response.refreshToken);
    final AdditionalUserInfo additionalUserInfo = AdditionalUserInfo._(isNewUser: response.isNewUser);
    return AuthResult._(user, additionalUserInfo);
  }

  /// Tries to create a new user account with the given email address and password.
  ///
  /// If successful, it also signs the user in into the app and updates
  /// the [onAuthStateChanged] stream.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is malformed.
  ///   * [FirebaseAuthError.emailAlreadyInUse] - Indicates the email used to attempt sign up already exists. Call
  ///       [fetchSignInMethodsForEmail] to check which sign-in mechanisms the user used, and prompt the user to sign in
  ///       with one of those.
  ///   * [FirebaseAuthError.operationNotAllowed] -  Indicates that email and password accounts are not enabled. Enable
  ///       them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.weakPassword] - Indicates an attempt to set a password that is considered too weak.
  Future<AuthResult> createUserWithEmailAndPassword({@required String email, @required String password}) async {
    assert(email != null);
    assert(password != null);

    final IdentitytoolkitRelyingpartySignupNewUserRequest request = IdentitytoolkitRelyingpartySignupNewUserRequest()
      ..email = email
      ..password = password;
    final SignupNewUserResponse response = await _firebaseAuthApi.signupNewUser(request);

    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(response.expiresIn), response.refreshToken);

    final AdditionalUserInfo additionalUserInfo =
        AdditionalUserInfo._(providerId: ProviderType.password, isNewUser: true);

    return AuthResult._(user, additionalUserInfo);
  }

  /// Resets the password using the email code sent to the user and a new password.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.weakPassword] - Indicates an attempt to set a password that is considered too weak.
  ///   * [FirebaseAuthError.operationNotAllowed] - Indicates the administrator disabled sign in with the specified
  ///       identity provider.
  ///   * [FirebaseAuthError.expiredActionCode] - Indicates the OOB code is expired.
  ///   * [FirebaseAuthError.invalidActionCode] - Indicates the OOB code is invalid.
  Future<void> confirmPasswordReset({@required String oobCode, @required String newPassword}) async {
    assert(oobCode != null && oobCode.isNotEmpty);
    assert(newPassword != null && newPassword.isNotEmpty);

    final IdentitytoolkitRelyingpartyResetPasswordRequest request = IdentitytoolkitRelyingpartyResetPasswordRequest()
      ..oobCode = oobCode
      ..newPassword = newPassword;

    return _firebaseAuthApi.resetPassword(request);
  }

  /// Checks the validity of an out of band code.
  ///
  /// Return the metadata corresponding to the action code.
  Future<ActionCodeInfo> checkActionCode(String oobCode) async {
    assert(oobCode != null && oobCode.isNotEmpty);

    final IdentitytoolkitRelyingpartyResetPasswordRequest request = IdentitytoolkitRelyingpartyResetPasswordRequest()
      ..oobCode = oobCode;

    final gitkit.ResetPasswordResponse response = await _firebaseAuthApi.resetPassword(request);

    final ActionCodeOperation operation = ActionCodeOperation.values
        .firstWhere((ActionCodeOperation it) => it.value == response.requestType, orElse: () => null);
    return ActionCodeInfo._(operation, response.email, response.newEmail);
  }

  /// Checks the validity of a verify password reset code
  ///
  /// Returns the email address of the user for which the out of band code applies.
  Future<String> verifyPasswordReset(String oobCode) async {
    final ActionCodeInfo response = await checkActionCode(oobCode);
    return response.email;
  }

  /// Applies out of band code.
  ///
  /// This method will not work for out of band codes which require an additional parameter, such as password reset
  /// code.
  Future<void> applyActionCode(String oobCode) async {
    assert(oobCode != null && oobCode.isNotEmpty);
    final IdentitytoolkitRelyingpartySetAccountInfoRequest request = IdentitytoolkitRelyingpartySetAccountInfoRequest()
      ..oobCode = oobCode;
    return _firebaseAuthApi.setAccountInfo(request);
  }

  /// Triggers the Firebase Authentication backend to send a password-reset email to the given email address, which must
  /// correspond to an existing user of your app.
  ///
  /// Errors:
  ///  * [FirebaseAuthError.invalidRecipientEmail] - Indicates an invalid recipient email was sent in the request.
  ///  * [FirebaseAuthError.invalidSender] - Indicates an invalid sender email is set in the console for this action.
  ///  * [FirebaseAuthError.invalidMessagePayload] - Indicates an invalid email template for sending update email.
  ///  * [FirebaseAuthError.missingIosBundleID] - Indicates that the iOS bundle ID is missing when
  ///     [ActionCodeSettings.handleCodeInApp] is set to true.
  ///  * [FirebaseAuthError.missingAndroidPackageName] - Indicates that the android package name is missing when the
  ///     [ActionCodeSettings.androidInstallApp] flag is set to true.
  ///  * [FirebaseAuthError.unauthorizedDomain] - Indicates that the domain specified in the continue URL is not
  ///     whitelisted in the Firebase console.
  ///  * [FirebaseAuthError.invalidContinueURI] - Indicates that the domain specified in the continue URI is not valid.
  ///  * [FirebaseAuthError.userNotFound] - Indicates that there is no user corresponding to the given [email] address.
  Future<void> sendPasswordResetEmail(String email, [ActionCodeSettings settings]) async {
    assert(email != null);

    final Relyingparty request = Relyingparty()
      ..requestType = OobCodeType.passwordReset.value
      ..email = email;

    return _firebaseAuthApi.getOobConfirmationCode(request, settings);
  }

  /// Signs in using an email address and email sign-in link.
  ///
  /// If successful, it also signs the user in into the app and updates the [onAuthStateChanged] stream.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.operationNotAllowed] - Indicates that email and email sign-in link accounts are not
  ///       enabled. Enable them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is invalid.
  Future<void> sendSignInWithEmailLink(String email, ActionCodeSettings settings) async {
    assert(email != null);
    assert(settings != null);

    final Relyingparty request = Relyingparty()
      ..requestType = OobCodeType.emailLinkSignIn.value
      ..email = email;

    return _firebaseAuthApi.getOobConfirmationCode(request, settings);
  }

  /// Signs out the current user and clears it from the disk cache.
  ///
  /// If successful, it signs the user out of the app and updates
  /// the [onAuthStateChanged] stream.
  Future<void> signOut() async {
    if (currentUser == null) {
      return;
    }
    _updateCurrentUser(null, saveToDisk: true);
  }

  /// Checks if link is an email sign-in link.
  bool isSignInWithEmailLink(String link) {
    if (link == null || link.isEmpty) {
      return false;
    }

    final Uri uri = Uri.tryParse(link);
    if (uri == null) {
      return false;
    }

    final Map<String, String> params = uri.queryParameters;
    if (params.isEmpty) {
      return false;
    }

    return params.containsKey('oobCode') && params['mode'] == 'signIn';
  }

  /// Starts the phone number authentication flow by sending a verification code to the specified phone number.
  ///
  /// You can use [presenter] to present the user with the recaptcha url in order to verify the app. Also you can
  /// implement a custom flow and just provide the recaptcha token using [provider].
  /// Errors:
  ///   * [FirebaseAuthError.captchaCheckFailed] - Indicates that the reCAPTCHA token obtained by the Firebase Auth is
  ///       invalid or has expired.
  ///   * [FirebaseAuthError.quotaExceeded] - Indicates that the phone verification quota for this project has been
  ///       exceeded.
  ///   * [FirebaseAuthError.invalidPhoneNumber] - Indicates that the phone number provided is invalid.
  ///   * [FirebaseAuthError.missingPhoneNumber] - Indicates that the phone number provided was not provided.
  Future<String> verifyPhoneNumber(
    String phoneNumber, {
    bool isTest = false,
    UrlPresenter presenter,
    RecaptchaTokenProvider provider,
  }) async {
    // todo: save the recaptcha token, and use it until it expires
    assert(phoneNumber != null);
    final IdentitytoolkitRelyingpartySendVerificationCodeRequest request =
        IdentitytoolkitRelyingpartySendVerificationCodeRequest()..phoneNumber = phoneNumber;

    if (provider != null) {
      request.recaptchaToken = await provider();
    } else if (!isTest) {
      final RecaptchaToken token = RecaptchaToken(_firebaseAuthApi);
      request.recaptchaToken = await token.get(
        urlPresenter: presenter ?? print,
        apiKey: app.options.apiKey,
        languageCode: languageCode,
      );
    }

    final IdentitytoolkitRelyingpartySendVerificationCodeResponse response =
        await _firebaseAuthApi.sendVerificationCode(request);
    return response.sessionInfo;
  }

  /// Signs in Firebase with the given 3rd party credentials (e.g. a Facebook login Access Token, a Google ID
  /// Token/Access Token pair, etc.) and returns additional identity provider data.
  Future<AuthResult> _signInAndRetrieveData(AuthCredential credential, {bool isReauthentication = false}) async {
    if (credential is EmailPasswordAuthCredential) {
      if (credential.link != null) {
        return _signInAndRetrieveDataEmailAndLink(credential.email, credential.link);
      } else {
        return _signInAndRetrieveDataEmailAndPassword(credential.email, credential.password);
      }
    } else if (credential is GameCenterAuthCredential) {
      return _signInAndRetrieveDataGameCenter(credential);
    } else if (credential is PhoneAuthCredential) {
      final AuthOperationType operation =
          isReauthentication ? AuthOperationType.reauthenticate : AuthOperationType.signUpOrSignIn;
      return _signInAndRetrieveDataPhone(credential, operation);
    }

    final IdentitytoolkitRelyingpartyVerifyAssertionRequest request =
        IdentitytoolkitRelyingpartyVerifyAssertionRequest()
          ..returnSecureToken = true
          ..autoCreate = true
          ..returnIdpCredential = true;
    credential.prepareVerifyAssertionRequest(request);

    final VerifyAssertionResponse response = await _firebaseAuthApi.verifyAssertion(request);

    final AuthCredential oAuthCredential = OAuthCredential._(
      providerId: response.providerId,
      idToken: response.oauthIdToken,
      accessToken: response.oauthAccessToken,
      secret: response.oauthTokenSecret,
      pendingToken: response.oauthRequestToken,
    );

    if (response.needConfirmation ?? false) {
      return Future<AuthResult>.error(FirebaseAuthCredentialAlreadyInUseError(credential, response.email));
    }

    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(response.expiresIn), response.refreshToken);
    final AdditionalUserInfo additionalUserInfo = AdditionalUserInfo._(
      providerId: response.providerId,
      profile: response.rawUserInfo != null ? Map<String, dynamic>.from(jsonDecode(response.rawUserInfo)) : null,
      username: response.screenName,
      isNewUser: response.isNewUser ?? false,
    );

    return AuthResult._(user, additionalUserInfo, oAuthCredential);
  }

  Future<AuthResult> _signInAndRetrieveDataEmailAndLink(String email, String link) async {
    assert(email != null && email.isNotEmpty);
    assert(link != null && link.isNotEmpty);

    final Uri uri = Uri.parse(link);
    final Map<String, String> params = uri.queryParameters;
    final String oobCode = params['oobCode'];

    final IdentitytoolkitRelyingpartyEmailLinkSigninRequest request =
        IdentitytoolkitRelyingpartyEmailLinkSigninRequest()
          ..email = email
          ..oobCode = oobCode;

    final EmailLinkSigninResponse response = await _firebaseAuthApi.emailLinkSignin(request);
    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(response.expiresIn), response.refreshToken);
    final AdditionalUserInfo additionalUserInfo =
        AdditionalUserInfo._(providerId: ProviderType.password, isNewUser: response.isNewUser);

    return AuthResult._(user, additionalUserInfo);
  }

  Future<AuthResult> _signInAndRetrieveDataEmailAndPassword(String email, String password) async {
    final IdentitytoolkitRelyingpartyVerifyPasswordRequest request = IdentitytoolkitRelyingpartyVerifyPasswordRequest()
      ..returnSecureToken = true
      ..email = email
      ..password = password;

    final VerifyPasswordResponse response = await _firebaseAuthApi.verifyPassword(request);

    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(response.expiresIn), response.refreshToken);
    final AdditionalUserInfo additionalUserInfo =
        AdditionalUserInfo._(providerId: ProviderType.password, isNewUser: false);
    return AuthResult._(user, additionalUserInfo);
  }

  Future<AuthResult> _signInAndRetrieveDataGameCenter(GameCenterAuthCredential credential) async {
    final SignInWithGameCenterRequest request = SignInWithGameCenterRequest(
      playerId: credential.playerId,
      publicKeyUrl: credential.publicKeyUrl,
      signature: credential.signature,
      salt: credential.salt,
      timestamp: credential.timestamp,
      displayName: credential.displayName,
    );

    final SignInWithGameCenterResponse response = await _firebaseAuthApi.signInWithGameCenter(request);
    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(response.expiresIn), response.refreshToken);
    final AdditionalUserInfo additionalUserInfo =
        AdditionalUserInfo._(providerId: ProviderType.gameCenter, isNewUser: response.isNewUser);
    return AuthResult._(user, additionalUserInfo);
  }

  Future<AuthResult> _signInAndRetrieveDataPhone(PhoneAuthCredential credential, AuthOperationType operation) async {
    final IdentitytoolkitRelyingpartyVerifyPhoneNumberRequest request =
        IdentitytoolkitRelyingpartyVerifyPhoneNumberRequest()..operation = operation.value;

    if (credential.temporaryProof != null && credential.phoneNumber != null) {
      request
        ..temporaryProof = credential.temporaryProof
        ..phoneNumber = credential.phoneNumber;
    } else {
      request
        ..sessionInfo = credential.verificationId
        ..code = credential.verificationCode;
    }

    final IdentitytoolkitRelyingpartyVerifyPhoneNumberResponse response =
        await _firebaseAuthApi.verifyPhoneNumber(request);

    // Check whether or not the successful response is actually the special case phone auth flow that returns a
    // temporary proof and phone number.
    if (response.temporaryProof != null && response.phoneNumber != null) {
      final PhoneAuthCredential credential = PhoneAuthProvider.credentialWithTemporaryProof(
          temporaryProof: response.temporaryProof, phoneNumber: response.phoneNumber);
      return Future<AuthResult>.error(FirebaseAuthCredentialAlreadyInUseError(credential));
    }

    final FirebaseUser user =
        await _completeSignInWithAccessToken(response.idToken, int.parse(response.expiresIn), response.refreshToken);
    final AdditionalUserInfo additionalUserInfo =
        AdditionalUserInfo._(providerId: ProviderType.phone, isNewUser: response.isNewUser);
    return AuthResult._(user, additionalUserInfo);
  }

  /// Completes a sign-in flow once we have [accessToken] and [refreshToken] for the user.
  Future<FirebaseUser> _completeSignInWithAccessToken(String accessToken, int expiresIn, String refreshToken,
      {bool anonymous = false}) async {
    final DateTime accessTokenExpirationDate = DateTime.now().add(Duration(seconds: expiresIn)).toUtc();
    final FirebaseUser user = await FirebaseUser._retrieveUserWithAuth(
      this,
      accessToken,
      accessTokenExpirationDate,
      refreshToken,
      anonymous: anonymous,
    );
    _updateCurrentUser(user, saveToDisk: true);
    return user;
  }

  /// Force signs out the current user.
  void _signOutByForce(String uid) {
    if (_currentUser.uid != uid) {
      return;
    }

    _updateCurrentUser(null, saveToDisk: true);
  }

  /// Updates the store for the given user.
  void _updateStore(FirebaseUser user) {
    if (_currentUser != user) {
      // No-op if the user is no longer signed in. This is not considered an error as we don't check
      // whether the user is still current on other callbacks of user operations either.
      return;
    }

    _userStorage.saveUser(user);
    _possiblyPostAuthStateChangeNotification();
  }

  AuthResult _ensureUserPersistence(AuthResult result) {
    _updateCurrentUser(result.user, saveToDisk: true);
    return result;
  }

  /// This method is called during: sign in and sign out events, as well as during class initialization time.
  ///
  /// The only time the [saveToDisk] parameter should be set to NO is during class initialization time because the user
  /// was just read from disk.
  void _updateCurrentUser(FirebaseUser user, {@required bool saveToDisk}) {
    if (user == _currentUser) {
      _possiblyPostAuthStateChangeNotification();
      return;
    }

    if (saveToDisk) {
      _userStorage.saveUser(user);
    }

    _currentUser = user;
    _possiblyPostAuthStateChangeNotification();
  }

  void _possiblyPostAuthStateChangeNotification() {
    final String token = _currentUser?._rawAccessToken;
    if (_lastNotifiedUserToken == token || (token != null && _lastNotifiedUserToken == token)) {
      return;
    }
    _lastNotifiedUserToken = token;
    if (_autoRefreshTokens && _currentUser != null) {
      // Schedule new refresh task after successful attempt.
      _scheduleAutoTokenRefresh();
    }

    _dispatchUser(_currentUser);
  }

  /// Schedules a task to automatically refresh tokens on the current user.
  ///
  /// The token refresh is scheduled 5 minutes before the scheduled expiration time.
  void _scheduleAutoTokenRefresh() {
    final DateTime preExpirationDate = _currentUser._accessTokenExpirationDate.subtract(_kTokenRefreshHeadStart);
    Duration tokenExpirationInterval = preExpirationDate.difference(DateTime.now());
    tokenExpirationInterval = tokenExpirationInterval < Duration.zero ? Duration.zero : tokenExpirationInterval;
    _scheduleAutoTokenRefreshWithDelay(tokenExpirationInterval, false);
  }

  /// Schedules a task to automatically refresh tokens on the current user.
  Future<void> _scheduleAutoTokenRefreshWithDelay(Duration delay, bool retry) async {
    final String accessToken = _currentUser._rawAccessToken;
    if (accessToken == null) {
      return;
    }

    if (retry) {
      Log.d('FirebaseAuth-${app.name}',
          'Token auto-refresh re-scheduled in $delay because of error on previous refresh attempt.');
    } else {
      Log.d('FirebaseAuth-${app.name}', 'Token auto-refresh scheduled in $delay for the new token.');
    }
    _autoRefreshScheduled = true;

    Timer(delay, () async {
      if (_currentUser._rawAccessToken != accessToken) {
        // Another auto refresh must have been scheduled so keep _autoRefreshScheduled unchanged.
        return;
      }
      _autoRefreshScheduled = false;
      if (_isAppInBackground) {
        return;
      }

      try {
        final String uid = _currentUser?.uid;
        await _currentUser._getToken(forceRefresh: true);

        if (_currentUser.uid != uid) {
          return;
        }
      } catch (e) {
        // Kicks off exponential back off logic to retry failed attempt. Starts with one minute delay (60 seconds) if
        // this is the first failed attempt.
        Duration rescheduleDelay;
        if (retry) {
          final Duration nextDelay = delay * 2;
          rescheduleDelay = nextDelay < _kMaxWaitTimeForBackoff ? nextDelay : _kMaxWaitTimeForBackoff;
        } else {
          rescheduleDelay = const Duration(minutes: 1);
        }
        await _scheduleAutoTokenRefreshWithDelay(rescheduleDelay, true);
      }
    });
  }

  void _dispatchUser(FirebaseUser user) {
    _authStateChangedControllers[app.name].add(user);
  }

  @override
  Future<GetTokenResult> getAccessToken({bool forceRefresh = false}) async {
    if (_currentUser == null) {
      return null;
    }

    if (!_autoRefreshTokens) {
      Log.d('FirebaseAuth-${app.name}', 'Token auto-refresh enabled.');
      _autoRefreshTokens = true;
      _scheduleAutoTokenRefresh();

      _backgroundChangedSub = app.onBackgroundChanged.listen(_backgroundStateChanged);
    }

    final String token = await _currentUser._getToken(forceRefresh: forceRefresh);
    return GetTokenResult(token);
  }

  @override
  String get uid => _currentUser?.uid;

  @override
  Stream<InternalTokenResult> get onTokenChanged {
    return onAuthStateChanged.map((FirebaseUser user) => InternalTokenResult(user?.refreshToken));
  }

  void _backgroundStateChanged(bool isBackground) {
    _isAppInBackground = isBackground;
    if (!isBackground && !_autoRefreshScheduled) {
      _scheduleAutoTokenRefresh();
    }
  }
}
