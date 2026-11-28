import 'dart:async';

import 'package:firebase_ai_dart/src/backend.dart';
import 'package:firebase_ai_dart/src/chat.dart';
import 'package:firebase_ai_dart/src/config.dart';
import 'package:firebase_ai_dart/src/content.dart';
import 'package:firebase_ai_dart/src/errors.dart';
import 'package:firebase_ai_dart/src/request.dart';
import 'package:firebase_ai_dart/src/response.dart';
import 'package:firebase_ai_dart/src/stream.dart';
import 'package:firebase_ai_dart/src/tool.dart';
import 'package:firebase_ai_dart/src/validation.dart';

/// A Gemini model of a `FirebaseAI` instance, with its default request settings.
///
/// Created by `FirebaseAI.generativeModel`. Every call checks only what protects the client or the
/// URL before sending: the server decides the rest and answers `invalid-argument`. Calls on a model
/// of a closed `FirebaseAI` fail with `ai-closed`.
///
/// Each call takes a `timeout`, which replaces the model's `requestTimeout` (and for a stream also
/// its `streamIdleTimeout`) and must not be negative, and an `abortTrigger`: when that future
/// completes, also with an error, the request is aborted and the call fails with `cancelled`. An
/// abort stops the client's work only; the backend may still finish the request and bill it.
final class GenerativeModel {
  GenerativeModel._(this._core);

  final ModelCore _core;

  /// The plain model name, for example `gemini-2.5-flash`.
  String get model => _core.model;

