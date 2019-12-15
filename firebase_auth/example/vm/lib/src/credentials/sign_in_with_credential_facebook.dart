// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithCredentialFacebook(FirebaseAuthOption option) async {
  final DeviceLogin deviceLogin = DeviceLogin(
    requestCodeUrl: Uri.https(
      'graph.facebook.com',
      'v5.0/device/login',
      <String, String>{
        'access_token': '419828908898516|18b08ea1546a6796dd90487566d86362',
        'scope': 'email',
      },
    ),
    pollUrl: Uri.https(
      'graph.facebook.com',
      'v5.0/device/login_status',
      <String, String>{
        'access_token': '419828908898516|18b08ea1546a6796dd90487566d86362',
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
  final AuthCredential credential = FacebookAuthProvider.getCredential(accessToken);

  console.println();
  final Progress progress = Progress('Siging in')..show();
  final AuthResult auth = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return auth;
}
