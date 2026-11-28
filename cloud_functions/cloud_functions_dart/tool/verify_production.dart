// The production verification kit of cloud_functions_dart: a command line tool that checks, against
// the Functions emulator or a real Firebase project, the behaviours the client relies on.
//
//     dart run tool/verify_production.dart --backend=emulator
//     dart run tool/verify_production.dart --backend=production          # prints what it would do
//     dart run tool/verify_production.dart --backend=production --yes
//
// See tool/verify_production_functions/README.md (repository root) for the commands, the fixture
// functions the project needs and how to read the report.
//
// The kit never reads, stores or prints credentials. In production mode it signs up one throwaway
// email user with a random password, hands its tokens only to the requests, and deletes the user at
// the end, also on Ctrl-C. It never prints a token, a request body or a response body: only codes,
// HTTP statuses, counts and durations.

// ignore_for_file: avoid_print, public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:cloud_functions_dart/cloud_functions_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the client relies on.
  pass('PASS'),

  /// The client misbehaved, or the backend does something the client does not handle.
  fail('FAIL'),

  /// The check measured something or could not come to a result; the summary says which.
  inconclusive('INCONCLUSIVE'),

  /// The check does not apply to this run.
  skipped('SKIPPED');

  const Status(this.label);

  final String label;
}

class CheckResult {
  const CheckResult(this.status, this.summary);

  final Status status;

  /// One line: what was observed. Never a token or a body.
  final String summary;
}

/// Where a check runs.
enum Mode { both, emulatorOnly, productionOnly }

class Check {
  const Check(this.id, this.name, this.mode, this.run);

  /// The id used with `--only`: `K1` to `K12`.
  final String id;
  final String name;
  final Mode mode;
  final Future<CheckResult> Function(Kit kit) run;
}

const String projectVariable = 'FIREBASE_TEST_PROJECT_ID';
const String appIdVariable = 'FIREBASE_TEST_APP_ID';
const String apiKeyVariable = 'FIREBASE_API_KEY';
const String emulatorHostVariable = 'FIREBASE_FUNCTIONS_EMULATOR_HOST';

/// The project of the emulator fixture (`tool/start_functions_emulator.sh`).
const String emulatorProject = 'demo-functions';

/// The uid of the emulator mode's user.
const String emulatorUid = 'kit-user';

/// The origin the CORS check asks for.
const String corsOrigin = 'http://localhost:8080';

/// How many bytes of a response [KitClient] keeps to tell a callable error body from another one.
const int _recordedBytes = 64 * 1024;

/// What the last response looked like: its status and the start of its body. The body is only
/// inspected ([hasEnvelope]), never printed.
class Recorded {
  Recorded(this.status);

  final int status;
  final List<int> _body = <int>[];

  void add(List<int> chunk) {
    final int room = _recordedBytes - _body.length;
    if (room > 0) {
      _body.addAll(chunk.length <= room ? chunk : chunk.sublist(0, room));
    }
  }

  /// Whether the body is a callable error body: a JSON object with an `error` object.
  bool get hasEnvelope {
    try {
      final Object? decoded = jsonDecode(
        utf8.decode(_body, allowMalformed: true),
      );
      return decoded is Map<String, Object?> &&
          decoded['error'] is Map<String, Object?>;
    } on FormatException {
      return false;
    }
  }
}

/// The HTTP client of the kit's SDK instances: passes every request on unchanged and remembers the
/// status and the start of the body of the last response.
class KitClient extends http.BaseClient {
  KitClient(this._inner);

  final http.Client _inner;

