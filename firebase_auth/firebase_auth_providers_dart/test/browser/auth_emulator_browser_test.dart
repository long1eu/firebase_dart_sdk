// FirebaseUserAuth in a browser, against the Firebase Auth emulator: the HTTP requests go through the browser's
// fetch (package:http picks BrowserClient), and the emulator answers with CORS headers.
//
//     tool/start_auth_emulators.sh                      # repository root
//     dart test -p chrome test/browser                  # dart2js
//     dart test -p chrome -c dart2wasm test/browser     # dart2wasm
//
// The host of the emulator is taken, in this order, from a compile-time define
// (`FIREBASE_AUTH_EMULATOR_HOST`, for a build that sets one), from the FIREBASE_AUTH_EMULATOR_HOST environment
// variable of the test runner (a browser has no environment: a hybrid isolate on the VM reads it), or is
// 127.0.0.1:9197, the default port of tool/start_auth_emulators.sh:
//
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9393 dart test -p chrome test/browser
//
// The tests skip themselves when the emulator does not answer.

@TestOn('browser')
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _definedHost = String.fromEnvironment(
  'FIREBASE_AUTH_EMULATOR_HOST',
);

/// Reads the environment of the test runner in a hybrid isolate on the VM.
const String _readEnvironment = '''
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

void hybridMain(StreamChannel<Object?> channel) {
  channel.sink
    ..add(Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? '')
    ..close();
}
''';

void main() {
  bool emulatorUp = false;
  late String emulatorHost;

  setUpAll(() async {
    emulatorHost = _definedHost;
    if (emulatorHost.isEmpty) {
      emulatorHost =
          ((await spawnHybridCode(_readEnvironment).stream.first) as String)
              .trim();
    }
    if (emulatorHost.isEmpty) {
      emulatorHost = '127.0.0.1:9197';
    }
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
    final GetTokenResult token = await auth.getAccessToken(forceRefresh: false);
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

  test(
    'the JS SDK headers (client version, app id, App Check) pass CORS',
    () async {
      skipWithoutEmulator();
      if (!emulatorUp) {
        return;
      }
      final FirebaseUserAuth auth = FirebaseUserAuth(
        apiKey: 'fake-api-key',
        appId: '1:1234567890:web:abcdef',
        appCheck: _AppCheck(),
        emulatorHost: emulatorHost,
      );
      addTearDown(auth.dispose);
      final AuthUser user = await auth.signInAnonymously();
      expect(
        (await auth.getAccessToken(forceRefresh: true)).claims['user_id'],
        user.uid,
      );
      await auth.deleteCurrentUser();
    },
  );

  test('account management from the browser', () async {
    skipWithoutEmulator();
    if (!emulatorUp) {
      return;
    }
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: emulatorHost,
    );
    addTearDown(auth.dispose);
    final String email =
        'browser${DateTime.now().microsecondsSinceEpoch}@example.com';
    await auth.createUserWithEmailAndPassword(email, 'password');
    // The continue URI is the page of the test, like in the JS SDK.
    expect(await auth.fetchSignInMethodsForEmail(email), <String>['password']);
    await auth.updateProfile(displayName: 'Browser');
    expect(auth.currentUser!.displayName, 'Browser');
    await auth.sendEmailVerification();
    await auth.sendPasswordResetEmail(email);
    await auth.updatePassword('password-2');
    await auth.reauthenticateWithEmailAndPassword(email, 'password-2');
    await auth.reload();
    expect(auth.currentUser!.displayName, 'Browser');
    await auth.deleteCurrentUser();
    expect(auth.uid, isNull);
  });

  test('the emulator host as an http:// URL, in the browser', () async {
    skipWithoutEmulator();
    if (!emulatorUp) {
      return;
    }
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: 'http://$emulatorHost/',
    );
    addTearDown(auth.dispose);
    await auth.signInAnonymously();
    await auth.deleteCurrentUser();
  });

  test('the emulator host is checked in the browser too', () async {
    for (final String host in <String>[
      'user@127.0.0.1:9099',
      '127.0.0.1:9099/path',
      '127.0.0.1:65536',
      'identitytoolkit.googleapis.com',
      'https://securetoken.googleapis.com',
    ]) {
      expect(
        () => FirebaseUserAuth(apiKey: 'k', emulatorHost: host),
        throwsA(isA<ArgumentError>()),
        reason: host,
      );
    }
    // An https:// emulator: the requests use TLS.
    final List<Uri> urls = <Uri>[];
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'k',
      emulatorHost: 'https://auth.example.test:8443',
      httpClient: MockClient((http.Request request) async {
        urls.add(request.url);
        return http.Response('{}', 500);
      }),
    );
    addTearDown(auth.dispose);
    await expectLater(
      auth.signInAnonymously(),
      throwsA(isA<FirebaseAuthProviderException>()),
    );
    expect(
      urls.single.toString(),
      'https://auth.example.test:8443/identitytoolkit.googleapis.com/v1/accounts:signUp?key=k',
    );
  });
}

class _AppCheck implements InternalAppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      const AppCheckTokenResult('app-check-token');

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}
