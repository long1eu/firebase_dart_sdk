// The production verification kit of firebase_ai_dart: a command line program that sends real
// requests to Firebase AI Logic and reports what the unit tests cannot know. EVERY CHECK COSTS
// MONEY: each one runs at least one paid Gemini request on the project.
//
//     dart run tool/verify_production.dart --yes --project-id=my-project --app-id=1:123:web:abc \
//         --api-key=... --model=gemini-x
//
// See tool/verify_production_ai/README.md (repository root) for what it needs and how to read its
// report.
//
// It runs the checks K1 to K14 of the specification (K8 was removed) for each backend asked for,
// through the client where the client is what is checked and through plain HTTP requests where the
// exact bytes, the timing or a request the client refuses to send is what is checked. It prints
// PASS, FAIL, INCONCLUSIVE or SKIPPED for each. It never prints the API key or a token.

// ignore_for_file: avoid_print, public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart'
    show apiClientHeader;
import 'package:args/args.dart';
import 'package:firebase_ai_dart/firebase_ai_dart.dart';
import 'package:firebase_ai_dart/src/backend.dart';
import 'package:firebase_ai_dart/src/version.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;

/// The most bytes of a plain HTTP answer the kit keeps; the 4K image check measures past the
/// client's 64 MiB cap.
const int _rawCap = 256 * 1024 * 1024;

/// The longest the kit waits for one request.
const Duration _requestWait = Duration(minutes: 5);

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the client relies on.
  pass('PASS'),

  /// The client misbehaved, or the backend did something the client does not handle.
  fail('FAIL'),

  /// The check could not come to a result, or it only records a fact; the line says what.
  inconclusive('INCONCLUSIVE'),

  /// The check was not run: it needs an option that was not given, or does not apply to this
  /// backend.
  skipped('SKIPPED');

  const Status(this.label);

  final String label;
}

/// The result of one check: a status, a line of explanation and lines of recorded facts.
class CheckResult {
  const CheckResult(this.status, this.summary, [this.facts = const <String>[]]);

  final Status status;
  final String summary;
  final List<String> facts;
}

/// What the operator asked for.
class _Settings {
  _Settings({
    required this.options,
    required this.model,
    required this.backends,
    required this.location,
    required this.imageModel,
    required this.appCheckEnforced,
    required this.largeRequests,
    required this.consumedAppCheckToken,
    required this.revokedIdToken,
    required this.unconfiguredProjectId,
    required this.unconfiguredApiKey,
  });

  final FirebaseOptions options;
  final String model;
  final List<String> backends;
  final String location;
  final String? imageModel;
  final bool appCheckEnforced;
  final bool largeRequests;
  final String? consumedAppCheckToken;
  final String? revokedIdToken;
  final String? unconfiguredProjectId;
  final String? unconfiguredApiKey;
}

/// One backend's run: the client objects and a plain HTTP client.
class _Run {
  _Run(this.settings, this.backendName, this.backend, this.app, this.ai)
    : model = ai.generativeModel(model: settings.model);

  final _Settings settings;
  final String backendName;
  final AIBackend backend;
  final FirebaseApp app;
  final FirebaseAI ai;
  final GenerativeModel model;
  final http.Client raw = http.Client();

  String get projectId => settings.options.projectId!;
}

/// A plain HTTP answer.
class _RawAnswer {
  _RawAnswer(this.status, this.headers, this.body, this.truncated);

  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  final bool truncated;
}

