import 'dart:collection';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/config.dart';
import 'package:firebase_ai_dart/src/content.dart';
import 'package:firebase_ai_dart/src/exception.dart';
import 'package:firebase_ai_dart/src/validation.dart';
import 'package:meta/meta.dart';

/// Why the model stopped generating a candidate.
///
/// The reasons for which [GenerateContentResponse.text] and the other accessors throw are listed in
/// the README; [maxTokens], [other], [stop] and [unknown] never make them throw.
enum FinishReason implements _WireEnum {
  /// The natural end, or a stop sequence (`STOP`).
  stop('STOP'),

  /// The output reached `maxOutputTokens` (`MAX_TOKENS`).
  maxTokens('MAX_TOKENS'),

  /// A safety filter stopped the candidate (`SAFETY`).
  safety('SAFETY'),

  /// The candidate recited training data (`RECITATION`).
  recitation('RECITATION'),

  /// Another reason (`OTHER`).
  other('OTHER'),

  /// A term of a block list matched (`BLOCKLIST`).
  blocklist('BLOCKLIST'),

  /// Prohibited content (`PROHIBITED_CONTENT`).
  prohibitedContent('PROHIBITED_CONTENT'),

  /// Sensitive personally identifiable information (`SPII`).
  spii('SPII'),

  /// The model wrote a function call that is not valid (`MALFORMED_FUNCTION_CALL`).
  malformedFunctionCall('MALFORMED_FUNCTION_CALL'),

  /// A generated image broke a safety rule (`IMAGE_SAFETY`).
  imageSafety('IMAGE_SAFETY'),

  /// A generated image had prohibited content (`IMAGE_PROHIBITED_CONTENT`).
  imageProhibitedContent('IMAGE_PROHIBITED_CONTENT'),

  /// Image generation stopped for another reason (`IMAGE_OTHER`).
  imageOther('IMAGE_OTHER'),

  /// An image was expected and none was generated (`NO_IMAGE`).
  noImage('NO_IMAGE'),

  /// A generated image recited training data (`IMAGE_RECITATION`).
  imageRecitation('IMAGE_RECITATION'),

  /// The language is not supported (`LANGUAGE`).
  language('LANGUAGE'),

  /// The model called a tool when none was expected (`UNEXPECTED_TOOL_CALL`).
  unexpectedToolCall('UNEXPECTED_TOOL_CALL'),

  /// The model made too many tool calls (`TOO_MANY_TOOL_CALLS`).
  tooManyToolCalls('TOO_MANY_TOOL_CALLS'),

  /// A model reply was sent back without its thought signature (`MISSING_THOUGHT_SIGNATURE`).
  missingThoughtSignature('MISSING_THOUGHT_SIGNATURE'),

  /// The model's output could not be read (`MALFORMED_RESPONSE`).
  malformedResponse('MALFORMED_RESPONSE'),

  /// A reason this version does not know.
  unknown(null);

  const FinishReason(this._wire);

  @override
  final String? _wire;
}

/// Why a prompt was blocked.
enum BlockReason implements _WireEnum {
  /// A safety filter (`SAFETY`).
  safety('SAFETY'),

  /// Another reason (`OTHER`).
  other('OTHER'),

  /// A term of a block list matched (`BLOCKLIST`).
  blocklist('BLOCKLIST'),

  /// Prohibited content (`PROHIBITED_CONTENT`).
  prohibitedContent('PROHIBITED_CONTENT'),

  /// A reason this version does not know.
  unknown(null);

  const BlockReason(this._wire);

  @override
  final String? _wire;
}

/// How likely content is to be harmful.
enum HarmProbability implements _WireEnum {
  /// `NEGLIGIBLE`.
  negligible('NEGLIGIBLE'),

  /// `LOW`.
  low('LOW'),

  /// `MEDIUM`.
  medium('MEDIUM'),

  /// `HIGH`.
  high('HIGH'),

  /// A value this version does not know.
  unknown(null);

  const HarmProbability(this._wire);

  @override
  final String? _wire;
}

/// How harmful content is.
enum HarmSeverity implements _WireEnum {
  /// `HARM_SEVERITY_NEGLIGIBLE`.
  negligible('HARM_SEVERITY_NEGLIGIBLE'),

