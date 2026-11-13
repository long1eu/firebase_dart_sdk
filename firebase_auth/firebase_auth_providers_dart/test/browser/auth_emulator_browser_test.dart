// FirebaseUserAuth in a browser, against the Firebase Auth emulator: the HTTP requests go through the browser's
// fetch (package:http picks BrowserClient), and the emulator answers with CORS headers.
//
//     tool/start_auth_emulators.sh                      # repository root
//     dart test -p chrome test/browser                  # dart2js
//     dart test -p chrome -c dart2wasm test/browser     # dart2wasm
//
// The host of the emulator is 127.0.0.1:9197 by default; another one is passed at compile time with
// `--dart-define=FIREBASE_AUTH_EMULATOR_HOST=host:port` (a browser has no environment). The tests skip themselves
// when the emulator does not answer.

@TestOn('browser')
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const String emulatorHost = String.fromEnvironment(
  'FIREBASE_AUTH_EMULATOR_HOST',
  defaultValue: '127.0.0.1:9197',
);

void main() {
  bool emulatorUp = false;

  setUpAll(() async {
    try {
      emulatorUp =
          (await http.get(Uri.parse('http://$emulatorHost/'))).statusCode ==
          200;
    } on Object {
      emulatorUp = false;
    }
  });

  void skipWithoutEmulator() {
    if (!emulatorUp) {
      markTestSkipped(
        'The Firebase Auth emulator does not answer on $emulatorHost '
        '(start it with tool/start_auth_emulators.sh)',
      );
    }
  }

  test('anonymous sign-in, refresh and sign-out from the browser', () async {
    skipWithoutEmulator();
    if (!emulatorUp) {
      return;
    }
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: emulatorHost,
    );
    addTearDown(auth.dispose);
    // No environment in a browser.
    expect(FirebaseUserAuth.emulatorHostFromEnvironment, isNull);

    final AuthUser user = await auth.signInAnonymously();
    expect(user.isAnonymous, isTrue);
    final GetTokenResult token = await auth.getAccessToken(
      forceRefresh: false,
    );
    expect(token.claims['user_id'], user.uid);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final GetTokenResult refreshed = await auth.getAccessToken(
      forceRefresh: true,
    );
    expect(refreshed.token, isNot(token.token));
    expect(refreshed.claims['user_id'], user.uid);

    await auth.deleteCurrentUser();
    expect(auth.uid, isNull);
  });

  test('email and password errors are mapped in the browser too', () async {
    skipWithoutEmulator();
    if (!emulatorUp) {
      return;
    }
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: emulatorHost,
    );
    addTearDown(auth.dispose);
    await expectLater(
      auth.createUserWithEmailAndPassword('not an email', 'password'),
      throwsA(
        isA<FirebaseAuthProviderException>().having(
          (FirebaseAuthProviderException e) => e.code,
          'code',
          'invalid-email',
        ),
      ),
    );
  });
}