  /// Sends one request with [prompt] and returns the decoded response.
  ///
  /// [safetySettings], [generationConfig], [tools] and [toolConfig] replace the model's values
  /// for this call. The response is returned also when the prompt or the candidate was blocked;
  /// only its accessors throw then (`response-error`).
  ///
  /// Throws [ArgumentError] for an empty prompt, a content without parts, a role other than `user`,
  /// `model`, `function` or null (a `system` content belongs in `systemInstruction`), a NaN or
  /// infinite number in the generation configuration, or a negative [timeout]. Throws
  /// `FirebaseAIException` for every failure of the call, `unsupported` for a safety setting with a
  /// method on the Gemini Developer API among them.
  Future<GenerateContentResponse> generateContent(
    Iterable<Content> prompt, {
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    final List<Content> contents = checkPrompt(prompt);
    final RequestSettings settings = _core.settingsFor(
      safetySettings: safetySettings,
      generationConfig: generationConfig,
      tools: tools,
      toolConfig: toolConfig,
    );
    final AiCall call = _core.startCall(timeout, abortTrigger);
    return _core.generate(contents, settings, call);
  }

  /// A single-subscription stream of the chunks of one generation; nothing is sent until it is
  /// listened to.
  ///
  /// Every SSE event that decodes is emitted, also one that carries only `usageMetadata` or
  /// `promptFeedback`. Cancelling the subscription aborts the request and is not an error. When
  /// the stream fails after at least one chunk, the exception's `response` holds the aggregate of
  /// the chunks emitted. A stream ends with `deadline-exceeded` when no bytes, or no event, arrive
  /// for the model's `streamIdleTimeout` (or [timeout]); a keep-alive comment does not count as an
  /// event.
  ///
  /// The arguments are checked before this method returns, as for [generateContent], and their
  /// errors are thrown synchronously.
  Stream<GenerateContentResponse> generateContentStream(
    Iterable<Content> prompt, {
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) {
    final List<Content> contents = checkPrompt(prompt);
    final RequestSettings settings = _core.settingsFor(
      safetySettings: safetySettings,
      generationConfig: generationConfig,
      tools: tools,
      toolConfig: toolConfig,
    );
    final StreamRequest request = _core.streamRequest(contents, settings);
    final AiCall call = _core.startCall(timeout, abortTrigger);
    return _core.generateStream(request, call, timeout);
  }

  /// Counts the tokens [contents] would use, together with the model's system instruction, tools
  /// and generation configuration.
  ///
  /// Throws [ArgumentError] as [generateContent] does, and `FirebaseAIException` for every failure
  /// of the call.
  Future<CountTokensResponse> countTokens(
    Iterable<Content> contents, {
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    final List<Content> checked = checkPrompt(contents, name: 'contents');
    final AiCall call = _core.startCall(timeout, abortTrigger);
    return _core.count(checked, call);
  }

  /// A chat with this model, starting from [history].
  ///
  /// [safetySettings] and [generationConfig] replace the model's values for every send of the chat;
  /// the model's tools, tool configuration and system instruction are sent as they are.
  ///
  /// Throws [ArgumentError] when [history] breaks a rule, naming the index: the first content has
  /// role `user`; every role is `user`, `model` or `function` and every content has a part; a
  /// `user` or `function` content follows a `model` one and a `model` content follows a `user` or
  /// `function` one.
  ChatSession startChat({
    List<Content>? history,
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
  }) {
    final List<Content> initial = checkHistory(history ?? const <Content>[]);
    return newChatSession(
      _core,
      history: initial,
      settings: _core.settingsFor(
        safetySettings: safetySettings,
        generationConfig: generationConfig,
      ),
    );
  }
}

/// Creates the [GenerativeModel] of [core]; used by `FirebaseAI.generativeModel`.
GenerativeModel newGenerativeModel(ModelCore core) => GenerativeModel._(core);

/// The settings of one request that a call or a chat may replace.
final class RequestSettings {
  /// Settings with these values; null means none is sent.
  const RequestSettings({
    this.safetySettings,
    this.generationConfig,
    this.tools,
    this.toolConfig,
  });

  /// The safety settings sent.
  final List<SafetySetting>? safetySettings;

  /// The generation configuration sent.
  final GenerationConfig? generationConfig;

  /// The tools sent.
  final List<Tool>? tools;

  /// The tool configuration sent.
  final ToolConfig? toolConfig;
}

/// A checked stream request: its URL and body, built before the stream is returned.
final class StreamRequest {
  /// A request to [url] with [body].
  const StreamRequest(this.url, this.body);

  /// The `streamGenerateContent` URL.
  final Uri url;

  /// The JSON body.
  final Map<String, Object?> body;
}

/// Everything a model and its chats need to send requests: the instance's connection, the backend,
/// the project and the model's defaults.
final class ModelCore {
  /// The core of [model] on [backend].
  ModelCore({
    required this.context,
    required this.backend,
    required this.origin,
    required this.projectId,
    required this.model,
    required this.safetySettings,
    required this.generationConfig,
    required this.tools,
    required this.toolConfig,
    required this.systemInstruction,
    required this.requestTimeout,
    required this.streamIdleTimeout,
  });

  /// What every request of the `FirebaseAI` instance shares.
  final AiRequestContext context;

  /// The backend and its location.
  final AIBackend backend;

  /// The checked server origin.
  final Uri origin;

  /// The project id of the app's options, as read at construction.
  final String? projectId;

  /// The plain model name.
  final String model;

  /// The model's safety settings.
  final List<SafetySetting>? safetySettings;

  /// The model's generation configuration.
  final GenerationConfig? generationConfig;

  /// The model's tools.
  final List<Tool>? tools;

  /// The model's tool configuration.
  final ToolConfig? toolConfig;

  /// The model's system instruction.
  final Content? systemInstruction;

  /// The deadline of a call that gives no timeout.
  final Duration requestTimeout;

  /// The idle bound of a stream that gives no timeout; null for none.
  final Duration? streamIdleTimeout;

  /// The settings of a request: each value given replaces the model's.
  ///
  /// Throws [ArgumentError] for a NaN or an infinite number in the resulting generation or tool
  /// configuration, or an unknown harm category; `FirebaseAIException` (`unsupported`) for a safety
  /// setting with a method on the Gemini Developer API.
  RequestSettings settingsFor({
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
  }) {
    final RequestSettings settings = RequestSettings(
      safetySettings: safetySettings ?? this.safetySettings,
      generationConfig: generationConfig ?? this.generationConfig,
      tools: tools ?? this.tools,
      toolConfig: toolConfig ?? this.toolConfig,
    );
    checkRequestOptions(
      safetySettings: settings.safetySettings,
      generationConfig: settings.generationConfig,
      toolConfig: settings.toolConfig,
      developerApi: !backend.isAgentPlatform,
    );
    return settings;
  }

  /// One call, started now: its deadline is [timeout] (else [requestTimeout]) and [abortTrigger]
  /// aborts it.
  ///
  /// Throws [ArgumentError] for a negative [timeout].
  AiCall startCall(Duration? timeout, Future<void>? abortTrigger) {
    checkTimeout(timeout, 'timeout');
    return context.startCall(
      timeout: timeout ?? requestTimeout,
      abortTrigger: abortTrigger,
    );
  }

  /// The checked URL and body of a stream of [contents] with [settings].
  ///
  /// Throws [StateError] when the app's options hold no project id, and `FirebaseAIException`
  /// (`unsupported`) for a safety setting the backend refuses.
  StreamRequest streamRequest(
    List<Content> contents,
    RequestSettings settings,
  ) {
    return StreamRequest(
      _url(ModelTask.streamGenerateContent),
      generateContentBody(_parts(contents, settings)),
    );
  }

  /// One `generateContent` call of [contents] with [settings], within [call].
  Future<GenerateContentResponse> generate(
    List<Content> contents,
    RequestSettings settings,
    AiCall call,
  ) async {
    final Uri url;
    final Map<String, Object?> body;
    try {
      call.throwIfEnded();
      url = _url(ModelTask.generateContent);
      body = generateContentBody(_parts(contents, settings));
    } on Object {
      call.dispose();
      rethrow;
    }
    final Map<String, Object?> json = await sendUnary(
      context,
      call,
      url: url,
      body: body,
      successCap: maxGenerateBodyBytes,
      errorContext: errorContext,
    );
    return decodeGenerateContentResponse(backend, json);
  }

  /// One `streamGenerateContent` call of [request], within [call]; sent when listened to.
  ///
  /// [timeout], when given, replaces [streamIdleTimeout] as well.
  Stream<GenerateContentResponse> generateStream(
    StreamRequest request,
    AiCall call,
    Duration? timeout,
  ) {
    try {
      return sendStream(
        context,
        call,
        url: request.url,
        body: request.body,
        idleTimeout: timeout ?? streamIdleTimeout,
        errorContext: errorContext,
        decode: (Map<String, Object?> json) =>
            decodeGenerateContentResponse(backend, json),
      );
    } on Object {
      call.dispose();
      rethrow;
    }
  }

  /// One `countTokens` call of [contents] with the model's settings, within [call].
  Future<CountTokensResponse> count(List<Content> contents, AiCall call) async {
    final Uri url;
    final Map<String, Object?> body;
    try {
      call.throwIfEnded();
      url = _url(ModelTask.countTokens);
      body = countTokensBody(
        backend,
        _parts(contents, settingsFor()),
        model: model,
      );
    } on Object {
      call.dispose();
      rethrow;
    }
    final Map<String, Object?> json = await sendUnary(
      context,
      call,
      url: url,
      body: body,
      successCap: maxCountTokensBodyBytes,
      errorContext: errorContext,
    );
    return decodeCountTokensResponse(json);
  }

  /// What the error mapping needs to know about calls of this model.
  ErrorContext get errorContext => ErrorContext(
    projectId: projectId,
    isAgentPlatform: backend.isAgentPlatform,
  );

  Uri _url(ModelTask task) {
    final String? project = projectId;
    if (project == null || project.isEmpty) {
      throw StateError(
        'FirebaseOptions.projectId is missing or empty: Firebase AI Logic puts it in the URL '
        'of every request.',
      );
    }
    return modelTaskUrl(
      origin,
      backend,
      projectId: project,
      model: model,
      task: task,
    );
  }

  GenerateParts _parts(List<Content> contents, RequestSettings settings) {
    return GenerateParts(
      contents: contents,
      systemInstruction: systemInstruction,
      tools: settings.tools,
      toolConfig: settings.toolConfig,
      safetySettings: settings.safetySettings,
      generationConfig: settings.generationConfig,
    );
  }
}