Future<void> main(List<String> arguments) async {
  final ArgParser parser = _parser();
  final ArgResults flags;
  try {
    flags = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (flags['help'] as bool) {
    print(
      'Usage: dart run tool/verify_production.dart --yes [options]\n\n${parser.usage}',
    );
    return;
  }
  final _Settings? settings = _configure(flags);
  if (settings == null) {
    return;
  }
  _printPlan(settings);
  if (!(flags['yes'] as bool)) {
    stderr.writeln(
      '\nNothing was sent. Every check costs money; run it again with --yes to run them.',
    );
    exitCode = 2;
    return;
  }
  bool failed = false;
  for (final String name in settings.backends) {
    failed = await _runBackend(settings, name) || failed;
  }
  exitCode = failed ? 1 : 0;
}

ArgParser _parser() {
  return ArgParser()
    ..addOption(
      'project-id',
      help: 'The project id (or FIREBASE_TEST_PROJECT_ID).',
    )
    ..addOption('app-id', help: 'The app id (or FIREBASE_TEST_APP_ID).')
    ..addOption(
      'api-key',
      help: 'The API key of the app (or FIREBASE_API_KEY).',
    )
    ..addOption(
      'model',
      help:
          'The model name, for example gemini-x. Required; there is no default.',
    )
    ..addMultiOption(
      'backend',
      allowed: <String>['google-ai', 'agent-platform'],
      defaultsTo: <String>['google-ai'],
      help: 'The backends to check; give it twice for both.',
    )
    ..addOption(
      'location',
      defaultsTo: 'global',
      help: 'The Agent Platform location.',
    )
    ..addOption('image-model', help: 'A model that answers images: runs K12.')
    ..addOption(
      'unconfigured-project-id',
      help:
          'A project whose Gemini Developer API is not set up in AI Logic, for K7 '
          '(its API key in FIREBASE_AI_UNCONFIGURED_API_KEY).',
    )
    ..addFlag(
      'app-check-enforced',
      negatable: false,
      help: 'The owner turned App Check enforcement on for AI Logic: runs K9.',
    )
    ..addFlag(
      'large-requests',
      negatable: false,
      help:
          'Runs K11: a 21 MiB inline request and a history of about 1.2 million tokens.',
    )
    ..addFlag(
      'yes',
      negatable: false,
      help: 'Confirm that the kit may spend money on the project.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');
}

/// The settings of [flags], or null (after printing the problem and setting the exit code to 2).
_Settings? _configure(ArgResults flags) {
  String? value(String? text) => text == null || text.isEmpty ? null : text;
  String? option(String name, [String? variable]) =>
      value(flags[name] as String?) ??
      (variable == null ? null : value(Platform.environment[variable]));

  final String? projectId = option('project-id', 'FIREBASE_TEST_PROJECT_ID');
  final String? appId = option('app-id', 'FIREBASE_TEST_APP_ID');
  final String? apiKey = option('api-key', 'FIREBASE_API_KEY');
  final String? model = option('model');
  final List<String> missing = <String>[
    if (projectId == null) '--project-id (FIREBASE_TEST_PROJECT_ID)',
    if (appId == null) '--app-id (FIREBASE_TEST_APP_ID)',
    if (apiKey == null) '--api-key (FIREBASE_API_KEY)',
    if (model == null) '--model',
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('Missing: ${missing.join(', ')}');
    exitCode = 2;
    return null;
  }
  return _Settings(
    options: FirebaseOptions(
      apiKey: apiKey!,
      appId: appId!,
      projectId: projectId,
    ),
    model: model!,
    backends: (flags['backend'] as List<String>).toSet().toList(),
    location: flags['location'] as String,
    imageModel: option('image-model'),
    appCheckEnforced: flags['app-check-enforced'] as bool,
    largeRequests: flags['large-requests'] as bool,
    consumedAppCheckToken: value(
      Platform.environment['FIREBASE_AI_CONSUMED_APP_CHECK_TOKEN'],
    ),
    revokedIdToken: value(Platform.environment['FIREBASE_AI_REVOKED_ID_TOKEN']),
    unconfiguredProjectId: option('unconfigured-project-id'),
    unconfiguredApiKey: value(
      Platform.environment['FIREBASE_AI_UNCONFIGURED_API_KEY'],
    ),
  );
}

void _printPlan(_Settings settings) {
  print('Firebase AI Logic production verification kit');
  print(
    '  EVERY CHECK COSTS MONEY: each runs at least one paid Gemini request on the project.',
  );
  print('  project id:  ${settings.options.projectId}');
  print('  app id:      ${settings.options.appId}');
  print('  API key:     given (never printed)');
  print('  model:       ${settings.model}');
  print(
    '  backends:    ${settings.backends.join(', ')} '
    '(location ${settings.location} for agent-platform)',
  );
  print('  image model: ${settings.imageModel ?? 'none (K12 skipped)'}');
  print(
    '  K7 unconfigured project: ${settings.unconfiguredProjectId ?? 'none (skipped)'}',
  );
  print(
    '  K9 App Check enforced:   ${settings.appCheckEnforced ? 'yes' : 'no (skipped)'}',
  );
  print(
    '  K10 revoked ID token:    ${settings.revokedIdToken == null ? 'none (skipped)' : 'given'}',
  );
  print(
    '  K11 large requests:      ${settings.largeRequests ? 'yes' : 'no (skipped)'}',
  );
}

/// Runs every check for the backend [name]; true when one of them failed.
Future<bool> _runBackend(_Settings settings, String name) async {
  final bool agentPlatform = name == 'agent-platform';
  final FirebaseApp app = FirebaseApp.withOptions(
    settings.options,
    name: 'ai-kit-$name',
  );
  final FirebaseAI ai = agentPlatform
      ? FirebaseAI.agentPlatform(app: app, location: settings.location)
      : FirebaseAI.googleAI(app: app);
  final _Run run = _Run(
    settings,
    name,
    agentPlatform
        ? AIBackend.agentPlatform(settings.location)
        : const AIBackend.googleAI(),
    app,
    ai,
  );
  print('\n== $name');
  bool failed = false;
  try {
    for (final (String, String, Future<CheckResult> Function(_Run)) check
        in _checks) {
      final CheckResult result = await _runOne(run, check.$3);
      failed = failed || result.status == Status.fail;
      print(
        '${check.$1.padRight(4)} ${result.status.label.padRight(12)} '
        '${check.$2}: ${result.summary}',
      );
      for (final String fact in result.facts) {
        print('       $fact');
      }
    }
  } finally {
    run.raw.close();
    await ai.close();
    await app.delete();
  }
  return failed;
}

Future<CheckResult> _runOne(
  _Run run,
  Future<CheckResult> Function(_Run) check,
) async {
  try {
    return await check(run).timeout(const Duration(minutes: 15));
  } on FirebaseAIException catch (error) {
    return CheckResult(Status.fail, 'the client threw ${_describe(error)}');
  } on TimeoutException {
    return const CheckResult(Status.fail, 'timed out');
  } on Object catch (error) {
    return CheckResult(Status.fail, 'the kit failed with ${error.runtimeType}');
  }
}

/// The text of [error] that is safe to print: code, HTTP status, server status and reason.
String _describe(FirebaseAIException error) {
  final List<String> parts = <String>[
    if (error.httpStatus != null) 'HTTP ${error.httpStatus}',
    if (error.serverStatus != null) '${error.serverStatus}',
    if (error.reason != null) 'reason ${error.reason}',
  ];
  return parts.isEmpty ? error.code : '${error.code} (${parts.join(', ')})';
}

final List<(String, String, Future<CheckResult> Function(_Run))> _checks =
    <(String, String, Future<CheckResult> Function(_Run))>[
      ('K1', 'generateContent', _k1Generate),
      ('K2', 'stream bytes', _k2StreamBytes),
      ('K3', 'countTokens', _k3CountTokens),
      ('K4', 'stream timing with thinking', _k4ThinkingTiming),
      ('K5', 'two-turn chat', _k5Chat),
      ('K6', 'structured output', _k6StructuredOutput),
      ('K7', 'error answers', _k7Errors),
      ('K9', 'App Check enforcement', _k9AppCheck),
      ('K10', 'revoked ID token', _k10RevokedToken),
      ('K11', 'size and context limits', _k11Limits),
      ('K12', '4K image size', _k12ImageSize),
      ('K13', 'client version header', _k13VersionHeader),
      ('K14', 'safety method on the Developer API', _k14SafetyMethod),
    ];

// -------------------------------------------------------------------------------------------------
// Plain HTTP helpers

Map<String, String> _headers(
  _Run run, {
  String? apiKey,
  String? apiClient,
}) => <String, String>{
  'content-type': 'application/json',
  'x-goog-api-key': apiKey ?? run.settings.options.apiKey,
  'x-goog-api-client': apiClient ?? apiClientHeader(sdkVersion: packageVersion),
  'x-firebase-appid': run.settings.options.appId,
};

Uri _url(_Run run, ModelTask task, {String? model, String? projectId}) =>
    modelTaskUrl(
      productionOrigin,
      run.backend,
      projectId: projectId ?? run.projectId,
      model: model ?? run.settings.model,
      task: task,
    );

Map<String, Object?> _body(
  List<Content> contents, {
  GenerationConfig? config,
}) => generateContentBody(
  GenerateParts(contents: contents, generationConfig: config),
);

Future<_RawAnswer> _post(
  _Run run,
  Uri url,
  Map<String, Object?> body, {
  Map<String, String>? headers,
}) async {
  final http.Request request = http.Request('POST', url)
    ..followRedirects = false
    ..headers.addAll(headers ?? _headers(run))
    ..body = jsonEncode(body);
  final http.StreamedResponse response = await run.raw
      .send(request)
      .timeout(_requestWait);
  final BytesBuilder bytes = BytesBuilder(copy: false);
  bool truncated = false;
  await for (final List<int> chunk in response.stream.timeout(_requestWait)) {
    if (bytes.length + chunk.length > _rawCap) {
      truncated = true;
      break;
    }
    bytes.add(chunk);
  }
  return _RawAnswer(
    response.statusCode,
    response.headers,
    bytes.takeBytes(),
    truncated,
  );
}

/// The `error.status`, the ErrorInfo `reason` and `domain` of an error body, as far as they parse.
String _errorFacts(_RawAnswer answer) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(answer.body));
  } on FormatException {
    return 'HTTP ${answer.status}, body is not JSON';
  }
  final Object? error = decoded is Map<String, Object?>
      ? decoded['error']
      : null;
  if (error is! Map<String, Object?>) {
    return 'HTTP ${answer.status}, no error envelope';
  }
  String? reason;
  String? domain;
  final Object? details = error['details'];
  for (final Object? detail
      in details is List<Object?> ? details : const <Object?>[]) {
    if (detail is Map<String, Object?> &&
        detail['@type'] == 'type.googleapis.com/google.rpc.ErrorInfo') {
      reason = detail['reason'] as String?;
      domain = detail['domain'] as String?;
      break;
    }
  }
  return 'HTTP ${answer.status}, status ${error['status']}, reason $reason, domain $domain';
}

