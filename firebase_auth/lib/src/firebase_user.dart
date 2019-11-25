// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

class FirebaseUser with UserInfoMixin {
  FirebaseUser({
    @required SecureTokenApi secureTokenApi,
    @required FirebaseAuth auth,
  })  : assert(secureTokenApi != null),
        assert(auth != null),
        _secureTokenApi = secureTokenApi,
        _configuration = auth._configuration,
        _auth = auth;

  /// Constructs a user with Secure Token Service tokens, and obtains user details from the getAccountInfo endpoint.
  static Future<FirebaseUser> _retrieveUserWithAuth(
      FirebaseAuth auth, String accessToken, DateTime accessTokenExpirationDate, String refreshToken,
      {bool anonymous}) async {
    final HttpService secureTokenService =
        HttpService(configuration: auth._configuration, host: 'https://securetoken.googleapis.com');
    final SecureTokenApi secureTokenApi = SecureTokenApi(
      secureTokenService: SecureTokenService(service: secureTokenService),
      accessToken: accessToken,
      accessTokenExpirationDate: accessTokenExpirationDate,
      refreshToken: refreshToken,
    );

    final FirebaseUser user = FirebaseUser(secureTokenApi: secureTokenApi, auth: auth);
    final String firebaseAccessToken = await user._getToken();

    final List<UserDataResponse> response = await auth._firebaseAuthApi.getAccountInfo(firebaseAccessToken);

    return user
      .._isAnonymous = anonymous
      .._updateWithUserDataResponse(response);
  }

  final SecureTokenApi _secureTokenApi;
  final AuthRequestConfiguration _configuration;
  final FirebaseAuth _auth;

  bool _isAnonymous;
  String _refreshToken;
  List<UserInfo> _providerData;
  UserMetadata _metadata;

  bool __hasEmailPasswordCredential;

  /// Indicates the user represents an anonymous user.
  bool get isAnonymous => _isAnonymous;

  /// A refresh token; useful for obtaining new access tokens independently.
  ///
  /// This property should only be used for advanced scenarios, and is not typically needed.
  String get refreshToken => _refreshToken;

  /// Profile data for each identity provider, if any.
  ///
  /// This data is cached on sign-in and updated when linking or unlinking.
  List<UserInfo> get providerData => _providerData.toList();

  /// Metadata associated with the Firebase user in question.
  UserMetadata get metadata => _metadata;

  /// The cached access token.
  ///
  /// This method is specifically for providing the access token to internal clients during deserialization and sign-
  /// in events, and should not be used to retrieve the access token by anyone else.
  String get _rawAccessToken => null;

  /// Whether or not the user can be authenticated by using Firebase email and password.
  bool get _hasEmailPasswordCredential => __hasEmailPasswordCredential;

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
        _auth._updateStore(this);
      }

      return token;
    } on FirebaseAuthError catch (e) {
      _signOutIfTokenIsInvalid(e);
      rethrow;
    }
  }

  void _updateWithUserDataResponse(List<UserDataResponse> response) {
    final UserDataResponse user = response.first;

    _userInfo = UserInfoImpl(
      uid: user.localId,
      email: user.email,
      isEmailVerified: user.emailVerified,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      phoneNumber: user.phoneNumber,
    );
    __hasEmailPasswordCredential = user.passwordHash?.isNotEmpty ?? false;
    _metadata = UserMetadataImpl(
      lastSignInDate: DateTime.fromMillisecondsSinceEpoch(user.lastLoginAt, isUtc: true),
      creationDate: DateTime.fromMillisecondsSinceEpoch(user.createdAt, isUtc: true),
    );

    _providerData = user.providerUserInfo.map((ProviderUserInfo info) => info.userInfo).toList();
  }

  static Serializer<FirebaseUser> get serializer => _$firebaseUserSerializer;

  void _signOutIfTokenIsInvalid(FirebaseAuthError e) {
    if (e is UserNotFound || e is UserDisabled || e is InvalidIdToken || e is TokenExpired) {
      print('Invalid user token detectedm user is automatically signed out.');
      _auth._signOutByForce(uid);
    }
  }

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

mixin UserInfoMixin implements UserInfo {
  UserInfo _userInfo;

  @override
  String get uid => _userInfo.uid;

  @override
  ProviderType get providerId => _userInfo.providerId;

  @override
  String get displayName => _userInfo.displayName;

  @override
  String get photoUrl => _userInfo.photoUrl;

  @override
  String get email => _userInfo.email;

  @override
  String get phoneNumber => _userInfo.phoneNumber;

  @override
  bool get isEmailVerified => _userInfo.isEmailVerified;
}
