// Child process of emulator_host_from_environment_test.dart: prints what
// FirebaseDatabase.emulatorHostFromEnvironment reads in this process, as JSON.
import 'dart:convert';

import 'package:firebase_database_dart/firebase_database_dart.dart';

void main() {
  print(jsonEncode(FirebaseDatabase.emulatorHostFromEnvironment));
}