// -------------------------------------------------------------------------------------------------
// The checks

Future<CheckResult> _k1Generate(_Run run) async {
  final GenerateContentResponse response = await run.model.generateContent(
    <Content>[Content.text('Reply with one word: hello.')],
    generationConfig: const GenerationConfig(maxOutputTokens: 10),
  );
  final List<String> facts = <String>[
    for (final (String, String, String) file in _fileUris)
      await _fileUriFact(run, file),
  ];
  final Candidate? first = response.candidates.isEmpty
      ? null
      : response.candidates.first;
  if (first == null) {
    return CheckResult(Status.fail, 'no candidate in the answer', facts);
  }
  return CheckResult(
    Status.pass,
    'finish reason ${first.finishReason?.name}, '
    '${response.usageMetadata?.totalTokenCount} tokens in all',
    facts,
  );
}

/// The `fileUri` schemes of open item O5: a label, the URI and its MIME type (public sample files).
const List<(String, String, String)> _fileUris = <(String, String, String)>[
  (
    'gs://',
    'gs://cloud-samples-data/generative-ai/image/scones.jpg',
    'image/jpeg',
  ),
  (
    'https://',
    'https://storage.googleapis.com/cloud-samples-data/generative-ai/image/scones.jpg',
    'image/jpeg',
  ),
  ('YouTube', 'https://www.youtube.com/watch?v=9hE5-98ZeCg', 'video/mp4'),
];

