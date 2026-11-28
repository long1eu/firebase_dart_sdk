import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/backend.dart';
import 'package:firebase_ai_dart/src/config.dart';
import 'package:firebase_ai_dart/src/content.dart';
import 'package:firebase_ai_dart/src/generative_model.dart';
import 'package:firebase_ai_dart/src/headers.dart';
import 'package:firebase_ai_dart/src/logger.dart';
import 'package:firebase_ai_dart/src/request.dart';
import 'package:firebase_ai_dart/src/tool.dart';
import 'package:firebase_ai_dart/src/validation.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Firebase AI Logic for one [FirebaseApp]: the entry point to Gemini models through the Firebase
/// proxy, with the app's API key, App Check and Auth.
///
/// ```dart
/// final FirebaseAI ai = FirebaseAI.googleAI(app: app);
/// final GenerativeModel model = ai.generativeModel(model: 'gemini-2.5-flash');
/// final GenerateContentResponse response =
///     await model.generateContent(<Content>[Content.text('Say hello')]);
/// print(response.text);
/// await ai.close();
/// ```
///
/// Each constructor call gives a new, independent instance; there is no instance cache. The app's
/// `authProvider`, `appCheckProvider` and `isAutomaticDataCollectionEnabled` are read at every
/// request, so a provider set on the app later is used from the next request. The instance closes
/// itself when the app is deleted.
///
/// An injected `httpClient` must support aborting requests (`http.Abortable`), must not retry and
/// must not follow redirects. A client that cannot abort still makes a call fail on time, but the
/// request runs on and is billed; a retrying client bills a generation twice. Redirects are refused
/// whatever the client does.
final class FirebaseAI {
  /// The Gemini Developer API. Sends nothing.
  ///
  /// Throws [ArgumentError] when `app.options.apiKey` or `appId` is present but holds characters a
  /// header may not carry, or `projectId` is present but does not match
  /// `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$` (it goes into the URL path). A missing or empty API key,
  /// app id or project id is not checked here: the first call that needs it throws [StateError]
  /// naming the option.
  ///
  /// [useLimitedUseAppCheckTokens] asks the App Check provider for a limited-use token for every
  /// request (each chat send included); a provider that cannot mint one gives no App Check header.
  /// [httpClient] is closed by [close] only when this instance created it. [logger] receives
  /// messages that never contain a token, the API key, a request body, a prompt, a response text or
  /// a function argument. [serverOrigin] replaces `https://firebasevertexai.googleapis.com` in
  /// tests; it must be `https`, or `http` to a loopback host.
  FirebaseAI.googleAI({
    required FirebaseApp app,
    bool useLimitedUseAppCheckTokens = false,
    http.Client? httpClient,
    AILogger? logger,
    @visibleForTesting Uri? serverOrigin,
  }) : this._(
         app: app,
         backend: const AIBackend.googleAI(),
         useLimitedUseAppCheckTokens: useLimitedUseAppCheckTokens,
         httpClient: httpClient,
         logger: logger,
         serverOrigin: serverOrigin,
       );

  /// Agent Platform in [location]. Sends nothing.
  ///
  /// Throws [ArgumentError] unless [location] matches `^[a-z0-9]+(-[a-z0-9]+)*$` (for example
  /// `global`, `us-central1`, `europe-west4`). The other arguments and checks are those of
  /// [FirebaseAI.googleAI].
  FirebaseAI.agentPlatform({
    required FirebaseApp app,
    String location = 'global',
    bool useLimitedUseAppCheckTokens = false,
    http.Client? httpClient,
    AILogger? logger,
    @visibleForTesting Uri? serverOrigin,
  }) : this._(
         app: app,
         backend: AIBackend.agentPlatform(_checkedLocation(location)),
         useLimitedUseAppCheckTokens: useLimitedUseAppCheckTokens,
         httpClient: httpClient,
         logger: logger,
         serverOrigin: serverOrigin,
       );

  FirebaseAI._({
    required this.app,
    required AIBackend backend,
    required this.useLimitedUseAppCheckTokens,
    required http.Client? httpClient,
    required AILogger? logger,
    required Uri? serverOrigin,
  }) : _backend = backend,
       _ownsClient = httpClient == null,
       _client = httpClient ?? http.Client() {
    final FirebaseOptions options = app.options;
    checkAppOptions(options);
    _projectId = options.projectId;
    final Uri origin = checkOrigin(serverOrigin ?? productionOrigin);
    _origin = origin;
    _context = AiRequestContext(
      client: _client,
      headers: AiHeaders(
        app: app,
        serverOrigin: origin,
        useLimitedUseAppCheckTokens: useLimitedUseAppCheckTokens,
        logger: logger,
      ),
    );
    _deleteSubscription = app.onDeleteApp.listen(
      (String _) => unawaited(close()),
    );
  }

  /// The app whose API key, project, App Check and Auth the requests use.
  final FirebaseApp app;

  /// Asks for a limited-use App Check token for every request.
  final bool useLimitedUseAppCheckTokens;

  final AIBackend _backend;
  final bool _ownsClient;
  final http.Client _client;
  late final String? _projectId;
  late final Uri _origin;
  late final AiRequestContext _context;
  late final StreamSubscription<String> _deleteSubscription;
  Future<void>? _closing;

  /// The Agent Platform location; null for the Gemini Developer API.
  String? get location => _backend.location;

  /// A model of this instance. Sends nothing.
  ///
  /// [model] is a plain name matching `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`, or that name prefixed
  /// with `models/`; [GenerativeModel.model] holds the plain name. The other arguments are the
  /// model's defaults: a call's own [safetySettings], [generationConfig], [tools] and [toolConfig]
  /// replace them rather than merging. [requestTimeout] bounds each call from the call until its
  /// body is read (for a stream, until its headers arrive); [streamIdleTimeout] ends a stream that
  /// receives no bytes, or no event, for that long, and null disables both of those bounds.
  ///
  /// Throws [ArgumentError] for a model name outside that rule, or a negative duration.
  GenerativeModel generativeModel({
    required String model,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
    Content? systemInstruction,
    Duration requestTimeout = const Duration(seconds: 180),
    Duration? streamIdleTimeout = const Duration(seconds: 180),
  }) {
    final String name = checkModelName(model);
    checkTimeout(requestTimeout, 'requestTimeout');
    checkTimeout(streamIdleTimeout, 'streamIdleTimeout');
    return newGenerativeModel(
      ModelCore(
        context: _context,
        backend: _backend,
        origin: _origin,
        projectId: _projectId,
        model: name,
        safetySettings: _frozen(safetySettings),
        generationConfig: generationConfig,
        tools: _frozen(tools),
        toolConfig: toolConfig,
        systemInstruction: systemInstruction,
        requestTimeout: requestTimeout,
        streamIdleTimeout: streamIdleTimeout,
      ),
    );
  }

  /// Closes this instance. Idempotent.
  ///
  /// Aborts the requests in flight, which fail with `ai-closed`, and closes the HTTP client if this
  /// instance created it. Later calls on this instance, its models and its chats fail with
  /// `ai-closed`.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _context.close();
    await _deleteSubscription.cancel();
    if (_ownsClient) {
      _client.close();
    }
  }

  static String _checkedLocation(String location) {
    checkLocation(location);
    return location;
  }

  static List<T>? _frozen<T>(List<T>? list) =>
      list == null ? null : List<T>.unmodifiable(list);
}
