import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One message of a conversation: a [role] and its [parts].
///
/// A prompt is a list of contents. The static helpers build the common ones; [Content.system] is
/// only for `systemInstruction`.
@immutable
final class Content {
  /// Creates a content with [role] and [parts]. A null [role] is not sent.
  ///
  /// The list is kept as given; do not change it afterwards.
  const Content(this.role, this.parts);

  /// The author: `user`, `model`, `function` or `system`. Null is sent as no role, which the server
  /// reads as `user`.
  final String? role;

  /// The parts of the message.
  final List<Part> parts;

  /// A user message with one text part.
  static Content text(String text) =>
      Content('user', List<Part>.unmodifiable(<Part>[TextPart(text)]));

  /// A user message with several parts, for example text and an image.
  static Content multi(Iterable<Part> parts) =>
      Content('user', List<Part>.unmodifiable(parts));

  /// A model message, for example a reply restored into a chat history.
  static Content model(Iterable<Part> parts) =>
      Content('model', List<Part>.unmodifiable(parts));

  /// A user message with one inline-data part holding [bytes] of [mimeType].
  static Content inlineData(String mimeType, Uint8List bytes) => Content(
    'user',
    List<Part>.unmodifiable(<Part>[InlineDataPart(mimeType, bytes)]),
  );

  /// A user message answering the function call [name] with [response].
  ///
  /// Pass the call's [id] when the model gave one.
  static Content functionResponse(
    String name,
    Map<String, Object?> response, {
    String? id,
  }) => Content(
    'user',
    List<Part>.unmodifiable(<Part>[FunctionResponse(name, response, id: id)]),
  );

  /// A user message answering several function calls at once.
  static Content functionResponses(Iterable<FunctionResponse> responses) =>
      Content('user', List<Part>.unmodifiable(responses));

  /// A system instruction with one text part, for `systemInstruction`.
  ///
  /// A prompt or a chat message that contains it is refused with an [ArgumentError].
  static Content system(String instructions) => Content(
    'system',
    List<Part>.unmodifiable(<Part>[TextPart(instructions)]),
  );

  /// The JSON object sent to the server: `role` (when not null) and `parts`.
  Map<String, Object?> toJson() => <String, Object?>{
    if (role case final String role) 'role': role,
    'parts': <Object?>[for (final Part part in parts) part.toJson()],
  };

  /// Reads a content from a server response.
  ///
  /// Decoding is lenient: a missing or non-text `role` becomes `model`, a field of the wrong type
  /// is ignored, a part with no keys is dropped, and a part this version does not know (or whose
  /// inline data is not valid base64) becomes an [UnknownPart].
  static Content fromJson(Map<String, Object?> json) {
    final Object? role = json['role'];
    final Object? parts = json['parts'];
    final List<Part> decoded = <Part>[
      if (parts is List<Object?>)
        for (final Object? part in parts)
          if (part is Map<String, Object?>) ?_partFromJson(part),
    ];
    return Content(
      role is String ? role : 'model',
      List<Part>.unmodifiable(decoded),
    );
  }
}

/// One piece of a [Content]: text, data, a function call or response, code, or a part this version
/// does not know.
///
/// [isThought] and [thoughtSignature] apply to every part type. Send a model reply back with its
/// signatures, or the model may end with `MISSING_THOUGHT_SIGNATURE`.
@immutable
sealed class Part {
  /// Sets the thought fields shared by every part type.
  const Part({this.isThought = false, this.thoughtSignature});

  /// Whether the part is a thought summary (wire `thought`). Written only when true.
  final bool isThought;

  /// The model's opaque signature of its thinking (wire `thoughtSignature`). Written when not null.
  final String? thoughtSignature;

  /// The JSON object sent to the server.
  Map<String, Object?> toJson();

  Map<String, Object?> _withThought(String key, Object? value) =>
      <String, Object?>{
        key: value,
        if (isThought) 'thought': true,
        if (thoughtSignature case final String signature)
          'thoughtSignature': signature,
      };
}

