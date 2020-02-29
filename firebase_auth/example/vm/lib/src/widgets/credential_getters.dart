// File created by
// Lung Razvan <long1eu>
// on 16/12/2019

part of firebase_auth_example;

Future<EmailPasswordAuthCredential> _getEmailPasswordAuthCredential() async {
  final EmailAndPassword result = await getEmailAndPassword();
  return EmailAuthProvider.getCredential(email: result.email, password: result.password);
}

Future<PhoneAuthCredential> _getPhoneAuthCredential() async {
  StringOption option = StringOption(
    question: 'Please enter your phone number.',
    fieldBuilder: () => 'phone: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'Try a valid phone number.';
      }

      return null;
    },
  );

  final String phoneNumber = await option.show();
  console.println();

  final String verificationId = await FirebaseAuth.instance.verifyPhoneNumber(
    phoneNumber: phoneNumber,
    presenter: (Uri uri) {
      console
        ..println('In order to verify the app please complete the recaptcha change by clicking the link below.')
        ..println(uri.toString().bold.cyan.reset);
    },
  );

  console.println();
  option = StringOption(
    question:
        'Great! A SMS was sent to ${phoneNumber.yellow.reset}. Please type the ${'code'.yellow.reset} you receive.',
    fieldBuilder: () => 'code: ',
    validator: (String response) {
      if (response.isEmpty) {
        return 'Try a non empty code';
      }

      return null;
    },
  );

  final String code = await option.show();
  return PhoneAuthProvider.getCredential(verificationId: verificationId, verificationCode: code);
}

Future<GoogleAuthCredential> _getGoogleAuthCredential() async {
  final DeviceLogin deviceLogin = DeviceLogin(
    requestCodeUrl: Uri.https(
      'accounts.google.com',
      'o/oauth2/device/code',
      <String, String>{
        'client_id': _googleClientId,
        'scope': 'email profile',
      },
    ),
    pollUrl: Uri.https(
      'oauth2.googleapis.com',
      'token',
      <String, String>{
        'client_id': _googleClientId,
        'client_secret': _googleClientSecret,
        'grant_type': 'http://oauth.net/grant_type/device/1.0',
      },
    ),
    providerName: 'Google',
    codeResponseBuilder:   (Map<String, dynamic> response) {
      return CodeResponse(
        code: response['device_code'],
        userCode: response['user_code'],
        verificationUri: response['verification_url'],
        expiresIn: Duration(seconds: response['expires_in']),
        interval: Duration(seconds: response['interval']),
      );
    },
    codePollValidator: (Map<String, dynamic> pollResponse) {
      if (pollResponse['access_token'] != null && pollResponse['id_token'] != null) {
        return null;
      } else if (pollResponse['error'] == 'access_denied') {
        return 'You canceled the authorization.';
      } else if (pollResponse['error'] == 'authorization_pending') {
        return '';
      } else {
        return pollResponse['error'];
      }
    },
  );

  final Map<String, dynamic> credentials = await deviceLogin.credentials;
  final String accessToken = credentials['access_token'];
  final String idToken = credentials['id_token'];

  return GoogleAuthProvider.getCredential(idToken: idToken, accessToken: accessToken);
}

Future<FacebookAuthCredential> _getFacebookAuthCredential() async {
  final DeviceLogin deviceLogin = DeviceLogin(
    requestCodeUrl: Uri.https(
      'graph.facebook.com',
      'v5.0/device/login',
      <String, String>{
        'access_token': _facebookAccessToken,
        'scope': 'email',
      },
    ),
    pollUrl: Uri.https(
      'graph.facebook.com',
      'v5.0/device/login_status',
      <String, String>{
        'access_token': _facebookAccessToken,
      },
    ),
    providerName: 'Facebook',
    codeResponseBuilder: (Map<String, dynamic> response) {
      return CodeResponse(
        code: response['code'],
        userCode: response['user_code'],
        verificationUri: response['verification_uri'],
        expiresIn: Duration(seconds: response['expires_in']),
        interval: Duration(seconds: response['interval']),
      );
    },
    codePollValidator: (Map<String, dynamic> pollResponse) {
      if (pollResponse['access_token'] != null) {
        return null;
      }
      final Map<String, dynamic> error = pollResponse['error'];
      switch (error['error_subcode']) {
        // pending
        case 1349174:
          return '';
        default:
          return error['error_user_title'];
      }
    },
  );

  final Map<String, dynamic> credentials = await deviceLogin.credentials;
  final String accessToken = credentials['access_token'];
  return FacebookAuthProvider.getCredential(accessToken);
}

Future<GithubAuthCredential> _getGithubAuthCredential() async {
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
    ..write(authSuccessHtml);
  await request.response.flush();
  await request.response.close();
  await server.close();

  final Progress progress = Progress('Verifying credentials')..show();
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
  if (response.statusCode > 200) {
    throw StateError(accessTokenResponse['error']);
  }
  final String accessToken = accessTokenResponse['access_token'];

  return GithubAuthProvider.getCredential(accessToken);
}

