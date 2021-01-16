// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of firebase_auth_vm;

/// Represents a credential.
abstract class AuthCredential {
  /// The identity provider for the credential
  String get providerId;

  /// The authentication sign in method for the credential. For example,
  /// 'password', or 'emailLink'. This corresponds to the sign-in method
  /// identifier returned in [FirebaseAuth.fetchSignInMethodsForEmail].
  String get signInMethod;

  Map<String, dynamic> get json;

  /// Called immediately before a request to the verifyAssertion endpoint is made.
  ///
  /// Implementers should update the passed request instance with their credentials.
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request);
}

/// Internal implementation of [AuthCredential] for Email/Password credentials.
class EmailPasswordAuthCredential implements AuthCredential {
  EmailPasswordAuthCredential._({
    @required this.email,
    this.password,
    this.link,
  })  : assert(password != null || link != null, 'You must either provide a password or the email link.'),
        providerId = ProviderType.password,
        signInMethod = link == null ? ProviderMethod.emailLink : ProviderMethod.password;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The user's email address.
  final String email;

  /// The user's password.
  /*@nullable*/
  final String password;

  /// The email sign-in link.
  /*@nullable*/
  final String link;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    throw FirebaseAuthError('NOT_IMPLEMENTED', 'You should not use the postBody of a EmailPasswordAuthCredential.');
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'email': email,
      if (password != null) 'password': password,
      if (link != null) 'link': link,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(EmailPasswordAuthCredential)
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('email', email)
          ..add('password', password)
          ..add('link', link))
        .toString();
  }
}

/// Internal implementation of [AuthCredential] for the Facebook IdP.
class FacebookAuthCredential implements AuthCredential {
  FacebookAuthCredential._(this.accessToken)
      : providerId = ProviderType.facebook,
        signInMethod = ProviderMethod.facebook;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The Access Token from Facebook.
  final String accessToken;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    request
      ..postBody = 'providerId=$providerId&access_token=$accessToken'
      ..requestUri = 'http://localhost';
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'accessToken': accessToken,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(FacebookAuthCredential)
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('accessToken', accessToken))
        .toString();
  }
}

/// Internal implementation of [AuthCredential] for Game Center credentials.
class GameCenterAuthCredential implements AuthCredential {
  GameCenterAuthCredential._({
    @required this.playerId,
    @required this.publicKeyUrl,
    @required this.signature,
    @required this.salt,
    @required this.timestamp,
    @required this.displayName,
  })  : providerId = ProviderType.gameCenter,
        signInMethod = ProviderMethod.gameCenter;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The ID of the Game Center local player.
  final String playerId;

  /// The URL for the public encryption key.
  final String publicKeyUrl;

  /// The verification signature data generated.
  final Uint8List signature;

  /// A random string used to compute the hash and keep it randomized.
  final Uint8List salt;

  /// The date and time that the signature was created.
  final DateTime timestamp;

  /// A string chosen by the player to identify themselves to other players.
  final String displayName;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    throw FirebaseAuthError('NOT_IMPLEMENTED', 'You should not use the postBody of a GameCenterAuthCredential.');
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'playerId': playerId,
      'publicKeyUrl': publicKeyUrl,
      'signature': signature,
      'salt': salt,
      'timestamp': timestamp,
      'displayName': displayName,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(GameCenterAuthCredential)
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('playerId', playerId)
          ..add('publicKeyUrl', publicKeyUrl)
          ..add('signature', signature)
          ..add('salt', salt)
          ..add('timestamp', timestamp)
          ..add('displayName', displayName))
        .toString();
  }
}

/// Internal implementation of [AuthCredential] for GitHub credentials.
class GithubAuthCredential implements AuthCredential {
  GithubAuthCredential._(this.token)
      : providerId = ProviderType.github,
        signInMethod = ProviderMethod.github;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The GitHub OAuth access token.
  final String token;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    request
      ..postBody = 'providerId=$providerId&access_token=$token'
      ..requestUri = 'http://localhost';
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'token': token,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(GithubAuthCredential) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('token', token))
        .toString();
  }
}

/// Internal implementation of [AuthCredential] for the Google IdP.
class GoogleAuthCredential implements AuthCredential {
  GoogleAuthCredential._({@required this.idToken, @required this.accessToken})
      : providerId = ProviderType.google,
        signInMethod = ProviderMethod.google;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The ID Token obtained from Google.
  final String idToken;

  /// The Access Token obtained from Google.
  final String accessToken;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    request
      ..postBody = 'providerId=$providerId&id_token=$idToken&access_token=$accessToken'
      ..requestUri = 'http://localhost';
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'idToken': idToken,
      'accessToken': accessToken,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(GoogleAuthCredential) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('idToken', idToken)
          ..add('accessToken', accessToken))
        .toString();
  }
}

