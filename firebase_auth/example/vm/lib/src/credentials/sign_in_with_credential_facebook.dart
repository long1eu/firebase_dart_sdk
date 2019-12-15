// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithCredentialFacebook(FirebaseAuthOption option) async {
  const String appAccessToken = '419828908898516|18b08ea1546a6796dd90487566d86362';
  final Uri requestCodeUri = Uri.https(
    'graph.facebook.com',
    'v5.0/device/login',
    <String, String>{'access_token': appAccessToken, 'scope': 'email'},
  );

  final Client client = Client();
  Progress progress = Progress('Fetching Facebook code')..show();
  final Response response = await client.post(requestCodeUri);
  await progress.cancel();

  final Map<String, dynamic> codeResponse = jsonDecode(response.body);

  final String code = codeResponse['code'];
  final String userCode = codeResponse['user_code'];
  final String verificationUri = codeResponse['verification_uri'];
  final Duration expiresIn = Duration(seconds: codeResponse['expires_in']);
  final Duration interval = Duration(seconds: codeResponse['interval']);

  final Uri verifyUri = Uri.parse(verificationUri).replace(queryParameters: <String, String>{'user_code': userCode});

  console //
    ..println('Visit this link to get the Facebook credentials.')
    ..println(verifyUri)
    ..println();

  final DateTime start = DateTime.now();
  progress = Progress('Waiting for you authorization on Facebook')..show();
  String accessToken;
  do {
    await Future<void>.delayed(interval);
    final Uri pollUri = Uri.https(
      'graph.facebook.com',
      'v5.0/device/login_status',
      <String, String>{'access_token': appAccessToken, 'code': code},
    );

    final Response response = await client.post(pollUri);
    final Map<String, dynamic> responseData = jsonDecode(response.body);
    if (responseData.containsKey('error')) {
      final Map<String, dynamic> error = responseData['error'];
      switch (error['error_subcode']) {
        // pending user authorization
        case 1349174:
          break;
        // code expired
        case 1349152:
          throw StateError(error['error_user_title']);
          break;
        default:
          throw StateError(error['error_user_title']);
      }
    } else {
      accessToken = responseData['access_token'];
      if (accessToken == null) {
        throw StateError('Facebook didn\'t send back your credentials, try again.');
      }
      break;
    }
  } while (start.difference(DateTime.now()) < expiresIn);
  await progress.cancel();

  final AuthCredential credential = FacebookAuthProvider.getCredential(accessToken);

  console.println();
  progress = Progress('Siging in')..show();
  final AuthResult auth = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return auth;
}
