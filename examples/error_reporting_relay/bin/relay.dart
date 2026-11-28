// The Error Reporting relay as a server. Configuration from the environment:
//
//   PROJECT_ID          the Firebase / Google Cloud project
//   PROJECT_NUMBER      optional: makes the App Check check exact
//   SERVICES            the allowed service names, comma-separated (for example notes-desktop,notes-web)
//   REQUIRE_APP_CHECK   "false" to accept requests without an App Check token (development only)
//   PORT                default 8080
//
// The forwarding credential is Application Default Credentials: on Cloud Run the service account of the
// service, which needs the role Error Reporting Writer (roles/errorreporting.writer) and nothing else.

import 'dart:io';

import 'package:error_reporting_relay/error_reporting_relay.dart';
import 'package:firebase_admin_dart/firebase_admin_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final String projectId =
      env['PROJECT_ID'] ?? (throw StateError('Set PROJECT_ID.'));
  final Set<String> services = (env['SERVICES'] ?? '')
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toSet();
  if (services.isEmpty) {
    throw StateError('Set SERVICES to the allowed service names.');
  }
  final OAuthTokenProvider credentials = applicationDefaultCredentials(
    scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
  );
  // Token checks need no credential; the admin app only names the project.
  final FirebaseAdminApp admin = FirebaseAdminApp(
    projectId: projectId,
    credential: AdminCredential.iam(credentials),
  );

  final Handler handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(
        relayGuard(
          verifier: AdminCallerVerifier(
            admin,
            projectNumber: env['PROJECT_NUMBER'],
          ),
          requireAppCheck: env['REQUIRE_APP_CHECK'] != 'false',
          log: stderr.writeln,
        ),
      )
      .addHandler(
        errorReportingRelay(
          projectId: projectId,
          services: services,
          accessToken: () async =>
              (await credentials.getAccessToken(forceRefresh: false)).token,
          log: stderr.writeln,
        ),
      );
  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    int.parse(env['PORT'] ?? '8080'),
  );
  stdout.writeln(
    'Error Reporting relay on port ${server.port} for ${services.join(', ')}',
  );
}
