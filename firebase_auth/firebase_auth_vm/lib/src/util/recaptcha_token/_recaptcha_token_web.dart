// File created by
// Lung Razvan <long1eu>
// on 31/08/2020

import 'dart:async';
import 'dart:html';

import 'package:firebase/firebase.dart';
import 'package:firebase_auth_vm/firebase_auth_vm.dart';

import 'recaptcha_token.dart' as base;

class RecaptchaToken implements base.RecaptchaToken {
  const RecaptchaToken({this.appName = 'RecaptchaTokenApp'});

  final String appName;

  @override
  Future<String> get({UrlPresenter urlPresenter, String apiKey, String languageCode}) async {
    final App app = initializeApp(apiKey: apiKey, name: appName);
    app.auth().languageCode = languageCode;

    final DivElement div = DivElement() //
      ..id = 'grecaptcha-badge';

    document.body.children.add(div);
    final String token = await RecaptchaVerifier(div.id, <String, dynamic>{'size': 'invisible'}, app).verify();
    document.body.children.remove(div);
    await app.delete();

    return token;
  }
}
