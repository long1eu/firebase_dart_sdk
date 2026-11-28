// Gets the installation id (FID) and prints each id change.
//
//     dart run example/get_id.dart --api-key <key> --app-id <id> --project-id <project>

import 'dart:async';

import 'package:firebase_installations_dart/firebase_installations_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseInstallations installations = exampleInstallations(arguments);
  final StreamSubscription<String> changes = installations.onIdChange.listen(
    (String id) => print('New installation id: $id'),
  );
  try {
    final String id = await installations.getId();
    print('Installation id: $id');
    // A second call returns the same id from the store.
    print('Same id again: ${await installations.getId() == id}');
  } finally {
    await changes.cancel();
    await installations.close();
    await installations.store.close();
  }
}
