import 'dart:collection';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/response.dart';

/// The candidate fields that take the last non-null value seen.
const List<String> _lastValueFields = <String>[
  'finishReason',
  'finishMessage',
  'safetyRatings',
  'citationMetadata',
  'groundingMetadata',
];

/// One response built from the chunks of a stream, in order. [chunks] must not be empty.
///
/// Works on the decoded JSON of each chunk ([GenerateContentResponse.raw], already mapped for the
/// backend) and decodes the result with the lenient rules of [GenerateContentResponse.fromJson]:
/// - candidates are grouped by `index` (absent counts as 0) and listed by index;
/// - per candidate, `finishReason`, `finishMessage`, `safetyRatings`, `citationMetadata` and
///   `groundingMetadata` take the last non-null value, and `urlContextMetadata` the first one with
///   a non-empty `urlMetadata` list;
/// - parts are concatenated in order; a text part with empty text and no `thoughtSignature` is
///   skipped, and adjacent text parts are not merged;
/// - the role is the first non-null one seen, else `model`;
/// - `promptFeedback` and `usageMetadata` are each the last non-null one.
///
/// The result's `raw` is the last chunk's top-level map with those three entries replaced, so the
/// unknown fields of earlier chunks are not kept.
GenerateContentResponse aggregateResponses(
  List<GenerateContentResponse> chunks,
) {
  assert(chunks.isNotEmpty, 'aggregateResponses needs at least one chunk');
  final SplayTreeMap<int, _CandidateAggregate> candidates =
      SplayTreeMap<int, _CandidateAggregate>();
  Object? promptFeedback;
  Object? usageMetadata;
  for (final GenerateContentResponse chunk in chunks) {
    final Map<String, Object?> raw = chunk.raw;
    final Object? list = raw['candidates'];
    if (list is List<Object?>) {
      for (final Object? candidate in list) {
        if (candidate is Map<String, Object?>) {
          final int index = _indexOf(candidate);
          candidates.putIfAbsent(index, _CandidateAggregate.new).add(candidate);
        }
      }
    }
    promptFeedback = raw['promptFeedback'] ?? promptFeedback;
    usageMetadata = raw['usageMetadata'] ?? usageMetadata;
  }
  final Map<String, Object?> result =
      <String, Object?>{
          ...chunks.last.raw,
          'candidates': <Object?>[
            for (final MapEntry<int, _CandidateAggregate> entry
                in candidates.entries)
              entry.value.toJson(entry.key),
          ],
        }
        ..remove('promptFeedback')
        ..remove('usageMetadata');
  if (promptFeedback != null) {
    result['promptFeedback'] = promptFeedback;
  }
  if (usageMetadata != null) {
    result['usageMetadata'] = usageMetadata;
  }
  return GenerateContentResponse.fromJson(result);
}

int _indexOf(Map<String, Object?> candidate) =>
    parseBoundedInt(candidate['index'], min: 0, max: 0x7fffffff) ?? 0;

/// The chunks of one candidate index, merged as they arrive.
final class _CandidateAggregate {
  Map<String, Object?> _latest = const <String, Object?>{};
  final Map<String, Object?> _fields = <String, Object?>{};
  Object? _urlContextMetadata;
  String? _role;
  final List<Object?> _parts = <Object?>[];

  void add(Map<String, Object?> candidate) {
    _latest = candidate;
    for (final String field in _lastValueFields) {
      final Object? value = candidate[field];
      if (value != null) {
        _fields[field] = value;
      }
    }
    _urlContextMetadata ??= _nonEmptyUrlContext(
      candidate['urlContextMetadata'],
    );
    final Object? content = candidate['content'];
    if (content is! Map<String, Object?>) {
      return;
    }
    final Object? role = content['role'];
    if (_role == null && role is String) {
      _role = role;
    }
    final Object? parts = content['parts'];
    if (parts is List<Object?>) {
      for (final Object? part in parts) {
        if (!_isEmptyTextPart(part)) {
          _parts.add(part);
        }
      }
    }
  }

  Map<String, Object?> toJson(int index) {
    final Map<String, Object?> json = <String, Object?>{
      ..._latest,
      'index': index,
      'content': <String, Object?>{'role': _role ?? 'model', 'parts': _parts},
    };
    for (final String field in _lastValueFields) {
      json.remove(field);
      final Object? value = _fields[field];
      if (value != null) {
        json[field] = value;
      }
    }
    json.remove('urlContextMetadata');
    final Object? urlContext = _urlContextMetadata;
    if (urlContext != null) {
      json['urlContextMetadata'] = urlContext;
    }
    return json;
  }

  static Object? _nonEmptyUrlContext(Object? value) {
    if (value is Map<String, Object?>) {
      final Object? list = value['urlMetadata'];
      if (list is List<Object?> && list.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static bool _isEmptyTextPart(Object? part) {
    if (part is! Map<String, Object?>) {
      return false;
    }
    return part['text'] == '' && part['thoughtSignature'] == null;
  }
}
