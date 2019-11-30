// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

part of firebase_auth;

Map<String, String> _defaultHeaderBuilder() => const <String, String>{};

class HttpService {
  HttpService({
    @required AuthRequestConfiguration configuration,
    @required String host,
    HeaderBuilder headersBuilder,
    Client client,
  })  : assert(configuration != null),
        assert(host != null && host.isNotEmpty),
        _configuration = configuration,
        _host = Uri.parse(host),
        _client = client ?? Client(),
        headersBuilder = headersBuilder ?? _defaultHeaderBuilder;

  final Client _client;
  final AuthRequestConfiguration _configuration;
  final HeaderBuilder headersBuilder;
  final Uri _host;

  Future<dynamic> post(String path, Map<String, dynamic> body,
      {Map<String, String> headers = const <String, String>{}}) async {
    final Response response = await _client.post(
      _host.replace(
        pathSegments: <String>[..._host.pathSegments, ...path.split('/')],
        queryParameters: <String, dynamic>{'key': _configuration.apiKey},
      ),
      headers: <String, String>{
        ...headers,
        ...headersBuilder(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    return _handleResponse(response);
  }

  String get locale => _configuration.languageCode;

  dynamic _handleResponse(Response response) {
    if (response.statusCode >= 400) {
      final Map<String, dynamic> error = Map<String, dynamic>.from(jsonDecode(response.body)['error']);
      final int code = error['code'];
      final String message = error['message'];
      // ERROR_CODE( : $MESSAGE)?.
      final String parts = message.split(' : ')[0];
      final String errorName = parts.trim();
      final String errorMessage = parts.length == 2 ? parts[1] : '';

      throw FirebaseAuthError(errorName, errorMessage);
    } else {
      return jsonDecode(response.body);
    }
  }
}