/// A text part.
final class TextPart extends Part {
  /// Creates a text part.
  const TextPart(this.text, {super.isThought, super.thoughtSignature});

  /// The text.
  final String text;

  @override
  Map<String, Object?> toJson() => _withThought('text', text);
}

/// Bytes sent inline, for example an image; base64 on the wire.
final class InlineDataPart extends Part {
  /// Creates an inline-data part.
  const InlineDataPart(
    this.mimeType,
    this.bytes, {
    super.isThought,
    super.thoughtSignature,
  });

  /// The media type of [bytes], for example `image/png`.
  final String mimeType;

  /// The data.
  final Uint8List bytes;

  @override
  Map<String, Object?> toJson() => _withThought('inlineData', <String, Object?>{
    'mimeType': mimeType,
    'data': base64Encode(bytes),
  });
}

/// A reference to a file the backend reads, for example a `gs://` URI.
final class FileData extends Part {
  /// Creates a file-data part.
  const FileData(
    this.mimeType,
    this.fileUri, {
    super.isThought,
    super.thoughtSignature,
  });

  /// The media type of the file.
  final String mimeType;

  /// The URI of the file.
  final String fileUri;

  @override
  Map<String, Object?> toJson() => _withThought('fileData', <String, Object?>{
    'mimeType': mimeType,
    'fileUri': fileUri,
  });
}

/// A call to one of the declared functions, made by the model.
final class FunctionCall extends Part {
  /// Creates a function-call part.
  const FunctionCall(
    this.name,
    this.args, {
    this.id,
    super.isThought,
    super.thoughtSignature,
  });

  /// The name of the function.
  final String name;

  /// The arguments, as the model wrote them.
  final Map<String, Object?> args;

  /// The id of the call, when the model gave one; answer with the same id.
  final String? id;

  @override
  Map<String, Object?> toJson() =>
      _withThought('functionCall', <String, Object?>{
        if (id case final String id) 'id': id,
        'name': name,
        'args': args,
      });
}

/// The result of a function call, sent back to the model.
final class FunctionResponse extends Part {
  /// Creates a function-response part.
  const FunctionResponse(
    this.name,
    this.response, {
    this.id,
    super.isThought,
    super.thoughtSignature,
  });

  /// The name of the function that was called.
  final String name;

  /// The result, as a JSON object.
  final Map<String, Object?> response;

  /// The id of the call this answers, when the call had one.
  final String? id;

  @override
  Map<String, Object?> toJson() =>
      _withThought('functionResponse', <String, Object?>{
        if (id case final String id) 'id': id,
        'name': name,
        'response': response,
      });
}

/// Code the model wrote for the code-execution tool.
final class ExecutableCodePart extends Part {
  /// Creates an executable-code part.
  const ExecutableCodePart({
    this.language,
    this.code,
    super.isThought,
    super.thoughtSignature,
  });

  /// The language as the wire string, for example `PYTHON`.
  final String? language;

  /// The code.
  final String? code;

  @override
  Map<String, Object?> toJson() =>
      _withThought('executableCode', <String, Object?>{
        if (language case final String language) 'language': language,
        if (code case final String code) 'code': code,
      });
}

/// The result of running an [ExecutableCodePart].
final class CodeExecutionResultPart extends Part {
  /// Creates a code-execution-result part.
  const CodeExecutionResultPart({
    this.outcome,
    this.output,
    super.isThought,
    super.thoughtSignature,
  });

  /// The outcome as the wire string, for example `OUTCOME_OK`.
  final String? outcome;

  /// What the code printed, or the error.
  final String? output;

  @override
  Map<String, Object?> toJson() =>
      _withThought('codeExecutionResult', <String, Object?>{
        if (outcome case final String outcome) 'outcome': outcome,
        if (output case final String output) 'output': output,
      });
}

/// A part this version does not know, kept as its JSON and sent back unchanged.
final class UnknownPart extends Part {
  /// Creates a part holding [data].
  const UnknownPart(this.data);

  /// The part's JSON object.
  final Map<String, Object?> data;

