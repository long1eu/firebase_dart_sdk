// Gets an App Check token from a custom provider whose callback returns a token
// that was minted elsewhere, and prints its length and expiry.
//
// A real program asks its own server for a fresh token in the callback (see
// custom_provider.dart); a fixed token is enough to see the package work.
// There is no App Check emulator, and a custom provider sends no request, so
// this example contacts no server:
//
//     dart run example/main.dart <api key> <app id> <project id> <token>

import 'dart:io';

import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run example/main.dart '
      '<api key> <app id> <project id> <token>',
    );
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: arguments[0],
      appId: arguments[1],
      projectId: arguments[2],
    ),
  );
  final String fixedToken = arguments[3];
  final FirebaseAppCheck appCheck = FirebaseAppCheck(
    app,
    provider: CustomAppCheckProvider(
      getToken: ({required bool limitedUse, required bool forceRefresh}) async {
        return AppCheckToken(
          token: fixedToken,
          expireTime: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
      },
    ),
    // A program that exits by itself must not keep the refresh timer alive.
    autoRefresh: false,
  );
  try {
    final AppCheckToken token = await appCheck.getToken();
    print('token of ${token.token.length} characters');
    print('expires ${token.expireTime.toIso8601String()}');
  } on FirebaseAppCheckException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await appCheck.close();
  }
}
