// The production verification kit of firebase_app_check_dart: a command line program that runs the client against
// a real Firebase project and reports what the unit tests cannot know.
//
//     FIREBASE_APPCHECK_DEBUG_TOKEN=<registered debug token> \
//       dart run tool/verify_production.dart --yes --project-id=my-project --app-id=1:123:web:abc --api-key=...
//
// See tool/verify_production_app_check/README.md (repository root) for what it needs and how to read its report.
//
// The debug token is read only from the environment variable FIREBASE_APPCHECK_DEBUG_TOKEN, never from the command
// line (other users can see it in the process list), and is never printed. Neither is an App Check token or the API
// key: the kit prints lengths, lifetimes, error codes and HTTP statuses only.
//
// It runs six checks in order: exchange a session token, a second getToken that must send nothing, a forced refresh
// after 31 s, a limited-use token, a second instance on the same file store, and an unregistered debug token that
// must be refused and then paused. It prints PASS, FAIL, INCONCLUSIVE or SKIPPED for each. It stores the session
// token in a private temporary directory, which it deletes when it ends, also after a failure and on Ctrl-C.

// ignore_for_file: avoid_print, public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:firebase_app_check_dart/io.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:http/http.dart' as http;

/// The only place the debug token is read from.
const String debugTokenVariable = 'FIREBASE_APPCHECK_DEBUG_TOKEN';

/// A forced refresh inside the first 30 s of a token returns that token; the kit waits one second more.
const Duration forcedRefreshWait = Duration(seconds: 31);

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the client relies on.
  pass('PASS'),

  /// The client misbehaved, or the backend did something the client does not handle.
  fail('FAIL'),

  /// The check could not come to a result; the line says what to do.
  inconclusive('INCONCLUSIVE'),

  /// The check was not run: an earlier check it needs did not pass.
  skipped('SKIPPED');

  const Status(this.label);

  final String label;
}

/// The result of one check: a status and a line of explanation.
class CheckResult {
  const CheckResult(this.status, this.summary);

  final Status status;
  final String summary;
}

/// Thrown into a running check when the operator presses Ctrl-C.
class _Interrupted implements Exception {
  const _Interrupted();
}

/// Counts the requests the clients send, so a check can tell that a call sent none.
class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner);

  final http.Client _inner;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests += 1;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// What the checks share: the clients, and the facts one check hands to the next. The token strings are kept only to
/// compare them; they are never printed.
class _Kit {
  _Kit({required this.options, required this.provider});

  final FirebaseOptions options;
  final DebugAppCheckProvider provider;
  final _CountingClient client = _CountingClient(http.Client());
  final Completer<void> interrupted = Completer<void>();
  final Stopwatch sinceFirstToken = Stopwatch();

  Directory? directory;
  FirebaseApp? app;
  FileKeyValueStore? store;
  FirebaseAppCheck? first;
  FirebaseAppCheck? second;
  FirebaseAppCheck? unregistered;

  /// The session token the first instance holds, once check 1 passed.
  String? sessionToken;

  /// Runs [action], and throws [_Interrupted] instead if Ctrl-C is pressed first.
  Future<T> guard<T>(Future<T> action) {
    return Future.any<T>(<Future<T>>[
      action,
      interrupted.future.then((_) => throw const _Interrupted()),
    ]);
  }

  /// Waits [duration]; throws [_Interrupted] at once, leaving no timer, if Ctrl-C is pressed first.
  Future<void> sleep(Duration duration) async {
    final Completer<void> done = Completer<void>();
    final Timer timer = Timer(duration, done.complete);
    try {
      await guard(done.future);
    } finally {
      timer.cancel();
    }
  }

  FirebaseAppCheck instance({
    required AppCheckProvider provider,
    FileKeyValueStore? store,
  }) {
    return FirebaseAppCheck(
      app!,
      provider: provider,
      store: store,
      install: false,
      httpClient: client,
    );
  }
}