  /// `HARM_SEVERITY_LOW`.
  low('HARM_SEVERITY_LOW'),

  /// `HARM_SEVERITY_MEDIUM`.
  medium('HARM_SEVERITY_MEDIUM'),

  /// `HARM_SEVERITY_HIGH`.
  high('HARM_SEVERITY_HIGH'),

  /// `HARM_SEVERITY_UNSUPPORTED`.
  unsupported('HARM_SEVERITY_UNSUPPORTED'),

  /// A value this version does not know.
  unknown(null);

  const HarmSeverity(this._wire);

  @override
  final String? _wire;
}

/// The kind of data a token count is about.
enum Modality implements _WireEnum {
  /// Not given (`MODALITY_UNSPECIFIED`, also when the field is absent or not text).
  unspecified('MODALITY_UNSPECIFIED'),

  /// `TEXT`.
  text('TEXT'),

  /// `IMAGE`.
  image('IMAGE'),

  /// `VIDEO`.
  video('VIDEO'),

  /// `AUDIO`.
  audio('AUDIO'),

  /// `DOCUMENT`.
  document('DOCUMENT'),

  /// A value this version does not know.
  unknown(null);

  const Modality(this._wire);

  @override
  final String? _wire;
}

/// Whether the URL context tool could read a URL.
enum UrlRetrievalStatus implements _WireEnum {
  /// `URL_RETRIEVAL_STATUS_UNSPECIFIED`.
  unspecified('URL_RETRIEVAL_STATUS_UNSPECIFIED'),

  /// `URL_RETRIEVAL_STATUS_SUCCESS`.
  success('URL_RETRIEVAL_STATUS_SUCCESS'),

  /// `URL_RETRIEVAL_STATUS_ERROR`.
  error('URL_RETRIEVAL_STATUS_ERROR'),

  /// `URL_RETRIEVAL_STATUS_PAYWALL`.
  paywall('URL_RETRIEVAL_STATUS_PAYWALL'),

  /// `URL_RETRIEVAL_STATUS_UNSAFE`.
  unsafe('URL_RETRIEVAL_STATUS_UNSAFE'),

  /// A value this version does not know.
  unknown(null);

  const UrlRetrievalStatus(this._wire);

  @override
  final String? _wire;
}

