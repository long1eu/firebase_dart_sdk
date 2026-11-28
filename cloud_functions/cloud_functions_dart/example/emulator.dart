// The emulator and a signed-in user.
//
// The Functions emulator does not check ID tokens: it decodes any JWT, also an
// unsigned one, and shows the user to the function as `request.auth`. This
// example hands such a token to the client through an AuthTokenProvider and
// asks the fixture function `context` who the function saw.
//
//     ./tool/start_functions_emulator.sh 9501
//     dart run example/emulator.dart --emulator 127.0.0.1:9501

import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions_dart/cloud_functions_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseFunctions functions = exampleFunctions(
    arguments,
    configureApp: (FirebaseApp app) {
      app.authProvider = UnsignedUserProvider('alice');
    },
  );
  try {
    final HttpsCallableResult result = await functions
        .httpsCallable('context')
        .call();
    final Map<String, Object?> seen = result.data! as Map<String, Object?>;
    final Map<String, Object?>? auth = seen['auth'] as Map<String, Object?>?;
    print('the function saw the user ${auth?['uid']}');
  } on FirebaseFunctionsException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await functions.close();
  }
}

/// A user for the emulator: the token is an unsigned JWT and means nothing to a
/// real project.
class UnsignedUserProvider extends AuthTokenProvider {
  UnsignedUserProvider(this.uid);

  @override
  final String uid;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final String header = encode(<String, Object?>{
      'alg': 'none',
      'typ': 'JWT',
    });
    final String payload = encode(<String, Object?>{
      'sub': uid,
      'user_id': uid,
      'firebase': <String, Object?>{'sign_in_provider': 'password'},
    });
    return GetTokenResult('$header.$payload.');
  }

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}