Future<void> main(List<String> arguments) async {
  final ArgParser parser = _parser();
  final ArgResults flags;
  try {
    flags = parser.parse(arguments);
  } on FormatException {
    // The parser's message can quote an argument; a debug token typed there by mistake must not be printed back.
    stderr.writeln('The arguments could not be read.\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (flags['help'] as bool) {
    print(
      'Usage: $debugTokenVariable=<debug token> dart run tool/verify_production.dart --yes [options]\n\n'
      '${parser.usage}',
    );
    return;
  }
  final _Kit? kit = _configure(flags);
  if (kit == null) {
    return;
  }
  if (!(flags['yes'] as bool)) {
    _printPlan(kit);
    kit.client.close();
    stderr.writeln(
      '\nNothing was done. Run it again with --yes to run the checks.',
    );
    exitCode = 2;
    return;
  }
  exitCode = await _run(kit);
}

ArgParser _parser() {
  return ArgParser()
    ..addOption(
      'project-id',
      help: 'The project id (or FIREBASE_TEST_PROJECT_ID).',
    )
    ..addOption(
      'app-id',
      help:
          'The app id, 1:<project number>:<platform>:<hash> (or FIREBASE_TEST_APP_ID).',
    )
    ..addOption(
      'api-key',
      help: 'The API key of the app (or FIREBASE_API_KEY).',
    )
    ..addFlag(
      'yes',
      negatable: false,
      help: 'Confirm that the kit may use the project.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');
}

/// The kit for [flags], or null (after printing the problem and setting the exit code to 2).
_Kit? _configure(ArgResults flags) {
  String? value(String option, String variable) {
    final String text =
        (flags[option] as String?) ?? Platform.environment[variable] ?? '';
    return text.isEmpty ? null : text;
  }

  final String? projectId = value('project-id', 'FIREBASE_TEST_PROJECT_ID');
  final String? appId = value('app-id', 'FIREBASE_TEST_APP_ID');
  final String? apiKey = value('api-key', 'FIREBASE_API_KEY');
  final List<String> problems = <String>[
    if (projectId == null) 'Missing: --project-id (FIREBASE_TEST_PROJECT_ID)',
    if (appId == null) 'Missing: --app-id (FIREBASE_TEST_APP_ID)',
    if (apiKey == null) 'Missing: --api-key (FIREBASE_API_KEY)',
    if (flags.rest.isNotEmpty)
      'Unexpected arguments: the kit takes options only. The debug token is never given on the command line.',
  ];
  final DebugAppCheckProvider? provider = _providerFromEnvironment();
  if (provider == null) {
    problems.add(
      'The environment variable $debugTokenVariable must hold the debug token registered for the app '
      '(a version 4 UUID).',
    );
  }
  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exitCode = 2;
    return null;
  }
  return _Kit(
    options: FirebaseOptions(
      apiKey: apiKey!,
      appId: appId!,
      projectId: projectId,
    ),
    provider: provider!,
  );
}

/// The provider for the debug token of the environment, or null when the variable is unset, empty or not a UUID.
DebugAppCheckProvider? _providerFromEnvironment() {
  try {
    return debugProviderFromEnvironment();
  } on StateError {
    return null;
  }
}

void _printPlan(_Kit kit) {
  print('App Check production verification kit');
  print('  project id:   ${kit.options.projectId}');
  print('  app id:       ${kit.options.appId}');
  print('  API key:      given (never printed)');
  print('  debug token:  read from $debugTokenVariable (never printed)');
  print(
    '  it will:      exchange the debug token about four times, and once an unregistered random one; '
    'it changes nothing in the project',
  );
  print(
    '  it takes:     about ${forcedRefreshWait.inSeconds + 10} s (one check waits ${forcedRefreshWait.inSeconds} s)',
  );
}

Future<int> _run(_Kit kit) async {
  _printPlan(kit);
  final StreamSubscription<ProcessSignal> sigint = ProcessSignal.sigint
      .watch()
      .listen((_) {
        if (!kit.interrupted.isCompleted) {
          print('\nInterrupted: cleaning up.');
          kit.interrupted.complete();
        }
      });
  final List<CheckResult> results = <CheckResult>[];
  bool interrupted = false;
  try {
    _setUp(kit);
    for (final (String, Future<CheckResult> Function(_Kit)) check in _checks) {
      final CheckResult result = await _runOne(kit, check.$2);
      results.add(result);
      print(
        '${results.length}. ${result.status.label.padRight(12)} ${check.$1}: ${result.summary}',
      );
    }
  } on _Interrupted {
    interrupted = true;
  } on Object catch (error) {
    stderr.writeln('The kit stopped: ${_describe(error)}');
    results.add(CheckResult(Status.fail, _describe(error)));
  } finally {
    await _cleanUp(kit);
    await sigint.cancel();
  }
  if (interrupted) {
    return 130;
  }
  return results.any((CheckResult r) => r.status == Status.fail) ? 1 : 0;
}

