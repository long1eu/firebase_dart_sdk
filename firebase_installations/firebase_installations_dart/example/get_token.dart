// Gets an auth token, then forces a new one. Tokens are credentials: this
// example prints only their length.
//
//     dart run example/get_token.dart --api-key <key> --app-id <id> --project-id <project>

import 'package:firebase_installations_dart/firebase_installations_dart.dart';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final FirebaseInstallations installations = exampleInstallations(arguments);
  try {
    final ({String id, String token}) pair = await installations
        .getIdAndToken();
    print('Token of ${pair.id}: ${pair.token.length} characters');
    final String refreshed = await installations.getToken(forceRefresh: true);
    print('A new token: ${refreshed != pair.token}');
  } on FirebaseInstallationsException catch (e) {
    print('Failed: ${e.code} (HTTP ${e.httpStatus}) ${e.serverMessage ?? ''}');
  } finally {
    await installations.close();
    await installations.store.close();
  }
}
