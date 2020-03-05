// File created by
// Lung Razvan <long1eu>
// on 02/03/2020

part of '../google_sign_in_dart.dart';

/// Creates an authentication Uri and listens on the local web server for the
/// authorization response.
///
/// Once the auth code comes back it make a post to [exchangeEndpoint] for
/// to obtain the access and refresh tokens.
Future<Map<String, dynamic>> _codeExchangeSignIn({
  @required String clientId,
  @required String exchangeEndpoint,
  @required String scope,
  @required UrlPresenter presenter,
  String hostedDomains,
  String uid,
}) async {
  assert(clientId != null);
  assert(exchangeEndpoint != null);
  assert(presenter != null);
  assert(scope != null);

  final Completer<Map<String, dynamic>> completer =
      Completer<Map<String, dynamic>>();

  final String state = _generateSecureRandomString();
  final String codeVerifier = _generateSecureRandomString();
  final String codeVerifierChallenge =
      _deriveCodeVerifierChallenge(codeVerifier);

  final InternetAddress address = InternetAddress.loopbackIPv4;
  final HttpServer server = await HttpServer.bind(address, 0);
  final int port = server.port;
  final String redirectUrl = 'http://${address.host}:$port';

  server.listen((HttpRequest request) async {
    final Uri uri = request.requestedUri;

    if (uri.path == '/') {
      return _sendData(request, _verifyQueryHtml);
    } else if (uri.path == '/response') {
      return _validateAndExchangeCodeResponse(
        request: request,
        exchangeEndpoint: exchangeEndpoint,
        redirectUrl: redirectUrl,
        state: state,
        clientId: clientId,
        codeVerifier: codeVerifier,
      )
          .then(completer.complete)
          .catchError(completer.completeError)
          .whenComplete(server.close);
    } else {
      return _sendData(request, _imageData, 'image/png; base64');
    }
  });

  final Map<String, String> queryParameters = <String, String>{
    'client_id': clientId,
    'redirect_uri': redirectUrl,
    'response_type': 'code',
    'scope': scope,
    'code_challenge': codeVerifierChallenge,
    'code_challenge_method': 'S256',
    'state': state,
    'access_type': 'offline',
  };

  if (hostedDomains != null && hostedDomains.isNotEmpty) {
    queryParameters['hd'] = hostedDomains;
  }
  if (uid != null && uid.isNotEmpty) {
    queryParameters['login_hint'] = uid;
  }

  final Uri authenticationUri =
      Uri.https('accounts.google.com', '/o/oauth2/v2/auth', queryParameters);

  presenter(authenticationUri);
  return completer.future.timeout(const Duration(minutes: 2));
}

Future<Map<String, dynamic>> _validateAndExchangeCodeResponse({
  @required HttpRequest request,
  @required String state,
  @required String exchangeEndpoint,
  @required String redirectUrl,
  @required String clientId,
  @required String codeVerifier,
}) {
  final Map<String, String> authResponse = request.requestedUri.queryParameters;
  final String returnedState = authResponse['state'];
  final String code = authResponse['code'];

  String message;
  if (state != returnedState) {
    message = 'Invalid response from server (state did not match).';
  }
  if (code == null || code.isEmpty) {
    message = 'Invalid response from server (no code transmitted).';
  }

  if (message != null) {
    return _sendErrorAndThrow(request, message);
  } else {
    return _exchangeCode(
      exchangeEndpoint: exchangeEndpoint,
      redirectUrl: redirectUrl,
      clientId: clientId,
      code: code,
      codeVerifier: codeVerifier,
    )
        .then((Map<String, dynamic> value) =>
            _sendData(request, _successHtml).then((_) => value))
        .catchError(
            (dynamic error, StackTrace stackTrace) =>
                _sendErrorAndThrow<Map<String, dynamic>>(
                    request, error.message),
            test: (dynamic error) => error is StateError);
  }
}

Future<Map<String, dynamic>> _exchangeCode({
  @required String exchangeEndpoint,
  @required String redirectUrl,
  @required String clientId,
  @required String code,
  @required String codeVerifier,
}) async {
  final Response response = await post(
    exchangeEndpoint,
    body: json.encode(<String, String>{
      'code': code,
      'codeVerifier': codeVerifier,
      'clientId': clientId,
      'redirectUrl': redirectUrl,
    }),
  );
  if (response.statusCode == 200) {
    return Map<String, dynamic>.from(jsonDecode(response.body));
  } else {
    return Future<Map<String, dynamic>>.error(StateError(response.body));
  }
}
