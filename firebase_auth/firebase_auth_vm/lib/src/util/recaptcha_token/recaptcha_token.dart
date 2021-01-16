// File created by
// Lung Razvan <long1eu>
// on 31/08/2020

import 'package:firebase_auth_vm/firebase_auth_vm.dart';
import 'package:meta/meta.dart';

import '_recaptcha_token_io.dart' if (dart.library.html) '_recaptcha_token_web.dart' as impl;

/// Function for directing the user or it's user-agent to [uri].
///
/// The user is required to go to [uri] and either complete or decline the application verification.
typedef UrlPresenter = void Function(Uri uri);

/// Functions for allowing the client app to manage and retrieve a valid recaptcha token
typedef RecaptchaTokenProvider  = Future<String> Function();

abstract class RecaptchaToken {
  const factory RecaptchaToken(FirebaseAuthApi authApi) = impl.RecaptchaToken;

  /// It takes a user supplied function which will be called with an URI. The user is expected to navigate to that URI and
  /// verify the challenge.
  Future<String> get({
    @required UrlPresenter urlPresenter,
    @required String apiKey,
    @required String languageCode,
  });
}
