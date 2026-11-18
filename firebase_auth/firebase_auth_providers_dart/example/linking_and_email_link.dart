// The FlutterFire-style client calls of 0.3 against the Firebase Auth emulator:
// authStateChanges(), linking a federated credential to an anonymous user,
// email link sign-in, and unlink.
//
//     tool/start_auth_emulators.sh        (repository root; needs the firebase CLI)
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart run example/linking_and_email_link.dart
//
// The Google ID token here is a fake one that only the emulator accepts. In an
// app it comes from a Google sign-in package (google_sign_in on mobile, a
// browser flow on desktop): this package exchanges a token the app already
// has, it does not open a sign-in page. The emulator stands in for the inbox
// of the email link.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> main() async {
  final String? emulator = FirebaseUserAuth.emulatorHostFromEnvironment;
  if (emulator == null) {
    print(
      'Set FIREBASE_AUTH_EMULATOR_HOST (see the comment at the top of this file).',
    );
    return;
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-test',
    ),
  );
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    emulatorHost: emulator,
  );
  // The emails the backend sends are in this language.
  auth.languageCode = 'en';

  // Starts with the current user (null), then each sign-in and sign-out.
  auth.authStateChanges().listen(
    (AuthUser? user) => print(
      user == null
          ? 'state: signed out'
          : 'state: signed in (anonymous: ${user.isAnonymous})',
    ),
  );
  await Future<void>.delayed(Duration.zero);

  // An anonymous user keeps its uid when it links a Google account.
  final UserCredential guest = await auth.signInAnonymously();
  final String unique = '${DateTime.now().microsecondsSinceEpoch}';
  final UserCredential linked = await auth.linkWithCredential(
    GoogleAuthProvider.credential(
      idToken: _fakeGoogleIdToken('google-$unique'),
    ),
  );
  print('linked Google, same user: ${linked.uid == guest.uid}');
  print(
    'providers: ${linked.providerData.map((UserInfo i) => i.providerId).join(', ')}',
  );

  // Passwordless sign-in: the email carries a link that the app passes back.
  final String email = 'ada$unique@example.com';
  await auth.sendSignInLinkToEmail(
    email: email,
    actionCodeSettings: const ActionCodeSettings(
      url: 'https://example.com/finish-sign-in',
      handleCodeInApp: true,
    ),
  );
  final String link = await _lastEmailLink(emulator, email);
  print('is a sign-in link: ${auth.isSignInWithEmailLink(link)}');
  final UserCredential byLink = await auth.signInWithEmailLink(
    email: email,
    emailLink: link,
  );
  print(
    'signed in by link: new account ${byLink.additionalUserInfo?.isNewUser}, '
    'email verified ${byLink.emailVerified}',
  );

  // The Google account goes back to the first user, who then unlinks it.
  await auth.signInWithCredential(
    GoogleAuthProvider.credential(
      idToken: _fakeGoogleIdToken('google-$unique'),
    ),
  );
  final AuthUser unlinked = await auth.unlink(GoogleAuthProvider.PROVIDER_ID);
  print('unlinked Google, providers left: ${unlinked.providerData.length}');

  await auth.signOut();
  await Future<void>.delayed(Duration.zero);
  await auth.dispose();
  await app.delete();
}

/// An unsigned JWT with a subject: the emulator takes it for a Google ID token.
String _fakeGoogleIdToken(String subject) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none'})}.${part(<String, Object?>{'sub': subject, 'name': 'Ada'})}.';
}

/// The last sign-in link the emulator "sent" to [email].
Future<String> _lastEmailLink(String emulator, String email) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(
      Uri.parse('http://$emulator/emulator/v1/projects/demo-test/oobCodes'),
    );
    final Map<String, Object?> body =
        jsonDecode(await utf8.decodeStream(await request.close()))
            as Map<String, Object?>;
    return (body['oobCodes']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .lastWhere(
              (Map<String, Object?> c) => c['email'] == email,
            )['oobLink']!
        as String;
  } finally {
    client.close();
  }
}
