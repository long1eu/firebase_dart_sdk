// Calls the callable function `echo` of a Firebase project and prints what it
// answers.
//
//     dart run example/main.dart <api key> <app id> <project id>

import 'dart:io';

import 'package:cloud_functions_dart/cloud_functions_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run example/main.dart <api key> <app id> <project id>',
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
  final FirebaseFunctions functions = FirebaseFunctions(app);
  try {
    final HttpsCallableResult result = await functions
        .httpsCallable('echo')
        .call(<String, Object?>{'hello': 'world'});
    print('echo answered: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await functions.close();
  }
}
