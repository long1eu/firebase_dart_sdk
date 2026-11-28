// The Analytics relay as a server. Configuration from the environment:
//
//   GA_MEASUREMENT_ID   the G-… id of the GA4 web data stream
//   GA_API_SECRET       a Measurement Protocol API secret of that stream; never printed
//   GA_REGION           optional: "eu" forwards to region1.google-analytics.com (default: www.google-analytics.com)
//   PROJECT_ID          the Firebase project whose App Check and ID tokens are accepted
//   PROJECT_NUMBER      optional: makes the App Check check exact
//   ALLOWED_APP_IDS     optional: the Firebase app ids that may send, comma-separated (checked against the
//                       verified App Check token)
//   REQUIRE_USER        "true" to accept only requests with a valid ID token (default: anonymous allowed; a
//                       token that is sent is always checked)
//   TRUSTED_PROXY_HOPS  how many proxies append to X-Forwarded-For (1 on Cloud Run); used only without App Check
//   MAX_PER_CALLER      optional: requests a minute per App Check token and per user (default 60)
//   MAX_PER_APP         optional: requests a minute per app id (default 600)
//   MAX_PER_MINUTE      optional: requests a minute in all, per instance (default 3000)
//   REQUIRE_APP_CHECK   "false" to accept requests without an App Check token: development only, and refused
//                       unless HOST is a loopback address
//   HOST                default 0.0.0.0
//   PORT                default 8080
//
// Events are accepted on POST /collect only. Checking the tokens needs no credential, only the project id.

import 'dart:io';

import 'package:analytics_relay/analytics_relay.dart';
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

  final String measurementId =
      value('GA_MEASUREMENT_ID') ??
      (throw StateError('Set GA_MEASUREMENT_ID.'));
  final String apiSecret =
      value('GA_API_SECRET') ?? (throw StateError('Set GA_API_SECRET.'));
  final CollectionRegion region = switch (value('GA_REGION')) {
    null || 'global' => CollectionRegion.global,
    'eu' => CollectionRegion.eu,
    _ => throw StateError('GA_REGION must be "eu" or "global".'),
  };
  final String projectId =
      value('PROJECT_ID') ?? (throw StateError('Set PROJECT_ID.'));
  final String? appIds = value('ALLOWED_APP_IDS');
  final Set<String>? allowedAppIds = appIds
      ?.split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toSet();
  if (allowedAppIds != null && allowedAppIds.isEmpty) {
    throw StateError('ALLOWED_APP_IDS names no app.');
  }
  bool flag(String name, {required bool fallback}) => switch (value(name)) {
    null => fallback,
    'true' => true,
    'false' => false,
    _ => throw StateError('$name must be "true" or "false".'),
  };
  int count(String name, {required int fallback, int min = 1}) {
    final String? raw = value(name);
    final int? parsed = raw == null ? fallback : int.tryParse(raw);
    if (parsed == null || parsed < min) {
      throw StateError('$name must be a whole number of at least $min.');
    }
    return parsed;
  }

  final bool requireUser = flag('REQUIRE_USER', fallback: false);
  final InternetAddress host = InternetAddress(value('HOST') ?? '0.0.0.0');
  final bool requireAppCheck = flag('REQUIRE_APP_CHECK', fallback: true);
  if (!requireAppCheck) {
    if (!host.isLoopback) {
      throw StateError(
        'REQUIRE_APP_CHECK=false is for development: set HOST to a loopback address.',
      );
    }
    stderr.writeln(
      'WARNING: App Check is not required; anyone who can reach this relay can send events.',
    );
  }

  // FirebaseAdminApp needs a credential, but checking tokens never uses it: the keys are public. Application
  // Default Credentials are looked up only if something asks for a token.
  final FirebaseAdminApp admin = FirebaseAdminApp(
    projectId: projectId,
    credential: AdminCredential.iam(
      applicationDefaultCredentials(scopes: AdminCredential.scopes),
    ),
  );
  // Throws at start for a PROJECT_NUMBER that is not a number.
  final AdminCallerVerifier verifier = AdminCallerVerifier(
    admin,
    projectNumber: value('PROJECT_NUMBER'),
  );

  final Handler handler = const Pipeline()
      // Not logRequests(): it prints the caller's query, where a misconfigured app could put a secret.
      .addMiddleware(
        relayGuard(
          verifier: verifier,
          path: 'collect',
          requireAppCheck: requireAppCheck,
          requireUser: requireUser,
          maxBodyBytes: guardMaxBodyBytes,
          trustedProxyHops: count('TRUSTED_PROXY_HOPS', fallback: 0, min: 0),
          // A refreshed App Check token starts a new per-caller budget, so the per-app limit is what bounds
          // one install without an ID token: lower than relay_guard's default, and configurable.
          maxPerCallerPerMinute: count('MAX_PER_CALLER', fallback: 60),
          maxPerAppPerMinute: count('MAX_PER_APP', fallback: 600),
          maxPerMinute: count('MAX_PER_MINUTE', fallback: 3000),
          log: stderr.writeln,
        ),
      )
      .addHandler(
        analyticsRelay(
          measurementId: measurementId,
          apiSecret: apiSecret,
          region: region,
          allowedAppIds: allowedAppIds,
          log: stderr.writeln,
        ),
      );
  final HttpServer server = await serveGuarded(
    handler,
    host,
    count('PORT', fallback: 8080),
    // Above the guard's 10 s for the body, the token checks and the relay's 10 s for Google, so the deadline
    // never cuts a request whose events Google already took.
    connectionDeadline: const Duration(seconds: 40),
  );
  stdout.writeln(
    'Analytics relay on ${host.address}:${server.port} for $measurementId via ${region.host}',
  );
}