Future<CheckResult> _runOne(
  _Kit kit,
  Future<CheckResult> Function(_Kit) check,
) async {
  try {
    return await kit.guard(check(kit).timeout(const Duration(minutes: 2)));
  } on _Interrupted {
    rethrow;
  } on FirebaseAppCheckException catch (error) {
    return CheckResult(Status.fail, 'app check error ${_describe(error)}');
  } on TimeoutException {
    return const CheckResult(Status.fail, 'timed out');
  }
}

/// The text of [error] that is safe to print: the code, HTTP status and server status of an App Check exception
/// (never its server message or cause), else the type.
String _describe(Object error) {
  if (error is FirebaseAppCheckException) {
    return '${error.code} (status ${error.httpStatus}, ${error.serverStatus})';
  }
  return error.runtimeType.toString();
}

void _setUp(_Kit kit) {
  final Directory directory = Directory.systemTemp.createTempSync(
    'app_check_kit_',
  );
  kit.directory = directory;
  kit.app = FirebaseApp.withOptions(kit.options, name: 'app-check-kit');
  final FileKeyValueStore store = FileKeyValueStore(directory.path);
  kit
    ..store = store
    ..first = kit.instance(provider: kit.provider, store: store);
}

/// Closes everything and removes the temporary directory, which holds the stored session token. It never throws:
/// a failure is printed with what to remove by hand.
Future<void> _cleanUp(_Kit kit) async {
  final List<Future<void> Function()> steps = <Future<void> Function()>[
    () async => kit.first?.close(),
    () async => kit.second?.close(),
    () async => kit.unregistered?.close(),
    () async => kit.store?.close(),
    () async => kit.app?.delete(),
    () async => kit.client.close(),
  ];
  for (final Future<void> Function() step in steps) {
    try {
      await step().timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      print('Clean-up: a close failed (${_describe(error)}); continuing.');
    }
  }
  try {
    kit.directory?.deleteSync(recursive: true);
  } on Object catch (error) {
    print(
      'Clean-up of local files failed (${_describe(error)}): remove ${kit.directory?.path} by hand; '
      'it holds an App Check token.',
    );
  }
}

final List<(String, Future<CheckResult> Function(_Kit))> _checks =
    <(String, Future<CheckResult> Function(_Kit))>[
      ('exchange a session token', _sessionToken),
      ('a second getToken sends no request', _cachedToken),
      ('forced refresh after ${forcedRefreshWait.inSeconds} s', _forcedRefresh),
      ('limited-use token', _limitedUseToken),
      ('a second instance on the same store', _secondInstance),
      ('an unregistered debug token', _unregisteredToken),
    ];

CheckResult _skipped(String why) => CheckResult(Status.skipped, why);

/// The lifetime of [token] in whole seconds, as seen from [before], a wall-clock reading taken just before the
/// call that fetched it.
int _ttlSeconds(AppCheckToken token, DateTime before) =>
    token.expireTime.difference(before).inSeconds;

Future<CheckResult> _sessionToken(_Kit kit) async {
  final DateTime before = DateTime.now().toUtc();
  final AppCheckToken token = await kit.first!.getToken();
  kit.sinceFirstToken.start();
  if (kit.client.requests != 1) {
    return CheckResult(
      Status.fail,
      'got a token, but the client sent ${kit.client.requests} requests instead of 1',
    );
  }
  kit.sessionToken = token.token;
  return CheckResult(
    Status.pass,
    'ttl ${_ttlSeconds(token, before)} s; the token has ${token.token.length} characters',
  );
}

Future<CheckResult> _cachedToken(_Kit kit) async {
  final String? session = kit.sessionToken;
  if (session == null) {
    return _skipped('no session token');
  }
  final int before = kit.client.requests;
  final AppCheckToken token = await kit.first!.getToken();
  final int sent = kit.client.requests - before;
  if (sent != 0 || token.token != session) {
    return CheckResult(
      Status.fail,
      'the second call sent $sent request(s) and returned '
      '${token.token == session ? 'the same' : 'another'} token',
    );
  }
  return const CheckResult(Status.pass, 'the cached token, with no request');
}

