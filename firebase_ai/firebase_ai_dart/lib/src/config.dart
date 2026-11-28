import 'package:firebase_ai_dart/src/schema.dart';
import 'package:meta/meta.dart';

/// A category of harmful content, used by [SafetySetting] and in safety ratings.
enum HarmCategory {
  /// Harassment (`HARM_CATEGORY_HARASSMENT`).
  harassment('HARM_CATEGORY_HARASSMENT'),

  /// Hate speech (`HARM_CATEGORY_HATE_SPEECH`).
  hateSpeech('HARM_CATEGORY_HATE_SPEECH'),

  /// Sexually explicit content (`HARM_CATEGORY_SEXUALLY_EXPLICIT`).
  sexuallyExplicit('HARM_CATEGORY_SEXUALLY_EXPLICIT'),

  /// Dangerous content (`HARM_CATEGORY_DANGEROUS_CONTENT`).
  dangerousContent('HARM_CATEGORY_DANGEROUS_CONTENT'),

  /// A category this version does not know, read from a response. It cannot be sent.
  unknown(null);

  const HarmCategory(this._wire);

  final String? _wire;

  /// The wire string. Throws [ArgumentError] for [unknown], which cannot be sent.
  String toJson() =>
      _wire ??
      (throw ArgumentError.value(
        this,
        'category',
        'HarmCategory.unknown cannot be sent',
      ));
}

/// The level from which content of a [HarmCategory] is blocked.
enum HarmBlockThreshold {
  /// Block low probability and above (`BLOCK_LOW_AND_ABOVE`).
  low('BLOCK_LOW_AND_ABOVE'),

  /// Block medium probability and above (`BLOCK_MEDIUM_AND_ABOVE`).
  medium('BLOCK_MEDIUM_AND_ABOVE'),

  /// Block only high probability (`BLOCK_ONLY_HIGH`).
  high('BLOCK_ONLY_HIGH'),

  /// Block nothing, but still rate (`BLOCK_NONE`).
  none('BLOCK_NONE'),

  /// Turn the filter off (`OFF`).
  off('OFF');

  const HarmBlockThreshold(this._wire);

  final String _wire;

  /// The wire string.
  String toJson() => _wire;
}

/// What a [HarmBlockThreshold] is measured on. Agent Platform only.
enum HarmBlockMethod {
  /// The severity of the content (`SEVERITY`).
  severity('SEVERITY'),

  /// The probability that the content is harmful (`PROBABILITY`).
  probability('PROBABILITY');

  const HarmBlockMethod(this._wire);

  final String _wire;

  /// The wire string.
  String toJson() => _wire;
}

/// How much the model thinks, for models that support thinking levels.
enum ThinkingLevel {
  /// `MINIMAL`.
  minimal('MINIMAL'),

  /// `LOW`.
  low('LOW'),

  /// `MEDIUM`.
  medium('MEDIUM'),

  /// `HIGH`.
  high('HIGH');

  const ThinkingLevel(this._wire);

  final String _wire;

  /// The wire string.
  String toJson() => _wire;
}

/// A kind of output the model may produce.
enum ResponseModality {
  /// Text (`TEXT`).
  text('TEXT'),

  /// Images (`IMAGE`).
  image('IMAGE'),

  /// Audio (`AUDIO`).
  audio('AUDIO');

  const ResponseModality(this._wire);

  final String _wire;

  /// The wire string.
  String toJson() => _wire;
}

/// Options for how the model generates its answer.
///
/// Every field is optional; null fields are not sent.
@immutable
final class GenerationConfig {
  /// Creates a configuration. Every `double` must be finite when the request is made.
  const GenerationConfig({
    this.candidateCount,
    this.stopSequences,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
    this.responseMimeType,
    this.responseSchema,
    this.responseJsonSchema,
    this.responseModalities,
    this.thinkingConfig,
    this.speechConfig,
    this.imageConfig,
  });

  /// The number of candidates to generate.
  final int? candidateCount;

  /// Text sequences that stop generation.
  final List<String>? stopSequences;

  /// The largest number of tokens in a candidate.
  final int? maxOutputTokens;

  /// The randomness of the output.
  final double? temperature;

  /// The cumulative probability of tokens considered (nucleus sampling).
  final double? topP;

  /// The number of most likely tokens considered.
  final int? topK;

