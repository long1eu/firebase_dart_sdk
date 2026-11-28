// Exchanges a debug token for an App Check token and prints its length and
// expiry.
//
// A debug token is a secret. Create one for your app in the Firebase console
// (App Check, Apps, Manage debug tokens), put it in the environment variable
// FIREBASE_APPCHECK_DEBUG_TOKEN, and delete it in the console when you are
// done. This program never prints it.
//
//     FIREBASE_APPCHECK_DEBUG_TOKEN=<token> \
//       dart run example/debug_provider.dart --api-key <key> --app-id <id> --project-id <project>

import 'package:args/args.dart';
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:firebase_app_check_dart/io.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = exampleParser();
  final FirebaseApp app = exampleApp(parser, parser.parse(arguments));
  final FirebaseAppCheck appCheck = FirebaseAppCheck(
    app,
    // Throws a StateError that names the variable, never its value, when it
    // is unset or not a version 4 UUID.
    provider: debugProviderFromEnvironment(),
    logger: exampleLogger,
    autoRefresh: false,
  );
  try {
    final AppCheckToken token = await appCheck.getToken();
    print(describeToken(token));
  } on FirebaseAppCheckException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await appCheck.close();
  }
}