Future<CheckResult> _forcedRefresh(_Kit kit) async {
  final String? session = kit.sessionToken;
  if (session == null) {
    return _skipped('no session token');
  }
  final Duration wait = forcedRefreshWait - kit.sinceFirstToken.elapsed;
  if (wait > Duration.zero) {
    print(
      '   Waiting ${wait.inSeconds + 1} s: a forced refresh in the first 30 s of a token returns that token.',
    );
    await kit.sleep(wait);
  }
  final int before = kit.client.requests;
  final AppCheckToken token = await kit.first!.getToken(forceRefresh: true);
  final int sent = kit.client.requests - before;
  if (token.token == session) {
    return CheckResult(
      Status.fail,
      'the forced call returned the same token ($sent request(s) sent)',
    );
  }
  kit.sessionToken = token.token;
  return CheckResult(Status.pass, 'a different token, with $sent request');
}

Future<CheckResult> _limitedUseToken(_Kit kit) async {
  final int requests = kit.client.requests;
  final DateTime before = DateTime.now().toUtc();
  final AppCheckToken token = await kit.first!.getLimitedUseToken();
  final int sent = kit.client.requests - requests;
  if (sent != 1 || token.token == kit.sessionToken) {
    return CheckResult(
      Status.fail,
      'got a token with $sent request(s); it is '
      '${token.token == kit.sessionToken ? 'the session token' : 'a new token'}',
    );
  }
  return CheckResult(
    Status.pass,
    'ttl ${_ttlSeconds(token, before)} s; the token has ${token.token.length} characters',
  );
}

Future<CheckResult> _secondInstance(_Kit kit) async {
  final String? session = kit.sessionToken;
  if (session == null) {
    return _skipped('no session token');
  }
  await kit.first!.close();
  final FirebaseAppCheck second = kit.instance(
    provider: kit.provider,
    store: kit.store,
  );
  kit.second = second;
  final int before = kit.client.requests;
  final AppCheckToken token = await second.getToken();
  final int sent = kit.client.requests - before;
  if (sent != 0) {
    return CheckResult(
      Status.fail,
      'the second instance sent $sent request(s): the stored token was not written, not read or refused',
    );
  }
  if (token.token != session) {
    return const CheckResult(
      Status.fail,
      'the second instance answered without a request, but not with the stored token',
    );
  }
  return const CheckResult(Status.pass, 'the stored token, with no request');
}

Future<CheckResult> _unregisteredToken(_Kit kit) async {
  final FirebaseAppCheck unregistered = kit.instance(
    provider: DebugAppCheckProvider(
      debugToken: DebugAppCheckProvider.generateDebugToken(),
    ),
  );
  kit.unregistered = unregistered;
  final FirebaseAppCheckException? refusal = await _failureOf(unregistered);
  if (refusal == null) {
    return const CheckResult(
      Status.fail,
      'the server gave a token for a random debug token that was never registered',
    );
  }
  if (refusal.code != 'fetch-status-error') {
    return CheckResult(
      Status.inconclusive,
      'the request failed with ${_describe(refusal)} before the server could refuse it: run the kit again',
    );
  }
  final String echo = _echoOf(refusal.serverMessage);
  final String refused =
      'refused with HTTP ${refusal.httpStatus}, ${refusal.serverStatus}; $echo';
  final int before = kit.client.requests;
  final FirebaseAppCheckException? paused = await _failureOf(unregistered);
  final int sent = kit.client.requests - before;
  if (paused?.code != 'throttled' || sent != 0) {
    return CheckResult(
      Status.fail,
      '$refused; but the next call ${paused == null ? 'got a token' : 'failed with ${paused.code}'} '
      'and sent $sent request(s) instead of being paused',
    );
  }
  return CheckResult(
    Status.pass,
    '$refused; the next call was throttled, with no request',
  );
}

/// Whether the server's error [message] echoed the debug token: the client replaces an echo by `<redacted>`.
String _echoOf(String? message) {
  if (message == null) {
    return 'no server message';
  }
  return message.contains('<redacted>')
      ? 'the server message echoed the debug token, which was replaced by <redacted>'
      : 'the server message did not echo the debug token';
}

/// The exception a `getToken` of [appCheck] throws, or null when it returns a token.
Future<FirebaseAppCheckException?> _failureOf(FirebaseAppCheck appCheck) async {
  try {
    await appCheck.getToken();
    return null;
  } on FirebaseAppCheckException catch (error) {
    return error;
  }
}