  Recorded? last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse response = await _inner.send(request);
    final Recorded recorded = Recorded(response.statusCode);
    last = recorded;
    return http.StreamedResponse(
      response.stream.map((List<int> chunk) {
        recorded.add(chunk);
        return chunk;
      }),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// The user of the emulator mode: an unsigned token (`{"alg":"none"}`) for the uid [emulatorUid],
/// which the Functions emulator accepts without verifying it. It is worth nothing anywhere else.
class EmulatorUser extends AuthTokenProvider {
  EmulatorUser(String projectId) : _token = _unsignedToken(projectId);

  final String _token;

  static String _unsignedToken(String projectId) {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String part(Map<String, Object?> json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final String header = part(<String, Object?>{'alg': 'none', 'typ': 'JWT'});
    final String payload = part(<String, Object?>{
      'iss': 'https://securetoken.google.com/$projectId',
      'aud': projectId,
      'sub': emulatorUid,
      'user_id': emulatorUid,
      'iat': now,
      'auth_time': now,
      'exp': now + 3600,
    });
    return '$header.$payload.';
  }

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    return GetTokenResult(_token);
  }

  @override
  String? get uid => emulatorUid;

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

/// Hands out the token of [_real] with its signature changed (check K12). The forged token is
/// never printed.
class ForgedTokenUser extends AuthTokenProvider {
  ForgedTokenUser(this._real);

  final AuthTokenProvider _real;

  /// [token] with the first character of its signature replaced, or null when it does not have
  /// the three parts of a signed token.
  static String? forge(String token) {
    final List<String> parts = token.split('.');
    if (parts.length != 3 || parts[2].isEmpty) {
      return null;
    }
    final String signature = parts[2];
    final String first = signature.startsWith('A') ? 'B' : 'A';
    return '${parts[0]}.${parts[1]}.$first${signature.substring(1)}';
  }

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    final GetTokenResult real = await _real.getAccessToken(
      forceRefresh: forceRefresh,
    );
    final String? forged = forge(real.token);
    if (forged == null) {
      throw StateError('The ID token is not a signed token.');
    }
    return GetTokenResult(forged);
  }

  @override
  String? get uid => _real.uid;

  @override
  Stream<AuthTokenChange> get onTokenChanged => _real.onTokenChanged;
}

/// What the command line and the environment ask for.
class Settings {
  const Settings({
    required this.production,
    required this.projectId,
    required this.appId,
    required this.apiKey,
    required this.region,
    required this.emulatorHost,
    required this.confirmed,
    required this.selected,
  });

  final bool production;
  final String projectId;
  final String appId;
  final String apiKey;
  final String region;
  final String? emulatorHost;

  /// `--yes` was given.
  final bool confirmed;
  final List<Check> selected;

  String get label => production ? 'production' : 'emulator';
}

/// The state of one run.
class Kit {
  Kit(this.settings, this.runId, this.app, this.userAuth, this.expectedUid)
    : client = KitClient(http.Client()) {
    functions = FirebaseFunctions(
      app,
      region: settings.region,
      emulatorHost: settings.emulatorHost,
      httpClient: client,
    );
  }

  final Settings settings;
  final String runId;
  final FirebaseApp app;

  /// The throwaway user's session in production mode; null in emulator mode.
  final FirebaseUserAuth? userAuth;

  /// The uid `context` must report.
  final String? expectedUid;

  final KitClient client;
  late final FirebaseFunctions functions;

  Future<void> close() async {
    await functions.close();
    client.close();
  }
}

// -------------------------------------------------------------------------------------------------
// The checks.

/// A code and an HTTP status, or a type name: never the message of an error, which may quote the
/// server.
String _describe(Object error) {
  if (error is FirebaseFunctionsException) {
    return '${error.code} (HTTP ${error.httpStatus})';
  }
  if (error is FirebaseException) {
    return '${error.runtimeType}: ${error.code}';
  }
  return '${error.runtimeType}';
}

/// Deep equality of decoded values; numbers compare by value, so `2` equals `2.0`.
bool _same(Object? a, Object? b) {
  if (a is num && b is num) {
    return a == b;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (final Object? key in a.keys) {
      if (!b.containsKey(key) || !_same(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// The error of [action], or null when it completed.
Future<FirebaseFunctionsException?> _errorOf(
  Future<Object?> Function() action,
) async {
  try {
    await action();
    return null;
  } on FirebaseFunctionsException catch (e) {
    return e;
  }
}

Future<CheckResult> _echo(Kit kit) async {
  final Map<String, Object?> values = <String, Object?>{
    'null': null,
    'bool': true,
    'int': 42,
    'whole double': 2.0,
    'fractional double': 1.5,
    'string with emoji': 'héllo \u{1F600}',
    'nested list': <Object?>[
      1,
      'two',
      <Object?>[3, null],
    ],
    'nested map': <String, Object?>{
      'a': <String, Object?>{
        'b': <Object?>[true, 0.25],
      },
    },
  };
  final HttpsCallable echo = kit.functions.httpsCallable('echo');
  final List<String> wrong = <String>[];
  for (final MapEntry<String, Object?> entry in values.entries) {
    final HttpsCallableResult result = await echo.call(entry.value);
    if (!_same(result.data, entry.value)) {
      wrong.add(entry.key);
    }
  }
  if (wrong.isNotEmpty) {
    return CheckResult(
      Status.fail,
      'These values did not come back equal: ${wrong.join(', ')}.',
    );
  }
  return CheckResult(
    Status.pass,
    'All ${values.length} value types came back equal.',
  );
}

Future<CheckResult> _context(Kit kit) async {
  final HttpsCallableResult result = await kit.functions
      .httpsCallable('context')
      .call();
  final Object? data = result.data;
  final Object? auth = data is Map<String, Object?> ? data['auth'] : null;
  final Object? uid = auth is Map<String, Object?> ? auth['uid'] : null;
  if (uid == null) {
    return const CheckResult(
      Status.fail,
      'The function saw no signed-in user.',
    );
  }
  if (uid != kit.expectedUid) {
    return const CheckResult(
      Status.fail,
      'The function saw another uid than the kit user.',
    );
  }
  return const CheckResult(Status.pass, "The function saw the kit user's uid.");
}

Future<CheckResult> _conflictCodes(Kit kit) async {
  final HttpsCallable fail = kit.functions.httpsCallable('fail');
  final List<String> seen = <String>[];
  bool ok = true;
  for (final String code in <String>['already-exists', 'aborted']) {
    final FirebaseFunctionsException? error = await _errorOf(
      () => fail.call(<String, Object?>{'code': code}),
    );
    seen.add(error == null ? 'no error' : _describe(error));
    ok = ok && error != null && error.code == code && error.httpStatus == 409;
  }
  return CheckResult(
    ok ? Status.pass : Status.fail,
    'already-exists gave ${seen[0]}, aborted gave ${seen[1]}.',
  );
}

Future<CheckResult> _deadline(Kit kit) async {
  final HttpsCallable slow = kit.functions.httpsCallable(
    'slow',
    options: const HttpsCallableOptions(timeout: Duration(seconds: 2)),
  );
  final Stopwatch watch = Stopwatch()..start();
  final FirebaseFunctionsException? error = await _errorOf(slow.call);
  final int ms = watch.elapsedMilliseconds;
  if (error == null) {
    return CheckResult(Status.fail, 'The call completed after $ms ms.');
  }
  final bool ok = error.code == 'deadline-exceeded' && ms < 4500;
  return CheckResult(
    ok ? Status.pass : Status.fail,
    '${_describe(error)} after $ms ms (timeout 2000 ms, the function takes 5000 ms).',
  );
}

Future<CheckResult> _stream(Kit kit) async {
  final List<CallableStreamEvent> events = await kit.functions
      .httpsCallable('stream')
      .stream()
      .toList();
  final List<Object?> messages = <Object?>[
    for (final CallableStreamEvent event in events)
      if (event is CallableMessage) event.data,
  ];
  const List<Object?> expected = <Object?>[
    <String, Object?>{'n': 1},
    'two',
    3,
  ];
  final bool resultLast = events.isNotEmpty && events.last is CallableResult;
  final bool ok = resultLast && events.length == 4 && _same(messages, expected);
  return CheckResult(
    ok ? Status.pass : Status.fail,
    '${messages.length} messages${_same(messages, expected) ? '' : ' (not the expected ones)'}, '
    '${resultLast ? 'the result last' : 'no result as the last event'}.',
  );
}

Future<CheckResult> _heartbeat(Kit kit) async {
  final HttpsCallable callable = kit.functions.httpsCallable(
    'streamHb',
    options: const HttpsCallableOptions(timeout: Duration(seconds: 5)),
  );
  final Stopwatch watch = Stopwatch()..start();
  final List<int> messageTimes = <int>[];
  bool gotResult = false;
  try {
    await for (final CallableStreamEvent event in callable.stream()) {
      switch (event) {
        case CallableMessage():
          messageTimes.add(watch.elapsedMilliseconds);
        case CallableResult():
          gotResult = true;
      }
    }
  } on FirebaseFunctionsException catch (e) {
    return CheckResult(
      Status.fail,
      'The stream failed with ${_describe(e)} after ${watch.elapsedMilliseconds} ms and '
      '${messageTimes.length} messages: with a 5 s timeout that means the pings did not arrive.',
    );
  }
  if (!gotResult || messageTimes.length != 2) {
    return CheckResult(
      Status.fail,
      '${messageTimes.length} messages, ${gotResult ? 'a' : 'no'} result.',
    );
  }
  final int gap = messageTimes[1] - messageTimes[0];
  final bool inWindow = gap >= 7000 && gap <= 9000;
  return CheckResult(
    inWindow ? Status.pass : Status.inconclusive,
    'The stream outlived its 5 s idle timeout; the late chunk came $gap ms after the first '
    '(expected 7000 to 9000 ms).',
  );
}

Future<CheckResult> _wrappedInt64(Kit kit) async {
  final HttpsCallableResult result = await kit.functions
      .httpsCallable('wrappedInt64')
      .call();
  final Object? data = result.data;
  final Object? value = data is Map<String, Object?> ? data['v'] : null;
  final bool ok = value is int && value == 9223372036854775807;
  return CheckResult(
    ok ? Status.pass : Status.fail,
    ok
        ? 'The wrapped value decoded to the exact int 9223372036854775807.'
        : 'The wrapped value decoded to a ${value.runtimeType}, not the exact int.',
  );
}

Future<CheckResult> _wrappedUnknownType(Kit kit) async {
  final HttpsCallableResult result = await kit.functions
      .httpsCallable('wrappedUnknownType')
      .call();
  const Map<String, Object?> expected = <String, Object?>{
    'other': <String, Object?>{'@type': 'x', 'value': '1'},
  };
  final bool ok = _same(result.data, expected);
  return CheckResult(
    ok ? Status.pass : Status.fail,
    ok
        ? 'The map with an unknown @type came back unchanged.'
        : 'The map with an unknown @type did not come back unchanged.',
  );
}

Future<CheckResult> _unknownFunction(Kit kit) async {
  final FirebaseFunctionsException? error = await _errorOf(
    kit.functions.httpsCallable('kitNoSuchFunction').call,
  );
  if (error == null) {
    return const CheckResult(
      Status.fail,
      'A function that does not exist answered with a result.',
    );
  }
  final Recorded? last = kit.client.last;
  final bool envelope = last != null && last.hasEnvelope;
  final bool ok =
      error.code == 'not-found' && error.httpStatus == 404 && !envelope;
  return CheckResult(
    ok ? Status.pass : Status.fail,
    '${_describe(error)}, ${envelope ? 'with' : 'without'} a callable error body.',
  );
}

Future<CheckResult> _corsPreflight(Kit kit) async {
  final Uri url = kit.functions.httpsCallable('echo').url;
  final http.Client client = http.Client();
  try {
    final http.Request request = http.Request('OPTIONS', url)
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        'Origin': corsOrigin,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers':
            'content-type,authorization,x-firebase-appcheck,accept',
      });
    final http.StreamedResponse response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    await response.stream.drain<void>();
    final String? allowed = response.headers['access-control-allow-origin'];
    final bool success =
        response.statusCode >= 200 && response.statusCode < 300;
    final bool originAllowed = allowed == corsOrigin || allowed == '*';
    return CheckResult(
      success && originAllowed ? Status.pass : Status.fail,
      'The preflight answered HTTP ${response.statusCode}; the origin is '
      '${originAllowed ? 'allowed' : 'not allowed'}.',
    );
  } finally {
    client.close();
  }
}

Future<CheckResult> _appCheck(Kit kit) async {
  return const CheckResult(
    Status.skipped,
    'needs an App Check provider that mints limited-use tokens (the App Check package)',
  );
}

/// K12: what the backend answers to an ID token whose signature is wrong. It measures whether a
/// front end refuses the token with a bare 401 or the callable layer with an error body.
Future<CheckResult> _forgedToken(Kit kit) async {
  final FirebaseUserAuth? real = kit.userAuth;
  if (real == null) {
    return const CheckResult(
      Status.inconclusive,
      'No signed-in user to forge a token of.',
    );
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    kit.app.options,
    name: 'verify-functions-forged-${kit.runId}',
  )..authProvider = ForgedTokenUser(real);
  final KitClient client = KitClient(http.Client());
  final FirebaseFunctions functions = FirebaseFunctions(
    app,
    region: kit.settings.region,
    httpClient: client,
  );
  try {
    final FirebaseFunctionsException? error = await _errorOf(
      functions.httpsCallable('context').call,
    );
    final Recorded? last = client.last;
    if (last == null) {
      return CheckResult(
        Status.inconclusive,
        'No response arrived: ${error == null ? 'no error' : _describe(error)}.',
      );
    }
    final bool envelope = last.hasEnvelope;
    final String meaning = envelope
        ? 'the callable layer refused it, so the forced Auth refresh after a bare 401 never '
              'fires here'
        : last.status == 401
        ? 'a bare 401: the next call forces an Auth refresh'
        : 'not a 401 and not a callable error body';
    return CheckResult(
      Status.inconclusive,
      'A forged ID token was answered HTTP ${last.status} '
      '${envelope ? 'with' : 'without'} a callable error body '
      '(${error == null ? 'the call succeeded' : 'code ${error.code}'}): $meaning.',
    );
  } finally {
    await functions.close();
    client.close();
    await app.delete();
  }
}

const List<Check> checks = <Check>[
  Check('K1', 'echo round trip of every value type', Mode.both, _echo),
  Check('K2', 'context sees the signed-in user', Mode.both, _context),
  Check(
    'K3',
    'already-exists and aborted: both HTTP 409, codes from the body',
    Mode.both,
    _conflictCodes,
  ),
  Check(
    'K4',
    'slow with a 2 s timeout gives deadline-exceeded',
    Mode.both,
    _deadline,
  ),
  Check(
    'K5',
    'stream delivers three messages and the result',
    Mode.both,
    _stream,
  ),
  Check(
    'K6',
    'pings keep a stream alive past its idle timeout',
    Mode.both,
    _heartbeat,
  ),
  Check(
    'K7',
    'a wrapped int64 decodes exactly',
    Mode.emulatorOnly,
    _wrappedInt64,
  ),
  Check(
    'K8',
    'a map with an unknown @type is kept',
    Mode.emulatorOnly,
    _wrappedUnknownType,
  ),
  Check(
    'K9',
    'an unknown function gives not-found without a callable body',
    Mode.both,
    _unknownFunction,
  ),
  Check('K10', 'the CORS preflight is answered', Mode.both, _corsPreflight),
  Check('K11', 'App Check', Mode.productionOnly, _appCheck),
  Check(
    'K12',
    'a forged ID token (measurement)',
    Mode.productionOnly,
    _forgedToken,
  ),
];

// -------------------------------------------------------------------------------------------------
// The run.

class KitRun {
  const KitRun(this.exitCode, this.results);

  /// 0: no check failed. 1: a check failed. 2: nothing was run (usage, or no `--yes`). 130: the
  /// run was interrupted.
  final int exitCode;
  final Map<String, CheckResult> results;
}

ArgParser _parser() {
  return ArgParser()
    ..addOption(
      'backend',
      allowed: <String>['emulator', 'production'],
      help: 'emulator needs $emulatorHostVariable; production needs --yes.',
    )
    ..addFlag(
      'yes',
      negatable: false,
      help: 'Run against the real project (production only).',
    )
    ..addOption('project-id', help: 'Or $projectVariable.')
    ..addOption('app-id', help: 'Or $appIdVariable.')
    ..addOption('api-key', help: 'The Web API key. Or $apiKeyVariable.')
    ..addOption('region', defaultsTo: 'us-central1')
    ..addOption('only', help: 'Check ids, comma separated: K1,K5.')
    ..addFlag('help', abbr: 'h', negatable: false);
}

/// The command line or the environment is not usable; [message] says why.
class UsageError implements Exception {
  const UsageError(this.message);

  final String message;
}

/// The settings, or null after a usage error was written to [sink].
Settings? _settingsOf(
  List<String> arguments,
  Map<String, String> env,
  StringSink sink,
) {
  final ArgParser parser = _parser();
  try {
    final ArgResults args = parser.parse(arguments);
    final String? backend = args.option('backend');
    if (args.flag('help') || backend == null) {
      throw const UsageError(
        '--backend=production or --backend=emulator is required.',
      );
    }
    final List<Check>? selected = _selectedChecks(args.option('only'));
    if (selected == null) {
      throw const UsageError('--only names an unknown check id.');
    }
    return backend == 'production'
        ? _productionSettings(args, env, selected)
        : _emulatorSettings(args, env, selected);
  } on FormatException catch (e) {
    sink.writeln(e.message);
  } on UsageError catch (e) {
    sink.writeln(e.message);
  }
  sink.writeln(parser.usage);
  return null;
}

/// The trimmed value of [value], or null when it is null or blank.
String? _nonBlank(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Settings _emulatorSettings(
  ArgResults args,
  Map<String, String> env,
  List<Check> selected,
) {
  final String? emulatorHost = _nonBlank(env[emulatorHostVariable]);
  if (emulatorHost == null) {
    throw const UsageError(
      '$emulatorHostVariable is not set: it is the host:port of the Functions emulator.',
    );
  }
  return Settings(
    production: false,
    projectId: emulatorProject,
    appId: '1:0:dart:verify-functions-kit',
    apiKey: 'fake-api-key',
    region: args.option('region')!,
    emulatorHost: emulatorHost,
    confirmed: args.flag('yes'),
    selected: selected,
  );
}

Settings _productionSettings(
  ArgResults args,
  Map<String, String> env,
  List<Check> selected,
) {
  final String? projectId = _nonBlank(
    args.option('project-id') ?? env[projectVariable],
  );
  final String? appId = _nonBlank(args.option('app-id') ?? env[appIdVariable]);
  final String? apiKey = _nonBlank(
    args.option('api-key') ?? env[apiKeyVariable],
  );
  if (projectId == null || appId == null || apiKey == null) {
    throw const UsageError(
      'Production mode needs --project-id, --app-id and --api-key (or $projectVariable, '
      '$appIdVariable, $apiKeyVariable).',
    );
  }
  return Settings(
    production: true,
    projectId: projectId,
    appId: appId,
    apiKey: apiKey,
    region: args.option('region')!,
    emulatorHost: null,
    confirmed: args.flag('yes'),
    selected: selected,
  );
}

/// The checks `--only` names, every check without it, or null for an unknown id.
List<Check>? _selectedChecks(String? only) {
  if (only == null) {
    return checks;
  }
  final Set<String> ids = only.split(',').map((String id) => id.trim()).toSet();
  final Set<String> known = checks.map((Check check) => check.id).toSet();
  if (!known.containsAll(ids)) {
    return null;
  }
  return <Check>[
    for (final Check check in checks)
      if (ids.contains(check.id)) check,
  ];
}

void _writePlan(Settings settings, String runId, StringSink sink) {
  final String backend = settings.production
      ? settings.label
      : '${settings.label} (${settings.emulatorHost})';
  final String user = settings.production
      ? 'a throwaway user functions-verify-$runId@example.com is signed up with a random '
            'password and deleted at the end'
      : 'an unsigned emulator token for the uid $emulatorUid';
  final String functions = settings.production
      ? 'echo, context, fail, slow, stream, streamHb (deployed by the owner from '
            'tool/functions_emulator/functions)'
      : 'echo, context, fail, slow, stream, streamHb, wrappedInt64, wrappedUnknownType';
  sink
    ..writeln('Functions production verification kit')
    ..writeln('  backend:   $backend')
    ..writeln('  project:   ${settings.projectId}')
    ..writeln('  region:    ${settings.region}')
    ..writeln('  user:      $user')
    ..writeln('  functions: $functions')
    ..writeln(
      '  checks:    ${settings.selected.map((Check c) => c.id).join(', ')}',
    );
}

String _randomPassword() {
  final math.Random secure = math.Random.secure();
  const String alphabet =
      'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return <String>[
    for (int i = 0; i < 32; i++) alphabet[secure.nextInt(alphabet.length)],
  ].join();
}

/// Creates the app and its user. In production mode a throwaway user is signed up; null when that
/// failed (the reason was written to [sink]).
Future<Kit?> _startKit(Settings settings, String runId, StringSink sink) async {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: settings.apiKey,
      appId: settings.appId,
      projectId: settings.projectId,
    ),
    name: 'verify-functions-$runId',
  );
  if (!settings.production) {
    app.authProvider = EmulatorUser(settings.projectId);
    return Kit(settings, runId, app, null, emulatorUid);
  }
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  try {
    final UserCredential created = await auth.createUserWithEmailAndPassword(
      email: 'functions-verify-$runId@example.com',
      password: _randomPassword(),
    );
    return Kit(settings, runId, app, auth, created.uid);
  } on FirebaseAuthException catch (e) {
    sink.writeln(
      'Signing up the throwaway user failed: ${e.code}. Nothing was called.',
    );
    await auth.dispose();
    await app.delete();
    return null;
  }
}

/// Deletes the throwaway user and closes everything. Runs once: at the end of the run, or on
/// Ctrl-C, whichever comes first.
class CleanUp {
  CleanUp(this._kit, this._sink);

  final Kit _kit;
  final StringSink _sink;
  Future<void>? _done;

  Future<void> call() => _done ??= _run();

  Future<void> _run() async {
    final FirebaseUserAuth? auth = _kit.userAuth;
    if (auth != null) {
      final String? uid = _kit.expectedUid;
      try {
        await auth.deleteCurrentUser();
        _sink.writeln('The throwaway user was deleted.');
      } on Object catch (e) {
        _sink.writeln(
          'Deleting the throwaway user FAILED: ${_describe(e)}. Delete the user with uid $uid '
          'by hand (Authentication > Users in the console).',
        );
      }
    }
    try {
      await _kit.close().timeout(const Duration(seconds: 15));
      await auth?.dispose();
      await _kit.app.delete();
    } on Object catch (e) {
      _sink.writeln('Closing the kit failed: ${_describe(e)}.');
    }
  }
}

Future<CheckResult> _runCheck(Check check, Kit kit) async {
  final bool production = kit.settings.production;
  if (check.mode == Mode.emulatorOnly && production) {
    return const CheckResult(
      Status.skipped,
      'emulator only: the fixture builds the value itself',
    );
  }
  if (check.mode == Mode.productionOnly && !production) {
    return const CheckResult(Status.skipped, 'production only');
  }
  try {
    return await check.run(kit).timeout(const Duration(minutes: 2));
  } on TimeoutException {
    return const CheckResult(
      Status.inconclusive,
      'The check did not finish within 2 minutes.',
    );
  } on Object catch (e) {
    return CheckResult(Status.fail, 'Unexpected error: ${_describe(e)}');
  }
}

void _writeSummary(
  Settings settings,
  Map<String, CheckResult> results,
  StringSink sink,
) {
  sink
    ..writeln('')
    ..writeln(
      'Summary (${settings.label}, project ${settings.projectId}, region ${settings.region}):',
    );
  for (final Check check in settings.selected) {
    final CheckResult? result = results[check.id];
    sink.writeln(
      '  ${check.id.padRight(4)}${(result?.status.label ?? 'NOT RUN').padRight(13)}${check.name}',
    );
  }
}

/// Runs the selected checks in order into [results], until the end or until [interrupted]
/// completes.
Future<void> _runChecks(
  Kit kit,
  Future<void> interrupted,
  Map<String, CheckResult> results,
  StringSink sink,
) async {
  bool stopped = false;
  unawaited(interrupted.then<void>((_) => stopped = true));
  for (final Check check in kit.settings.selected) {
    if (stopped) {
      return;
    }
    sink.writeln('[${check.id}] ${check.name} ...');
    final CheckResult? result = await Future.any<CheckResult?>(
      <Future<CheckResult?>>[
        _runCheck(check, kit),
        interrupted.then<CheckResult?>((_) => null),
      ],
    );
    if (result == null) {
      return;
    }
    results[check.id] = result;
    sink
      ..writeln('[${check.id}] ${result.status.label}: ${result.summary}')
      ..writeln('');
  }
}

/// Runs the kit. [out] and [environment] are for the emulator test of the kit; [interrupts]
/// emits when the run must stop and clean up (Ctrl-C).
Future<KitRun> runKit(
  List<String> arguments, {
  StringSink? out,
  Map<String, String>? environment,
  Stream<Object?>? interrupts,
}) async {
  final StringSink sink = out ?? stdout;
  final Settings? settings = _settingsOf(
    arguments,
    environment ?? Platform.environment,
    sink,
  );
  if (settings == null) {
    return const KitRun(2, <String, CheckResult>{});
  }
  final DateTime now = DateTime.now().toUtc();
  final String stamp = now
      .toIso8601String()
      .replaceAll(RegExp('[^0-9]'), '')
      .substring(0, 14);
  final String runId = '$stamp${math.Random().nextInt(1296).toRadixString(36)}';
  _writePlan(settings, runId, sink);
  if (settings.production && !settings.confirmed) {
    sink
      ..writeln('')
      ..writeln(
        'Nothing was done. Pass --yes to run this against the real project above.',
      );
    return const KitRun(2, <String, CheckResult>{});
  }
  sink.writeln('');
  final Kit? kit = await _startKit(settings, runId, sink);
  if (kit == null) {
    return const KitRun(2, <String, CheckResult>{});
  }
  final CleanUp cleanUp = CleanUp(kit, sink);
  final Completer<void> interrupted = Completer<void>();
  final StreamSubscription<Object?>? signals = interrupts?.listen((_) {
    if (!interrupted.isCompleted) {
      interrupted.complete();
    }
  });
  final Map<String, CheckResult> results = <String, CheckResult>{};
  try {
    await _runChecks(kit, interrupted.future, results, sink);
  } finally {
    if (interrupted.isCompleted) {
      sink.writeln('Interrupted: cleaning up.');
    }
    await cleanUp();
    unawaited(signals?.cancel());
  }
  _writeSummary(settings, results, sink);
  if (interrupted.isCompleted) {
    return KitRun(130, results);
  }
  final bool failed = results.values.any(
    (CheckResult result) => result.status == Status.fail,
  );
  return KitRun(failed ? 1 : 0, results);
}

Future<void> main(List<String> arguments) async {
  final KitRun run = await runKit(
    arguments,
    interrupts: ProcessSignal.sigint.watch(),
  );
  await stdout.flush();
  exit(run.exitCode);
}
