// File created by
// Lung Razvan <long1eu>
// on 07/12/2019

part of firebase_auth_vm;

/// Represents the parameters for the token endpoint.
class SecureTokenRequest {
  SecureTokenRequest._({
    @required this.grantType,
    this.scope,
    this.refreshToken,
    this.code,
  });

  /// Creates an authorization code request with the given code (legacy Gitkit "ID Token").
  ///
  /// Exchanges a Gitkit "ID Token" for an STS Access Token and Refresh Token.
  factory SecureTokenRequest.withCode(String code) {
    return SecureTokenRequest._(grantType: 'authorization_code', code: code);
  }

  /// Creates a refresh request with the given refresh token.
  ///
  /// Uses an existing Refresh Token to create a new Access Token.
  factory SecureTokenRequest.withRefreshToken(String refreshToken) {
    return SecureTokenRequest._(grantType: 'refresh_token', refreshToken: refreshToken);
  }

  /// The type of grant requested.
  final String grantType;

  /// The scopes requested (a comma-delimited list of scope strings.)
  /*@nullable*/
  final String scope;

  /// The client's refresh token.
  /*@nullable*/
  final String refreshToken;

  /// The client's authorization code (legacy Gitkit "ID Token").
  /*@nullable*/
  final String code;

  Map<String, dynamic> get json {
    return <String, dynamic>{
      'grantType': grantType,
      if (scope != null) 'scope': scope,
      if (refreshToken != null) 'refreshToken': refreshToken,
      if (code != null) 'code': code,
    };
  }

  @override
  String toString() {
    return (ToStringHelper(SecureTokenRequest) //
          ..add('grantType', grantType)
          ..add('scope', scope)
          ..add('refreshToken', refreshToken)
          ..add('code', code))
        .toString();
  }
}

/// Represents the response from the token endpoint.
class SecureTokenResponse {
  SecureTokenResponse._({
    this.approximateExpirationDate,
    this.refreshToken,
    this.accessToken,
    this.idToken,
  });

  factory SecureTokenResponse.fromJson(Map<dynamic, dynamic> json) {
    if (json.containsKey('expires_in')) {
      final int seconds = int.parse(json['expires_in']);
      final Duration duration = Duration(seconds: seconds);
      json['expires_in'] = DateTime.now().toUtc().add(duration).microsecondsSinceEpoch;
    }

    return SecureTokenResponse._(
      approximateExpirationDate: json['expires_in'],
      refreshToken: json['refresh_token'],
      accessToken: json['access_token'],
      idToken: json['id_token'],
    );
  }

  /// The approximate expiration date of the access token.
  /*@nullable*/
  final DateTime approximateExpirationDate;

  /// The refresh token. (Possibly an updated one for refresh requests.)
  /*@nullable*/
  final String refreshToken;

  /// The new access token.
  /*@nullable*/
  final String accessToken;

  /// The new ID Token.
  /*@nullable*/
  final String idToken;

  @override
  String toString() {
    return (ToStringHelper(SecureTokenResponse)
          ..add('approximateExpirationDate', approximateExpirationDate)
          ..add('refreshToken', refreshToken)
          ..add('accessToken', accessToken)
          ..add('idToken', idToken))
        .toString();
  }
}
