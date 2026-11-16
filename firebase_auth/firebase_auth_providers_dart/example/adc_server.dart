// Application Default Credentials on a server: the token provider of a
// backend on Cloud Run, Compute Engine or GKE, or of a tool on your machine.
//
//     gcloud auth application-default login      (on your machine; not needed on Google Cloud)
//     FIREBASE_PROJECT_ID=my-project dart run example/adc_server.dart [document path]
//
// Needs a real project and network access: there is no emulator for this.
// The credentials are, in this order, the key file named by
// GOOGLE_APPLICATION_CREDENTIALS, the ones of `gcloud auth application-default
// login`, and the service account of the machine (metadata server). The
// account needs the Cloud Datastore User role. The program reads one document
// (default examples/adc) and writes nothing. Without FIREBASE_PROJECT_ID it
// prints this note and exits.
//
// These credentials bypass the security rules: access is decided by IAM, and
// request.auth is not a Firebase user. Dart VM only (adc.dart needs dart:io).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart';

Future<void> main(List<String> arguments) async {
  final String? projectId = Platform.environment['FIREBASE_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    print(
      'Set FIREBASE_PROJECT_ID to the id of your project (see the comment at '
      'the top of this file).',
    );
    return;
  }
  final String path = arguments.isEmpty ? 'examples/adc' : arguments.first;

  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      // An empty API key is not sent with Firestore requests.
      apiKey: '',
      // Any non-empty id works outside of Android and iOS.
      appId: '1:1234567890:dart:server',
      projectId: projectId,
    ),
  );
  // Before the Firestore instance is created: Firestore reads the provider of
  // the app once. The credentials are looked up when the first request needs
  // a token.
  app.authProvider = applicationDefaultCredentials();

  // A server has no use for a cache on disk: the default memory cache.
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
  try {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await firestore
        .doc(path)
        .get(Source.server);
    print('$path exists: ${snapshot.exists}');
  } on FirestoreException catch (e) {
    // unauthenticated: no credentials were found, or they were refused;
    // permission-denied: the account lacks the Cloud Datastore User role.
    print('reading $path failed: ${e.errorCode}: ${e.message}');
    exitCode = 1;
  } finally {
    // Release the gRPC channel so that the process can exit.
    await firestore.terminate();
    await app.delete();
  }
}
