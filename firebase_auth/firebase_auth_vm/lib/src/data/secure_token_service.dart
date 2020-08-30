// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

part of firebase_auth_vm;

const String _securetokenUserAgent = 'dart-api-client securetoken/v1/token';

class SecureTokenService {
  SecureTokenService(Client client)
      : assert(client != null),
        _requester = ApiRequester(
          client,
          'https://securetoken.googleapis.com/',
          '',
          _securetokenUserAgent,
        );

  final ApiRequester _requester;

  /// Refresh a Firebase ID token by issuing an HTTP POST request to the securetoken.googleapis.com endpoint.
  Future<SecureTokenResponse> refreshToken(SecureTokenRequest request) async {
    return _requester
        .request('/v1/token', 'POST', body: jsonEncode(request.json))
        .then((dynamic data) => SecureTokenResponse.fromJson(data));
  }
}
