// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth_vm;

typedef UpdateSetAccountInfoRequest = void Function(
    gitkit.UserInfo user, IdentitytoolkitRelyingpartySetAccountInfoRequest request);

class FirebaseUser with UserInfoMixin {
  FirebaseUser._({@required SecureTokenApi secureTokenApi, @required FirebaseAuth auth})
      : assert(secureTokenApi != null),
        assert(auth != null),
        _secureTokenApi = secureTokenApi,
        _auth = auth,
        _runner = SequentialRunner();

  /// Constructs a user with Secure Token Service tokens, and obtains user details from the getAccountInfo endpoint.
  static Future<FirebaseUser> _retrieveUserWithAuth(
      FirebaseAuth auth, String accessToken, DateTime accessTokenExpirationDate, String refreshToken,
      {bool anonymous}) async {
    final SecureTokenApi secureTokenApi = SecureTokenApi(
      client: auth._apiKeyClient,
      accessToken: accessToken,
      accessTokenExpirationDate: accessTokenExpirationDate,
      refreshToken: refreshToken,
    );

    final FirebaseUser user = FirebaseUser._(secureTokenApi: secureTokenApi, auth: auth);
    final String newAccessToken = await user._getToken();

    final IdentitytoolkitRelyingpartyGetAccountInfoRequest request = IdentitytoolkitRelyingpartyGetAccountInfoRequest()
      ..idToken = newAccessToken;

    final GetAccountInfoResponse response = await auth._firebaseAuthApi.getAccountInfo(request);

    return user
      .._isAnonymous = anonymous
      .._updateWithUserDataResponse(response);
  }

  final FirebaseAuth _auth;
  final SequentialRunner _runner;

  SecureTokenApi _secureTokenApi;
  bool _isAnonymous;
  Map<String, UserInfo> _providerData;
  UserMetadataImpl _metadata;

  /// Whether or not the user can be authenticated by using Firebase email and password.
  bool _hasEmailPasswordCredential;

  /// Profile data for each identity provider, if any.
  ///
  /// This data is cached on sign-in and updated when linking or unlinking.
  List<UserInfo> get providerData => _providerData.values.toList();

  /// Indicates the user represents an anonymous user.
  bool get isAnonymous => _isAnonymous;

  /// A refresh token; useful for obtaining new access tokens independently.
  ///
  /// This property should only be used for advanced scenarios, and is not typically needed.
  String get refreshToken => _secureTokenApi._refreshToken;

  /// Metadata associated with the Firebase user in question.
  UserMetadata get metadata => _metadata;

  /// Updates the email address of the user.
  ///
  /// The original email address recipient will receive an email that allows them to revoke the email address change,
  /// in order to protect them from account hijacking.
  ///
  /// May fail if there is already an account with this email address that was created using email and password
  /// authentication.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidRecipientEmail] - Indicates an invalid recipient email was sent in the request.
  ///   * [FirebaseAuthError.invalidSender] - Indicates an invalid sender email is set in the console for this action.
  ///   * [FirebaseAuthError.invalidMessagePayload] - Indicates an invalid email template for sending update email.
  ///   * [FirebaseAuthError.emailAlreadyInUse] - Indicates the email is already in use by another account.
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is malformed.
  ///   * [FirebaseAuthError.requiresRecentLogin] - Indicates that the user's last sign-in time does not meet the
  ///       security threshold. Use reauthenticate methods to resolve.
  Future<void> updateEmail(String email) async {
    assert(email != null);
    return _updateEmailAndPassword(email, null);
  }

  /// Updates the password of the user.
  ///
  /// Anonymous users who update both their email and password will no longer be anonymous. They will be able to log in
  /// with these credentials.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.weakPassword] - Indicates an attempt to set a password that is considered too weak.
  ///   * [FirebaseAuthError.requiresRecentLogin] - Indicates that the user's last sign-in time does not meet the
  ///       security threshold. Use reauthenticate methods to resolve.
  Future<void> updatePassword(String password) async {
    assert(password != null);
    return _updateEmailAndPassword(null, password);
  }

