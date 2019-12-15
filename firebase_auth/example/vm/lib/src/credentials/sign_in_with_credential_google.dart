// File created by
// Lung Razvan <long1eu>
// on 14/12/2019

part of firebase_auth_example;

Future<AuthResult> _signInWithCredentialGoogle(FirebaseAuthOption option) async {
  final DeviceLogin deviceLogin = DeviceLogin(
    requestCodeUrl: Uri.https(
      'accounts.google.com',
      'o/oauth2/device/code',
      <String, String>{
        'client_id': '233259864964-nheocpjikl28sp3refc4mqshb7clnprs.apps.googleusercontent.com',
        'scope': 'email profile',
      },
    ),
    pollUrl: Uri.https(
      'oauth2.googleapis.com',
      'token',
      <String, String>{
        'client_id': '233259864964-nheocpjikl28sp3refc4mqshb7clnprs.apps.googleusercontent.com',
        'client_secret': 'E4oZUwE05-y9UE9nmI70mmoy',
        'grant_type': 'http://oauth.net/grant_type/device/1.0',
      },
    ),
    providerName: 'Google',
    codeResponseBuilder: (Map<String, dynamic> response) {
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

  final AuthCredential credential = GoogleAuthProvider.getCredential(idToken: idToken, accessToken: accessToken);

  console.println();
  final Progress progress = Progress('Siging in')..show();
  final AuthResult auth = await FirebaseAuth.instance.signInWithCredential(credential);
  await progress.cancel();
  console.clearScreen();
  return auth;
}
