// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

class FirebaseAuth {
  FirebaseAuth._(this._app, this._firebaseAuthApi, this._configuration)
      : _urlPresenter = _app.platformDependencies.authUrlPresenter,
        _userStorage = UserStorage(userBox: _app.platformDependencies.box, appName: _app.name);

  factory FirebaseAuth.getInstance(FirebaseApp app) {
    final AuthRequestConfiguration configuration =
        AuthRequestConfiguration(apiKey: app.options.apiKey, languageCode: app.platformDependencies.locale);

    final HttpService identityToolkitService =
        HttpService(configuration: configuration, host: 'https://identitytoolkit.googleapis.com/v1/accounts');

    final FirebaseAuthApi firebaseAuthApi =
        FirebaseAuthApi(firebaseAuthService: FirebaseAuthService(service: identityToolkitService));

    final FirebaseAuth auth = FirebaseAuth._(app, firebaseAuthApi, configuration);
    _instances[FirebaseApp.instance.name] = auth;
    _authStateChangedControllers[FirebaseApp.instance.name] = StreamController<FirebaseUser>.broadcast();
    return auth;
  }

  // ignore: prefer_constructors_over_static_methods
  static FirebaseAuth get instance {
    if (_instances.containsKey(FirebaseApp.instance.name)) {
      return _instances[FirebaseApp.instance.name];
    } else {
      return FirebaseAuth.getInstance(FirebaseApp.instance);
    }
  }

  final FirebaseApp _app;
  final FirebaseAuthApi _firebaseAuthApi;
  final UserStorage _userStorage;
  final AuthRequestConfiguration _configuration;

  AuthUrlPresenter _urlPresenter;
  FirebaseUser _currentUser;
  String _lastNotifiedUserToken;
  bool _autoRefreshTokens = false;

  static final Map<String, FirebaseAuth> _instances = <String, FirebaseAuth>{};
  static final Map<String, StreamController<FirebaseUser>> _authStateChangedControllers =
      <String, StreamController<FirebaseUser>>{};

  /// Receive [FirebaseUser] each time the user signIn or signOut
  Stream<FirebaseUser> get onAuthStateChanged => _authStateChangedControllers[_app.name].stream;

  /// Asynchronously creates and becomes an anonymous user.
  ///
  /// If there is already an anonymous user signed in, that user will be
  /// returned instead. If there is any other existing user signed in, that
  /// user will be signed out.
  ///
  /// **Important**: You must enable Anonymous accounts in the Auth section
  /// of the Firebase console before being able to use them.
  ///
  /// Errors:
  ///   • [OperationNotAllowed] - Indicates that Anonymous accounts are not enabled.
  Future<AuthResult> signInAnonymously() async {
    if (_currentUser != null && _currentUser.isAnonymous) {
      return _ensureUserPersistence(AuthResult._(_currentUser));
    }

    final BaseAuthRequest request = BaseAuthRequest();
    final BaseAuthResponse response = await _firebaseAuthApi.signUpNewUser(request);

    final DateTime accessTokenExpirationDate = DateTime.now().add(Duration(seconds: response.expiresIn)).toUtc();
    final FirebaseUser user = await _completeSignInWithAccessToken(
      response.idToken,
      accessTokenExpirationDate,
      response.refreshToken,
      anonymous: true,
    );
    return _ensureUserPersistence(AuthResult._(user, AdditionalUserInfoImpl.newAnonymous()));
  }

  /// Synchronously gets the cached current user, or null if there is none.
  FirebaseUser get currentUser => _currentUser;

  AuthResult _ensureUserPersistence(AuthResult result) {
    _updateCurrentUser(result.user, false, true);
    return result;
  }

  void _updateCurrentUser(FirebaseUser user, bool force, bool saveToDisk) {
    if (user == _currentUser) {
      _possiblyPostAuthStateChangeNotification();
      return;
    }

    if (saveToDisk) {
      _userStorage.save(user);
    }

    if (force) {
      _currentUser = user;
      _possiblyPostAuthStateChangeNotification();
    }
  }

  void _possiblyPostAuthStateChangeNotification() {
    final String token = _currentUser._rawAccessToken;
    if (_lastNotifiedUserToken == token || (token != null && _lastNotifiedUserToken == token)) {
      return;
    }
    _lastNotifiedUserToken = token;
    if (_autoRefreshTokens) {
      // Schedule new refresh task after successful attempt.
      _scheduleAutoTokenRefresh();
    }

    _dispatchUser(_currentUser);
  }

  void _scheduleAutoTokenRefresh() {}

  void _dispatchUser(FirebaseUser user) {
    _authStateChangedControllers[_app.name].add(user);
  }

  /// Completes a sign-in flow once we have [accessToken] and [refreshToken] for the user.
  Future<FirebaseUser> _completeSignInWithAccessToken(
      String accessToken, DateTime accessTokenExpirationDate, String refreshToken,
      {bool anonymous}) {
    return FirebaseUser._retrieveUserWithAuth(
      this,
      accessToken,
      accessTokenExpirationDate,
      refreshToken,
      anonymous: anonymous,
    );
  }

  /// Force signs out the current user.
  void _signOutByForce(String uid) {
    if (_currentUser.uid != uid) {
      return;
    }

    _updateCurrentUser(null, true, true);
  }

  /// Updates the store for the given user.
  void _updateStore(FirebaseUser user) {
    if (_currentUser != user) {
      // No-op if the user is no longer signed in. This is not considered an error as we don't check
      // whether the user is still current on other callbacks of user operations either.
      return;
    }

    _userStorage.save(user);
    _possiblyPostAuthStateChangeNotification();
  }
}