Future<String> _fileUriFact(_Run run, (String, String, String) file) async {
  try {
    await run.model.generateContent(<Content>[
      Content.multi(<Part>[
        FileData(file.$3, file.$2),
        const TextPart('Describe it in three words.'),
      ]),
    ], generationConfig: const GenerationConfig(maxOutputTokens: 10));
    return 'fileUri ${file.$1}: accepted';
  } on FirebaseAIException catch (error) {
    return 'fileUri ${file.$1}: refused, ${_describe(error)}';
  }
}

Future<CheckResult> _k2StreamBytes(_Run run) async {
  final _StreamFacts facts = await _rawStream(
    run,
    _body(<Content>[Content.text('Count from 1 to 40, one number per line.')]),
  );
  if (facts.status != 200) {
    return CheckResult(Status.fail, 'the stream answered ${facts.errorFacts}');
  }
  final List<String> lines = <String>[
    'first event bytes: ${facts.firstEventText}',
    'events: ${facts.events}; promptFeedback without candidates: ${facts.feedbackOnlyEvents}',
  ];
  if (facts.events < 2) {
    return CheckResult(
      Status.inconclusive,
      'only ${facts.events} event(s); ask for a longer answer',
      lines,
    );
  }
  int clientChunks = 0;
  await for (final GenerateContentResponse _ in run.model.generateContentStream(
    <Content>[Content.text('Count from 1 to 40, one number per line.')],
  )) {
    clientChunks++;
  }
  lines.add('the client emitted $clientChunks chunk(s) for the same prompt');
  return CheckResult(
    Status.pass,
    '${facts.events} events; the client decoded the same stream',
    lines,
  );
}

Future<CheckResult> _k3CountTokens(_Run run) async {
  final List<Content> contents = <Content>[
    Content.text('How many tokens is this sentence?'),
  ];
  final CountTokensResponse plain = await run.model.countTokens(contents);
  final GenerativeModel withInstruction = run.ai.generativeModel(
    model: run.settings.model,
    systemInstruction: Content.system(
      'You answer in exactly one short sentence, in English, without lists.',
    ),
  );
  final CountTokensResponse instructed = await withInstruction.countTokens(
    contents,
  );
  final String counts =
      'without a system instruction ${plain.totalTokens}, with one ${instructed.totalTokens}';
  if (instructed.totalTokens <= plain.totalTokens) {
    return CheckResult(
      Status.fail,
      '$counts: the system instruction was not counted',
    );
  }
  return CheckResult(Status.pass, counts);
}

