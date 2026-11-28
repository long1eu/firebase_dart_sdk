import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/json_guard.dart';
import 'package:meta/meta.dart';

/// The largest stored record, in UTF-8 bytes; a larger one is treated as absent (5.10).
const int maxRecordBytes = 16 * 1024 * 1024;

/// The longest ETag kept, in UTF-8 bytes.
const int maxEtagBytes = 1024;

/// Receives a short description of a field that was dropped. It never holds a value.
typedef DropReporter = void Function(String field);

/// A stored template: the `fetched` and the `active` record of 5.10.
///
/// Metadata keeps only the fields of 3.4, each checked; [toString] prints `<redacted>`.
@immutable
final class TemplateRecord {
  /// Creates a record. The collections are copied into unmodifiable ones.
  TemplateRecord({
    required Map<String, String> entries,
    required this.fetchTime,
    this.etag,
    this.templateVersion,
    List<Map<String, Object?>> experimentDescriptions =
        const <Map<String, Object?>>[],
    List<Map<String, Object?>> rolloutMetadata = const <Map<String, Object?>>[],
    Map<String, Map<String, Object?>> personalizationMetadata =
        const <String, Map<String, Object?>>{},
  }) : entries = Map<String, String>.unmodifiable(entries),
       experimentDescriptions = List<Map<String, Object?>>.unmodifiable(
         experimentDescriptions,
       ),
       rolloutMetadata = List<Map<String, Object?>>.unmodifiable(
         rolloutMetadata,
       ),
       personalizationMetadata = Map<String, Map<String, Object?>>.unmodifiable(
         personalizationMetadata,
       );

  /// The parameter values.
  final Map<String, String> entries;

  /// The ETag of the response, when it was valid.
  final String? etag;

  /// The template version, when the server gave one.
  final int? templateVersion;

  /// The experiments of 3.4, each with checked fields.
  final List<Map<String, Object?>> experimentDescriptions;

  /// The rollouts of 3.4, each with checked fields.
  final List<Map<String, Object?>> rolloutMetadata;

  /// The personalization entries of 3.4, by parameter key.
  final Map<String, Map<String, Object?>> personalizationMetadata;

  /// When the response was received.
  final DateTime fetchTime;

  /// The JSON of the record, with `"v": 1`.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'entries': entries,
    'etag': ?etag,
    'templateVersion': ?templateVersion,
    'experimentDescriptions': experimentDescriptions,
    'rolloutMetadata': rolloutMetadata,
    'personalizationMetadata': personalizationMetadata,
    'fetchTime': fetchTime.millisecondsSinceEpoch,
  };

  /// The stored text of the record.
  String encode() => jsonEncode(toJson());

  /// Reads a stored record. Returns null for a missing, oversized, too deep, non-JSON, unknown-`v` or
  /// wrong-shape record; never throws. Wrong metadata items are dropped one by one and reported to
  /// [onDrop]. When [now] is given, a fetch time later than [now] becomes [now] (5.10).
  static TemplateRecord? tryParse(
    String? text, {
    DropReporter? onDrop,
    DateTime? now,
  }) {
    final Map<String, Object?>? json = decodeRecord(text);
    if (json == null) {
      return null;
    }
    final Map<String, String>? entries = asStringMap(json['entries']);
    final int? fetchMillis = parseBoundedInt(
      json['fetchTime'],
      min: -maxDateMillis,
      max: maxDateMillis,
    );
    if (entries == null || fetchMillis == null) {
      return null;
    }
    DateTime fetchTime = DateTime.fromMillisecondsSinceEpoch(
      fetchMillis,
      isUtc: true,
    );
    if (now != null && fetchTime.isAfter(now)) {
      fetchTime = now;
    }
    int? version;
    if (json.containsKey('templateVersion')) {
      version = parseBoundedInt(
        json['templateVersion'],
        min: 0,
        max: maxSafeInteger,
      );
      if (version == null) {
        return null;
      }
    }
    final Object? etag = json['etag'];
    return TemplateRecord(
      entries: entries,
      fetchTime: fetchTime,
      etag: etag is String ? validEtag(etag) : null,
      templateVersion: version,
      experimentDescriptions: readExperiments(
        json['experimentDescriptions'],
        onDrop,
      ),
      rolloutMetadata: readRollouts(json['rolloutMetadata'], onDrop),
      personalizationMetadata: readPersonalization(
        json['personalizationMetadata'],
        onDrop,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TemplateRecord &&
      const DeepCollectionEquality().equals(toJson(), other.toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());

  @override
  String toString() => 'TemplateRecord(<redacted>)';
}

/// Decodes a stored record: null when [text] is missing, over [maxRecordBytes], too deep, not JSON, not an
/// object, or its `v` is not 1. Never throws.
Map<String, Object?>? decodeRecord(String? text) {
  if (text == null ||
      utf8Length(text, stopAfter: maxRecordBytes) > maxRecordBytes) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = decodeGuardedText(text);
  } on FormatException {
    return null;
  }
  final Map<String, Object?>? json = asObject(decoded);
  if (json == null || json['v'] != 1) {
    return null;
  }
  return json;
}

/// The UTF-8 length of [text], counting no further than just past [stopAfter].
int utf8Length(String text, {required int stopAfter}) {
  if (text.length * 3 <= stopAfter) {
    return text.length;
  }
  int length = 0;
  for (final int rune in text.runes) {
    length += rune < 0x80
        ? 1
        : rune < 0x800
        ? 2
        : rune < 0x10000
        ? 3
        : 4;
    if (length > stopAfter) {
      return length;
    }
  }
  return length;
}

/// [etag] when it is printable ASCII (0x20-0x7e, so no C0 or C1 control characters and nothing a request
/// header refuses) and at most [maxEtagBytes] long, else null.
String? validEtag(String etag) {
  if (etag.isEmpty || etag.length > maxEtagBytes) {
    return null;
  }
  for (final int unit in etag.codeUnits) {
    if (unit < 0x20 || unit > 0x7e) {
      return null;
    }
  }
  return etag;
}

/// Reads `experimentDescriptions` (3.4). An item without string `experimentId` and `variantId`, or with
/// a known field of the wrong type, is dropped and reported; unknown fields are not kept.
List<Map<String, Object?>> readExperiments(
  Object? value,
  DropReporter? onDrop,
) {
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Map<String, Object?> item in _items(
    value,
    'experimentDescriptions',
    onDrop,
  )) {
    final Map<String, Object?>? experiment = _readExperiment(item);
    if (experiment == null) {
      onDrop?.call('experimentDescriptions item');
      continue;
    }
    result.add(experiment);
  }
  return result;
}