  /// Whether [data] has `thought: true`.
  @override
  bool get isThought => data['thought'] == true;

  /// The `thoughtSignature` of [data], when it is text.
  @override
  String? get thoughtSignature => switch (data['thoughtSignature']) {
    final String signature => signature,
    _ => null,
  };

  @override
  Map<String, Object?> toJson() => data;
}

/// Decodes one part; null for a part with no keys, which is dropped.
Part? _partFromJson(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }
  final bool thought = json['thought'] == true;
  final Object? rawSignature = json['thoughtSignature'];
  final String? signature = rawSignature is String ? rawSignature : null;
  final Part? known = _knownPart(json, thought, signature);
  return known ?? UnknownPart(UnmodifiableMapView<String, Object?>(json));
}

/// The first known key decides the type, in the order JS uses (`assignPartType`).
Part? _knownPart(Map<String, Object?> json, bool thought, String? signature) {
  if (json.containsKey('text')) {
    return switch (json['text']) {
      final String text => TextPart(
        text,
        isThought: thought,
        thoughtSignature: signature,
      ),
      _ => null,
    };
  }
  if (json['inlineData'] case final Map<String, Object?> data) {
    return _inlineData(data, thought, signature);
  }
  if (json['functionCall'] case final Map<String, Object?> call) {
    return _functionCall(call, thought, signature);
  }
  if (json['functionResponse'] case final Map<String, Object?> response) {
    return _functionResponse(response, thought, signature);
  }
  if (json['fileData'] case final Map<String, Object?> file) {
    return _fileData(file, thought, signature);
  }
  return _codePart(json, thought, signature);
}

Part? _inlineData(Map<String, Object?> json, bool thought, String? signature) {
  final Object? mimeType = json['mimeType'];
  final Object? data = json['data'];
  if (mimeType is! String || data is! String) {
    return null;
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } on FormatException {
    return null;
  }
  return InlineDataPart(
    mimeType,
    bytes,
    isThought: thought,
    thoughtSignature: signature,
  );
}

Part? _fileData(Map<String, Object?> json, bool thought, String? signature) {
  final Object? mimeType = json['mimeType'];
  final Object? fileUri = json['fileUri'];
  if (mimeType is! String || fileUri is! String) {
    return null;
  }
  return FileData(
    mimeType,
    fileUri,
    isThought: thought,
    thoughtSignature: signature,
  );
}

Part? _functionCall(
  Map<String, Object?> json,
  bool thought,
  String? signature,
) {
  final Object? name = json['name'];
  if (name is! String) {
    return null;
  }
  return FunctionCall(
    name,
    _objectOrEmpty(json['args']),
    id: _stringOrNull(json['id']),
    isThought: thought,
    thoughtSignature: signature,
  );
}

Part? _functionResponse(
  Map<String, Object?> json,
  bool thought,
  String? signature,
) {
  final Object? name = json['name'];
  if (name is! String) {
    return null;
  }
  return FunctionResponse(
    name,
    _objectOrEmpty(json['response']),
    id: _stringOrNull(json['id']),
    isThought: thought,
    thoughtSignature: signature,
  );
}

Part? _codePart(Map<String, Object?> json, bool thought, String? signature) {
  if (json['executableCode'] case final Map<String, Object?> code) {
    return ExecutableCodePart(
      language: _stringOrNull(code['language']),
      code: _stringOrNull(code['code']),
      isThought: thought,
      thoughtSignature: signature,
    );
  }
  if (json['codeExecutionResult'] case final Map<String, Object?> result) {
    return CodeExecutionResultPart(
      outcome: _stringOrNull(result['outcome']),
      output: _stringOrNull(result['output']),
      isThought: thought,
      thoughtSignature: signature,
    );
  }
  return null;
}

String? _stringOrNull(Object? value) => value is String ? value : null;

Map<String, Object?> _objectOrEmpty(Object? value) =>
    value is Map<String, Object?>
    ? UnmodifiableMapView<String, Object?>(value)
    : const <String, Object?>{};