Future<CheckResult> _k4ThinkingTiming(_Run run) async {
  final _StreamFacts facts = await _rawStream(
    run,
    _body(
      <Content>[
        Content.text(
          'A bat and a ball cost 1.10 in total. The bat costs 1.00 more. What does the ball cost?',
        ),
      ],
      config: const GenerationConfig(
        thinkingConfig: ThinkingConfig.withThinkingBudget(
          1024,
          includeThoughts: true,
        ),
      ),
    ),
  );
  if (facts.status != 200) {
    return CheckResult(Status.fail, 'the stream answered ${facts.errorFacts}');
  }
  return CheckResult(Status.pass, '${facts.events} events', <String>[
    'time to headers: ${facts.headersAt.inMilliseconds} ms',
    'time to first event: ${facts.firstEventAt?.inMilliseconds} ms',
    'longest gap between events: ${facts.longestGap.inMilliseconds} ms',
    'SSE comment lines: ${facts.comments}',
  ]);
}

Future<CheckResult> _k5Chat(_Run run) async {
  final ChatSession chat = run.model.startChat();
  await chat.sendMessage(Content.text('My name is Ada. Reply with OK.'));
  final GenerateContentResponse second = await chat.sendMessage(
    Content.text('What is my name? One word.'),
  );
  final int length = chat.history.length;
  if (length != 4) {
    return CheckResult(
      Status.fail,
      'the history has $length entries after two turns, not 4',
    );
  }
  final bool remembered = (second.text ?? '').contains('Ada');
  return CheckResult(
    Status.pass,
    '4 history entries; the second reply ${remembered ? 'names' : 'does not name'} Ada',
  );
}

Future<CheckResult> _k6StructuredOutput(_Run run) async {
  final GenerationConfig schemaConfig = GenerationConfig(
    responseMimeType: 'application/json',
    responseSchema: Schema.object(
      properties: <String, Schema>{'answer': Schema.string()},
    ),
  );
  const GenerationConfig jsonSchemaConfig = GenerationConfig(
    responseMimeType: 'application/json',
    responseJsonSchema: JsonSchema(<String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'answer': <String, Object?>{'type': 'string'},
      },
      'required': <String>['answer'],
    }),
  );
  final List<String> facts = <String>[];
  for (final (String, GenerationConfig) variant in <(String, GenerationConfig)>[
    ('responseSchema', schemaConfig),
    ('responseJsonSchema', jsonSchemaConfig),
  ]) {
    final GenerateContentResponse response = await run.model.generateContent(
      <Content>[Content.text('What is the capital of France?')],
      generationConfig: variant.$2,
    );
    final bool valid = _hasAnswerField(response.text);
    facts.add(
      '${variant.$1}: ${valid ? 'a JSON object with "answer"' : 'not the requested JSON'}',
    );
  }
  final bool allValid = facts.every((String fact) => fact.endsWith('"answer"'));
  return CheckResult(
    allValid ? Status.pass : Status.fail,
    allValid ? 'both forms' : 'see below',
    facts,
  );
}

bool _hasAnswerField(String? text) {
  try {
    final Object? decoded = jsonDecode(text ?? '');
    return decoded is Map<String, Object?> && decoded['answer'] is String;
  } on FormatException {
    return false;
  }
}

Future<CheckResult> _k7Errors(_Run run) async {
  final List<String> facts = <String>[];
  final bool unknownModelOk = await _expectCode(
    run.ai.generativeModel(model: 'no-such-model-for-the-kit'),
    'not-found',
    'unknown model',
    facts,
  );
  final FirebaseApp badKeyApp = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'AIzaSyInvalidKeyForTheVerificationKit00',
      appId: run.settings.options.appId,
      projectId: run.projectId,
    ),
    name: 'ai-kit-bad-key-${run.backendName}',
  );
  final FirebaseAI badKeyAi = run.backend.isAgentPlatform
      ? FirebaseAI.agentPlatform(
          app: badKeyApp,
          location: run.settings.location,
        )
      : FirebaseAI.googleAI(app: badKeyApp);
  try {
    await _expectCode(
      badKeyAi.generativeModel(model: run.settings.model),
      null,
      'invalid key',
      facts,
    );
  } finally {
    await badKeyAi.close();
    await badKeyApp.delete();
  }
  facts.add(await _unconfiguredFact(run));
  return CheckResult(
    unknownModelOk ? Status.pass : Status.fail,
    unknownModelOk
        ? 'recorded below (open item O6)'
        : 'an unknown model did not give not-found',
    facts,
  );
}

