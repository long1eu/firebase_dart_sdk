/// The production verification kit of `firebase_error_reporting_dart` and of this relay: named checks against
/// the real Cloud Error Reporting API of a project, for the maintainer to run (`tool/verify_production.dart`).
///
/// The checks run the real client, so what they prove is what an app gets: the API accepts what the client
/// sends, through each transport, and refuses what it should. Each prints `PASS`, `FAIL`, `INCONCLUSIVE` or
/// `SKIPPED`. Every report carries the service `verify-kit` and the run tag as its version, so the console can be
/// filtered to one run. The code takes its HTTP client from the caller, so its own test runs it against a fake.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:http/http.dart' as http;
import 'package:relay_guard/relay_guard.dart';
import 'package:shelf/shelf.dart';

import 'error_reporting_relay.dart';

/// The outcome of a check.
enum Outcome {
  /// The check proved what it states.
  pass,

  /// The check proved the opposite.
  fail,

  /// The check could not tell.
  inconclusive,

  /// The check needs something the run does not have.
  skipped,
}

/// One check's result.
final class CheckResult {
  /// A result of the check [id].
  const CheckResult(this.id, this.outcome, this.note);

  /// The check.
  final String id;

  /// What it found.
  final Outcome outcome;

  /// One line of explanation, without credentials.
  final String note;

  @override
  String toString() => '${outcome.name.toUpperCase().padRight(12)} $id: $note';
}

/// What the kit needs. Exactly one of [accessToken] and [apiKey] is enough for the direct checks; the relay
/// check needs [accessToken].
final class KitConfig {
  /// A configuration.
  const KitConfig({
    required this.projectId,
    this.accessToken,
    this.apiKey,
    this.otherApiKey,
    required this.runTag,
  });

  /// The project.
  final String projectId;

  /// An OAuth access token with the Error Reporting Writer role.
  final String? accessToken;

  /// An API key restricted to the Error Reporting API.
  final String? apiKey;

  /// A key restricted to another API, for the refusal check.
  final String? otherApiKey;

  /// The tag of this run: the `serviceContext.version` of every report.
  final String runTag;
}

