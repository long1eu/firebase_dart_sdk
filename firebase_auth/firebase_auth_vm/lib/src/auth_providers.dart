// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth_vm;

/// A base class which all providers must extend.
abstract class AuthProvider {
  /// Constructs a new instance with a given provider identifier.
  const AuthProvider({@required this.providerId, @required this.signInMethod});

  /// The provider ID.
  final String providerId;

  final String signInMethod;
}

class EmailAuthProvider extends AuthProvider {
  const EmailAuthProvider() : super(providerId: ProviderType.password, signInMethod: ProviderMethod.password);

  /// Creates an [AuthCredential] for an email & password sign in.
  static AuthCredential credential({@required String email, @required String password}) {
    return EmailPasswordAuthCredential._(email: email, password: password);
  }

  /// Creates an [AuthCredential] for an email & link sign in.
  static AuthCredential credentialWithLink({@required String email, @required String link}) {
    return EmailPasswordAuthCredential._(email: email, link: link);
  }
}

class FacebookAuthProvider extends AuthProvider {
  const FacebookAuthProvider({this.scopes = const <String>[], this.parameters = const <dynamic, dynamic>{}})
      : super(providerId: ProviderType.facebook, signInMethod: ProviderMethod.facebook);

  /// The OAuth scopes
  final List<String> scopes;

  /// The OAuth custom parameters to pass in a Google OAuth request for
  /// popup and redirect sign-in operations.
  final Map<dynamic, dynamic> parameters;

  /// Creates an [AuthCredential] for a Facebook sign in.
  static AuthCredential credential(String accessToken) {
    return FacebookAuthCredential._(accessToken);
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('scopes', scopes)
          ..add('parameters', parameters))
        .toString();
  }
}

class GameCenterAuthProvider extends AuthProvider {
  const GameCenterAuthProvider() : super(providerId: ProviderType.gameCenter, signInMethod: ProviderMethod.gameCenter);

  /// Creates an [AuthCredential] for a GameCenter sign in.
  static AuthCredential credential({
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

class GithubAuthProvider extends AuthProvider {
  const GithubAuthProvider({this.scopes = const <String>[], this.parameters = const <dynamic, dynamic>{}})
      : super(providerId: ProviderType.github, signInMethod: ProviderMethod.github);

  /// The OAuth scopes
  final List<String> scopes;

  /// The OAuth custom parameters to pass in a Github OAuth request for
  /// popup and redirect sign-in operations.
  final Map<dynamic, dynamic> parameters;

  /// Creates an [AuthCredential] for a GitHub sign in.
  static AuthCredential credential(String token) {
    return GithubAuthCredential._(token);
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('scopes', scopes)
          ..add('parameters', parameters))
        .toString();
  }
}

class GoogleAuthProvider extends AuthProvider {
  const GoogleAuthProvider({this.scopes = const <String>[], this.parameters = const <dynamic, dynamic>{}})
      : super(providerId: ProviderType.google, signInMethod: ProviderMethod.google);

  /// The OAuth scopes
  final List<String> scopes;

  /// The OAuth custom parameters to pass in a Google OAuth request for
  /// popup and redirect sign-in operations.
  final Map<dynamic, dynamic> parameters;

  /// Creates an [AuthCredential] for a Google sign in.
  static AuthCredential credential({@required String idToken, @required String accessToken}) {
    return GoogleAuthCredential._(idToken: idToken, accessToken: accessToken);
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('scopes', scopes)
          ..add('parameters', parameters))
        .toString();
  }
}

class OAuthProvider extends AuthProvider {
  const OAuthProvider(String providerId, {this.scopes = const <String>[], this.parameters = const <dynamic, dynamic>{}})
      : super(providerId: providerId, signInMethod: ProviderMethod.oauth);

  /// The OAuth scopes
  final List<String> scopes;

  /// The OAuth custom parameters to pass in a OAuth request for
  /// popup and redirect sign-in operations.
  final Map<dynamic, dynamic> parameters;

  static AuthCredential credentialWithAccessToken({
    @required String providerId,
    @required String accessToken,
    String idToken,
  }) {
    return OAuthCredential._(
      providerId: providerId,
      accessToken: accessToken,
      idToken: idToken,
    );
  }

  static AuthCredential credentialWithNonce({
    @required String providerId,
    @required String accessToken,
    @required String rawNonce,
    @required String idToken,
  }) {
    return OAuthCredential._(
      providerId: providerId,
      accessToken: accessToken,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('scopes', scopes)
          ..add('parameters', parameters))
        .toString();
  }
}

class PhoneAuthProvider extends AuthProvider {
  const PhoneAuthProvider() : super(providerId: ProviderType.phone, signInMethod: ProviderMethod.phone);

  static AuthCredential credential({@required String verificationId, @required String verificationCode}) {
    return PhoneAuthCredential._(verificationId: verificationId, verificationCode: verificationCode);
  }

  static AuthCredential credentialWithTemporaryProof({@required String temporaryProof, @required String phoneNumber}) {
    return PhoneAuthCredential._(temporaryProof: temporaryProof, phoneNumber: phoneNumber);
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod))
        .toString();
  }
}

class TwitterAuthProvider extends AuthProvider {
  const TwitterAuthProvider({this.parameters = const <dynamic, dynamic>{}})
      : super(providerId: ProviderType.twitter, signInMethod: ProviderMethod.twitter);

  /// The OAuth custom parameters to pass in a Twitter OAuth request for
  /// popup and redirect sign-in operations.
  final Map<dynamic, dynamic> parameters;

  /// Creates an [AuthCredential] for Twitter sign in.
  static AuthCredential credential({@required String authToken, @required String authTokenSecret}) {
    return TwitterAuthCredential._(authToken: authToken, authTokenSecret: authTokenSecret);
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('providerId', providerId)
          ..add('signInMethod', signInMethod)
          ..add('parameters', parameters))
        .toString();
  }
}