  /// The penalty for tokens that already appeared.
  final double? presencePenalty;

  /// The penalty for tokens by how often they already appeared.
  final double? frequencyPenalty;

  /// The media type of the answer, for example `application/json`.
  final String? responseMimeType;

  /// The schema of the answer, with [responseMimeType] `application/json`.
  final Schema? responseSchema;

  /// A JSON Schema for the answer, sent as it is.
  final JsonSchema? responseJsonSchema;

  /// The kinds of output the model may produce.
  final List<ResponseModality>? responseModalities;

  /// Options for thinking models.
  final ThinkingConfig? thinkingConfig;

  /// Options for spoken output.
  final SpeechConfig? speechConfig;

  /// Options for image output.
  final ImageConfig? imageConfig;

  /// The `generationConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'candidateCount': ?candidateCount,
    'stopSequences': ?stopSequences,
    'maxOutputTokens': ?maxOutputTokens,
    'temperature': ?temperature,
    'topP': ?topP,
    'topK': ?topK,
    'presencePenalty': ?presencePenalty,
    'frequencyPenalty': ?frequencyPenalty,
    'responseMimeType': ?responseMimeType,
    'responseSchema': ?responseSchema?.toJson(),
    'responseJsonSchema': ?responseJsonSchema?.json,
    if (responseModalities case final List<ResponseModality> modalities)
      'responseModalities': <String>[
        for (final ResponseModality modality in modalities) modality.toJson(),
      ],
    'thinkingConfig': ?thinkingConfig?.toJson(),
    'speechConfig': ?speechConfig?.toJson(),
    'imageConfig': ?imageConfig?.toJson(),
  };
}

/// Options for thinking models: either a token budget or a level.
@immutable
final class ThinkingConfig {
  /// Thinking bounded by [thinkingBudget] tokens.
  const ThinkingConfig.withThinkingBudget(
    int this.thinkingBudget, {
    this.includeThoughts,
  }) : thinkingLevel = null;

  /// Thinking at [thinkingLevel].
  const ThinkingConfig.withThinkingLevel(
    ThinkingLevel this.thinkingLevel, {
    this.includeThoughts,
  }) : thinkingBudget = null;

  /// The token budget for thinking.
  final int? thinkingBudget;

  /// The thinking level.
  final ThinkingLevel? thinkingLevel;

  /// Whether the answer includes thought summaries (parts with `isThought`).
  final bool? includeThoughts;

  /// The `thinkingConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'thinkingBudget': ?thinkingBudget,
    'thinkingLevel': ?thinkingLevel?.toJson(),
    'includeThoughts': ?includeThoughts,
  };
}

/// Options for spoken output.
@immutable
final class SpeechConfig {
  /// Creates speech options.
  const SpeechConfig({this.languageCode, this.voiceName});

  /// The language, for example `en-US`.
  final String? languageCode;

  /// The name of a prebuilt voice (wire `voiceConfig.prebuiltVoiceConfig.voiceName`).
  final String? voiceName;

  /// The `speechConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'languageCode': ?languageCode,
    if (voiceName case final String voiceName)
      'voiceConfig': <String, Object?>{
        'prebuiltVoiceConfig': <String, Object?>{'voiceName': voiceName},
      },
  };
}

/// Options for image output.
@immutable
final class ImageConfig {
  /// Creates image options. Both values are strings because the server adds new ones.
  const ImageConfig({this.aspectRatio, this.imageSize});

  /// The aspect ratio, for example `16:9`.
  final String? aspectRatio;

  /// The size, for example `1K` or `4K`.
  final String? imageSize;

  /// The `imageConfig` JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'aspectRatio': ?aspectRatio,
    'imageSize': ?imageSize,
  };
}

/// The block threshold for one [HarmCategory].
@immutable
final class SafetySetting {
  /// Creates a setting. [method] is refused on the Gemini Developer API.
  const SafetySetting(this.category, this.threshold, [this.method]);

  /// The category. [HarmCategory.unknown] cannot be sent.
  final HarmCategory category;

  /// The threshold.
  final HarmBlockThreshold threshold;

  /// What the threshold is measured on; Agent Platform only.
  final HarmBlockMethod? method;

  /// The JSON object. Throws [ArgumentError] for [HarmCategory.unknown].
  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.toJson(),
    'threshold': threshold.toJson(),
    'method': ?method?.toJson(),
  };
}
