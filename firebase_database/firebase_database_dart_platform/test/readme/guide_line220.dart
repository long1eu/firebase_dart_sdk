// GENERATED from the docs by test/readme_snippets_test.dart. Do not edit: change the
// document and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

// ../../docs/guides/database_flutter.md:220
late FirebaseDatabase database;
Future<void> guideLine220() async {
  final DataSnapshot top = await database.ref('players').orderByChild('score').limitToLast(3).get();
  for (final DataSnapshot child in top.children.toList().reversed) {
    print('${child.key}: ${child.value}');
  }
  await database.ref('players/ada').onDisconnect.remove();
}