/// Sends one request to [model] that must fail; records the failure in [facts]. True when the code
/// is [code] (any code when null) and the failure came from the server.
Future<bool> _expectCode(
  GenerativeModel model,
  String? code,
  String label,
  List<String> facts,
) async {
  try {
    await model.generateContent(<Content>[Content.text('Hello')]);
    facts.add('$label: accepted (unexpected)');
    return false;
  } on FirebaseAIException catch (error) {
    final String message = error.serverMessage ?? '';
    facts.add(
      '$label: ${_describe(error)}; server message: '
      '${message.length > 160 ? message.substring(0, 160) : message}',
    );
    return error.httpStatus != null && (code == null || error.code == code);
  }
}

Future<String> _unconfiguredFact(_Run run) async {
  final String? projectId = run.settings.unconfiguredProjectId;
  final String? apiKey = run.settings.unconfiguredApiKey;
  if (projectId == null || apiKey == null) {
    return 'Developer API not configured: skipped (no --unconfigured-project-id and '
        'FIREBASE_AI_UNCONFIGURED_API_KEY)';
  }
  final _RawAnswer answer = await _post(
    run,
    _url(run, ModelTask.generateContent, projectId: projectId),
    _body(<Content>[Content.text('Hello')]),
    headers: _headers(run, apiKey: apiKey),
  );
  return 'Developer API not configured: ${_errorFacts(answer)}';
}

Future<CheckResult> _k9AppCheck(_Run run) async {
  if (!run.settings.appCheckEnforced) {
    return const CheckResult(
      Status.skipped,
      'needs --app-check-enforced (an owner-made project change)',
    );
  }
  final Uri url = _url(run, ModelTask.generateContent);
  final Map<String, Object?> body = _body(<Content>[
    Content.text('Hello'),
  ], config: const GenerationConfig(maxOutputTokens: 5));
  final List<(String, String?)> attempts = <(String, String?)>[
    ('no App Check token', null),
    ('the placeholder token', AppCheckTokenResult.placeholderToken),
    if (run.settings.consumedAppCheckToken case final String token)
      ('a consumed limited-use token', token),
  ];
  final List<String> facts = <String>[];
  bool allRefused = true;
  for (final (String, String?) attempt in attempts) {
    final Map<String, String> headers = _headers(run);
    if (attempt.$2 case final String token) {
      headers['x-firebase-appcheck'] = token;
    }
    final _RawAnswer answer = await _post(run, url, body, headers: headers);
    allRefused = allRefused && (answer.status == 401 || answer.status == 403);
    facts.add(
      '${attempt.$1}: ${answer.status == 200 ? 'HTTP 200 (accepted)' : _errorFacts(answer)}',
    );
  }
  if (run.settings.consumedAppCheckToken == null) {
    facts.add(
      'a consumed limited-use token: skipped (no FIREBASE_AI_CONSUMED_APP_CHECK_TOKEN)',
    );
  }
  return CheckResult(
    allRefused ? Status.pass : Status.inconclusive,
    allRefused
        ? 'every request without a valid token was refused'
        : 'a request was accepted: enforcement may not have taken effect yet (it can take minutes)',
    facts,
  );
}

Future<CheckResult> _k10RevokedToken(_Run run) async {
  final String? token = run.settings.revokedIdToken;
  if (token == null) {
    return const CheckResult(
      Status.skipped,
      'needs FIREBASE_AI_REVOKED_ID_TOKEN (a revoked ID token)',
    );
  }
  final Map<String, String> headers = _headers(run)
    ..['authorization'] = 'Firebase $token';
  final _RawAnswer answer = await _post(
    run,
    _url(run, ModelTask.generateContent),
    _body(<Content>[
      Content.text('Hello'),
    ], config: const GenerationConfig(maxOutputTokens: 5)),
    headers: headers,
  );
  if (answer.status == 200) {
    return const CheckResult(
      Status.inconclusive,
      'HTTP 200: the proxy accepted the revoked token',
    );
  }
  final bool billed = utf8
      .decode(answer.body, allowMalformed: true)
      .contains('usageMetadata');
  return CheckResult(
    billed ? Status.fail : Status.pass,
    billed
        ? 'the refusal carries usageMetadata: billed work can precede a 401 (open item K10)'
        : 'refused without usageMetadata',
    <String>[_errorFacts(answer)],
  );
}

