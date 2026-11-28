// Creates an installation, then deletes it from the project and from the store.
//
//     dart run example/delete.dart --api-key <key> --app-id <id> --project-id <project>

import 'package:firebase_installations_dart/firebase_installations_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseInstallations installations = exampleInstallations(arguments);
  try {
    final String id = await installations.getId();
    // Wait for the registration, so there is something to delete on the server.
    await installations.getToken();
    await installations.delete();
    print('Deleted $id');
    print('The next getId creates a new id: ${await installations.getId()}');
    await installations.delete();
  } on FirebaseInstallationsException catch (e) {
    print('Failed: ${e.code} (HTTP ${e.httpStatus}) ${e.serverMessage ?? ''}');
  } finally {
    await installations.close();
    await installations.store.close();
  }
}
