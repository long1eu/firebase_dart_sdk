// File created by
// Lung Razvan <long1eu>
// on 31/08/2020

import 'dart:async';
import 'dart:html';

import 'package:firebase_auth_vm/firebase_auth_vm.dart';

import 'recaptcha_token.dart' as base;

/// Function for directing the user or it's user-agent to [uri].
///
/// The user is required to go to [uri] and either complete or decline the application verification.
typedef UrlPresenter = void Function(Uri uri);

/// Runs an reCAPTCHA flow using an HTTP server.
///
/// It takes a user supplied function which will be called with an URI. The user is expected to navigate to that URI and
/// verify the challenge.
class RecaptchaToken implements base.RecaptchaToken {
  const RecaptchaToken();

  /// Once the user successfully verified the app, the HTTP server will redirect the user agent to a URL pointing to a
  /// locally running HTTP server. Which in turn will be able to extract the recaptcha token.
  @override
  Future<String> get({UrlPresenter urlPresenter, String apiKey, String languageCode}) async {
    final String state = randomString(32);
    final WindowBase win = window.open(
      'reCAPTCHA-Challenge.html?state=$state&apiKey=$apiKey${languageCode != null ? '&languageCode=$languageCode' : ''}',
      'reCAPTCHA Challenge',
      'toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes,width=600,height=800',
    );

    final MessageEvent event = await window.onMessage.take(1).first;
    // todo: check the state value
    final String token = event.data['token'];
    win.close();
    return token;
  }
}
