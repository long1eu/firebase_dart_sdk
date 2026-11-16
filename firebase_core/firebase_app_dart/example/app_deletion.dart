// Deleting an app: what is left of it, who hears about it, and how the name
// becomes free again.
//
//     dart run example/app_deletion.dart
//
// Needs nothing else: no emulator, no network. cloud_firestore_dart listens to
// onDeleteApp and shuts down the Firestore instances of a deleted app; call
// `terminate()` on them yourself first when you need to wait for that.

import 'package:firebase_app_dart/firebase_app_dart.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: '<YOUR_API_KEY>',
  appId: '1:1234567890:dart:example',
  projectId: 'my-project',
);

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(_options, name: 'session');

  // onDeleteApp emits the name once, when the app is deleted.
  final Future<String> deleted = app.onDeleteApp.first;
  app.delete();
  print('onDeleteApp: ${await deleted}');

  // The app is gone from the registry.
  print('still listed: ${FirebaseApp.apps.contains(app)}');
  try {
    FirebaseApp.getInstance('session');
  } on StateError {
    print('getInstance: no such app');
  }

  // Its name and options can no longer be read.
  try {
    print(app.name);
  } on StateError catch (e) {
    print('app.name: ${e.message}');
  }

  // Deleting twice does nothing.
  app.delete();

  // The name is free: a new app can take it.
  final FirebaseApp again = FirebaseApp.withOptions(_options, name: 'session');
  print('new app: ${again.name}, same object: ${identical(again, app)}');

  // The persistence key of the deleted app can still be computed, for example
  // to remove files that a service stored for it.
  print(
    'persistence key: '
    '${FirebaseApp.getPersistenceKeyFor('session', _options.appId)}',
  );
}
