// languageCode (X-Firebase-Locale), useDeviceLanguage, and tenantId on the requests that take it.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_providers_dart/src/environment_io.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late FakeBackend backend;
  late FirebaseUserAuth auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.create();
  });

  tearDown(() => auth.dispose());

  /// Every operation that sends a request, once.
  Future<void> everything() async {
    await auth.signInAnonymously();
    await auth.createUserWithEmailAndPassword(
      email: 'a@example.com',
      password: 'secret',
    );
    await auth.signInWithEmailAndPassword(
      email: 'a@example.com',
      password: 'secret',
    );
    await auth.signInWithCustomToken('t');
    await auth.signInWithEmailAndPassword(
      email: 'a@example.com',
      password: 'secret',
    );
    await auth.reauthenticateWithEmailAndPassword(
      email: 'a@example.com',
      password: 'secret',
    );
    backend.on(
      'accounts:resetPassword',
      (_) => jsonResponse(<String, Object?>{
        'requestType': 'PASSWORD_RESET',
        'email': 'a@example.com',
      }),
    );
    await auth.sendPasswordResetEmail(email: 'a@example.com');
    await auth.sendEmailVerification();
    await auth.verifyBeforeUpdateEmail('b@example.com');
    await auth.confirmPasswordReset(code: 'c', newPassword: 'n');
    await auth.checkActionCode('c');
    await auth.applyActionCode('c');
    await auth.fetchSignInMethodsForEmail('a@example.com');
    await auth.updateProfile(displayName: 'Ada');
    await auth.reload();
    await auth.getAccessToken(forceRefresh: true);
    await auth.deleteCurrentUser();
  }

  group('languageCode', () {
    test('none by default: no X-Firebase-Locale', () async {
      expect(auth.languageCode, isNull);
      await everything();
      expect(
        backend.requests.where(
          (http.Request r) => r.headers.containsKey('X-Firebase-Locale'),
        ),
        isEmpty,
      );
    });

    test('sent with every request but the token refresh', () async {
      auth.languageCode = 'pt-BR';
      await everything();
      for (final http.Request request in backend.requests) {
        expect(
          request.headers['X-Firebase-Locale'],
          request.url.pathSegments.last == 'token' ? isNull : 'pt-BR',
          reason: request.url.path,
        );
      }
    });

    test('setLanguageCode, and null for the language of the device', () async {
      await auth.setLanguageCode('fr');
      expect(auth.languageCode, 'fr');
      await auth.setLanguageCode(null);
      expect(auth.languageCode, languageTagOf(Platform.localeName));
      auth.useDeviceLanguage();
      expect(auth.languageCode, languageTagOf(Platform.localeName));
    });

    test('the locale of the process becomes a BCP 47 tag', () {
      expect(languageTagOf('en_US.UTF-8'), 'en-US');
      expect(languageTagOf('de_DE@euro'), 'de-DE');
      expect(languageTagOf('fr-CA'), 'fr-CA');
      expect(languageTagOf('ja'), 'ja');
      expect(languageTagOf('C'), isNull);
      expect(languageTagOf('POSIX'), isNull);
      expect(languageTagOf('C.UTF-8'), isNull);
      expect(languageTagOf(''), isNull);
    });
  });

  group('tenantId', () {
    setUp(() {
      // Every account of the fake backend belongs to the tenant.
      final Future<http.Response> Function(http.Request) answer =
          backend.answer;
      backend.handler = (http.Request request) async {
        if (request.url.pathSegments.last == 'accounts:lookup') {
          final http.Response response = await answer(request);
          final Map<String, Object?> body =
              jsonDecode(response.body) as Map<String, Object?>;
          for (final Object? user in body['users']! as List<Object?>) {
            (user! as Map<String, Object?>)['tenantId'] = 'tenant-1';
          }
          return jsonResponse(body);
        }
        return answer(request);
      };
    });

    test('goes where the JS SDK sends it, and nowhere else', () async {
      auth.tenantId = 'tenant-1';
      await everything();
      const Set<String> withTenant = <String>{
        'accounts:signUp',
        'accounts:signInWithPassword',
        'accounts:signInWithCustomToken',
        'accounts:sendOobCode',
        'accounts:resetPassword',
        'accounts:createAuthUri',
      };
      final Set<String> seen = <String>{};
      for (final http.Request request in backend.requests) {
        final String method = request.url.pathSegments.last;
        seen.add(method);
        if (method == 'token') {
          expect(request.bodyFields, isNot(contains('tenantId')));
          continue;
        }
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        if (method == 'accounts:update') {
          // applyActionCode (oobCode) takes it; the updates with an ID token do not.
          expect(
            body['tenantId'],
            body.containsKey('oobCode') ? 'tenant-1' : isNull,
            reason: '$body',
          );
        } else {
          expect(
            body['tenantId'],
            withTenant.contains(method) ? 'tenant-1' : isNull,
            reason: method,
          );
        }
      }
      expect(seen, containsAll(withTenant));
      expect(auth.currentUser, isNull); // deleted at the end
    });

    test('the user of a sign-in has the tenant', () async {
      auth.tenantId = 'tenant-1';
      final UserCredential result = await auth.signInAnonymously();
      expect(result.tenantId, 'tenant-1');
    });

    test('a user of another tenant is refused: tenant-id-mismatch', () async {
      // The instance is for the project's own users; the backend answers with a tenant user.
      await expectLater(
        auth.signInAnonymously(),
        throwsAuth('tenant-id-mismatch'),
      );
      expect(auth.currentUser, isNull);
      auth.tenantId = 'tenant-2';
      await expectLater(
        auth.signInAnonymously(),
        throwsAuth('tenant-id-mismatch'),
      );
      expect(auth.currentUser, isNull);
    });

    test('the tenant of the ID token counts when the account has none', () async {
      backend.handler = backend.answer;
      backend.on('accounts:signUp', (_) {
        final Map<String, Object?> tokens = backend.tokensFor(
          'anon-user',
          provider: 'anonymous',
        );
        final String token = tokens['idToken']! as String;
        final List<String> parts = token.split('.');
        final Map<String, Object?> claims =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
                )
                as Map<String, Object?>;
        (claims['firebase']! as Map<String, Object?>)['tenant'] = 'tenant-1';
        tokens['idToken'] =
            '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.';
        return jsonResponse(tokens);
      });
      await expectLater(
        auth.signInAnonymously(),
        throwsAuth('tenant-id-mismatch'),
      );
      auth.tenantId = 'tenant-1';
      expect((await auth.signInAnonymously()).tenantId, 'tenant-1');
    });

    test('updateCurrentUser checks the tenant', () async {
      final FirebaseUserAuth other = backend.create(
        storage: InMemoryAuthStorage(),
      )..tenantId = 'tenant-1';
      addTearDown(other.dispose);
      await other.signInAnonymously();
      await expectLater(
        auth.updateCurrentUser(other.currentUser),
        throwsAuth('tenant-id-mismatch'),
      );
      auth.tenantId = 'tenant-1';
      await auth.updateCurrentUser(other.currentUser);
      expect(auth.uid, other.uid);
    });

    test('a request that names a tenant keeps it', () async {
      auth.tenantId = 'tenant-1';
      await auth.sendPasswordResetEmail(email: 'a@example.com');
      expect(
        backend.bodiesOf('accounts:sendOobCode').single['tenantId'],
        'tenant-1',
      );
    });
  });
}