/// Internal implementation of [AuthCredential] for GitHub credentials.
class OAuthCredential implements AuthCredential {
  OAuthCredential._({
    @required this.providerId,
    this.scopes,
    this.customParameters,
    this.sessionId,
    this.requestUri,
    this.idToken,
    this.accessToken,
    this.secret,
    this.pendingToken,
    this.nonce,
  }) : signInMethod = ProviderMethod.oauth;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// Used to configure the OAuth scopes.
  /*@nullable*/
  final List<String> scopes;

  /// Used to configure the OAuth custom parameters.
  /*@nullable*/
  final Map<String, String> customParameters;

  /// The session ID used when completing the headful-lite flow.
  /*@nullable*/
  final String sessionId;

  /// A string representation of the response URL corresponding to this OAuthCredential.
  /*@nullable*/
  final String requestUri;

  /*@nullable*/
  final String idToken;

  /*@nullable*/
  final String accessToken;

  /*@nullable*/
  final String secret;

  /// The pending token used when completing the headful-lite flow.
  ///
  /// Where the IdP response is encrypted.
  /*@nullable*/
  final String pendingToken;

  /*@nullable*/
  final String nonce;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    final Map<String, String> fields = <String, String>{
      if (customParameters != null) ...customParameters,
      if (scopes != null && scopes.isNotEmpty) 'scope': scopes.join(' '),
      if (idToken != null) 'id_token': idToken,
      if (secret != null) 'oauth_token_secret': secret,
      'providerId': providerId,
      'access_token': accessToken,
    };

    request
      ..postBody = fields.keys.map((String key) => '$key=${fields[key]}').join('&')
      ..requestUri = requestUri ?? 'http://localhost'
      ..sessionId = sessionId
      ..pendingIdToken = pendingToken;
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'scopes': scopes,
      'customParameters': customParameters,
      'sessionId': sessionId,
      'requestUri': requestUri,
      'idToken': idToken,
      'accessToken': accessToken,
      'secret': secret,
      'pendingToken': pendingToken,
      'nonce': nonce,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(OAuthCredential)
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('scopes', scopes)
          ..add('customParameters', customParameters)
          ..add('sessionId', sessionId)
          ..add('requestUri', requestUri)
          ..add('idToken', idToken)
          ..add('accessToken', accessToken)
          ..add('secret', secret)
          ..add('pendingToken', pendingToken)
          ..add('nonce', nonce))
        .toString();
  }
}

class PhoneAuthCredential implements AuthCredential {
  PhoneAuthCredential._({
    this.verificationId,
    this.verificationCode,
    this.temporaryProof,
    this.phoneNumber,
  })  : providerId = ProviderType.phone,
        signInMethod = ProviderMethod.phone;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The verification ID obtained from invoking [FirebaseAuth.verifyPhoneNumber]
  /*@nullable*/
  final String verificationId;

  /// The verification code provided by the user.
  /*@nullable*/
  final String verificationCode;

  /// The a temporary proof code pertaining to this credential, returned from the backend.
  /*@nullable*/
  final String temporaryProof;

  /// The a phone number pertaining to this credential, returned from the backend.
  /*@nullable*/
  final String phoneNumber;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    throw FirebaseAuthError('NOT_IMPLEMENTED', 'You should not use the postBody of a PhoneAuthCredential.');
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'verificationId': verificationId,
      'verificationCode': verificationCode,
      'temporaryProof': temporaryProof,
      'phoneNumber': phoneNumber,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(PhoneAuthCredential)
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('verificationId', verificationId)
          ..add('verificationCode', verificationCode)
          ..add('temporaryProof', temporaryProof)
          ..add('phoneNumber', phoneNumber))
        .toString();
  }
}

/// Internal implementation of FIRAuthCredential for Twitter credentials.
class TwitterAuthCredential implements AuthCredential {
  TwitterAuthCredential._({@required this.authToken, @required this.authTokenSecret})
      : providerId = ProviderType.twitter,
        signInMethod = ProviderMethod.twitter;

  /// The identity provider for the credential
  @override
  final String providerId;

  /// The authentication sign in method for the credential.
  @override
  final String signInMethod;

  /// The Twitter OAuth token.
  final String authToken;

  /// The Twitter OAuth secret.
  final String authTokenSecret;

  @override
  void prepareVerifyAssertionRequest(IdentitytoolkitRelyingpartyVerifyAssertionRequest request) {
    request
      ..postBody = 'providerId=$providerId&access_token=$authToken&oauth_token_secret=$authTokenSecret'
      ..requestUri = 'http://localhost';
  }

  @override
  Map<String, dynamic> get json {
    return <String, dynamic>{
      'providerId': providerId,
      'authToken': authToken,
      'authTokenSecret': authTokenSecret,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(TwitterAuthCredential)
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('authToken', authToken)
          ..add('authTokenSecret', authTokenSecret))
        .toString();
  }
}