  /// Updates the phone number of the user.
  ///
  /// The new phone number credential corresponding to the phone number to be added to the Firebase account, if a phone
  /// number is already linked to the account, this new phone number will replace it.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.requiresRecentLogin] - Indicates that the user's last sign-in time does not meet the
  ///       security threshold. Use reauthenticate methods to resolve.
  Future<void> updatePhoneNumberCredential(PhoneAuthCredential credential) async {
    assert(credential != null);
    return _updateOrLinkPhoneNumberCredential(credential, isLinkOperation: false);
  }

  /// Updates the user profile information.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///   * [FirebaseAuthError.userNotFound] - Indicates the user account was not found.
  Future<void> updateProfile(UserUpdateInfo userUpdateInfo) async {
    assert(userUpdateInfo != null);
    return _runUserUpdateTransaction(
      (_, gitkit.IdentitytoolkitRelyingpartySetAccountInfoRequest request) {
        if (userUpdateInfo.hasDisplayName) {
          request.displayName = userUpdateInfo.displayName;
        }

        if (userUpdateInfo.hasPhotoUrl) {
          request.photoUrl = userUpdateInfo.photoUrl;
        }
      },
    );
  }

  /// Reloads the user's profile data from the server.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.requiresRecentLogin] - Indicates that the user's last sign-in time does not meet the
  ///       security threshold. Use reauthenticate methods to resolve.
  Future<void> reload() async => _getAccountInfoRefreshingCache();

  /// Renews the user’s authentication tokens by validating a fresh set of [credential]s supplied by the user and
  /// returns additional identity provider data.
  ///
  /// This is used to prevent or resolve [FirebaseAuthError.requiresRecentLogin] response to operations that require a
  /// recent sign-in.
  ///
  /// If the user associated with the supplied credential is different from the current user, or if the validation of
  /// the supplied credentials fails; an error is returned and the current user remains signed in.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidCredential] - Indicates the supplied credential is invalid. This could happen if it
  ///       has expired or it is malformed.
  ///   * [FirebaseAuthError.operationNotAllowed] - Indicates that accounts with the identity provider represented by
  ///       the credential are not enabled. Enable them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.emailAlreadyInUse] -  Indicates the email asserted by the credential (e.g. the email in a
  ///       Facebook access token) is already in use by an existing account, that cannot be authenticated with this
  ///       method. Call [fetchProvidersForEmail] for this user’s email and then prompt them to sign in with any of the
  ///       sign-in providers returned. This error will only be thrown if the "One account per email address" setting is
  ///       enabled in the Firebase console, under Auth settings. Please note that the error code raised in this
  ///       specific situation may not be the same on Web and Android.
  ///   * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///   * [FirebaseAuthError.wrongPassword] - Indicates the user attempted reauthentication with an incorrect password,
  ///       if credential is of the type [EmailPasswordAuthCredential].
  ///   * [FirebaseAuthError.userMismatch] -  Indicates that an attempt was made to reauthenticate with a user which is
  ///       not the current user.
  ///   * [FirebaseAuthError.invalidEmail] - Indicates the email address is malformed.
  Future<AuthResult> reauthenticateWithCredential(AuthCredential credential) async {
    assert(credential != null);
    try {
      final AuthResult result = await _auth._signInAndRetrieveData(credential, isReauthentication: true);
      if (result.user.uid != _auth.uid) {
        throw FirebaseAuthError.userMismatch;
      }

      // Successful reauthenticate
      await _setTokenService(result.user._secureTokenApi);
      return result;
    } on FirebaseAuthError catch (e) {
      // If "user not found" error returned by backend, translate to user mismatch error which is
      // more accurate.
      if (e == FirebaseAuthError.userNotFound) {
        throw FirebaseAuthError.userMismatch;
      }

      rethrow;
    }
  }

  /// Obtains the id token result for the current user, forcing a [refresh] if desired.
  ///
  /// Useful when authenticating against your own backend. Use our server SDKs or follow the official documentation to
  /// securely verify the integrity and validity of this token.
  ///
  /// Completes with an error if the user is signed out.
  Future<GetTokenResult> getIdToken({bool forceRefresh = false}) async {
    final String token = await _getToken(forceRefresh: forceRefresh);
    return GetTokenResult(token);
  }

