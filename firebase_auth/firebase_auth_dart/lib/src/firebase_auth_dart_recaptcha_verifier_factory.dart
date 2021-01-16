// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of firebase_auth_dart;

/// The delegate implementation for [RecaptchaVerifierFactoryPlatform].
///
/// This factory class is implemented to the user facing code has no underlying knowledge
/// of the delegate implementation.
class RecaptchaVerifierFactoryDart extends platform.RecaptchaVerifierFactoryPlatform {
  /// Creates a new [RecaptchaVerifierFactoryDart] with a container and parameters.
  RecaptchaVerifierFactoryDart._(this._auth, this._presenter) : _delegate = const dart.RecaptchaToken();

  final dart.RecaptchaToken _delegate;
  final dart.FirebaseAuth _auth;
  final dart.UrlPresenter _presenter;

  // todo: document this
  @override
  platform.RecaptchaVerifierFactoryPlatform delegateFor({String container, Map<String, dynamic> parameters}) {
    final String appName = parameters['appName'] ?? dart.FirebaseApp.defaultAppName;
    final dart.FirebaseAuth auth = dart.FirebaseAuth.getInstance(dart.FirebaseApp.getInstance(appName));
    final dart.UrlPresenter presenter = parameters['presenter'] ?? (Uri uri) => launch('$uri');

    return RecaptchaVerifierFactoryDart._(auth, presenter);
  }

  // todo: What is this??
  @override
  T getDelegate<T>() => _delegate as T;

  @override
  String get type => 'recaptcha';

  @override
  void clear() {
    // no-op
  }

  @override
  Future<String> verify() {
    try {
      return _delegate.get(
        urlPresenter: _presenter,
        apiKey: _auth.app.options.apiKey,
        languageCode: _auth.languageCode,
      );
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<int> render() async {
    // no-op
    return -1;
  }
}
