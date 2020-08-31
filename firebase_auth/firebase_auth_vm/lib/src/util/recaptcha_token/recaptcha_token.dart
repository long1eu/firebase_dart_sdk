// File created by
// Lung Razvan <long1eu>
// on 31/08/2020

import '_recaptcha_token_io.dart' if (dart.library.html) '_recaptcha_token_web.dart' as impl;

/// Function for directing the user or it's user-agent to [uri].
///
/// The user is required to go to [uri] and either complete or decline the application verification.
typedef UrlPresenter = void Function(Uri uri);

abstract class RecaptchaToken {
  const factory RecaptchaToken() = impl.RecaptchaToken;

  /// It takes a user supplied function which will be called with an URI. The user is expected to navigate to that URI and
  /// verify the challenge.
  Future<String> get({
    UrlPresenter urlPresenter,
    String apiKey,
    String languageCode,
  });
}