  /// Associates a user account from a third-party identity provider with this user and returns additional identity
  /// provider data.
  ///
  /// This allows the user to sign in to this account in the future with the given account.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.weakPassword] - Indicates an attempt to set a password that is considered too weak.
  ///   * [FirebaseAuthError.invalidCredential] - Indicates the supplied credential is invalid. This could happen if it
  ///       has expired or it is malformed.
  ///   * [FirebaseAuthError.credentialAlreadyInUse] - Indicates an attempt to link with a credential that has already
  ///       been linked with a different Firebase account.
  ///   * [FirebaseAuthError.userDisabled] - Indicates the user's account is disabled.
  ///   * [FirebaseAuthError.requiresRecentLogin] - Indicates that the user's last sign-in time does not meet the
  ///       security threshold. Use reauthenticate methods to resolve.
  ///   * [FirebaseAuthError.providerAlreadyLinked] - Indicates an attempt to link a provider of a type already linked
  ///       to this account.
  ///   * [FirebaseAuthError.operationNotAllowed] - Indicates that accounts with the identity provider represented by
  ///       the credential are not enabled. Enable them in the Auth section of the Firebase console.
  ///   * [FirebaseAuthError.invalidActionCode] - Indicates that the action code in the link is malformed, expired, or
  ///       has already been used. This can only occur when using [EmailAuthProvider.getCredentialWithLink] to obtain
  ///       the credential.
  Future<AuthResult> linkWithCredential(AuthCredential credential) async {
    assert(credential != null);
    if (providerData.map((UserInfo it) => it.providerId).contains(credential.providerId)) {
      return Future<AuthResult>.error(FirebaseAuthError.providerAlreadyLinked);
    }

    AuthResult result = AuthResult._(this);
    if (credential is EmailPasswordAuthCredential) {
      if (_hasEmailPasswordCredential) {
        return Future<AuthResult>.error(FirebaseAuthError.providerAlreadyLinked);
      }

      if (credential.password != null) {
        await _updateEmailAndPassword(credential.email, credential.password);
        return result;
      } else {
        await _linkWithEmailLink(credential);
        return result;
      }
    } else if (credential is GameCenterAuthCredential) {
      await _linkWithGameCenter(credential);
      return result;
    } else if (credential is PhoneAuthCredential) {
      await _updateOrLinkPhoneNumberCredential(credential, isLinkOperation: true);
      return result;
    }
    final String accessToken = await _getToken();

    final IdentitytoolkitRelyingpartyVerifyAssertionRequest request =
        IdentitytoolkitRelyingpartyVerifyAssertionRequest()
          ..returnSecureToken = true
          ..autoCreate = true
          ..returnIdpCredential = true;
    credential.prepareVerifyAssertionRequest(request);
    request.idToken = accessToken;

    try {
      final VerifyAssertionResponse response = await _firebaseAuthApi.verifyAssertion(request);

      final AuthCredential oAuthCredential = OAuthCredential._(
        providerId: response.providerId,
        idToken: response.oauthIdToken,
        accessToken: response.oauthAccessToken,
        secret: response.oauthTokenSecret,
        pendingToken: response.oauthRequestToken,
      );
      final AdditionalUserInfoImpl additionalUserInfo = AdditionalUserInfoImpl.fromVerifyAssertionResponse(response);
      result = AuthResult._(this, additionalUserInfo, oAuthCredential);

      // Update the new token
      _updateSecureToken(response.idToken, response.expiresIn, response.refreshToken);

      // Get account info to update cached user info.
      await _getAccountInfoRefreshingCache();
      _isAnonymous = false;
      _updateStore();
      return result;
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  /// Disassociates a user account from a third-party identity provider with this user.
  ///
  /// This will prevent the user from signing in to this account with those credentials.
  ///
  /// Use the [ProviderType] class to get the correct [providerId].
  ///
  /// Errors:
  /// * [FirebaseAuthError.invalidRecipientEmail] - Indicates an invalid recipient email was sent in the request.
  /// * [FirebaseAuthError.invalidSender] - Indicates an invalid sender email is set in the console for this action.
  /// * [FirebaseAuthError.invalidMessagePayload] - Indicates an invalid email template for sending update email.
  /// * [FirebaseAuthError.userNotFound] - Indicates the user account was not found.
  Future<void> unlinkFromProvider(String providerId) async {
    assert(providerId != null);

    if (!_providerData.containsKey(providerId)) {
      throw FirebaseAuthError.noSuchProvider;
    }

    final String accessToken = await _getToken();
    final IdentitytoolkitRelyingpartySetAccountInfoRequest request = IdentitytoolkitRelyingpartySetAccountInfoRequest()
      ..idToken = accessToken
      ..deleteProvider = <String>[providerId];

    final SetAccountInfoResponse response = await _firebaseAuthApi.setAccountInfo(request);
    // We can't just use the provider info objects in SetAccountInfoResponse because they don't have localId and email
    // fields. Remove the specific provider manually.
    _providerData.remove(providerId);

    if (providerId == ProviderType.password) {
      _hasEmailPasswordCredential = false;
    }

    // After successfully unlinking a phone auth provider, remove the phone number from the cached user info.
    if (providerId == ProviderType.phone) {
      _userInfo = _userInfo.rebuild((UserInfoImplBuilder b) => b.phoneNumber = null);
    }

    if (response.idToken != null && response.refreshToken != null) {
      _updateSecureToken(response.idToken, response.expiresIn, response.refreshToken);
    }
    _updateStore();
  }

  /// Initiates email verification for the user.
  ///
  /// Errors:
  ///   * [FirebaseAuthError.invalidRecipientEmail] - Indicates an invalid recipient email was sent in the request.
  ///   * [FirebaseAuthError.invalidSender] - Indicates the supplied credential is invalid. This could happen if it
  ///       has expired or it is malformed.
  ///   * [FirebaseAuthError.credentialAlreadyInUse] - Indicates an invalid sender email is set in the console for this
  ///       action.
  ///   * [FirebaseAuthError.invalidMessagePayload] - Indicates an invalid email template for sending update email.
  ///   * [FirebaseAuthError.userNotFound] - Indicates the user account was not found.
  Future<void> sendEmailVerification({ActionCodeSettings settings}) async {
    final String accessToken = await _getToken();

    final Relyingparty request = Relyingparty()
      ..requestType = ActionCodeOperation.verifyEmail.value
      ..idToken = accessToken
      ..updateWith(settings);

    return _firebaseAuthApi.getOobConfirmationCode(request);
  }

  /// Deletes the current user (also signs out the user).
  ///
  /// Errors:
  ///   * [FirebaseAuthError.requiresRecentLogin] - Indicates that the user's last sign-in time does not meet the
  ///       security threshold. Use reauthenticate methods to resolve.
  Future<void> delete() async {
    final String accessToken = await _getToken();

    final IdentitytoolkitRelyingpartyDeleteAccountRequest request = IdentitytoolkitRelyingpartyDeleteAccountRequest()
      ..localId = uid
      ..idToken = accessToken;

    try {
      await _firebaseAuthApi._requester.deleteAccount(request);

      _auth._signOutByForce(uid);
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  /// The cached access token.
  ///
  /// This method is specifically for providing the access token to internal clients during deserialization and sign-
  /// in events, and should not be used to retrieve the access token by anyone else.
  String get _rawAccessToken => _secureTokenApi._accessToken;

  /// The expiration date of the cached access token.
  DateTime get _accessTokenExpirationDate => _secureTokenApi._accessTokenExpirationDate;

  FirebaseAuthApi get _firebaseAuthApi => _auth._firebaseAuthApi;

  /// Updates email address and/or password for the current user.
  ///
  /// May fail if there is already an email/password-based account for the same email address.
  Future<void> _updateEmailAndPassword(String email, String password) async {
    assert(password == null || password.isNotEmpty);

    final bool hadEmailPasswordCredential = _hasEmailPasswordCredential;

    await _runUserUpdateTransaction(
      (gitkit.UserInfo user, IdentitytoolkitRelyingpartySetAccountInfoRequest request) {
        request
          ..email = email
          ..password = password;
      },
    );

    if (email != null) {
      _userInfo = _userInfo._copyWith(email: email);
    }
    if (this.email != null && !hadEmailPasswordCredential) {
      // The list of providers need to be updated for the newly added email-password provider.
      final String accessToken = await _getToken();

      final IdentitytoolkitRelyingpartyGetAccountInfoRequest request =
          IdentitytoolkitRelyingpartyGetAccountInfoRequest()..idToken = accessToken;

      try {
        final GetAccountInfoResponse response = await _firebaseAuthApi.getAccountInfo(request);
        for (gitkit.UserInfo userAccountInfo in response.users) {
          // Set the account to non-anonymous if there are any providers, even if they're not email/password ones.
          if (userAccountInfo.providerUserInfo.isNotEmpty) {
            _isAnonymous = false;
          }

          for (UserInfoProviderUserInfo providerUserInfo in userAccountInfo.providerUserInfo) {
            if (providerUserInfo.providerId == ProviderType.password) {
              _hasEmailPasswordCredential = true;
            }
          }
        }
        _updateWithUserDataResponse(response);
        _updateStore();
      } on FirebaseAuthError catch (e) {
        _signOutIfTokenIsInvalid(e);
        rethrow;
      }
    } else {
      _updateStore();
    }
  }

  /// Links a game center account with this user. On success, the cached user profile data is updated.
  Future<void> _linkWithEmailLink(EmailPasswordAuthCredential credential) async {
    final String accessToken = await _getToken();
    final Uri link = Uri.parse(credential.link);
    final String actionCode = link.queryParameters['oobCode'];

    final IdentitytoolkitRelyingpartyEmailLinkSigninRequest request =
        IdentitytoolkitRelyingpartyEmailLinkSigninRequest()
          ..email = credential.email
          ..oobCode = actionCode
          ..idToken = accessToken;

    try {
      await _firebaseAuthApi.emailLinkSignin(request);

      // Get account info to update cached user info.
      await _getAccountInfoRefreshingCache();
      _isAnonymous = false;
      _updateStore();
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  /// Links a game center account with this user. On success, the cached user profile data is updated.
  Future<void> _linkWithGameCenter(GameCenterAuthCredential credential) async {
    final String accessToken = await _getToken();
    final SignInWithGameCenterRequest request = SignInWithGameCenterRequest(
      playerId: credential.playerId,
      publicKeyUrl: credential.publicKeyUrl,
      signature: credential.signature,
      salt: credential.salt,
      timestamp: credential.timestamp,
      displayName: credential.displayName,
      accessToken: accessToken,
    );

    try {
      await _firebaseAuthApi.signInWithGameCenter(request);

      // Get account info to update cached user info.
      await _getAccountInfoRefreshingCache();
      _isAnonymous = false;
      _updateStore();
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  /// Updates the phone number for the user. On success, the cached user profile data is updated.
  Future<void> _updateOrLinkPhoneNumberCredential(PhoneAuthCredential credential,
      {@required bool isLinkOperation}) async {
    final String accessToken = await _getToken();
    final AuthOperationType operation = isLinkOperation ? AuthOperationType.link : AuthOperationType.update;
    final IdentitytoolkitRelyingpartyVerifyPhoneNumberRequest request =
        IdentitytoolkitRelyingpartyVerifyPhoneNumberRequest()
          ..sessionInfo = credential.verificationId
          ..code = credential.verificationCode
          ..operation = operation.value
          ..idToken = accessToken;
    try {
      await _firebaseAuthApi.verifyPhoneNumber(request);

      // Get account info to update cached user info.
      await _getAccountInfoRefreshingCache();
      _isAnonymous = false;
      _updateStore();
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  /// Performs a setAccountInfo request by mutating the results of a getAccountInfo response, atomically in regards to
  /// other calls to this method.
  Future<void> _runUserUpdateTransaction(UpdateSetAccountInfoRequest updateRequest) {
    return _runner.enqueue<void>(() async {
      final gitkit.UserInfo user = await _getAccountInfoRefreshingCache();

      final String accessToken = await _getToken();
      final IdentitytoolkitRelyingpartySetAccountInfoRequest request =
          IdentitytoolkitRelyingpartySetAccountInfoRequest()..idToken = accessToken;
      updateRequest(user, request);

      try {
        final SetAccountInfoResponse response = await _firebaseAuthApi.setAccountInfo(request);
        if (response.idToken != null && response.refreshToken != null) {
          _updateSecureToken(response.idToken, response.expiresIn, response.refreshToken);
        }
      } on FirebaseAuthError catch (e) {
        _signOutIfTokenIsInvalid(e);
        rethrow;
      }
    });
  }

  /// Creates and sets a new token service for this instance.
  void _updateSecureToken(String accessToken, String expiresIn, String refreshToken) {
    final DateTime accessTokenExpirationDate = DateTime.now().add(Duration(seconds: int.parse(expiresIn))).toUtc();
    final SecureTokenApi secureTokenApi = SecureTokenApi(
      client: _auth._apiKeyClient,
      accessToken: accessToken,
      accessTokenExpirationDate: accessTokenExpirationDate,
      refreshToken: refreshToken,
    );
    _setTokenService(secureTokenApi);
  }

  /// Sets a new token service for this instance.
  Future<void> _setTokenService(SecureTokenApi secureTokenApi) async {
    await secureTokenApi.fetchAccessToken();
    _secureTokenApi = secureTokenApi;
    _updateStore();
  }

  /// Gets the users's account data from the server, updating our local values.
  Future<gitkit.UserInfo> _getAccountInfoRefreshingCache() async {
    final String accessToken = await _getToken();

    final IdentitytoolkitRelyingpartyGetAccountInfoRequest request = IdentitytoolkitRelyingpartyGetAccountInfoRequest()
      ..idToken = accessToken;
    try {
      final GetAccountInfoResponse response = await _firebaseAuthApi.getAccountInfo(request);
      _updateWithUserDataResponse(response);
      _updateStore();
      return response.users.first;
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  /// Retrieves the Firebase authentication token, possibly refreshing it if it has expired.
  Future<String> _getToken({bool forceRefresh = false}) async {
    bool tokenUpdate = forceRefresh || !_secureTokenApi.hasValidAccessToken;

    final String oldAccessToken = _secureTokenApi._accessToken;
    final String oldRefreshToken = _secureTokenApi._refreshToken;

    try {
      final String token = await _secureTokenApi.fetchAccessToken(forceRefresh: forceRefresh);

      tokenUpdate = tokenUpdate ||
          oldAccessToken != _secureTokenApi._accessToken ||
          oldRefreshToken != _secureTokenApi._refreshToken;

      if (tokenUpdate) {
        _updateStore();
      }
      return token;
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  void _updateWithUserDataResponse(GetAccountInfoResponse response) {
    final gitkit.UserInfo user = response.users.first;

    _userInfo = UserInfoImpl(
      uid: user.localId,
      email: user.email,
      isEmailVerified: user.emailVerified ?? false,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      phoneNumber: user.phoneNumber,
    );
    _hasEmailPasswordCredential = user.passwordHash?.isNotEmpty ?? false;
    _metadata = UserMetadataImpl(
      lastSignInDate: DateTime.fromMillisecondsSinceEpoch(int.parse(user.lastLoginAt), isUtc: true),
      creationDate: DateTime.fromMillisecondsSinceEpoch(int.parse(user.createdAt), isUtc: true),
    );

    _providerData =
        user.providerUserInfo?.asMap()?.map((_, UserInfoProviderUserInfo info) => MapEntry<String, UserInfoImpl>(
                info.providerId,
                UserInfoImpl(
                  providerId: info.providerId,
                  uid: info.federatedId,
                  displayName: info.displayName,
                  photoUrl: info.photoUrl,
                  email: info.email,
                  phoneNumber: info.phoneNumber,
                ))) ??
            <String, UserInfo>{};
  }

  void _updateStore() {
    _auth._updateStore(this);
  }

  void _signOutIfTokenIsInvalid(FirebaseAuthError e) {
    if (e == FirebaseAuthError.userNotFound ||
        e == FirebaseAuthError.userDisabled ||
        e == FirebaseAuthError.invalidUserToken ||
        e == FirebaseAuthError.userTokenExpired) {
      print('Invalid user token detected user is automatically signed out.');
      _auth._signOutByForce(uid);
    }
  }

  static Serializer<FirebaseUser> get serializer => _$firebaseUserSerializer;

  @override
  String toString() {
    return (ToStringHelper(FirebaseUser)
          ..add('uid', uid)
          ..add('providerId', providerId)
          ..add('displayName', displayName)
          ..add('photoUrl', photoUrl)
          ..add('email', email)
          ..add('phoneNumber', phoneNumber)
          ..add('isEmailVerified', isEmailVerified)
          ..add('isAnonymous', _isAnonymous)
          ..add('providerData', _providerData)
          ..add('metadata', _metadata))
        .toString();
  }
}