/// The answer to a `generateContent` call, or one chunk of a stream.
///
/// Decoding is lenient: a field of the wrong type is treated as absent and stays in [raw], and an
/// unknown enum string becomes `unknown`.
@immutable
final class GenerateContentResponse {
  /// Creates a response. The package creates them; you need this only in tests.
  GenerateContentResponse({
    List<Candidate> candidates = const <Candidate>[],
    this.promptFeedback,
    this.usageMetadata,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : candidates = List<Candidate>.unmodifiable(candidates),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// Reads a response from its decoded JSON object.
  factory GenerateContentResponse.fromJson(Map<String, Object?> json) {
    final List<Object?> candidates = _list(json['candidates']);
    return GenerateContentResponse(
      candidates: <Candidate>[
        for (int i = 0; i < candidates.length; i++)
          if (_map(candidates[i]) case final Map<String, Object?> candidate)
            _candidate(candidate, i),
      ],
      promptFeedback: _decode(json['promptFeedback'], _promptFeedback),
      usageMetadata: _decode(json['usageMetadata'], _usageMetadata),
      raw: json,
    );
  }

  /// The candidates, in the order of the answer.
  final List<Candidate> candidates;

  /// Why the prompt was blocked, when it was, and its safety ratings.
  final PromptFeedback? promptFeedback;

  /// The token counts of the request and the answer.
  final UsageMetadata? usageMetadata;

  /// The decoded JSON object, so fields this version does not model can be read.
  final Map<String, Object?> raw;

  /// The text parts of the first candidate that are not thoughts, joined with `''`; null when there
  /// are none.
  ///
  /// Throws a [FirebaseAIException] with code `response-error` when the prompt was blocked (no
  /// candidate and a block reason), or when the first candidate ended with a blocking finish
  /// reason. The same holds for [thoughtSummary], [inlineDataParts] and [functionCalls].
  String? get text => _joinText(thoughts: false);

  /// The thought text parts of the first candidate, joined with `''`; null when there are none.
  String? get thoughtSummary => _joinText(thoughts: true);

  /// The inline-data parts of the first candidate.
  List<InlineDataPart> get inlineDataParts => List<InlineDataPart>.unmodifiable(
    _firstParts().whereType<InlineDataPart>(),
  );

  /// The function-call parts of the first candidate.
  List<FunctionCall> get functionCalls =>
      List<FunctionCall>.unmodifiable(_firstParts().whereType<FunctionCall>());

  String? _joinText({required bool thoughts}) {
    final List<String> texts = <String>[
      for (final Part part in _firstParts())
        if (part is TextPart && part.isThought == thoughts) part.text,
    ];
    return texts.isEmpty ? null : texts.join();
  }

  List<Part> _firstParts() {
    if (candidates.isEmpty) {
      final BlockReason? blockReason = promptFeedback?.blockReason;
      if (blockReason != null) {
        throw FirebaseAIException(
          code: 'response-error',
          message:
              'The prompt was blocked (${blockReason._wire ?? 'unknown'}). '
              'See response.promptFeedback.',
          response: this,
        );
      }
      return const <Part>[];
    }
    final Candidate first = candidates.first;
    final FinishReason? finishReason = first.finishReason;
    if (isBlockingFinishReason(finishReason)) {
      throw FirebaseAIException(
        code: 'response-error',
        message:
            'The candidate was blocked (${finishReason?._wire}). '
            'See response.candidates.',
        response: this,
      );
    }
    return first.content.parts;
  }
}

/// One answer of the model.
@immutable
final class Candidate {
  /// Creates a candidate. The package creates them; you need this only in tests.
  Candidate({
    required this.index,
    required this.content,
    this.finishReason,
    this.finishMessage,
    List<SafetyRating> safetyRatings = const <SafetyRating>[],
    this.citationMetadata,
    this.groundingMetadata,
    this.urlContextMetadata,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : safetyRatings = List<SafetyRating>.unmodifiable(safetyRatings),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// The position of the candidate; its place in the list when the server left it out.
  final int index;

  /// The content; `Content('model', [])` when the server sent none.
  final Content content;

  /// Why generation stopped, when it did.
  final FinishReason? finishReason;

  /// The server's explanation of [finishReason].
  final String? finishMessage;

  /// The safety ratings of the candidate.
  final List<SafetyRating> safetyRatings;

  /// The sources the candidate cites.
  final CitationMetadata? citationMetadata;

  /// The search or map results the candidate is grounded on.
  final GroundingMetadata? groundingMetadata;

  /// The URLs the URL context tool read.
  final UrlContextMetadata? urlContextMetadata;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// Why a prompt was blocked, and its safety ratings.
@immutable
final class PromptFeedback {
  /// Creates prompt feedback. The package creates them; you need this only in tests.
  PromptFeedback({
    this.blockReason,
    this.blockReasonMessage,
    List<SafetyRating> safetyRatings = const <SafetyRating>[],
    Map<String, Object?> raw = const <String, Object?>{},
  }) : safetyRatings = List<SafetyRating>.unmodifiable(safetyRatings),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// Why the prompt was blocked; null when it was not.
  final BlockReason? blockReason;

  /// The server's explanation of [blockReason].
  final String? blockReasonMessage;

  /// The safety ratings of the prompt.
  final List<SafetyRating> safetyRatings;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// How harmful content of one category is.
@immutable
final class SafetyRating {
  /// Creates a rating. The package creates them; you need this only in tests.
  SafetyRating({
    required this.category,
    this.probability,
    this.severity,
    this.probabilityScore,
    this.severityScore,
    this.blocked,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : raw = UnmodifiableMapView<String, Object?>(raw);

  /// The category.
  final HarmCategory category;

  /// How likely the content is to be harmful.
  final HarmProbability? probability;

  /// How harmful the content is; the Gemini Developer API may leave it out.
  final HarmSeverity? severity;

  /// The probability as a score.
  final double? probabilityScore;

  /// The severity as a score.
  final double? severityScore;

  /// Whether the content was blocked for this category.
  final bool? blocked;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// The sources a candidate cites.
@immutable
final class CitationMetadata {
  /// Creates citation metadata. The package creates them; you need this only in tests.
  CitationMetadata({
    List<Citation> citations = const <Citation>[],
    Map<String, Object?> raw = const <String, Object?>{},
  }) : citations = List<Citation>.unmodifiable(citations),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// The citations.
  final List<Citation> citations;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// One source cited by a candidate.
@immutable
final class Citation {
  /// Creates a citation. The package creates them; you need this only in tests.
  Citation({
    this.startIndex,
    this.endIndex,
    this.uri,
    this.license,
    this.title,
    this.publicationDate,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : raw = UnmodifiableMapView<String, Object?>(raw);

  /// The start of the cited text in the candidate.
  final int? startIndex;

  /// The end of the cited text in the candidate.
  final int? endIndex;

  /// The URI of the source.
  final String? uri;

  /// The license of the source.
  final String? license;

  /// The title of the source.
  final String? title;

  /// The publication date; null unless year, month and day are all present and in range.
  final ({int year, int month, int day})? publicationDate;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// The search or map results a candidate is grounded on.
@immutable
final class GroundingMetadata {
  /// Creates grounding metadata. The package creates them; you need this only in tests.
  GroundingMetadata({
    this.searchEntryPointRenderedContent,
    List<GroundingChunk> groundingChunks = const <GroundingChunk>[],
    List<GroundingSupport> groundingSupports = const <GroundingSupport>[],
    List<String> webSearchQueries = const <String>[],
    this.googleMapsWidgetContextToken,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : groundingChunks = List<GroundingChunk>.unmodifiable(groundingChunks),
       groundingSupports = List<GroundingSupport>.unmodifiable(
         groundingSupports,
       ),
       webSearchQueries = List<String>.unmodifiable(webSearchQueries),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// The HTML of the Google Search suggestions to show (wire `searchEntryPoint.renderedContent`).
  final String? searchEntryPointRenderedContent;

  /// The results used.
  final List<GroundingChunk> groundingChunks;

  /// Which parts of the answer each result supports.
  final List<GroundingSupport> groundingSupports;

  /// The search queries the model made.
  final List<String> webSearchQueries;

  /// The token of the Google Maps widget to show.
  final String? googleMapsWidgetContextToken;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// One search or map result.
@immutable
final class GroundingChunk {
  /// Creates a grounding chunk. The package creates them; you need this only in tests.
  GroundingChunk({
    this.web,
    this.maps,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : raw = UnmodifiableMapView<String, Object?>(raw);

  /// A web result.
  final WebGroundingChunk? web;

  /// A map result.
  final MapsGroundingChunk? maps;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// A web search result.
@immutable
final class WebGroundingChunk {
  /// Creates a web result. The package creates them; you need this only in tests.
  const WebGroundingChunk({this.uri, this.title, this.domain});

  /// The URI of the page.
  final String? uri;

  /// The title of the page.
  final String? title;

  /// The domain of the page.
  final String? domain;
}

/// A Google Maps result.
@immutable
final class MapsGroundingChunk {
  /// Creates a map result. The package creates them; you need this only in tests.
  const MapsGroundingChunk({this.uri, this.title, this.text, this.placeId});

  /// The URI of the place.
  final String? uri;

  /// The name of the place.
  final String? title;

  /// A description of the place.
  final String? text;

  /// The Google Maps place id.
  final String? placeId;
}

/// Which part of an answer some results support.
@immutable
final class GroundingSupport {
  /// Creates a grounding support. The package creates them; you need this only in tests.
  GroundingSupport({
    this.segment,
    List<int> groundingChunkIndices = const <int>[],
    Map<String, Object?> raw = const <String, Object?>{},
  }) : groundingChunkIndices = List<int>.unmodifiable(groundingChunkIndices),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// The supported part of the answer.
  final GroundingSegment? segment;

  /// The positions in [GroundingMetadata.groundingChunks] of the supporting results.
  final List<int> groundingChunkIndices;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// A piece of a candidate's text. Absent numbers are 0 and absent text is empty.
@immutable
final class GroundingSegment {
  /// Creates a segment. The package creates them; you need this only in tests.
  const GroundingSegment({
    required this.partIndex,
    required this.startIndex,
    required this.endIndex,
    required this.text,
  });

  /// The position of the part in the candidate's content.
  final int partIndex;

  /// The start of the segment in the part's text.
  final int startIndex;

  /// The end of the segment in the part's text.
  final int endIndex;

  /// The text of the segment.
  final String text;
}

/// The URLs the URL context tool read.
@immutable
final class UrlContextMetadata {
  /// Creates URL context metadata. The package creates them; you need this only in tests.
  UrlContextMetadata({
    List<UrlMetadata> urlMetadata = const <UrlMetadata>[],
    Map<String, Object?> raw = const <String, Object?>{},
  }) : urlMetadata = List<UrlMetadata>.unmodifiable(urlMetadata),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// One entry per URL.
  final List<UrlMetadata> urlMetadata;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// One URL the URL context tool tried to read.
@immutable
final class UrlMetadata {
  /// Creates URL metadata. The package creates them; you need this only in tests.
  const UrlMetadata({this.retrievedUrl, this.urlRetrievalStatus});

  /// The URL.
  final String? retrievedUrl;

  /// Whether it could be read.
  final UrlRetrievalStatus? urlRetrievalStatus;
}

/// The token counts of a request and its answer.
@immutable
final class UsageMetadata {
  /// Creates usage metadata. The package creates them; you need this only in tests.
  UsageMetadata({
    this.promptTokenCount,
    this.candidatesTokenCount,
    this.totalTokenCount,
    this.thoughtsTokenCount,
    this.toolUsePromptTokenCount,
    this.cachedContentTokenCount,
    List<ModalityTokenCount> promptTokensDetails = const <ModalityTokenCount>[],
    List<ModalityTokenCount> candidatesTokensDetails =
        const <ModalityTokenCount>[],
    List<ModalityTokenCount> toolUsePromptTokensDetails =
        const <ModalityTokenCount>[],
    List<ModalityTokenCount> cacheTokensDetails = const <ModalityTokenCount>[],
    Map<String, Object?> raw = const <String, Object?>{},
  }) : promptTokensDetails = List<ModalityTokenCount>.unmodifiable(
         promptTokensDetails,
       ),
       candidatesTokensDetails = List<ModalityTokenCount>.unmodifiable(
         candidatesTokensDetails,
       ),
       toolUsePromptTokensDetails = List<ModalityTokenCount>.unmodifiable(
         toolUsePromptTokensDetails,
       ),
       cacheTokensDetails = List<ModalityTokenCount>.unmodifiable(
         cacheTokensDetails,
       ),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// The tokens of the prompt.
  final int? promptTokenCount;

  /// The tokens of all candidates.
  final int? candidatesTokenCount;

  /// The tokens of the request and the answer.
  final int? totalTokenCount;

  /// The tokens spent thinking.
  final int? thoughtsTokenCount;

  /// The tokens of tool results added to the prompt.
  final int? toolUsePromptTokenCount;

  /// The tokens of the prompt served from a cache.
  final int? cachedContentTokenCount;

  /// [promptTokenCount] per modality.
  final List<ModalityTokenCount> promptTokensDetails;

  /// [candidatesTokenCount] per modality.
  final List<ModalityTokenCount> candidatesTokensDetails;

  /// [toolUsePromptTokenCount] per modality.
  final List<ModalityTokenCount> toolUsePromptTokensDetails;

  /// [cachedContentTokenCount] per modality.
  final List<ModalityTokenCount> cacheTokensDetails;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

/// A token count for one modality. An absent count is 0.
@immutable
final class ModalityTokenCount {
  /// Creates a count. The package creates them; you need this only in tests.
  const ModalityTokenCount({required this.modality, required this.tokenCount});

  /// The modality.
  final Modality modality;

  /// The number of tokens.
  final int tokenCount;
}

/// The answer to a `countTokens` call.
@immutable
final class CountTokensResponse {
  /// Creates a response. The package creates them; you need this only in tests.
  CountTokensResponse({
    required this.totalTokens,
    List<ModalityTokenCount> promptTokensDetails = const <ModalityTokenCount>[],
    Map<String, Object?> raw = const <String, Object?>{},
  }) : promptTokensDetails = List<ModalityTokenCount>.unmodifiable(
         promptTokensDetails,
       ),
       raw = UnmodifiableMapView<String, Object?>(raw);

  /// Reads a response from its decoded JSON object. An absent `totalTokens` is 0.
  factory CountTokensResponse.fromJson(Map<String, Object?> json) =>
      CountTokensResponse(
        totalTokens: _int(json['totalTokens']) ?? 0,
        promptTokensDetails: _modalityCounts(json['promptTokensDetails']),
        raw: json,
      );

  /// The tokens of the request.
  final int totalTokens;

  /// [totalTokens] per modality.
  final List<ModalityTokenCount> promptTokensDetails;

  /// The decoded JSON object.
  final Map<String, Object?> raw;
}

abstract interface class _WireEnum {
  String? get _wire;
}

/// 2^31 - 1, the bound of every integer read from a response.
const int _maxInt32 = 2147483647;

T _fromWire<T extends _WireEnum>(List<T> values, Object? value, T unknown) {
  if (value is String) {
    for (final T member in values) {
      if (member._wire == value) {
        return member;
      }
    }
  }
  return unknown;
}

T? _fromWireOrNull<T extends _WireEnum>(
  List<T> values,
  Object? value,
  T unknown,
) => value is String ? _fromWire(values, value, unknown) : null;

HarmCategory _harmCategory(Object? value) {
  for (final HarmCategory category in HarmCategory.values) {
    if (category != HarmCategory.unknown && category.toJson() == value) {
      return category;
    }
  }
  return HarmCategory.unknown;
}

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<Object?> _list(Object? value) =>
    value is List<Object?> ? value : const <Object?>[];

String? _string(Object? value) => value is String ? value : null;

bool? _bool(Object? value) => value is bool ? value : null;

int? _int(Object? value) => parseBoundedInt(value, min: 0, max: _maxInt32);

double? _score(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

T? _decode<T>(Object? value, T Function(Map<String, Object?> json) decode) {
  final Map<String, Object?>? json = _map(value);
  return json == null ? null : decode(json);
}

List<T> _decodeAll<T>(
  Object? value,
  T Function(Map<String, Object?> json) decode,
) => <T>[
  for (final Object? item in _list(value))
    if (_map(item) case final Map<String, Object?> json) decode(json),
];

List<String> _strings(Object? value) => <String>[
  for (final Object? item in _list(value))
    if (item is String) item,
];

Candidate _candidate(Map<String, Object?> json, int position) {
  final Map<String, Object?>? content = _map(json['content']);
  return Candidate(
    index: _int(json['index']) ?? position,
    content: content == null
        ? const Content('model', <Part>[])
        : Content.fromJson(content),
    finishReason: _fromWireOrNull(
      FinishReason.values,
      json['finishReason'],
      FinishReason.unknown,
    ),
    finishMessage: _string(json['finishMessage']),
    safetyRatings: _decodeAll(json['safetyRatings'], _safetyRating),
    citationMetadata: _decode(json['citationMetadata'], _citationMetadata),
    groundingMetadata: _decode(json['groundingMetadata'], _groundingMetadata),
    urlContextMetadata: _decode(
      json['urlContextMetadata'],
      _urlContextMetadata,
    ),
    raw: json,
  );
}

PromptFeedback _promptFeedback(Map<String, Object?> json) => PromptFeedback(
  blockReason: _fromWireOrNull(
    BlockReason.values,
    json['blockReason'],
    BlockReason.unknown,
  ),
  blockReasonMessage: _string(json['blockReasonMessage']),
  safetyRatings: _decodeAll(json['safetyRatings'], _safetyRating),
  raw: json,
);

SafetyRating _safetyRating(Map<String, Object?> json) => SafetyRating(
  category: _harmCategory(json['category']),
  probability: _fromWireOrNull(
    HarmProbability.values,
    json['probability'],
    HarmProbability.unknown,
  ),
  severity: _fromWireOrNull(
    HarmSeverity.values,
    json['severity'],
    HarmSeverity.unknown,
  ),
  probabilityScore: _score(json['probabilityScore']),
  severityScore: _score(json['severityScore']),
  blocked: _bool(json['blocked']),
  raw: json,
);

CitationMetadata _citationMetadata(Map<String, Object?> json) =>
    CitationMetadata(
      citations: _decodeAll(json['citations'], _citation),
      raw: json,
    );

Citation _citation(Map<String, Object?> json) => Citation(
  startIndex: _int(json['startIndex']),
  endIndex: _int(json['endIndex']),
  uri: _string(json['uri']),
  license: _string(json['license']),
  title: _string(json['title']),
  publicationDate: _date(_map(json['publicationDate'])),
  raw: json,
);

({int year, int month, int day})? _date(Map<String, Object?>? json) {
  if (json == null) {
    return null;
  }
  final int? year = parseBoundedInt(json['year'], min: 1, max: 9999);
  final int? month = parseBoundedInt(json['month'], min: 1, max: 12);
  final int? day = parseBoundedInt(json['day'], min: 1, max: 31);
  if (year == null || month == null || day == null) {
    return null;
  }
  return (year: year, month: month, day: day);
}

GroundingMetadata _groundingMetadata(
  Map<String, Object?> json,
) => GroundingMetadata(
  searchEntryPointRenderedContent: _string(
    _map(json['searchEntryPoint'])?['renderedContent'],
  ),
  groundingChunks: _decodeAll(json['groundingChunks'], _groundingChunk),
  groundingSupports: _decodeAll(json['groundingSupports'], _groundingSupport),
  webSearchQueries: _strings(json['webSearchQueries']),
  googleMapsWidgetContextToken: _string(json['googleMapsWidgetContextToken']),
  raw: json,
);

GroundingChunk _groundingChunk(Map<String, Object?> json) => GroundingChunk(
  web: _decode(
    json['web'],
    (Map<String, Object?> web) => WebGroundingChunk(
      uri: _string(web['uri']),
      title: _string(web['title']),
      domain: _string(web['domain']),
    ),
  ),
  maps: _decode(
    json['maps'],
    (Map<String, Object?> maps) => MapsGroundingChunk(
      uri: _string(maps['uri']),
      title: _string(maps['title']),
      text: _string(maps['text']),
      placeId: _string(maps['placeId']),
    ),
  ),
  raw: json,
);

GroundingSupport _groundingSupport(Map<String, Object?> json) =>
    GroundingSupport(
      segment: _decode(
        json['segment'],
        (Map<String, Object?> segment) => GroundingSegment(
          partIndex: _int(segment['partIndex']) ?? 0,
          startIndex: _int(segment['startIndex']) ?? 0,
          endIndex: _int(segment['endIndex']) ?? 0,
          text: _string(segment['text']) ?? '',
        ),
      ),
      groundingChunkIndices: <int>[
        for (final Object? item in _list(json['groundingChunkIndices']))
          if (_int(item) case final int index) index,
      ],
      raw: json,
    );

UrlContextMetadata _urlContextMetadata(Map<String, Object?> json) =>
    UrlContextMetadata(
      urlMetadata: _decodeAll(
        json['urlMetadata'],
        (Map<String, Object?> url) => UrlMetadata(
          retrievedUrl: _string(url['retrievedUrl']),
          urlRetrievalStatus: _fromWireOrNull(
            UrlRetrievalStatus.values,
            url['urlRetrievalStatus'],
            UrlRetrievalStatus.unknown,
          ),
        ),
      ),
      raw: json,
    );

UsageMetadata _usageMetadata(Map<String, Object?> json) => UsageMetadata(
  promptTokenCount: _int(json['promptTokenCount']),
  candidatesTokenCount: _int(json['candidatesTokenCount']),
  totalTokenCount: _int(json['totalTokenCount']),
  thoughtsTokenCount: _int(json['thoughtsTokenCount']),
  toolUsePromptTokenCount: _int(json['toolUsePromptTokenCount']),
  cachedContentTokenCount: _int(json['cachedContentTokenCount']),
  promptTokensDetails: _modalityCounts(json['promptTokensDetails']),
  candidatesTokensDetails: _modalityCounts(json['candidatesTokensDetails']),
  toolUsePromptTokensDetails: _modalityCounts(
    json['toolUsePromptTokensDetails'],
  ),
  cacheTokensDetails: _modalityCounts(json['cacheTokensDetails']),
  raw: json,
);

List<ModalityTokenCount> _modalityCounts(Object? value) => _decodeAll(
  value,
  (Map<String, Object?> json) => ModalityTokenCount(
    modality:
        _fromWireOrNull(Modality.values, json['modality'], Modality.unknown) ??
        Modality.unspecified,
    tokenCount: _int(json['tokenCount']) ?? 0,
  ),
);
