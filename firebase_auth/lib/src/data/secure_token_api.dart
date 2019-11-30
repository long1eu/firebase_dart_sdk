// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of firebase_auth;

class SecureTokenApi {
  SecureTokenApi({
    @required SecureTokenService secureTokenService,
    @required String accessToken,
    @required DateTime accessTokenExpirationDate,
    @required String refreshToken,
  })  : assert(secureTokenService != null),
        _secureTokenService = secureTokenService,
        _accessToken = accessToken,
        _accessTokenExpirationDate = accessTokenExpirationDate,
        _refreshToken = refreshToken;

  final SecureTokenService _secureTokenService;
  String _accessToken;
  DateTime _accessTokenExpirationDate;
  String _refreshToken;

  Future<String> fetchAccessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && hasValidAccessToken) {
      return _accessToken;
    } else {
      final ExchangeRefreshTokenRequest request = ExchangeRefreshTokenRequest(refreshToken: _refreshToken);
      final ExchangeRefreshTokenResponse response = await _secureTokenService.refreshToken(request);

      final String newAccessToken = response.accessToken;
      if (newAccessToken != null && newAccessToken != _accessToken) {
        _accessToken = newAccessToken;
        _accessTokenExpirationDate = DateTime.now().add(Duration(seconds: response.expiresIn)).toUtc();
      }

      final String newRefreshToken = response.refreshToken;
      if (newRefreshToken != null && newRefreshToken != _refreshToken) {
        _refreshToken = newRefreshToken;
      }

      return newAccessToken;
    }
  }

  bool get hasValidAccessToken {
    return _accessToken != null && _accessTokenExpirationDate.difference(DateTime.now().toUtc()) > const Duration(minutes: 5);
  }
}