Future<CheckResult> _k11Limits(_Run run) async {
  if (!run.settings.largeRequests) {
    return const CheckResult(
      Status.skipped,
      'needs --large-requests (large, possibly expensive requests)',
    );
  }
  final List<String> facts = <String>[];
  final Uint8List inline = Uint8List.fromList(
    List<int>.filled(21 * 1024 * 1024, 0x61),
  );
  final bool inlineOk = await _recordLargeRequest(
    run,
    'inline text/plain of 21 MiB',
    <Content>[Content.inlineData('text/plain', inline)],
    facts,
  );
  final List<Content> history = <Content>[
    Content.text(List<String>.filled(1200000, 'word').join(' ')),
  ];
  final CountTokensResponse count = await run.model.countTokens(history);
  facts.add('long history: countTokens says ${count.totalTokens} tokens');
  final bool historyOk = await _recordLargeRequest(
    run,
    'long history',
    history,
    facts,
  );
  return CheckResult(
    inlineOk && historyOk ? Status.pass : Status.fail,
    'recorded below (open items O4 and O11)',
    facts,
  );
}

/// Sends [contents] and records the answer in [facts]; false when the client failed locally instead
/// of reporting the server's answer.
Future<bool> _recordLargeRequest(
  _Run run,
  String label,
  List<Content> contents,
  List<String> facts,
) async {
  try {
    await run.model.generateContent(
      contents,
      generationConfig: const GenerationConfig(maxOutputTokens: 1),
    );
    facts.add('$label: accepted');
    return true;
  } on FirebaseAIException catch (error) {
    facts.add('$label: ${_describe(error)}');
    return error.httpStatus != null;
  }
}

Future<CheckResult> _k12ImageSize(_Run run) async {
  final String? imageModel = run.settings.imageModel;
  if (imageModel == null) {
    return const CheckResult(Status.skipped, 'needs --image-model');
  }
  final _RawAnswer answer = await _post(
    run,
    _url(run, ModelTask.generateContent, model: imageModel),
    _body(
      <Content>[
        Content.text('A detailed photograph of a mountain lake at sunrise.'),
      ],
      config: const GenerationConfig(
        responseModalities: <ResponseModality>[
          ResponseModality.text,
          ResponseModality.image,
        ],
        imageConfig: ImageConfig(imageSize: '4K'),
      ),
    ),
  );
  if (answer.status != 200) {
    return CheckResult(Status.inconclusive, 'no image: ${_errorFacts(answer)}');
  }
  const int clientCap = 64 * 1024 * 1024;
  final int size = answer.body.length;
  final String measured = answer.truncated
      ? 'more than $_rawCap bytes'
      : '$size bytes';
  if (answer.truncated || size > clientCap) {
    return CheckResult(
      Status.fail,
      'the body is $measured, over the client cap of $clientCap (open item O10)',
    );
  }
  return CheckResult(
    Status.pass,
    'the body is $measured, under the client cap of $clientCap',
  );
}

Future<CheckResult> _k13VersionHeader(_Run run) async {
  final Uri url = _url(run, ModelTask.generateContent);
  final Map<String, Object?> body = _body(<Content>[
    Content.text('Hello'),
  ], config: const GenerationConfig(maxOutputTokens: 5));
  final _RawAnswer js = await _post(
    run,
    url,
    body,
    headers: _headers(run, apiClient: 'gl-js/12.6.0 fire/3.1.0'),
  );
  final _RawAnswer ours = await _post(run, url, body);
  final String facts =
      'fire/3.1.0: HTTP ${js.status}; fire/$packageVersion: HTTP ${ours.status}';
  if (js.status != ours.status) {
    return CheckResult(
      Status.fail,
      '$facts: the version is treated differently (open item O9)',
    );
  }
  return CheckResult(
    js.status == 200 ? Status.pass : Status.inconclusive,
    facts,
  );
}

Future<CheckResult> _k14SafetyMethod(_Run run) async {
  if (run.backend.isAgentPlatform) {
    return const CheckResult(Status.skipped, 'Developer API only');
  }
  final Map<String, Object?> body = <String, Object?>{
    ..._body(<Content>[
      Content.text('Hello'),
    ], config: const GenerationConfig(maxOutputTokens: 5)),
    'safetySettings': <Object?>[
      <String, Object?>{
        'category': 'HARM_CATEGORY_HARASSMENT',
        'threshold': 'BLOCK_ONLY_HIGH',
        'method': 'SEVERITY',
      },
    ],
  };
  final _RawAnswer answer = await _post(
    run,
    _url(run, ModelTask.generateContent),
    body,
  );
  if (answer.status == 200) {
    return const CheckResult(
      Status.fail,
      'the server accepts SafetySetting.method: remove the client refusal (unsupported)',
    );
  }
  return CheckResult(
    Status.pass,
    'refused, so the client refusal stays',
    <String>[_errorFacts(answer)],
  );
}

