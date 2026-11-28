/// The local checks of the request (§5.2, §5.3) and of chat histories and messages (§5.6).
///
/// Every check throws [ArgumentError] unless its documentation says otherwise. Not exported.
library;

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/config.dart';
import 'package:firebase_ai_dart/src/content.dart';
import 'package:firebase_ai_dart/src/exception.dart';
import 'package:firebase_ai_dart/src/response.dart';
import 'package:firebase_ai_dart/src/schema.dart';
import 'package:firebase_ai_dart/src/tool.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

final RegExp _modelName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _location = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _projectId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

const String _modelsPrefix = 'models/';

const Set<String> _promptRoles = <String>{'user', 'model', 'function'};

/// The finish reasons for which the response accessors throw (JS `badFinishReasons`).
const Set<FinishReason> blockingFinishReasons = <FinishReason>{
  FinishReason.recitation,
  FinishReason.safety,
  FinishReason.blocklist,
  FinishReason.prohibitedContent,
  FinishReason.spii,
  FinishReason.malformedFunctionCall,
  FinishReason.imageSafety,
  FinishReason.imageProhibitedContent,
  FinishReason.imageOther,
  FinishReason.noImage,
  FinishReason.imageRecitation,
  FinishReason.language,
  FinishReason.unexpectedToolCall,
  FinishReason.tooManyToolCalls,
  FinishReason.missingThoughtSignature,
  FinishReason.malformedResponse,
};

/// Whether [reason] is one of the [blockingFinishReasons].
bool isBlockingFinishReason(FinishReason? reason) =>
    blockingFinishReasons.contains(reason);

/// Returns the plain model name of [model]: a name matching
/// `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`, optionally prefixed with `models/`, which is removed.
String checkModelName(String model) {
  final String name = model.startsWith(_modelsPrefix)
      ? model.substring(_modelsPrefix.length)
      : model;
  if (!_modelName.hasMatch(name)) {
    throw ArgumentError.value(
      model,
      'model',
      'Expected a plain model name such as gemini-x, optionally prefixed '
          'with models/',
    );
  }
  return name;
}

/// Checks an Agent Platform [location], for example `global` or `us-central1`.
void checkLocation(String location) {
  if (!_location.hasMatch(location)) {
    throw ArgumentError.value(
      location,
      'location',
      'Expected a location such as global, us-central1 or europe-west4',
    );
  }
}

/// Checks the app options that are present: the API key and app id must be header values, and the
/// project id must match `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`, because it goes into the URL path.
///
/// A missing or empty value is not checked here; the first call that needs it throws [StateError].
/// The API key is never part of the message.
void checkAppOptions(FirebaseOptions options) {
  if (options.apiKey.isNotEmpty && !isHeaderValue(options.apiKey)) {
    throw ArgumentError(
      'app.options.apiKey contains characters a header cannot carry.',
    );
  }
  if (options.appId.isNotEmpty && !isHeaderValue(options.appId)) {
    throw ArgumentError(
      'app.options.appId contains characters a header cannot carry.',
    );
  }
  final String? projectId = options.projectId;
  if (projectId != null &&
      projectId.isNotEmpty &&
      !_projectId.hasMatch(projectId)) {
    throw ArgumentError(
      'app.options.projectId is not a valid project id: expected letters, '
      'digits, ".", "_", ":" or "-", at most 128 characters.',
    );
  }
}

/// Checks that the duration [value] named [name] is not negative. Null passes.
void checkTimeout(Duration? value, String name) {
  if (value != null && value.isNegative) {
    throw ArgumentError.value(value, name, 'Must not be negative');
  }
}

/// Returns [prompt] as a list after checking that it is not empty, that every content has a part,
/// and that every role is `user`, `model`, `function` or null.
///
/// [name] is the argument named in the error: `prompt` or `contents`.
List<Content> checkPrompt(Iterable<Content> prompt, {String name = 'prompt'}) {
  final List<Content> contents = List<Content>.of(prompt);
  if (contents.isEmpty) {
    throw ArgumentError.value(contents, name, 'Must not be empty');
  }
  for (int i = 0; i < contents.length; i++) {
    final Content content = contents[i];
    final String? role = content.role;
    if (role == 'system') {
      throw ArgumentError.value(
        role,
        '$name[$i].role',
        'A system content belongs in systemInstruction, not in the $name',
      );
    }
    if (role != null && !_promptRoles.contains(role)) {
      throw ArgumentError.value(
        role,
        '$name[$i].role',
        'Expected user, model, function or null',
      );
    }
    if (content.parts.isEmpty) {
      throw ArgumentError.value(
        content.parts,
        '$name[$i].parts',
        'Must not be empty',
      );
    }
  }
  return contents;
}

/// Checks the per-request options before anything is sent.
///
/// Throws [ArgumentError] for a [HarmCategory.unknown] safety setting, or a `double` that is not
/// finite in [generationConfig] (its schema included) or in [toolConfig]. Throws
/// [FirebaseAIException] with code `unsupported` for a [SafetySetting.method] when [developerApi]
/// is true.
void checkRequestOptions({
  List<SafetySetting>? safetySettings,
  GenerationConfig? generationConfig,
  ToolConfig? toolConfig,
  required bool developerApi,
}) {
  if (safetySettings != null) {
    _checkSafetySettings(safetySettings, developerApi: developerApi);
  }
  if (generationConfig != null) {
    _checkGenerationConfig(generationConfig);
  }
  final LatLng? latLng = toolConfig?.retrievalConfig?.latLng;
  if (latLng != null) {
    _checkFinite(latLng.latitude, 'toolConfig.retrievalConfig.latLng.latitude');
    _checkFinite(
      latLng.longitude,
      'toolConfig.retrievalConfig.latLng.longitude',
    );
  }
}

