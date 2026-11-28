// Gets a limited-use App Check token. It is never cached: every call exchanges
// again, and the token is meant to be consumed once by a backend that checks
// for replays (for example a callable function with replay protection).
//
// Needs the same setup as debug_provider.dart:
//
//     FIREBASE_APPCHECK_DEBUG_TOKEN=<token> \
//       dart run example/limited_use.dart --api-key <key> --app-id <id> --project-id <project>

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
    provider: debugProviderFromEnvironment(),
    logger: exampleLogger,
    autoRefresh: false,
  );
  try {
    final AppCheckToken token = await appCheck.getLimitedUseToken();
    print(describeToken(token));
  } on FirebaseAppCheckException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await appCheck.close();
  }
}
