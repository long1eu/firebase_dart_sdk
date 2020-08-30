// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth_vm;

abstract class EmailAuthProvider {
  /// Creates an [AuthCredential] for an email & password sign in.
  static AuthCredential getCredential({@required String email, @required String password}) {
    return EmailPasswordAuthCredential._(email: email, password: password);
  }

  /// Creates an [AuthCredential] for an email & link sign in.
  static AuthCredential getCredentialWithLink({@required String email, @required String link}) {
    return EmailPasswordAuthCredential._(email: email, link: link);
  }
}

class FacebookAuthProvider {
  /// Creates an [AuthCredential] for a Facebook sign in.
  static AuthCredential getCredential(String accessToken) {
    return FacebookAuthCredential._(accessToken);
  }
}

class GameCenterAuthProvider {
  /// Creates an [AuthCredential] for a Facebook sign in.
  static AuthCredential getCredential({
    @required String playerId,
    @required String publicKeyUrl,
    @required Uint8List signature,
    @required Uint8List salt,
    @required DateTime timestamp,
    @required String displayName,
  }) {
    return GameCenterAuthCredential._(
      playerId: playerId,
      publicKeyUrl: publicKeyUrl,
      signature: signature,
      salt: salt,
      timestamp: timestamp,
      displayName: displayName,
    );
  }
}

class GithubAuthProvider {
  /// Creates an [AuthCredential] for a GitHub sign in.
  static AuthCredential getCredential(String token) {
    return GithubAuthCredential._(token);
  }
}

class GoogleAuthProvider {
  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential getCredential({@required String idToken, @required String accessToken}) {
    return GoogleAuthCredential._(idToken: idToken, accessToken: accessToken);
  }
}

class OAuthProvider {
  static AuthCredential getCredentialWithAccessToken({
    @required String providerId,
    @required String accessToken,
    List<String> scopes,
    Map<String, String> customParameters,
    String sessionId,
    String requestUri,
    String idToken,
    String secret,
    String pendingToken,
    String nonce,
  }) {
    assert(nonce == null || pendingToken == null);
    return OAuthCredential._(
      providerId: providerId,
      accessToken: accessToken,
      scopes: scopes,
      customParameters: customParameters,
      sessionId: sessionId,
      requestUri: requestUri,
      idToken: idToken,
      secret: secret,
      pendingToken: pendingToken,
      nonce: nonce,
    );
  }

  static AuthCredential getCredentialOAuth1({
    @required String providerId,
    @required String oauthToken,
    @required String oauthTokenSecret,
  }) {
    return OAuthCredential._(
      providerId: providerId,
      accessToken: oauthToken,
      secret: oauthTokenSecret,
    );
  }
}

class PhoneAuthProvider {
  static AuthCredential getCredential({
    @required String verificationId,
    @required String verificationCode,
  }) {
    return PhoneAuthCredential._(verificationId: verificationId, verificationCode: verificationCode);
  }

  static AuthCredential getCredentialWithTemporaryProof({
    @required String temporaryProof,
    @required String phoneNumber,
  }) {
    return PhoneAuthCredential._(temporaryProof: temporaryProof, phoneNumber: phoneNumber);
  }
}

class TwitterAuthProvider {
  /// Creates an [AuthCredential] for Twitter sign in.
  static AuthCredential getCredential({
    @required String authToken,
    @required String authTokenSecret,
  }) {
    return TwitterAuthCredential._(authToken: authToken, authTokenSecret: authTokenSecret);
  }
}
