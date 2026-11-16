// The token provider hook of CloudFirestoreDart.use, against a Firestore
// emulator. Needs FIRESTORE_EMULATOR_HOST; skipped without it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];

/// A signed-in user with an unsigned ID token, which the emulator accepts.
class _FakeUser implements dart_app.InternalTokenProvider {
  int tokenRequests = 0;

  @override
  String? get uid => 'user-1';

  @override
  Stream<dart_app.InternalTokenResult> get onTokenChanged =>
      const Stream<dart_app.InternalTokenResult>.empty();

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) async {
    tokenRequests++;
    String part(Map<String, Object?> json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final String token =
        '${part(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
        '${part(<String, Object?>{
          'iss': 'https://securetoken.google.com/demo-test',
          'aud': 'demo-test',
          'auth_time': now,
          'user_id': 'user-1',
          'sub': 'user-1',
          'iat': now,
          'exp': now + 3600,
          'firebase': <String, Object?>{'sign_in_provider': 'custom', 'identities': <String, Object?>{}},
        })}.';
    return dart_app.GetTokenResult(token);
  }
}

void main() {
  test(
    'requests use the provider that tokenProviderFor returns',
    skip: _emulator == null
        ? 'Set FIRESTORE_EMULATOR_HOST to run the emulator tests'
        : null,
    () async {
      final _FakeUser user = _FakeUser();
      final List<String> asked = <String>[];
      CloudFirestoreDart.use(
        useDartCore: true,
        tokenProviderFor: (FirebaseApp app) {
          asked.add(app.name);
          return user;
        },
      );
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'with-user',
        options: const FirebaseOptions(
          apiKey: 'emulator-api-key',
          appId: '1:1:web:1',
          messagingSenderId: '1',
          projectId: 'demo-test',
        ),
      );
      final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
        app: app,
      );
      final List<String> hostAndPort = _emulator!.split(':');
      firestore.useFirestoreEmulator(
        hostAndPort[0],
        int.parse(hostAndPort[1]),
        automaticHostMapping: false,
      );
      final DocumentReference<Map<String, dynamic>> ref = firestore.doc(
        'platform-tests/auth-${DateTime.now().microsecondsSinceEpoch}',
      );
      await ref.set(<String, Object?>{'by': 'user-1'});
      expect((await ref.get()).get('by'), 'user-1');
      expect(asked, <String>['with-user']);
      expect(user.tokenRequests, greaterThan(0));
      await firestore.terminate();
    },
  );
}