/// A random tag for a run.
String newRunTag([Random? random]) {
  final Random r = random ?? Random.secure();
  return List<String>.generate(
    6,
    (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[r.nextInt(31)],
  ).join();
}

/// The service of every report of the kit.
const String kitService = 'verify-kit';

final class _StaticToken extends AuthTokenProvider {
  _StaticToken(this.token);

  final String token;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async =>
      GetTokenResult(token);

  @override
  String? get uid => null;

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

final class _KitAppCheck extends AppCheckTokenProvider {
  _KitAppCheck(this.token);

  final String token;

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      AppCheckTokenResult(token);

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// Accepts only the one App Check token the kit made up for its in-process relay: the relay check proves the
/// forwarding, not App Check (which `firebase_admin_dart`'s own production checks cover).
final class _KitVerifier implements CallerVerifier {
  _KitVerifier(this.token);

  final String token;

  @override
  Future<String> appIdOf(String value) async => value == token
      ? '1:0:web:verify-kit'
      : throw const CallerRejected('not the kit token');

  @override
  Future<String> uidOf(String value) async =>
      throw const CallerRejected('the kit has no users');
}

int _apps = 0;

FirebaseApp _app(String projectId) => FirebaseApp.withOptions(
  FirebaseOptions(
    apiKey: 'unused',
    appId: '1:0:web:verify-kit',
    projectId: projectId,
  ),
  name: 'verify-kit-${_apps++}',
);

/// Runs the checks with [client] for every request, and returns their results. [log] receives a line per
/// diagnostic of the reporters (they never hold credentials).
Future<List<CheckResult>> runKit(
  KitConfig config, {
  required http.Client client,
  void Function(String line)? log,
}) async {
  final List<CheckResult> results = <CheckResult>[];
  final void Function(String) note = log ?? (_) {};

  /// Sends [count] errors through a reporter on [transport] and tells whether all were delivered.
  Future<(bool delivered, List<String> diagnostics)> send(
    ErrorReportingTransport transport,
    String label, {
    FirebaseApp? app,
    MessageFormat format = MessageFormat.v8,
    bool fatal = false,
    http.Client? via,
  }) async {
    final List<String> diagnostics = <String>[];
    final ErrorReporter reporter = ErrorReporter(
      app ?? _app(config.projectId),
      service: kitService,
      version: config.runTag,
      transport: transport,
      messageFormat: format,
      httpClient: via ?? client,
      sendDelay: Duration.zero,
      onDiagnostic: (String line) {
        diagnostics.add(line);
        note('[$label] $line');
      },
    );
    await reporter.recordError(
      StateError('verify-kit $label ${config.runTag}'),
      StackTrace.current,
      fatal: fatal,
    );
    await reporter.flush();
    final bool delivered =
        reporter.pendingCount == 0 &&
        !diagnostics.any((String d) => d.contains('dropped'));
    await reporter.close(timeout: const Duration(seconds: 5));
    return (delivered, diagnostics);
  }

  CheckResult judge(String id, (bool, List<String>) outcome, String what) {
    final (bool delivered, List<String> diagnostics) = outcome;
    if (delivered) {
      return CheckResult(id, Outcome.pass, what);
    }
    final String last = diagnostics.isEmpty
        ? 'no diagnostic'
        : diagnostics.last;
    return last.contains('refused')
        ? CheckResult(id, Outcome.fail, 'refused: $last')
        : CheckResult(id, Outcome.inconclusive, 'not delivered: $last');
  }

  // 1. Direct with an API key.
  final String? apiKey = config.apiKey;
  if (apiKey == null) {
    results.add(
      const CheckResult('direct-api-key', Outcome.skipped, 'no ER_API_KEY'),
    );
  } else {
    results.add(
      judge(
        'direct-api-key',
        await send(
          ErrorReportingTransport.direct(apiKey: apiKey),
          'direct-api-key',
        ),
        'the API took a report sent with the key',
      ),
    );
  }

  // 2. Direct with an access token, in each message format, and a fatal report.
  final String? token = config.accessToken;
  if (token == null) {
    for (final String id in <String>[
      'direct-token-v8',
      'direct-token-dart',
      'direct-token-fatal',
      'relay',
    ]) {
      results.add(CheckResult(id, Outcome.skipped, 'no ER_ACCESS_TOKEN'));
    }
  } else {
    final ErrorReportingTransport direct = ErrorReportingTransport.direct(
      credentials: _StaticToken(token),
    );
    results
      ..add(
        judge(
          'direct-token-v8',
          await send(direct, 'direct-token-v8'),
          'the API took a report in the V8 format with a reportLocation',
        ),
      )
      ..add(
        judge(
          'direct-token-dart',
          await send(direct, 'direct-token-dart', format: MessageFormat.dart),
          'the API took a report with the Dart trace and a reportLocation',
        ),
      )
      ..add(
        judge(
          'direct-token-fatal',
          await send(direct, 'direct-token-fatal', fatal: true),
          'the API took a fatal report',
        ),
      );

    // 3. Through the relay, run in this process on a loopback port.
    final String kitAppCheck = 'verify-kit-app-check-${config.runTag}';
    final Handler handler = const Pipeline()
        .addMiddleware(
          relayGuard(verifier: _KitVerifier(kitAppCheck), path: 'errors'),
        )
        .addHandler(
          errorReportingRelay(
            projectId: config.projectId,
            services: <String>{kitService},
            accessToken: ({bool forceRefresh = false}) async => token,
            client: client,
          ),
        );
    final HttpServer server = await serveGuarded(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    // The client reaches the relay over loopback with a client of its own; only the relay's forwarding uses
    // [client].
    final http.Client loopback = http.Client();
    try {
      final FirebaseApp app = _app(config.projectId)
        ..appCheckProvider = _KitAppCheck(kitAppCheck);
      results.add(
        judge(
          'relay',
          await send(
            ErrorReportingTransport.relay(
              Uri.parse('http://127.0.0.1:${server.port}/errors'),
            ),
            'relay',
            app: app,
            via: loopback,
          ),
          'the relay checked the request and the API took the report it forwarded',
        ),
      );
    } finally {
      loopback.close();
      await server.close(force: true);
    }
  }

  // 4. A key restricted to another API must be refused, and the client must drop the report, not loop.
  final String? otherKey = config.otherApiKey;
  if (otherKey == null) {
    results.add(
      const CheckResult('refused-key', Outcome.skipped, 'no ER_OTHER_API_KEY'),
    );
  } else {
    final (bool delivered, List<String> diagnostics) = await send(
      ErrorReportingTransport.direct(apiKey: otherKey),
      'refused-key',
    );
    final String last = diagnostics.isEmpty
        ? 'no diagnostic'
        : diagnostics.last;
    results.add(
      delivered
          ? const CheckResult(
              'refused-key',
              Outcome.fail,
              'the API took a report sent with a key for another API',
            )
          : last.contains('refused')
          ? CheckResult(
              'refused-key',
              Outcome.pass,
              'refused and dropped: $last',
            )
          : CheckResult(
              'refused-key',
              Outcome.inconclusive,
              'not delivered, but not refused either: $last',
            ),
    );
  }
  return results;
}

/// What to look for in the console after a run.
String consoleChecklist(KitConfig config) =>
    '''
In the Google Cloud console > Error Reporting of ${config.projectId}, filter by service $kitService and
version ${config.runTag}. Each report's message contains "verify-kit <check> ${config.runTag}".
  - direct-token-v8 and direct-token-dart: is the trace shown as frames? Are they in one group or two?
  - direct-token-fatal: is "[fatal]" in the header, and is it apart from direct-token-v8?
  - relay: is it there, with the same shape as direct-token-v8?
Record the answers with the date and the run tag in docs/error_reporting_spec.md, section 11.''';
