import 'package:firebase_ai_dart/src/config.dart';
import 'package:firebase_ai_dart/src/content.dart';
import 'package:firebase_ai_dart/src/response.dart';
import 'package:firebase_ai_dart/src/tool.dart';

/// The API version of every REST path. Moving to `v1` is a minor release, made after the
/// production kit passes on `v1`.
const String apiVersion = 'v1beta';

/// The origin of the Firebase AI Logic proxy.
final Uri productionOrigin = Uri(
  scheme: 'https',
  host: 'firebasevertexai.googleapis.com',
);

/// The model service behind the proxy, and where it runs.
///
/// Every difference between the two backends lives in this file.
final class AIBackend {
  /// The Gemini Developer API.
  const AIBackend.googleAI() : location = null;

  /// Agent Platform in [location], already checked by the caller.
  const AIBackend.agentPlatform(String this.location);

  /// The Agent Platform location; null for the Gemini Developer API.
  final String? location;

  /// True for Agent Platform.
  bool get isAgentPlatform => location != null;
}

/// The last part of a model path: what the request asks the model to do.
enum ModelTask {
  /// One unary generation.
  generateContent('generateContent'),

  /// A generation answered as Server-Sent Events (`?alt=sse`).
  streamGenerateContent('streamGenerateContent'),

  /// A token count.
  countTokens('countTokens');

  const ModelTask(this.wireName);

  /// The task as it appears after the `:` of the last path segment.
  final String wireName;
}

/// The URL of [task] on [model] for [backend], under [origin] (already passed through
/// `checkOrigin`).
///
/// [projectId] and [model] are already checked: the project id against the pattern of the
/// constructor, the model as a plain name. The path is built from segments, so nothing in them can
/// add a segment, a query or a fragment.
Uri modelTaskUrl(
  Uri origin,
  AIBackend backend, {
  required String projectId,
  required String model,
  required ModelTask task,
}) {
  final String? location = backend.location;
  final List<String> segments = <String>[
    apiVersion,
    'projects',
    projectId,
    if (location != null) ...<String>[
      'locations',
      location,
      'publishers',
      'google',
    ],
    'models',
    '$model:${task.wireName}',
  ];
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    pathSegments: segments,
    queryParameters: task == ModelTask.streamGenerateContent
        ? const <String, String>{'alt': 'sse'}
        : null,
  );
}

/// What one generate request sends, before the backend shapes it.
final class GenerateParts {
  /// The parts of one request; [contents] is the prompt, or a chat's history plus its message.
  const GenerateParts({
    required this.contents,
    this.systemInstruction,
    this.tools,
    this.toolConfig,
    this.safetySettings,
    this.generationConfig,
  });

  /// The contents sent, in order.
  final List<Content> contents;

  /// The model's system instruction.
  final Content? systemInstruction;

  /// The model's tools.
  final List<Tool>? tools;

  /// The model's tool configuration.
  final ToolConfig? toolConfig;

  /// The safety settings of the call, else of the chat or the model.
  final List<SafetySetting>? safetySettings;

  /// The generation configuration of the call, else of the chat or the model.
  final GenerationConfig? generationConfig;
}

/// The body of a `generateContent` or `streamGenerateContent` request: the same on both backends,
/// with no `model` field.
///
/// A safety setting with a method, which the Gemini Developer API refuses, was already refused by
/// `checkRequestOptions`.
Map<String, Object?> generateContentBody(GenerateParts parts) {
  return <String, Object?>{
    'contents': <Object?>[
      for (final Content content in parts.contents) content.toJson(),
    ],
    ..._optionalFields(parts),
  };
}

/// The body of a `countTokens` request for [backend].
///
/// The Gemini Developer API takes the whole generate request, nested under
/// `generateContentRequest`, with `model` written `models/<name>` and no `role` on the contents.
/// Agent Platform takes the contents, the system instruction, the tools and the generation
/// configuration, flat.
Map<String, Object?> countTokensBody(
  AIBackend backend,
  GenerateParts parts, {
  required String model,
}) {
  if (backend.isAgentPlatform) {
    final Map<String, Object?> optional = _optionalFields(parts)
      ..remove('toolConfig')
      ..remove('safetySettings');
    return <String, Object?>{
      'contents': <Object?>[
        for (final Content content in parts.contents) content.toJson(),
      ],
      ...optional,
    };
  }
  return <String, Object?>{
    'generateContentRequest': <String, Object?>{
      'model': 'models/$model',
      'contents': <Object?>[
        for (final Content content in parts.contents)
          Content(null, content.parts).toJson(),
      ],
      ..._optionalFields(parts),
    },
  };
}

/// Decodes one success body, or the data of one SSE event, of a generate call on [backend].
///
/// [json] is the decoded top-level object. On the Gemini Developer API,
/// `citationMetadata.citationSources` of each candidate becomes `citations`; nothing else is
/// renamed and no default is invented.
GenerateContentResponse decodeGenerateContentResponse(
  AIBackend backend,
  Map<String, Object?> json,
) {
  if (backend.isAgentPlatform) {
    return GenerateContentResponse.fromJson(json);
  }
  return GenerateContentResponse.fromJson(_withCitations(json));
}

/// Decodes one success body of a `countTokens` call; the two backends answer alike.
CountTokensResponse decodeCountTokensResponse(Map<String, Object?> json) =>
    CountTokensResponse.fromJson(json);

Map<String, Object?> _optionalFields(GenerateParts parts) {
  final Content? systemInstruction = parts.systemInstruction;
  final List<Tool>? tools = parts.tools;
  final ToolConfig? toolConfig = parts.toolConfig;
  final List<SafetySetting>? safetySettings = parts.safetySettings;
  final GenerationConfig? generationConfig = parts.generationConfig;
  return <String, Object?>{
    if (systemInstruction != null)
      'systemInstruction': systemInstruction.toJson(),
    if (tools != null)
      'tools': <Object?>[for (final Tool tool in tools) tool.toJson()],
    if (toolConfig != null) 'toolConfig': toolConfig.toJson(),
    if (safetySettings != null)
      'safetySettings': <Object?>[
        for (final SafetySetting setting in safetySettings) setting.toJson(),
      ],
    if (generationConfig != null) 'generationConfig': generationConfig.toJson(),
  };
}

Map<String, Object?> _withCitations(Map<String, Object?> json) {
  final Object? candidates = json['candidates'];
  if (candidates is! List<Object?>) {
    return json;
  }
  return <String, Object?>{
    ...json,
    'candidates': <Object?>[
      for (final Object? candidate in candidates)
        _candidateWithCitations(candidate),
    ],
  };
}

Object? _candidateWithCitations(Object? candidate) {
  if (candidate is! Map<String, Object?>) {
    return candidate;
  }
  final Object? metadata = candidate['citationMetadata'];
  if (metadata is! Map<String, Object?> ||
      !metadata.containsKey('citationSources') ||
      metadata.containsKey('citations')) {
    return candidate;
  }
  final Map<String, Object?> renamed = <String, Object?>{
    for (final MapEntry<String, Object?> entry in metadata.entries)
      if (entry.key == 'citationSources')
        'citations': entry.value
      else
        entry.key: entry.value,
  };
  return <String, Object?>{...candidate, 'citationMetadata': renamed};
}