/// Returns [history] as a list after checking the rules of §5.6, in order: the first content has
/// role `user`; every role is `user`, `model` or `function` and every content has a part; user-side
/// (`user` or `function`) and `model` contents alternate.
List<Content> checkHistory(Iterable<Content> history) {
  final List<Content> contents = List<Content>.of(history);
  if (contents.isNotEmpty && contents.first.role != 'user') {
    throw ArgumentError.value(
      contents.first.role,
      'history[0].role',
      'The first content of a history must have role user',
    );
  }
  for (int i = 0; i < contents.length; i++) {
    final Content content = contents[i];
    if (!_promptRoles.contains(content.role)) {
      throw ArgumentError.value(
        content.role,
        'history[$i].role',
        'Expected user, model or function',
      );
    }
    if (content.parts.isEmpty) {
      throw ArgumentError.value(
        content.parts,
        'history[$i].parts',
        'Must not be empty',
      );
    }
  }
  for (int i = 1; i < contents.length; i++) {
    final bool previousIsModel = contents[i - 1].role == 'model';
    final bool currentIsModel = contents[i].role == 'model';
    if (previousIsModel == currentIsModel) {
      throw ArgumentError.value(
        contents[i].role,
        'history[$i].role',
        currentIsModel
            ? 'A model content must follow a user or function content'
            : 'A user or function content must follow a model content',
      );
    }
  }
  return contents;
}

/// Checks a chat message: role `user` or null, at least one part, and either only function-response
/// parts or none.
void checkMessage(Content message) {
  final String? role = message.role;
  if (role != null && role != 'user') {
    throw ArgumentError.value(
      role,
      'message.role',
      role == 'system'
          ? 'A system content belongs in systemInstruction'
          : 'A chat message must have role user or null',
    );
  }
  if (message.parts.isEmpty) {
    throw ArgumentError.value(
      message.parts,
      'message.parts',
      'Must not be empty',
    );
  }
  final int responses = message.parts.whereType<FunctionResponse>().length;
  if (responses != 0 && responses != message.parts.length) {
    throw ArgumentError.value(
      message.parts,
      'message.parts',
      'A message holds either only function responses or none',
    );
  }
}

/// Whether a chat turn with [response] as its reply is added to the history: the first candidate's
/// content has a part and its finish reason is not blocking.
bool canAppendTurn(GenerateContentResponse response) {
  if (response.candidates.isEmpty) {
    return false;
  }
  final Candidate first = response.candidates.first;
  return first.content.parts.isNotEmpty &&
      !isBlockingFinishReason(first.finishReason);
}

void _checkSafetySettings(
  List<SafetySetting> settings, {
  required bool developerApi,
}) {
  for (int i = 0; i < settings.length; i++) {
    final SafetySetting setting = settings[i];
    if (setting.category == HarmCategory.unknown) {
      throw ArgumentError.value(
        setting.category,
        'safetySettings[$i].category',
        'HarmCategory.unknown cannot be sent',
      );
    }
    if (developerApi && setting.method != null) {
      throw const FirebaseAIException(
        code: 'unsupported',
        message:
            'SafetySetting.method is not supported by the Gemini Developer '
            'API; use FirebaseAI.agentPlatform or remove it.',
      );
    }
  }
}

void _checkGenerationConfig(GenerationConfig config) {
  final Map<String, double?> doubles = <String, double?>{
    'temperature': config.temperature,
    'topP': config.topP,
    'presencePenalty': config.presencePenalty,
    'frequencyPenalty': config.frequencyPenalty,
  };
  for (final MapEntry<String, double?> entry in doubles.entries) {
    final double? value = entry.value;
    if (value != null) {
      _checkFinite(value, 'generationConfig.${entry.key}');
    }
  }
  final Schema? schema = config.responseSchema;
  if (schema != null) {
    _checkSchema(schema, 'generationConfig.responseSchema');
  }
}

void _checkSchema(Schema schema, String name) {
  final num? minimum = schema.minimum;
  if (minimum != null) {
    _checkFinite(minimum, '$name.minimum');
  }
  final num? maximum = schema.maximum;
  if (maximum != null) {
    _checkFinite(maximum, '$name.maximum');
  }
  final Schema? items = schema.items;
  if (items != null) {
    _checkSchema(items, '$name.items');
  }
  final Map<String, Schema>? properties = schema.properties;
  if (properties != null) {
    for (final MapEntry<String, Schema> entry in properties.entries) {
      _checkSchema(entry.value, '$name.properties[${entry.key}]');
    }
  }
  final List<Schema>? anyOf = schema.anyOf;
  if (anyOf != null) {
    for (int i = 0; i < anyOf.length; i++) {
      _checkSchema(anyOf[i], '$name.anyOf[$i]');
    }
  }
}

void _checkFinite(num value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'Must be a finite number');
  }
}
