// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth;

/// Represents a credential.
mixin AuthCredential {
  /// The identity provider for the credential
  String get provider;

  @memoized
  Map<String, dynamic> get json;

  /// A request to the verifyAssertion endpoint uses this as the postBody parameter.
  String get postBody => json.keys.map((String key) => '$key=${json[key]}').join('&');
}

/// Internal implementation of [AuthCredential] for Email/Password credentials.
abstract class EmailPasswordAuthCredential with AuthCredential {
  factory EmailPasswordAuthCredential.withPassword({@required String email, @required String password}) {
    return _$EmailPasswordAuthCredentialImpl((EmailPasswordAuthCredentialImplBuilder b) {
      b
        ..provider = ProviderType.password
        ..email = email
        ..password = password;
    });
  }

  factory EmailPasswordAuthCredential.withLink({@required String email, @required String link}) {
    return _$EmailPasswordAuthCredentialImpl((EmailPasswordAuthCredentialImplBuilder b) {
      b
        ..provider = ProviderType.password
        ..email = email
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

  @override
  String get postBody {
    throw FirebaseAuthError('NOT_IMPLEMENTED', 'You should not use the postBody of a EmailPasswordAuthCredential.');
  }
}

/// Internal implementation of [AuthCredential] for the Facebook IdP.
abstract class FacebookAuthCredential with AuthCredential {
  factory FacebookAuthCredential(String accessToken) {
    return _$FacebookAuthCredentialImpl((FacebookAuthCredentialImplBuilder b) {
      b
        ..accessToken = accessToken
        ..provider = ProviderType.facebook;
    });
  }

  /// The Access Token from Facebook.
  String get accessToken;
}

/// Internal implementation of [AuthCredential] for Game Center credentials.
abstract class GameCenterAuthCredential with AuthCredential {
  factory GameCenterAuthCredential({
    @required String playerId,
    @required String publicKeyUrl,
    @required Uint8List signature,
    @required Uint8List salt,
    @required DateTime timestamp,
    @required String displayName,
  }) {
    return _$GameCenterAuthCredentialImpl((GameCenterAuthCredentialImplBuilder b) {
      b
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

  @override
  String get postBody {
    throw FirebaseAuthError('NOT_IMPLEMENTED', 'You should not use the postBody of a GameCenterAuthCredential.');
  }
}

/// Internal implementation of [AuthCredential] for GitHub credentials.
abstract class GithubAuthCredential with AuthCredential {
  factory GithubAuthCredential(String token) {
    return _$GithubAuthCredentialImpl((GithubAuthCredentialImplBuilder b) {
      b
        ..provider = ProviderType.github
        ..token = token;
    });
  }

  /// The GitHub OAuth access token.
  String get token;
}

/// Internal implementation of [AuthCredential] for the Google IdP.
abstract class GoogleAuthCredential with AuthCredential {
  factory GoogleAuthCredential({@required String idToken, @required String accessToken}) {
    return _$GoogleAuthCredentialImpl((GoogleAuthCredentialImplBuilder b) {
      b
        ..provider = ProviderType.google
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
  factory OAuthCredential({
    @required String providerId,
    String idToken,
    String accessToken,
    String secret,
    String pendingToken,
  }) {
    return _$OAuthCredentialImpl((OAuthCredentialImplBuilder b) {
      b
        ..provider = providerId
        ..idToken = idToken
        ..accessToken = accessToken
        ..secret = secret
        ..pendingToken = pendingToken;
    });
  }

  factory OAuthCredential.withSession({
    @required String providerId,
    @required String sessionId,
    @required String oAuthResponseURLString,
  }) {
    return _$OAuthCredentialImpl((OAuthCredentialImplBuilder b) {
      b
        ..provider = providerId
        ..sessionId = sessionId
        ..oAuthResponseURLString = oAuthResponseURLString
      ;
    });
  }

  /// The provider ID associated with the credential being created.
  @override
  String get provider;

  /// Used to configure the OAuth scopes.
  @nullable
  BuiltList<String> get scopes;

  /// Used to configure the OAuth custom parameters.
  @nullable
  BuiltMap<String, String> get customParameters;

  /// The session ID used when completing the headful-lite flow.
  String get sessionId;

  /// A string representation of the response URL corresponding to this OAuthCredential.
  String get oAuthResponseURLString;

  String get idToken;

  String get accessToken;

  String get secret;

  /// The pending token used when completing the headful-lite flow.
  String get pendingToken;
}

abstract class PhoneAuthCredential with AuthCredential {
  factory PhoneAuthCredential({
    String verificationId,
    String verificationCode,
    String temporaryProof,
    String phoneNumber,
  }) {
    return _$PhoneAuthCredentialImpl((PhoneAuthCredentialImplBuilder b) {
      b
        ..provider = ProviderType.phone
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
  factory TwitterAuthCredential({@required String authToken, @required String authTokenSecret}) {
    return _$TwitterAuthCredentialImpl((TwitterAuthCredentialImplBuilder b) {
      b
        ..provider = ProviderType.twitter
        ..authToken = authToken
        ..authTokenSecret = authTokenSecret;
    });
  }

  String get authToken;

  String get authTokenSecret;
}
