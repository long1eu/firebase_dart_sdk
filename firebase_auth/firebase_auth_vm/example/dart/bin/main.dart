import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_vm/firebase_auth_vm.dart';

import '../lib/example.dart';

// ignore_for_file: avoid_relative_lib_imports
Future<void> main(List<String> arguments, [Map<String, String> config]) async {
  printTitle();

  final Progress progress = Progress('Initializing')..show();
  if (arguments.isNotEmpty) {
    final File configFile = File(arguments[0]);
    // ignore: parameter_assignments
    config =
        Map<String, String>.from(jsonDecode(await configFile.readAsString()));
  }

  await init(config);
  await progress.cancel();

  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    await noUserWelcome();
  } else {
    await userWelcome();
  }

  close();
}
