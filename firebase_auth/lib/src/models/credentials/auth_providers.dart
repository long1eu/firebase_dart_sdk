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

class TwitterAuthProvider {
  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential getCredential({@required String authToken, @required String authTokenSecret}) {
    return TwitterAuthCredential(authToken: authToken, authTokenSecret: authTokenSecret);
  }
}