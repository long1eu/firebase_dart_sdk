// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth;

abstract class EmailAuthProvider {
  /// Creates an [AuthCredential] for an email & password sign in.
  static AuthCredential getCredential({@required String email, @required String password}) {
    return EmailPasswordAuthCredential.withPassword(email: email, password: password);
  }

  /// Creates an [AuthCredential] for an email & link sign in.
  static AuthCredential getCredentialWithLink({@required String email, @required String link}) {
    return EmailPasswordAuthCredential.withLink(email: email, link: link);
  }
}

class FacebookAuthProvider {
  /// Creates an [AuthCredential] for a Facebook sign in.
  static AuthCredential getCredential(String accessToken) {
    return FacebookAuthCredential(accessToken);
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
    return GameCenterAuthCredential(
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
    return GithubAuthCredential(token);
  }
}

class GoogleAuthProvider {
  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential getCredential({@required String idToken, @required String accessToken}) {
    return GoogleAuthCredential(idToken: idToken, accessToken: accessToken);
  }
}

class OAuthProvider {
  /// Creates an [AuthCredential] corresponding to the specified provider ID.
  static AuthCredential getCredential(String providerId) {
    assert(
        providerId != ProviderType.facebook,
        'Sign in with Facebook is not supported via generic IDP; the Facebook TOS dictate that you must use the '
        'Facebook iOS SDK for Facebook login.');
    assert(providerId != ProviderType.apple || !Platform.isIOS,
        'Sign in with Apple is not supported via generic IDP; You must use the Apple iOS SDK for Sign in with Apple.');

    return OAuthCredential(providerId: providerId);
  }

  static AuthCredential getCredentialWithAccessToken(
      {@required String providerId, @required String accessToken, String idToken}) {
    return OAuthCredential(providerId: providerId, idToken: idToken, accessToken: accessToken);
  }
}

class PhoneNumberProvider {
  static AuthCredential getCredential({@required String verificationId, @required String verificationCode}) {
    return PhoneAuthCredential(verificationId: verificationId, verificationCode: verificationCode);
  }

  static AuthCredential getCredentialWithTemporaryProof({@required String temporaryProof, @required String phoneNumber}) {
    return PhoneAuthCredential(temporaryProof: temporaryProof, phoneNumber: phoneNumber);
  }
}

class TwitterAuthProvider {
  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential getCredential({@required String authToken, @required String authTokenSecret}) {
    return TwitterAuthCredential(authToken: authToken, authTokenSecret: authTokenSecret);
  }
}
