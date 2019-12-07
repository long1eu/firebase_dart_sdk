// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of firebase_auth;

class SecureTokenApi {
  /// Creates a SecureTokenService with access and refresh tokens.
  SecureTokenApi({
    @required Client client,
    @required String accessToken,
    @required DateTime accessTokenExpirationDate,
    @required String refreshToken,
  })  : assert(client != null),
        _secureTokenService = SecureTokenService(client),
        _accessToken = accessToken,
        _accessTokenExpirationDate = accessTokenExpirationDate,
        _refreshToken = refreshToken;

  /// Creates a SecureTokenService with an authorization code.
  ///
  /// [authorizationCode] needs to be exchanged for STS tokens.
  SecureTokenApi.authorizationCode({@required Client client, @required String authorizationCode})
      : assert(client != null),
        _secureTokenService = SecureTokenService(client),
        _authorizationCode = authorizationCode;

  final SecureTokenService _secureTokenService;

  /// The currently cached access token. Or null if no token is currently cached.
  String _accessToken;

  /// An authorization code which needs to be exchanged for Secure Token Service tokens.
  String _authorizationCode;

  DateTime _accessTokenExpirationDate;

  String _refreshToken;

  /// Fetch a fresh ephemeral access token for the ID associated with this instance.
  ///
  /// The token received in should be considered short lived and not cached.
  Future<String> fetchAccessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && hasValidAccessToken) {
      return _accessToken;
    } else {
      return _requestAccessToken();
    }
  }

  /// Makes a request to STS for an access token.
  Future<String> _requestAccessToken() async {
    SecureTokenRequest request;
    if (_refreshToken.isNotEmpty) {
      request = SecureTokenRequest.withRefreshToken(_refreshToken);
    } else {
      request = SecureTokenRequest.withCode(_authorizationCode);
    }

    final SecureTokenResponse response = await _secureTokenService.refreshToken(request);
    final String newAccessToken = response.accessToken;
    if (newAccessToken != null && newAccessToken != _accessToken) {
      _accessToken = newAccessToken;
      _accessTokenExpirationDate = response.approximateExpirationDate;
    }

    final String newRefreshToken = response.refreshToken;
    if (newRefreshToken != null && newRefreshToken != _refreshToken) {
      _refreshToken = newRefreshToken;
    }

    return newAccessToken;
  }

  bool get hasValidAccessToken {
    return _accessToken != null &&
        _accessTokenExpirationDate.difference(DateTime.now().toUtc()) > const Duration(minutes: 5);
  }
}
