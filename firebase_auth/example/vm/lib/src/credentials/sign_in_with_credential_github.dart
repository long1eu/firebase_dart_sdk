// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithCredentialGitHub(FirebaseAuthOption option) async {
  final HttpServer server = await HttpServer.bind('localhost', 55937);
  final String state = Uuid().v4();
  final Uri uri = Uri.https(
    'github.com',
    'login/oauth/authorize',
    <String, String>{
      'client_id': _githubClientId,
      'scope': 'read:user user:email',
      'state': state,
    },
  );

  console //
    ..println('Visit this link and login with GitHub')
    ..println(uri);

  final HttpRequest request = await server.first;
  final Map<String, dynamic> data = request.requestedUri.queryParameters;
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
          'provider': ProviderType.github,
          'code': code,
        },
      },
    ),
  );
  await progress.cancel();

  final Map<String, dynamic> accessTokenResponse = jsonDecode(response.body)['result'];
  final String accessToken = accessTokenResponse['access_token'];

  final AuthCredential credential = GithubAuthProvider.getCredential(accessToken);

  console.println();
  progress = Progress('Siging in')..show();
  final AuthResult auth = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return auth;
}
