// File created by
// Lung Razvan <long1eu>
// on 31/08/2020

import 'dart:async';
import 'dart:html';
import 'dart:js';

import 'package:firebase_auth_vm/firebase_auth_vm.dart';
import 'package:googleapis/identitytoolkit/v3.dart';

import 'recaptcha_token.dart' as base;

class RecaptchaToken implements base.RecaptchaToken {
  const RecaptchaToken(this.authApi);

  final FirebaseAuthApi authApi;

  @override
  Future<String> get({UrlPresenter urlPresenter, String apiKey, String languageCode}) async {
    final Completer<String> completer = Completer<String>();
    final GetRecaptchaParamResponse params = await authApi.getRecaptchaParam();

    final DivElement div = DivElement() //
      ..id = 'grecaptcha-badge';
    document.body.children.add(div);

    ScriptElement script;
    context['onLoad'] = () {
      final JsObject grecaptcha = context['grecaptcha'];

      void complete({String token, Object error}) {
        if (token != null) {
          completer.complete(token);
        } else {
          completer.completeError(error);
        }

        document.body.children.remove(div);
        document.head.children.remove(script);
      }

      final int id = grecaptcha.callMethod(
        'render',
        <dynamic>[
          div.id,
          JsObject.jsify(<String, dynamic>{
            'sitekey': params.recaptchaSiteKey,
            'size': 'invisible',
            'callback': (String token) => complete(token: token),
            'expired-callback': () => complete(error: StateError('Session expired')),
            'error-callback': (dynamic error) => complete(error: error),
          }),
        ],
      );

      grecaptcha.callMethod('execute', <int>[id]);
    };

    script = ScriptElement()..src = 'https://www.google.com/recaptcha/api.js?onload=onLoad&hl=$languageCode';
    document.head.children.add(script);

    return completer.future;
  }
}