Map<String, Object?>? _readExperiment(Map<String, Object?> item) {
  final Object? id = item['experimentId'];
  final Object? variant = item['variantId'];
  if (id is! String || variant is! String) {
    return null;
  }
  if (!isOptionalString(item, 'experimentStartTime')) {
    return null;
  }
  final Map<String, Object?> result = <String, Object?>{
    'experimentId': id,
    'variantId': variant,
    'experimentStartTime': ?item['experimentStartTime'],
  };
  for (final String key in const <String>[
    'triggerTimeoutMillis',
    'timeToLiveMillis',
  ]) {
    if (!item.containsKey(key)) {
      continue;
    }
    final int? millis = parseBoundedInt(item[key], min: 0, max: maxSafeInteger);
    if (millis == null) {
      return null;
    }
    result[key] = '$millis';
  }
  if (item.containsKey('affectedParameterKeys')) {
    final List<String>? keys = asStringList(item['affectedParameterKeys']);
    if (keys == null) {
      return null;
    }
    result['affectedParameterKeys'] = keys;
  }
  return result;
}

/// Reads `rolloutMetadata` (3.4). An item without string `rolloutId` and `variantId`, or with
/// `affectedParameterKeys` that is not a list of strings, is dropped and reported.
List<Map<String, Object?>> readRollouts(Object? value, DropReporter? onDrop) {
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Map<String, Object?> item in _items(
    value,
    'rolloutMetadata',
    onDrop,
  )) {
    final Object? id = item['rolloutId'];
    final Object? variant = item['variantId'];
    final List<String>? keys = item.containsKey('affectedParameterKeys')
        ? asStringList(item['affectedParameterKeys'])
        : const <String>[];
    if (id is! String || variant is! String || keys == null) {
      onDrop?.call('rolloutMetadata item');
      continue;
    }
    result.add(<String, Object?>{
      'rolloutId': id,
      'variantId': variant,
      'affectedParameterKeys': keys,
    });
  }
  return result;
}

/// Reads `personalizationMetadata` (3.4): an object of parameter key to an object with optional string
/// `personalizationId`, `group`, `choiceId` and integer `armIndex`. A wrong entry is dropped and
/// reported.
Map<String, Map<String, Object?>> readPersonalization(
  Object? value,
  DropReporter? onDrop,
) {
  final Map<String, Map<String, Object?>> result =
      <String, Map<String, Object?>>{};
  if (value == null) {
    return result;
  }
  final Map<String, Object?>? object = asObject(value);
  if (object == null) {
    onDrop?.call('personalizationMetadata');
    return result;
  }
  for (final MapEntry<String, Object?> entry in object.entries) {
    final Map<String, Object?>? read = _readPersonalizationEntry(entry.value);
    if (read == null) {
      onDrop?.call('personalizationMetadata entry');
      continue;
    }
    result[entry.key] = read;
  }
  return result;
}

Map<String, Object?>? _readPersonalizationEntry(Object? value) {
  final Map<String, Object?>? item = asObject(value);
  if (item == null) {
    return null;
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final String key in const <String>[
    'personalizationId',
    'group',
    'choiceId',
  ]) {
    if (!isOptionalString(item, key)) {
      return null;
    }
    if (item.containsKey(key)) {
      result[key] = item[key];
    }
  }
  if (item.containsKey('armIndex')) {
    final int? arm = parseBoundedInt(
      item['armIndex'],
      min: 0,
      max: maxSafeInteger,
    );
    if (arm == null) {
      return null;
    }
    result['armIndex'] = arm;
  }
  return result;
}

Iterable<Map<String, Object?>> _items(
  Object? value,
  String field,
  DropReporter? onDrop,
) sync* {
  if (value == null) {
    return;
  }
  if (value is! List<Object?>) {
    onDrop?.call(field);
    return;
  }
  for (final Object? element in value) {
    final Map<String, Object?>? item = asObject(element);
    if (item == null) {
      onDrop?.call('$field item');
      continue;
    }
    yield item;
  }
}
