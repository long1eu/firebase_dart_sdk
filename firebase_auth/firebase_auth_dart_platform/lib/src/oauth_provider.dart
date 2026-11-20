import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';

/// Why a provider flow throws for [providerId]: no `OAuthLoopbackProvider` was
/// passed for it.
String noProviderFlowFor(String providerId) =>
    'no OAuthLoopbackProvider was passed for "$providerId". Pass one to '
    'FirebaseAuthDart.use(oauthProviders: <OAuthLoopbackProvider>[...]), for '
    'example OAuthLoopbackProvider.google(...) or .github(...), or get the '
    'provider token yourself and use signInWithCredential.';

/// Why the provider flows throw on the web.
const String noLoopbackOnWeb =
    'the loopback provider flow needs dart:io (desktop, Android and iOS); on '
    'the web use the official implementation of firebase_auth.';

/// Why the provider flows throw on a platform where the client cannot open the
/// browser itself.
const String noPresentUrl =
    'on this platform the authorization URL needs a presenter. Pass '
    'presentUrl to FirebaseAuthDart.use, for example '
    '(Uri url) => launchUrl(url) of url_launcher.';

/// The scopes and custom parameters set on [provider] (`addScope`,
/// `setCustomParameters`), for the providers of FlutterFire that have them;
/// none for the others.
(List<String>, Map<String, String>) oauthRequestOf(AuthProvider provider) {
  final (
    List<String> scopes,
    Map<Object?, Object?> parameters,
  ) = switch (provider) {
    GoogleAuthProvider p => (p.scopes, p.parameters),
    FacebookAuthProvider p => (p.scopes, p.parameters),
    YahooAuthProvider p => (p.scopes, p.parameters),
    GithubAuthProvider p => (p.scopes, p.parameters),
    MicrosoftAuthProvider p => (p.scopes, p.parameters),
    AppleAuthProvider p => (p.scopes, p.parameters),
    OAuthProvider p => (p.scopes, p.parameters),
    TwitterAuthProvider p => (const <String>[], p.parameters),
    _ => (const <String>[], const <Object?, Object?>{}),
  };
  return (
    scopes,
    <String, String>{
      for (final MapEntry<Object?, Object?> entry in parameters.entries)
        '${entry.key}': '${entry.value}',
    },
  );
}
