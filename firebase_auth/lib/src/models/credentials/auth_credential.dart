// File created by
// Lung Razvan <long1eu>
// on 24/11/2019

part of models;

/// Represents a credential.
mixin AuthCredential {
  /// The identity provider for the credential
  ProviderType get provider;

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
}

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
