// Creates the default app and a named app, then reads them back.
//
//     dart run example/main.dart

import 'package:firebase_app_dart/firebase_app_dart.dart';

void main() {
  // On platforms Firebase does not register apps for (desktop, servers), any
  // unique application id works; see the package README.
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
  );
  print('default app: ${app.name}, project ${app.options.projectId}');

  final FirebaseApp secondary = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:dart:secondary',
      projectId: 'other-project',
    ),
    name: 'secondary',
  );
  print('named app: ${secondary.name}');
  print(
      'lookup: ${identical(FirebaseApp.getInstance('secondary'), secondary)}');
}
