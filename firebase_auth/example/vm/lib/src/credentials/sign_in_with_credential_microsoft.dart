// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithCredentialMicrosoft(FirebaseAuthOption option) async {
  final HttpServer server = await HttpServer.bind('localhost', 55937);
  final String state = Uuid().v4();
  const String redirectUri = 'http://localhost:55937/__/auth/handler';
  final Uri uri = Uri.https(
    'login.microsoftonline.com',
    'common/oauth2/v2.0/authorize',
    <String, String>{
      'client_id': _microsoftClientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'response_mode': 'query',
      'scope': 'openid profile email',
      'state': state,
    },
  );

  console //
    ..println('Visit this link and login with Microsoft')
    ..println(uri);

  final HttpRequest request = await server.first;
  final Map<String, dynamic> data = request.requestedUri.queryParameters;
  print('data: $data');
  final String code = data['code'];
  final String receivedState = data['state'];

  if (request.method != 'GET') {
    throw Exception('Invalid response from server (expected GET request callback, got: ${request.method}).');
  }
  if (receivedState != state) {
    throw StateError('The requested state doesn\'t match.');
  }

  request.response
    ..statusCode = 200
    ..headers.set('content-type', 'text/html; charset=UTF-8')
    ..write(_successHtml);
  await request.response.flush();
  await request.response.close();
  await server.close();

  Progress progress = Progress('Verifying credentials')..show();
  final Response response = await post(
    'https://us-central1-flutter-sdk.cloudfunctions.net/handler',
    headers: <String, String>{'content-type': 'application/json'},
    body: jsonEncode(
      <String, dynamic>{
        'data': <String, String>{
          'provider': 'microsoft.com',
          'redirect_uri': redirectUri,
          'code': code,
        },
      },
    ),
  );
  await progress.cancel();

  print(response.body);
  final Map<String, dynamic> accessTokenResponse = jsonDecode(response.body)['result'] ?? jsonDecode(response.body);
  if (response.statusCode > 200 || accessTokenResponse.containsKey('error')) {
    print(response.body);
    throw StateError(accessTokenResponse['error'].toString());
  }

  final String accessToken = accessTokenResponse['access_token'];

  final AuthCredential credential =
      OAuthProvider.getCredentialWithAccessToken(providerId: 'microsoft.com', accessToken: accessToken);

  console.println();
  progress = Progress('Siging in')..show();
  final AuthResult auth = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return auth;
}