Future<TwitterAuthCredential> _getTwitterAuthCredential() async {
  final TwitterClient client = TwitterClient(
    consumerKey: _twitterConsumerKey,
    consumerKeySecret: _twitterConsumerKeySecret,
    accessToken: _twitterAccessToken,
    accessTokenSecret: _twitterAccessTokenSecret,
  );

  Progress progress = Progress('Getting Twitter configuration')..show();
  await client.initialize();
  await progress.cancel();
  final TwitterRequestToken requestToken = client.requestToken;
  final HttpServer server = client.server;

  console
    ..println('Visit this link and login with Twitter')
    ..println('https://api.twitter.com/oauth/authenticate?oauth_token=${requestToken.token}');

  final HttpRequest request = await server.first;
  final Map<String, dynamic> data = request.requestedUri.queryParameters;
  final String oauthToken = data['oauth_token'];
  final String oauthVerifier = data['oauth_verifier'];

  if (request.method != 'GET') {
    throw Exception('Invalid response from server (expected GET request callback, got: ${request.method}).');
  }
  if (requestToken.token != oauthToken) {
    throw StateError('The request doesn\'t match.');
  }

  request.response
    ..statusCode = 200
    ..headers.set('content-type', 'text/html; charset=UTF-8')
    ..write(authSuccessHtml);
  await request.response.flush();
  await request.response.close();
  await server.close();

  progress = Progress('Validating credentials')..show();
  final Response response = await client.post('oauth/access_token', headers: <String, String>{
    'oauth_token': requestToken.token,
    'oauth_verifier': oauthVerifier,
  });
  await progress.cancel();

  if (response.statusCode > 200) {
    throw StateError(response.body);
  }

  final Map<String, String> queryParameters = response.body.queryParameters;
  final String userAuthToken = queryParameters['oauth_token'];
  final String userAuthTokenSecret = queryParameters['oauth_token_secret'];

  return TwitterAuthProvider.getCredential(authToken: userAuthToken, authTokenSecret: userAuthTokenSecret);
}

Future<OAuthCredential> _getYahooAuthCredential() {
  return _getOAuthAuthCredential(
    uri: Uri.https('api.login.yahoo.com', 'oauth2/request_auth'),
    providerName: 'Yahoo',
    providerId: 'yahoo.com',
    clientId: _yahooClientId,
  );
}

Future<OAuthCredential> _getMicrosoftAuthCredential() {
  return _getOAuthAuthCredential(
    uri: Uri.https('login.microsoftonline.com', 'common/oauth2/v2.0/authorize'),
    providerName: 'Microsoft',
    providerId: 'microsoft.com',
    clientId: _microsoftClientId,
  );
}

Future<OAuthCredential> _getOAuthAuthCredential({
  @required Uri uri,
  @required String providerName,
  @required String providerId,
  @required String clientId,
}) async {
  final HttpServer server = await HttpServer.bind('localhost', 55937);
  final String state = Uuid().v4();
  final String nonce = Uuid().v4().toString().replaceAll('-', '');
  const String redirectUri = 'http://localhost:55937/__/auth/handler';

  final Uri authorizationUri = uri.replace(
    queryParameters: <String, String>{
      'client_id': clientId,
      'nonce': nonce,
      'state': state,
      'scope': 'openid profile email',
      'redirect_uri': redirectUri,
      'response_type': 'code',
    },
  );

  console //
    ..println('Visit this link and login with $providerName')
    ..println(authorizationUri);

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
    ..write(authSuccessHtml);
  await request.response.flush();
  await request.response.close();
  await server.close();

  final Progress progress = Progress('Verifying credentials')..show();
  final Response response = await post(
    'https://us-central1-flutter-sdk.cloudfunctions.net/handler',
    headers: <String, String>{'content-type': 'application/json'},
    body: jsonEncode(
      <String, dynamic>{
        'data': <String, String>{
          'provider': providerId,
          'redirect_uri': redirectUri,
          'code': code,
        },
      },
    ),
  );
  await progress.cancel();

  final Map<String, dynamic> accessTokenResponse = jsonDecode(response.body)['result'] ?? jsonDecode(response.body);
  if (response.statusCode > 200 || accessTokenResponse.containsKey('error')) {
    print(response.body);
    throw StateError(accessTokenResponse['error'].toString());
  }

  final String accessToken = accessTokenResponse['access_token'];
  return OAuthProvider.getCredentialWithAccessToken(providerId: providerId, accessToken: accessToken);
}

Future<AuthResult> _presentSignInWithCredential(AuthCredential credential) async {
  console.println();
  final Progress progress = Progress('Siging in')..show();
  final AuthResult result = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return result;
}
