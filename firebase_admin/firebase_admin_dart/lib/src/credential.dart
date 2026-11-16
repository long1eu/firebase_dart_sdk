import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

import 'app.dart';

/// Who the admin calls run as, and how data (custom tokens) gets signed. Pass it to [FirebaseAdminApp].
///
/// * [AdminCredential.serviceAccount]: a service account key. Access tokens by the JWT bearer flow, custom tokens
///   signed locally. For machines you control: CI, a CLI, a test runner.
/// * [AdminCredential.iam]: access tokens from any source, custom tokens signed by the IAM Credentials API
///   (`signBlob`), so no private key is held. For Google Cloud with Application Default Credentials:
///   `applicationDefaultCredential()` in `package:firebase_admin_dart/adc.dart` builds one.
///
/// For the emulators use [FirebaseAdminApp.emulator], which needs no credential.
///
/// **Admin credentials bypass security rules and can act as any user.** Never put a service account key in an
/// app, a web page, a Flutter asset of a release build, or a repository.
sealed class AdminCredential {
  const AdminCredential._();

  /// A service account key: [json] is the decoded content of the key file (a `Map`) or the content itself (a
  /// `String`), as you loaded it. The package never reads a file or an environment variable for it.
  ///
  /// Throws an [ArgumentError] if [json] is not a service account key (the error does not quote it).
  ///
  /// ```dart
  /// import 'dart:convert';
  /// import 'dart:io';
  ///
  /// import 'package:firebase_admin_dart/firebase_admin_dart.dart';
  ///
  /// FirebaseAdminApp appFromKeyFile(String path) {
  ///   final Map<String, Object?> key =
  ///       jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  ///   return FirebaseAdminApp(
  ///     projectId: key['project_id']! as String,
  ///     credential: AdminCredential.serviceAccount(key),
  ///   );
  /// }
  /// ```
  factory AdminCredential.serviceAccount(Object json) =
      ServiceAccountCredential;

  /// Access tokens from [tokens] (they need the [scopes]), and custom tokens signed by the IAM Credentials API
  /// as [serviceAccountEmail]. Without [serviceAccountEmail] the email of the default service account comes from
  /// the metadata server (Cloud Run, Cloud Functions, GKE, Compute Engine).
  ///
  /// Signing needs the IAM Service Account Credentials API enabled in the project, and the role Service Account
  /// Token Creator (`iam.serviceAccounts.signBlob`) for the caller on the signing account; each token is one
  /// request, counted against 60,000 signing requests per project per minute.
  ///
  /// [quotaProjectId] is sent as `X-Goog-User-Project`: Google APIs may require it when [tokens] are the
  /// credentials of a person (`gcloud auth application-default login`) rather than of a service account.
  ///
  /// ```dart
  /// import 'package:firebase_admin_dart/firebase_admin_dart.dart';
  /// import 'package:firebase_auth_providers_dart/adc.dart';
  ///
  /// final FirebaseAdminApp app = FirebaseAdminApp(
  ///   projectId: 'my-project',
  ///   credential: AdminCredential.iam(
  ///     applicationDefaultCredentials(scopes: AdminCredential.scopes),
  ///   ),
  /// );
  /// ```
  factory AdminCredential.iam(
    OAuthTokenProvider tokens, {
    String? serviceAccountEmail,
    String? quotaProjectId,
  }) = IamCredential;

  /// The OAuth scopes the admin calls need: `cloud-platform` (Identity Toolkit, IAM Credentials and the other
  /// Google Cloud APIs) and `identitytoolkit`.
  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/identitytoolkit',
  ];
}

/// [AdminCredential.serviceAccount]. Not exported.
final class ServiceAccountCredential extends AdminCredential {
  /// Parses the key of [json].
  ServiceAccountCredential(this.json)
    : key = ServiceAccountKey.fromJson(json),
      super._();

  /// The key file as it was passed.
  final Object json;

  /// The parsed key.
  final ServiceAccountKey key;

  @override
  String toString() => 'AdminCredential.serviceAccount(${key.clientEmail})';
}

/// [AdminCredential.iam]. Not exported.
final class IamCredential extends AdminCredential {
  /// See [AdminCredential.iam].
  IamCredential(this.tokens, {this.serviceAccountEmail, this.quotaProjectId})
    : super._();

  /// The source of access tokens.
  final OAuthTokenProvider tokens;

  /// The signing account, or null for the default account of the metadata server.
  final String? serviceAccountEmail;

  /// Sent as `X-Goog-User-Project`, or null.
  final String? quotaProjectId;

  @override
  String toString() =>
      'AdminCredential.iam(${serviceAccountEmail ?? 'default'})';
}
