import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../lib/example.dart';

// ignore_for_file: avoid_relative_lib_imports
Future<void> main(List<String> arguments) async {
  printTitle();

  final Progress progress = Progress('Initializing')..show();
  await init();
  await progress.cancel();

  final FirebaseUser user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    await noUserWelcome();
  } else {
    await userWelcome();
  }

  close();
}
