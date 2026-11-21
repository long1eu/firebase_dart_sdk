import 'package:http/http.dart' as http;
import 'package:secure_flow/secure_flow.dart';

import 'oauth_loopback.dart';

/// Signs the user in to [provider] in the system browser and returns the provider's tokens. Needs `dart:io` (the
/// Dart VM: command line tools, Flutter desktop); on this platform it throws an [UnsupportedError]. See the VM
/// implementation for the details.
Future<OAuthLoopbackResult> authorizeWithOAuthLoopback(
  OAuthLoopbackProvider provider, {
  SecurePresenter? presenter,
  SecureEnvironment? environment,
  Duration timeout = const Duration(minutes: 5),
  http.Client? httpClient,
}) => throw UnsupportedError(
  'The loopback OAuth sign-in needs dart:io (desktop and command line).',
);
