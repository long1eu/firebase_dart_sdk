// The token provider hook of CloudFirestoreDart.use, against a Firestore
// emulator: a plain AuthTokenProvider, and the FlutterFireAuthTokenProvider of
// cloud_firestore_dart_flutterfire (driven by a fake user instead of the
// firebase_auth plugin). Needs FIRESTORE_EMULATOR_HOST; skipped without it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_dart_flutterfire/cloud_firestore_dart_flutterfire.dart';
import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];

/// An unsigned ID token for [uid], which the emulator accepts.
String _token(String uid) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${part(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
      '${part(<String, Object?>{
        'iss': 'https://securetoken.google.com/demo-test',
        'aud': 'demo-test',
        'auth_time': now,
        'user_id': uid,
        'sub': uid,
        'iat': now,
        'exp': now + 3600,
        'firebase': <String, Object?>{'sign_in_provider': 'custom', 'identities': <String, Object?>{}},
      })}.';
}

/// A token provider written by hand.
class _PlainProvider implements dart_app.AuthTokenProvider {
  int tokenRequests = 0;

  @override
  String? get uid => 'user-1';

  @override
  Stream<dart_app.AuthTokenChange> get onTokenChanged =>
      const Stream<dart_app.AuthTokenChange>.empty();

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) async {
    tokenRequests++;
    return dart_app.GetTokenResult(_token('user-1'));
  }
}

/// The signed-in user of a fake firebase_auth.
class _FakeUser implements IdTokenUser {
  int tokenRequests = 0;

  @override
  String get uid => 'user-2';

  @override
  Future<String?> getIdToken({required bool forceRefresh}) async {
    tokenRequests++;
    return _token(uid);
  }
}

void main() {
  final Object? skip = _emulator == null
      ? 'Set FIRESTORE_EMULATOR_HOST to run the emulator tests'
      : null;
  final _PlainProvider plain = _PlainProvider();
  final _FakeUser bridgeUser = _FakeUser();
  final List<String> asked = <String>[];

  setUpAll(() {
    CloudFirestoreDart.use(
      useDartCore: true,
      tokenProviderFor: (FirebaseApp app) {
        asked.add(app.name);
        return switch (app.name) {
          'with-user' => plain,
          // What an app with the official firebase_auth writes is
          // FlutterFireAuthTokenProvider(FirebaseAuth.instanceFor(app: app));
          // fromSource takes the user from a fake instead of the plugin.
          'with-bridge' => FlutterFireAuthTokenProvider.fromSource(
            currentUser: () => bridgeUser,
            idTokenChanges: Stream<IdTokenUser?>.value(bridgeUser),
          ),
          _ => null,
        };
      },
    );
  });

  Future<FirebaseFirestore> firestoreFor(String name) async {
    final FirebaseApp app = await Firebase.initializeApp(
      name: name,
      options: const FirebaseOptions(
        apiKey: 'emulator-api-key',
        appId: '1:1:web:1',
        messagingSenderId: '1',
        projectId: 'demo-test',
      ),
    );
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
    final List<String> hostAndPort = _emulator!.split(':');
    firestore.useFirestoreEmulator(
      hostAndPort[0],
      int.parse(hostAndPort[1]),
      automaticHostMapping: false,
    );
    return firestore;
  }

  Future<void> writeAndRead(FirebaseFirestore firestore, String by) async {
    final DocumentReference<Map<String, dynamic>> ref = firestore.doc(
      'platform-tests/auth-$by-${DateTime.now().microsecondsSinceEpoch}',
    );
    await ref.set(<String, Object?>{'by': by});
    expect((await ref.get()).get('by'), by);
    await firestore.terminate();
  }

  test(
    'requests use the provider that tokenProviderFor returns',
    skip: skip,
    () async {
      await writeAndRead(await firestoreFor('with-user'), 'user-1');
      expect(asked, contains('with-user'));
      expect(plain.tokenRequests, greaterThan(0));
    },
  );

  test(
    'the FlutterFireAuthTokenProvider of the bridge works as the provider',
    skip: skip,
    () async {
      await writeAndRead(await firestoreFor('with-bridge'), 'user-2');
      expect(asked, contains('with-bridge'));
      expect(bridgeUser.tokenRequests, greaterThan(0));
    },
  );
}
