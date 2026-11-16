/// Application Default Credentials for servers and command line tools. Needs `dart:io`: import this library only in
/// code that does not run on the web.
///
/// It also exports [OAuthTokenProvider] and [OAuthAccessToken].
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_auth_providers_dart/adc.dart';
///
/// void main() {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '',
///       appId: '1:1234567890:dart:server',
///       projectId: 'my-project',
///     ),
///   );
///   app.authProvider = applicationDefaultCredentials();
/// }
/// ```
library;

import 'package:googleapis_auth/auth_io.dart' as gapi;
import 'package:http/http.dart' as http;

import 'src/oauth_token_provider.dart';

export 'src/oauth_token_provider.dart';

/// A token provider on top of Application Default Credentials: the key file named by the
/// `GOOGLE_APPLICATION_CREDENTIALS` environment variable, else the credentials of
/// `gcloud auth application-default login`, else the metadata server of the machine (Compute Engine, Cloud Run,
/// GKE, ...). The lookup is the one of `package:googleapis_auth`.
///
/// **These credentials bypass security rules** (see [OAuthTokenProvider]).
///
/// The credentials are looked up when the first token is needed, and again each time a token is about to expire
/// (within [refreshBefore], default five minutes). [scopes] defaults to [OAuthTokenProvider.datastoreScopes].
/// [httpClient] is used for the token requests and is not closed by the provider.
///
/// Errors of the lookup (no credentials found, a key file that cannot be read, a metadata server that does not
/// answer) are those of `package:googleapis_auth`; they reach the caller of
/// [OAuthTokenProvider.getAccessToken], and Firestore fails the request with `unauthenticated`. Not exercised by
/// the tests of this package.
///
/// ```dart
/// // Before the Firestore instance of the app is created.
/// app.authProvider = applicationDefaultCredentials();
/// ```
OAuthTokenProvider applicationDefaultCredentials({
  List<String> scopes = OAuthTokenProvider.datastoreScopes,
  http.Client? httpClient,
  Duration refreshBefore = const Duration(minutes: 5),
}) {
  return OAuthTokenProvider(() async {
    final gapi.AutoRefreshingAuthClient client = await gapi
        .clientViaApplicationDefaultCredentials(
          scopes: scopes,
          baseClient: httpClient,
        );
    try {
      final gapi.AccessToken token = client.credentials.accessToken;
      return OAuthAccessToken(token.data, token.expiry);
    } finally {
      client.close();
    }
  }, refreshBefore: refreshBefore);
}
