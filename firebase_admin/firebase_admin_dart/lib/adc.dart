/// An [AdminCredential] from Application Default Credentials, for servers and command line tools on Google
/// Cloud. Needs `dart:io`: import this library only in code that does not run on the web.
///
/// ```dart
/// import 'package:firebase_admin_dart/adc.dart';
/// import 'package:firebase_admin_dart/auth.dart';
///
/// final FirebaseAdminApp app = FirebaseAdminApp(
///   projectId: 'my-project',
///   credential: applicationDefaultCredential(),
/// );
/// ```
library;

import 'package:firebase_auth_providers_dart/adc.dart';
import 'package:http/http.dart' as http;

import 'src/credential.dart';

/// [AdminCredential.iam] on top of Application Default Credentials (`applicationDefaultCredentials` of
/// `firebase_auth_providers_dart`, which looks up `GOOGLE_APPLICATION_CREDENTIALS`, the credentials of
/// `gcloud auth application-default login` and the metadata server, in that order).
///
/// Admin calls use its access tokens; custom tokens are signed by the IAM Credentials API as
/// [serviceAccountEmail], by default the default service account of the metadata server (Cloud Run, Cloud
/// Functions, GKE, Compute Engine). Off Google Cloud, pass [serviceAccountEmail], or load the key file yourself
/// and use [AdminCredential.serviceAccount] to sign locally.
///
/// [quotaProjectId] is sent as `X-Goog-User-Project`, which Google APIs may require with the credentials of a
/// person. [httpClient] is used for the token requests and is not closed.
AdminCredential applicationDefaultCredential({
  String? serviceAccountEmail,
  String? quotaProjectId,
  http.Client? httpClient,
}) => AdminCredential.iam(
  applicationDefaultCredentials(
    scopes: AdminCredential.scopes,
    httpClient: httpClient,
  ),
  serviceAccountEmail: serviceAccountEmail,
  quotaProjectId: quotaProjectId,
);
