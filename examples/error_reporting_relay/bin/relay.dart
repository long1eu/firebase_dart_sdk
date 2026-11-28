// The Error Reporting relay as a server. Configuration from the environment:
//
//   PROJECT_ID          the Firebase / Google Cloud project
//   PROJECT_NUMBER      optional: makes the App Check check exact
//   SERVICES            the allowed service names, comma-separated (for example notes-desktop,notes-web)
//   APP_SERVICES        optional: which app may report as which service, as service@appId pairs, comma-separated
//                       (for example notes-desktop@1:123:windows:abc,notes-web@1:123:web:def)
//   TRUSTED_PROXY_HOPS  how many proxies append to X-Forwarded-For (1 on Cloud Run); used only without App Check
//   REQUIRE_APP_CHECK   "false" to accept requests without an App Check token: development only, and refused
//                       unless HOST is a loopback address
//   HOST                default 0.0.0.0
//   PORT                default 8080
//
// The forwarding credential is Application Default Credentials: on Cloud Run the service account of the
// service, which needs the role Error Reporting Writer (roles/errorreporting.writer) and nothing else. Reports
// are accepted on POST /errors only.

import 'dart:io';

import 'package:error_reporting_relay/error_reporting_relay.dart';
import 'package:firebase_admin_dart/firebase_admin_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart';
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  String? value(String name) {
    final String? raw = env[name]?.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  final String projectId =
      value('PROJECT_ID') ?? (throw StateError('Set PROJECT_ID.'));
  final Set<String> services = (value('SERVICES') ?? '')
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toSet();
  if (services.isEmpty) {
    throw StateError('Set SERVICES to the allowed service names.');
  }
  Map<String, Set<String>>? servicesByApp;
  final String? appServices = value('APP_SERVICES');
  if (appServices != null) {
    servicesByApp = <String, Set<String>>{};
    for (final String pair in appServices.split(',')) {
      final int at = pair.indexOf('@');
      if (at <= 0 || at == pair.length - 1) {
        throw StateError('APP_SERVICES must be service@appId pairs.');
      }
      servicesByApp
          .putIfAbsent(pair.substring(at + 1).trim(), () => <String>{})
          .add(pair.substring(0, at).trim());
    }
  }
  final InternetAddress host = InternetAddress(value('HOST') ?? '0.0.0.0');
  final bool requireAppCheck = value('REQUIRE_APP_CHECK') != 'false';
  if (!requireAppCheck) {
    if (!host.isLoopback) {
      throw StateError(
        'REQUIRE_APP_CHECK=false is for development: set HOST to a loopback address.',
      );
    }
    stderr.writeln(
      'WARNING: App Check is not required; anyone who can reach this relay can report.',
    );
  }

  final OAuthTokenProvider credentials = applicationDefaultCredentials(
    scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
  );
  // Token checks need no credential; the admin app only names the project.
  final FirebaseAdminApp admin = FirebaseAdminApp(
    projectId: projectId,
    credential: AdminCredential.iam(credentials),
  );
  // Throws at start for a PROJECT_NUMBER that is not a number.
  final AdminCallerVerifier verifier = AdminCallerVerifier(
    admin,
    projectNumber: value('PROJECT_NUMBER'),
  );

  final Handler handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(
        relayGuard(
          verifier: verifier,
          path: 'errors',
          requireAppCheck: requireAppCheck,
          trustedProxyHops: int.parse(value('TRUSTED_PROXY_HOPS') ?? '0'),
          log: stderr.writeln,
        ),
      )
      .addHandler(
        errorReportingRelay(
          projectId: projectId,
          services: services,
          servicesByApp: servicesByApp,
          accessToken: ({bool forceRefresh = false}) async =>
              (await credentials.getAccessToken(
                forceRefresh: forceRefresh,
              )).token,
          log: stderr.writeln,
        ),
      );
  final HttpServer server = await serveGuarded(
    handler,
    host,
    int.parse(value('PORT') ?? '8080'),
  );
  stdout.writeln(
    'Error Reporting relay on ${host.address}:${server.port} for ${services.join(', ')}',
  );
}
