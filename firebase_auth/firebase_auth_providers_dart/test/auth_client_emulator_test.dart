// The client features of 0.3 against the Firebase Auth emulator: the full user record, the auth streams, the
// language and tenants, email link sign-in, credentials (federated sign-in with fake ID tokens), linking and
// unlinking, and the ready-made storages. What the emulator does not implement is said in each group.
//
//     tool/start_auth_emulators.sh        # repository root; prints the export
//     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197 dart test test/auth_client_emulator_test.dart
//
// Skipped unless FIREBASE_AUTH_EMULATOR_HOST is set. The project of the emulator is demo-test (the one
// tool/start_auth_emulators.sh starts), or FIREBASE_AUTH_EMULATOR_PROJECT. Never talks to the real service.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

int _counter = 0;
String uniqueEmail([String prefix = 'user']) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}x${_counter++}@example.com';

Matcher throwsAuth(Object code) => throwsA(
  isA<FirebaseAuthException>().having(
    (FirebaseAuthException e) => e.code,
    'code',
    code,
  ),
);

final String? host = FirebaseUserAuth.emulatorHostFromEnvironment;
final String project =
    Platform.environment['FIREBASE_AUTH_EMULATOR_PROJECT'] ?? 'demo-test';

/// A request to the emulator's own REST endpoints (as the project owner where it needs one).
Future<Map<String, Object?>> emulatorCall(
  String method,
  String path, [
  Map<String, Object?>? body,
]) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(
      method,
      Uri.parse('http://$host/$path'),
    );
    request.headers
      ..set('Authorization', 'Bearer owner')
      ..contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final HttpClientResponse response = await request.close();
    final String text = await utf8.decodeStream(response);
    return text.isEmpty
        ? <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

/// The last action code the emulator "sent" to [email] for [requestType], as the whole entry (`oobCode`,
/// `oobLink`, ...).
Future<Map<String, Object?>> lastOob(String email, String requestType) async {
  final Map<String, Object?> body = await emulatorCall(
    'GET',
    'emulator/v1/projects/$project/oobCodes',
  );
  final List<Map<String, Object?>> codes =
      (body['oobCodes'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .where(
            (Map<String, Object?> c) =>
                c['email'] == email && c['requestType'] == requestType,
          )
          .toList();
  expect(codes, isNotEmpty, reason: 'no $requestType code for $email');
  return codes.last;
}

void main() {
  final String? skip = host == null
      ? 'FIREBASE_AUTH_EMULATOR_HOST is not set (start the emulators with tool/start_auth_emulators.sh)'
      : null;

  late InMemoryAuthStorage storage;
  final List<FirebaseUserAuth> created = <FirebaseUserAuth>[];

  FirebaseUserAuth create({AuthStorage? withStorage}) {
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'fake-api-key',
      emulatorHost: host,
      storage: withStorage ?? storage,
    );
    created.add(auth);
    return auth;
  }

  setUp(() => storage = InMemoryAuthStorage());

  tearDown(() async {
    for (final FirebaseUserAuth auth in created) {
      await auth.dispose();
    }
    created.clear();
  });

  group('user record', () {
    test(
      'sign-up and sign-in read metadata, providers and AdditionalUserInfo',
      () async {
        final FirebaseUserAuth auth = create();
        final String email = uniqueEmail();
        final DateTime before = DateTime.now().toUtc().subtract(
          const Duration(seconds: 5),
        );
        final UserCredential signUp = await auth.createUserWithEmailAndPassword(
          email: email,
          password: 'correct horse',
        );
        expect(signUp.additionalUserInfo?.isNewUser, isTrue);
        expect(signUp.additionalUserInfo?.providerId, 'password');
        expect(signUp.metadata.creationTime, isNotNull);
        expect(signUp.metadata.creationTime!.isAfter(before), isTrue);
        expect(signUp.metadata.lastSignInTime, isNotNull);
        expect(signUp.providerData.single.providerId, 'password');
        expect(signUp.providerData.single.email, email);
        expect(signUp.providerData.single.uid, email);
        expect(signUp.phoneNumber, isNull);
        expect(signUp.tenantId, isNull);
        await auth.signOut();

        final UserCredential signIn = await auth.signInWithEmailAndPassword(
          email: email,
          password: 'correct horse',
        );
        expect(signIn.additionalUserInfo?.isNewUser, isFalse);
        expect(signIn.additionalUserInfo?.providerId, 'password');
        expect(signIn.metadata.creationTime, signUp.metadata.creationTime);

        final UserCredential anonymous = await auth.signInAnonymously();
        expect(anonymous.additionalUserInfo?.isNewUser, isTrue);
        expect(anonymous.additionalUserInfo?.providerId, isNull);
        expect(anonymous.providerData, isEmpty);
        expect(anonymous.isAnonymous, isTrue);
      },
      skip: skip,
    );

    test('the stored record is restored by a new instance', () async {
      final FirebaseUserAuth first = create();
      final UserCredential signUp = await first.createUserWithEmailAndPassword(
        email: uniqueEmail(),
        password: 'correct horse',
      );
      await first.updateProfile(displayName: 'Ada');
      final FirebaseUserAuth second = create();
      await second.restore();
      expect(second.currentUser!.metadata, signUp.metadata);
      expect(second.currentUser!.providerData, signUp.providerData);
      expect(second.currentUser!.displayName, 'Ada');
      await second.reload();
      // The emulator copies the new display name into the password provider's entry.
      expect(second.currentUser!.providerData.single.providerId, 'password');
      expect(second.currentUser!.providerData.single.displayName, 'Ada');
    }, skip: skip);
  });

  group('streams and state', () {
    test(
      'authStateChanges, idTokenChanges and updateCurrentUser with real tokens',
      () async {
        final FirebaseUserAuth first = create();
        final FirebaseUserAuth second = create(
          withStorage: InMemoryAuthStorage(),
        );
        final List<String?> states = <String?>[];
        final List<String?> tokens = <String?>[];
        second.authStateChanges().listen((AuthUser? u) => states.add(u?.uid));
        second.idTokenChanges().listen((AuthUser? u) => tokens.add(u?.uid));
        final UserCredential signedIn = await first
            .createUserWithEmailAndPassword(
              email: uniqueEmail(),
              password: 'correct horse',
            );
        await second.updateCurrentUser(first.currentUser);
        expect(second.uid, signedIn.uid);
        // The copied session refreshes on its own.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final String token = (await second.getAccessToken(
          forceRefresh: true,
        )).token;
        expect(
          token,
          isNot((await first.getAccessToken(forceRefresh: false)).token),
        );
        await second.reload();
        await second.signOut();
        await Future<void>.delayed(Duration.zero);
        expect(states, <String?>[null, signedIn.uid, null]);
        expect(tokens, <String?>[null, signedIn.uid, signedIn.uid, null]);
        expect(first.uid, signedIn.uid);
      },
      skip: skip,
    );
  });
}
