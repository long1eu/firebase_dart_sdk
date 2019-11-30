// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth;

class SecureTokenService {
  const SecureTokenService({@required HttpService service})
      : assert(service != null),
        _service = service;

  final HttpService _service;

  /// Refresh a Firebase ID token by issuing an HTTP POST request to the securetoken.googleapis.com endpoint.
  Future<ExchangeRefreshTokenResponse> refreshToken(ExchangeRefreshTokenRequest request) async {
    final dynamic data = await _service.post('v1/token', request.json);
    return ExchangeRefreshTokenResponse.fromJson(data);
  }
}
