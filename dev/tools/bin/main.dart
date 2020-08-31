// File created by
// Lung Razvan <long1eu>
// on 06/03/2020

import 'package:args/command_runner.dart';
import 'package:firebase_sdk_tools/commands/generate_firebase_options.dart';

void main(List<String> args) {
  CommandRunner<dynamic>(
      'firebase-sdk', 'Provides useful tool to generate the FirebaseOptions object on different platforms') //
    ..addCommand(GenerateFirebaseOptions())
    ..run(args);
}
