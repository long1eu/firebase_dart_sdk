import 'package:http/http.dart' as http;

import 'oauth_loopback.dart';

/// Signs the user in to [provider] in the system browser and returns the provider's tokens. Needs `dart:io` (the
/// Dart VM: command line tools, Flutter desktop); on this platform it throws an [UnsupportedError]. See the VM
/// implementation for the details.
Future<OAuthLoopbackResult> authorizeWithOAuthLoopback(
  OAuthLoopbackProvider provider, {
  UrlPresenter? presenter,
  Duration timeout = const Duration(minutes: 5),
  http.Client? httpClient,
}) => throw UnsupportedError(
  'The loopback OAuth sign-in needs dart:io (desktop and command line).',
);

/// Opens [url] in the system browser. Needs `dart:io`; on this platform it throws an [UnsupportedError].
Future<void> openInSystemBrowser(Uri url) => throw UnsupportedError(
  'openInSystemBrowser needs dart:io (desktop and command line).',
);