// -------------------------------------------------------------------------------------------------
// A plain SSE reader that records bytes and timing

class _StreamFacts {
  int status = 0;
  String errorFacts = '';
  Duration headersAt = Duration.zero;
  Duration? firstEventAt;
  Duration longestGap = Duration.zero;
  int events = 0;
  int comments = 0;
  int feedbackOnlyEvents = 0;
  String firstEventText = '';
}

Future<_StreamFacts> _rawStream(_Run run, Map<String, Object?> body) async {
  final _StreamFacts facts = _StreamFacts();
  final http.Request request =
      http.Request('POST', _url(run, ModelTask.streamGenerateContent))
        ..followRedirects = false
        ..headers.addAll(_headers(run))
        ..body = jsonEncode(body);
  final Stopwatch watch = Stopwatch()..start();
  final http.StreamedResponse response = await run.raw
      .send(request)
      .timeout(_requestWait);
  facts
    ..status = response.statusCode
    ..headersAt = watch.elapsed;
  if (response.statusCode != 200) {
    final Uint8List bytes = await response.stream.toBytes();
    facts.errorFacts = _errorFacts(
      _RawAnswer(response.statusCode, response.headers, bytes, false),
    );
    return facts;
  }
  final _SseScanner scanner = _SseScanner(facts, watch);
  await for (final List<int> chunk in response.stream.timeout(_requestWait)) {
    scanner.add(chunk);
  }
  return facts;
}

/// Splits an SSE body into lines (CR, LF or CRLF) and events, recording what [_StreamFacts] holds.
class _SseScanner {
  _SseScanner(this.facts, this.watch);

  final _StreamFacts facts;
  final Stopwatch watch;
  final List<int> _prefix = <int>[];
  final List<int> _line = <int>[];
  final StringBuffer _data = StringBuffer();
  bool _afterCr = false;
  bool _hasData = false;
  Duration? _lastEventAt;

  void add(List<int> chunk) {
    for (final int byte in chunk) {
      if (facts.events == 0 && _prefix.length < 400) {
        _prefix.add(byte);
      }
      if (byte == 0x0a && _afterCr) {
        _afterCr = false;
        continue;
      }
      _afterCr = byte == 0x0d;
      if (byte == 0x0a || byte == 0x0d) {
        _endLine();
      } else {
        _line.add(byte);
      }
    }
  }

  void _endLine() {
    final String line = utf8.decode(_line, allowMalformed: true);
    _line.clear();
    if (line.isEmpty) {
      if (_hasData) {
        _endEvent();
      }
      return;
    }
    if (line.startsWith(':')) {
      facts.comments++;
    } else if (line.startsWith('data:')) {
      final String value = line.substring(5);
      if (_hasData) {
        _data.write('\n');
      }
      _data.write(value.startsWith(' ') ? value.substring(1) : value);
      _hasData = true;
    }
  }

  void _endEvent() {
    final Duration now = watch.elapsed;
    facts.events++;
    if (facts.events == 1) {
      facts
        ..firstEventAt = now
        ..firstEventText = _escaped(_prefix);
    }
    final Duration? last = _lastEventAt;
    if (last != null && now - last > facts.longestGap) {
      facts.longestGap = now - last;
    }
    _lastEventAt = now;
    if (_isFeedbackOnly(_data.toString())) {
      facts.feedbackOnlyEvents++;
    }
    _data.clear();
    _hasData = false;
  }

  static bool _isFeedbackOnly(String data) {
    try {
      final Object? decoded = jsonDecode(data);
      return decoded is Map<String, Object?> &&
          decoded['promptFeedback'] != null &&
          decoded['candidates'] == null;
    } on FormatException {
      return false;
    }
  }

  /// The bytes up to the end of the first event, with CR, LF and other control bytes written as
  /// escapes and the JSON cut to 120 characters, so the line ends and the `data:` spacing are
  /// visible.
  static String _escaped(List<int> bytes) {
    final String text = utf8.decode(bytes, allowMalformed: true);
    final StringBuffer buffer = StringBuffer();
    for (final int unit in text.codeUnits) {
      buffer.write(switch (unit) {
        0x0d => r'\r',
        0x0a => r'\n',
        < 0x20 => '\\x${unit.toRadixString(16).padLeft(2, '0')}',
        _ => String.fromCharCode(unit),
      });
    }
    final String escaped = buffer.toString();
    if (escaped.length <= 160) {
      return escaped;
    }
    return '${escaped.substring(0, 120)} ... ${escaped.substring(escaped.length - 30)}';
  }
}
