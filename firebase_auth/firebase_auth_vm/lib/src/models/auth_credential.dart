// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth_vm;

/// Represents a credential.
mixin AuthCredential {
  /// The identity provider for the credential
  String get providerId;

  @memoized
  Map<String, dynamic> get json;

  /// Called immediately before a request to the verifyAssertion endpoint is made.
  ///
  /// Implementers should update the passed request instance with their credentials.
  void prepareVerifyAssertionRequest(
      IdentitytoolkitRelyingpartyVerifyAssertionRequest request);
}

/// Internal implementation of [AuthCredential] for Email/Password credentials.
abstract class EmailPasswordAuthCredential with AuthCredential {
  factory EmailPasswordAuthCredential._(
      {@required String email, String password, String link}) {
    return _$EmailPasswordAuthCredentialImpl(
        (EmailPasswordAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.password
        ..email = email
        ..password = password
        ..link = link;
    });
  }

  /// The user's email address.
  String get email;

  /// The user's password.
  @nullable
  String get password;

  /// The email sign-in link.
  @nullable
  String get link;
}

/// Internal implementation of [AuthCredential] for the Facebook IdP.
abstract class FacebookAuthCredential with AuthCredential {
  factory FacebookAuthCredential._(String accessToken) {
    return _$FacebookAuthCredentialImpl((FacebookAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.facebook
        ..accessToken = accessToken;
    });
  }

  /// The Access Token from Facebook.
  String get accessToken;
}

/// Internal implementation of [AuthCredential] for Game Center credentials.
abstract class GameCenterAuthCredential with AuthCredential {
  factory GameCenterAuthCredential._({
    @required String playerId,
    @required String publicKeyUrl,
    @required Uint8List signature,
    @required Uint8List salt,
    @required DateTime timestamp,
    @required String displayName,
  }) {
    return _$GameCenterAuthCredentialImpl(
        (GameCenterAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.gameCenter
        ..playerId = playerId
        ..publicKeyUrl = publicKeyUrl
        ..signature = signature
        ..salt = salt
        ..timestamp = timestamp
        ..displayName = displayName;
    });
  }

  /// The ID of the Game Center local player.
  String get playerId;

  /// The URL for the public encryption key.
  String get publicKeyUrl;

  /// The verification signature data generated.
  Uint8List get signature;

  /// A random string used to compute the hash and keep it randomized.
  Uint8List get salt;

  /// The date and time that the signature was created.
  DateTime get timestamp;

  /// The date and time that the signature was created.
  String get displayName;
}

/// Internal implementation of [AuthCredential] for GitHub credentials.
abstract class GithubAuthCredential with AuthCredential {
  factory GithubAuthCredential._(String token) {
    return _$GithubAuthCredentialImpl((GithubAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.github
        ..token = token;
    });
  }

  /// The GitHub OAuth access token.
  String get token;
}

/// Internal implementation of [AuthCredential] for the Google IdP.
abstract class GoogleAuthCredential with AuthCredential {
  factory GoogleAuthCredential._(
      {@required String idToken, @required String accessToken}) {
    return _$GoogleAuthCredentialImpl((GoogleAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.google
        ..idToken = idToken
        ..accessToken = accessToken;
    });
  }

  /// The ID Token obtained from Google.
  String get idToken;

  /// The Access Token obtained from Google.
  String get accessToken;
}

/// Internal implementation of [AuthCredential] for GitHub credentials.
abstract class OAuthCredential with AuthCredential {
  factory OAuthCredential._({
    @required String providerId,
    List<String> scopes,
    Map<String, String> customParameters,
    String sessionId,
    String requestUri,
    String idToken,
    String accessToken,
    String secret,
    String pendingToken,
    String nonce,
  }) {
    return _$OAuthCredentialImpl((OAuthCredentialImplBuilder b) {
      b
        ..providerId = providerId
        ..scopes = scopes == null ? null : ListBuilder<String>(scopes)
        ..customParameters = customParameters == null
            ? null
            : MapBuilder<String, String>(customParameters)
        ..sessionId = sessionId
        ..requestUri = requestUri
        ..idToken = idToken
        ..accessToken = accessToken
        ..secret = secret
        ..pendingToken = pendingToken
        ..nonce = nonce;
    });
  }

  /// Used to configure the OAuth scopes.
  @nullable
  BuiltList<String> get scopes;

  /// Used to configure the OAuth custom parameters.
  @nullable
  BuiltMap<String, String> get customParameters;

  /// The session ID used when completing the headful-lite flow.
  @nullable
  String get sessionId;

  /// A string representation of the response URL corresponding to this OAuthCredential.
  @nullable
  String get requestUri;

  @nullable
  String get idToken;

  @nullable
  String get accessToken;

  @nullable
  String get secret;

  /// The pending token used when completing the headful-lite flow.
  ///
  /// Where the IdP response is encrypted.
  @nullable
  String get pendingToken;

  @nullable
  String get nonce;
}

/// The SAML Auth credential class.
abstract class SamlAuthCredential with AuthCredential {
  factory SamlAuthCredential._({
    @required String providerId,
    @required String signInMethod,
    @required String pendingToken,
  }) {
    return _$SamlAuthCredentialImpl((SamlAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.phone
        ..providerId = providerId
        ..signInMethod = signInMethod
        ..pendingToken = pendingToken;
    });
  }

  String get signInMethod;

  String get pendingToken;
}

abstract class PhoneAuthCredential with AuthCredential {
  factory PhoneAuthCredential._({
    String verificationId,
    String verificationCode,
    String temporaryProof,
    String phoneNumber,
  }) {
    return _$PhoneAuthCredentialImpl((PhoneAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.phone
        ..verificationId = verificationId
        ..verificationCode = verificationCode
        ..temporaryProof = temporaryProof
        ..phoneNumber = phoneNumber;
    });
  }

  /// The verification ID obtained from invoking [FirebaseAuth.verifyPhoneNumber]
  @nullable
  String get verificationId;

  /// The verification code provided by the user.
  @nullable
  String get verificationCode;

  /// The a temporary proof code pertaining to this credential, returned from the backend.
  @nullable
  String get temporaryProof;

  /// The a phone number pertaining to this credential, returned from the backend.
  @nullable
  String get phoneNumber;
}

abstract class TwitterAuthCredential with AuthCredential {
  factory TwitterAuthCredential._(
      {@required String authToken, @required String authTokenSecret}) {
    return _$TwitterAuthCredentialImpl((TwitterAuthCredentialImplBuilder b) {
      b
        ..providerId = ProviderType.twitter
        ..authToken = authToken
        ..authTokenSecret = authTokenSecret;
    });
  }

  String get authToken;

  String get authTokenSecret;
}
