// The default app and named apps: create them, look them up, and see what
// happens when a name is taken or unknown.
//
//     dart run example/default_and_named_apps.dart
//
// Needs nothing else: no emulator, no network. A program usually has one
// app; a second one is for another project, or for a second user of the same
// project (each app has its own token provider and its own Firestore
// instance).

import 'package:firebase_app_dart/firebase_app_dart.dart';

void main() {
  // Without a name: the default app, called [DEFAULT].
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      appId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
  );
  print('default app: ${app.name}');
  print('FirebaseApp.instance is it: ${identical(FirebaseApp.instance, app)}');

  // With a name: another app, here for another project.
  final FirebaseApp reports = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      appId: '1:1234567890:dart:reports',
      projectId: 'reports-project',
    ),
    name: 'reports',
  );
  print(
    'getInstance finds it: '
    '${identical(FirebaseApp.getInstance('reports'), reports)}',
  );
  // Leading and trailing white space is not part of a name.
  print(
    'names are trimmed: '
    '${identical(FirebaseApp.getInstance(' reports '), reports)}',
  );

  print(
    'all apps: ${FirebaseApp.apps.map((FirebaseApp a) => a.name).join(', ')}',
  );

  // A name can be used by one app at a time.
  try {
    FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: '<YOUR_API_KEY>',
        appId: '1:1234567890:dart:reports',
        projectId: 'reports-project',
      ),
      name: 'reports',
    );
  } on StateError catch (e) {
    print('a second "reports" app: ${e.message}');
  }

  // An unknown name throws, and the message lists the names that exist.
  try {
    FirebaseApp.getInstance('missing');
  } on StateError catch (e) {
    print('an unknown name: ${e.message}');
  }
}
