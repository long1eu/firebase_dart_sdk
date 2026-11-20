// Copyright 2017 Google LLC (behaviour ported from `local_serializer.ts` of firebase-js-sdk)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/document.pb.dart'
    as v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as wkt;

/// Converts between the model of this SDK and the rows of the JS SDK's IndexedDB cache (`toDb...` and `fromDb...` of
/// `local_serializer.ts`).
///
/// Rows are JSON trees (maps, lists, strings, numbers, booleans and null): the web code turns them into the
/// structured-clone values IndexedDB stores and back. The protos inside them are proto3 JSON, as the JS SDK writes them
/// (`JsonProtoSerializer` with `useProto3Json`): int64 as strings, bytes and resume tokens as base64, timestamps inside
/// protos as RFC 3339 strings with nine fraction digits, document names fully qualified. The wrappers' own timestamps
/// are `{seconds, nanoseconds}` and the read time in a key is a `[seconds, nanoseconds]` pair (see
/// `indexeddb_schema.dart`).
///
/// The protos are built by [LocalSerializer] (the same protos the SQLite cache stores) and written with the proto3 JSON
/// of `package:protobuf`; only the timestamps are rewritten to nine fraction digits. The keys of an object can come out
/// in another order than the JS SDK's, which neither side looks at.
class IndexedDbSerializer {
  const IndexedDbSerializer(this.localSerializer);

  final LocalSerializer localSerializer;

  RemoteSerializer get _rpc => localSerializer.rpcSerializer;

  /// The proto3 JSON of [message] as the JS SDK's `JsonProtoSerializer` (`useProto3Json`) writes it.
  ///
  /// PORTING NOTE: `GeneratedMessage.toProto3Json()` alone is not faithful. It writes an empty `bytesValue` as `{}`
  /// (the value loses its type and can not be read back), the double -0.0 as `0`, and, compiled with dart2js, a
  /// timestamp rounded to milliseconds through `DateTime` (a time less than half a millisecond before a whole second
  /// comes out one second late, and the last second of year 9999 becomes year 10000, which can not be read back). The
  /// values and timestamps are written again here: timestamps as `toTimestamp` of the JS SDK (the whole seconds and
  /// nine digits of nanoseconds, no rounding), doubles as `toDouble` (`'-0'`, `'NaN'`, `'Infinity'`), bytes in base64.
  static Object? toProto3Json(GeneratedMessage message) {
    if (message is v1.Value) {
      return _encodeValue(message);
    }
    final Object? json = message.toProto3Json();
    _patch(message, json);
    return json;
  }

  /// Replaces the JSON of every timestamp and value below [message] in [json].
  static void _patch(GeneratedMessage message, Object? json) {
    if (json is! Map) {
      return;
    }
    for (final FieldInfo<dynamic> info in message.info_.fieldInfo.values) {
      final Object? field = message.getFieldOrNull(info.tagNumber);
      if (field == null) {
        continue;
      }
      final String key = info.name;
      if (!json.containsKey(key)) {
        continue;
      }
      if (field is wkt.Timestamp) {
        json[key] = _encodeTimestamp(field);
      } else if (field is v1.Value) {
        json[key] = _encodeValue(field);
      } else if (field is GeneratedMessage) {
        _patch(field, json[key]);
      } else if (field is Map) {
        final Object? encoded = json[key];
        if (encoded is Map) {
          field.forEach((Object? name, Object? element) {
            if (element is v1.Value) {
              encoded[name] = _encodeValue(element);
            } else if (element is GeneratedMessage) {
              _patch(element, encoded[name]);
            }
          });
        }
      } else if (field is List) {
        final Object? encoded = json[key];
        if (encoded is List && encoded.length == field.length) {
          for (int i = 0; i < field.length; i++) {
            final Object? element = field[i];
            if (element is v1.Value) {
              encoded[i] = _encodeValue(element);
            } else if (element is GeneratedMessage) {
              _patch(element, encoded[i]);
            }
          }
        }
      }
    }
  }

  /// `toDouble` of the JS SDK with proto3 JSON.
  static Object _encodeDouble(double value) {
    if (value.isNaN) {
      return 'NaN';
    } else if (value.isInfinite) {
      return value.isNegative ? '-Infinity' : 'Infinity';
    } else if (value == 0 && value.isNegative) {
      return '-0';
    }
    return value;
  }

  /// `toTimestamp` of the JS SDK: the whole seconds in ISO 8601 and nine digits of nanoseconds.
  static String _encodeTimestamp(wkt.Timestamp timestamp) =>
      _timestampString(timestamp.seconds.toInt(), timestamp.nanos);

  static Object? _encodeValue(v1.Value value) {
    // The oneof case, not hasXxx(): an empty bytes value 'has' no value.
    switch (value.whichValueType()) {
      case v1.Value_ValueType.timestampValue:
        return <String, Object?>{
          'timestampValue': _encodeTimestamp(value.timestampValue),
        };
      case v1.Value_ValueType.doubleValue:
        return <String, Object?>{
          'doubleValue': _encodeDouble(value.doubleValue),
        };
      case v1.Value_ValueType.bytesValue:
        return <String, Object?>{'bytesValue': base64.encode(value.bytesValue)};
      case v1.Value_ValueType.geoPointValue:
        return <String, Object?>{
          'geoPointValue': <String, Object?>{
            'latitude': _encodeDouble(value.geoPointValue.latitude),
            'longitude': _encodeDouble(value.geoPointValue.longitude),
          },
        };
      case v1.Value_ValueType.arrayValue:
        return <String, Object?>{
          'arrayValue': <String, Object?>{
            'values': <Object?>[
              for (final v1.Value element in value.arrayValue.values)
                _encodeValue(element),
            ],
          },
        };
      case v1.Value_ValueType.mapValue:
        return <String, Object?>{
          'mapValue': <String, Object?>{
            'fields': <String, Object?>{
              for (final MapEntry<String, v1.Value> field
                  in value.mapValue.fields.entries)
                field.key: _encodeValue(field.value),
            },
          },
        };
      // ignore: no_default_cases
      default:
        final Object? json = value.toProto3Json();
        _patch(value, json);
        return json;
    }
  }

  /// The fields that hold a `google.protobuf.Timestamp` in the protos the cache stores (`Document`, `Value`,
  /// `Precondition`). Inside `Document.fields` and `MapValue.fields` the values are objects, never strings, so a
  /// field of the user's data with one of these names is not touched.
  static const Set<String> _timestampFields = <String>{
    'createTime',
    'updateTime',
    'timestampValue',
  };

  static final RegExp _rfc3339 = RegExp(
    r'^(.*T\d\d:\d\d:\d\d)(?:\.(\d{1,9}))?Z$',
  );

  /// [json] (proto3 JSON the JS SDK wrote) in the strict form `package:protobuf` reads.
  ///
  /// The JS SDK's readers accept more than proto3 JSON (`normalizeTimestamp`, `normalizeByteString`,
  /// `normalizeNumber` of `normalize.ts`), and its rows hold such values: the local write time of a pending server
  /// timestamp is `{timestampValue: {seconds, nanos}}` (`server_timestamps.ts`), bytes may be a `Uint8Array` (a map of
  /// indexes once it went through `JSON.stringify`), numbers may be strings or numbers, and a document cached from the
  /// backend writes a null as `nullValue: null` (which proto3 JSON readers take for an unset field). This rewrites them
  /// to `NULL_VALUE`, RFC 3339 strings, base64 and the proto3 JSON number forms. As in [toProto3Json], a field is only rewritten when its
  /// value has the shape of such a value: inside `fields` the values are always objects of the `Value` message.
  static Object? fromJsProto3Json(Object? json) {
    if (json is Map) {
      final Map<String, Object?> result = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in json.entries) {
        final String key = entry.key! as String;
        result[key] = _fromJsField(key, entry.value);
      }
      return result;
    } else if (json is List) {
      return <Object?>[for (final Object? item in json) fromJsProto3Json(item)];
    }
    return json;
  }

  static Object? _fromJsField(String key, Object? value) {
    if (key == 'nullValue' && value == null) {
      // The backend's JSON (and so a document the JS SDK cached from a listen) writes a null as `nullValue: null`,
      // which proto3 JSON readers take for an unset field.
      return 'NULL_VALUE';
    } else if (_timestampFields.contains(key) || key == 'readTime') {
      if (value is Map &&
          (value.containsKey('seconds') || value.containsKey('nanos'))) {
        return _timestampString(
          value['seconds'],
          value['nanos'] ?? value['nanoseconds'],
        );
      }
      if (value is String) {
        return _nineDigits(value);
      }
    } else if (key == 'bytesValue' && value is Map) {
      final List<int>? bytes = _indexedBytes(value);
      if (bytes != null) {
        return base64.encode(bytes);
      }
    } else if (key == 'integerValue' && value is num) {
      return value.toInt().toString();
    } else if ((key == 'doubleValue' ||
            key == 'latitude' ||
            key == 'longitude') &&
        value is String) {
      // A double, also for "-0" (a JS -0 stays -0: `num.tryParse` would give the integer 0) and "NaN"/"Infinity".
      return double.tryParse(value) ?? value;
    }
    return fromJsProto3Json(value);
  }

  /// The bytes of a `Uint8Array` after `JSON.stringify` (`{"0": 1, "1": 2}`), or null for another map.
  static List<int>? _indexedBytes(Map<Object?, Object?> value) {
    final List<int> bytes = List<int>.filled(value.length, 0);
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final int? index = int.tryParse('${entry.key}');
      final Object? byte = entry.value;
      if (index == null || index < 0 || index >= bytes.length || byte is! num) {
        return null;
      }
      bytes[index] = byte.toInt();
    }
    return bytes;
  }

  /// `toTimestamp` of the JS SDK for [seconds] and [nanos], each a number or a numeric string.
  static String _timestampString(Object? seconds, Object? nanos) {
    int number(Object? value) => value is num
        ? value.toInt()
        : (value is String ? int.tryParse(value) ?? 0 : 0);
    final String date = DateTime.fromMillisecondsSinceEpoch(
      number(seconds) * 1000,
      isUtc: true,
    ).toIso8601String();
    final String fraction = '${number(nanos)}'.padLeft(9, '0');
    return '${date.substring(0, date.indexOf('.'))}.${fraction}Z';
  }

  static String _nineDigits(String timestamp) {
    final RegExpMatch? match = _rfc3339.firstMatch(timestamp);
    if (match == null) {
      return timestamp;
    }
    final String fraction = (match.group(2) ?? '').padRight(9, '0');
    return '${match.group(1)}.${fraction}Z';
  }

  // Remote documents

  /// The row of `remoteDocumentsV14` for [document] read at [readTime] (`toDbRemoteDocument`).
  Map<String, Object?> toDbRemoteDocument(
    MaybeDocument document,
    SnapshotVersion readTime,
  ) {
    final DocumentKey key = document.key;
    final List<String> path = key.path.segments;
    final proto.MaybeDocument encoded = localSerializer.encodeMaybeDocument(
      document,
    );
    final Map<String, Object?> row = <String, Object?>{
      'prefixPath': path.sublist(0, path.length - 2),
      'collectionGroup': path[path.length - 2],
      'documentId': path[path.length - 1],
      'readTime': dbTimestampKey(readTime),
      'hasCommittedMutations': encoded.hasCommittedMutations,
    };
    if (document is Document) {
      final Map<String, Object?> json =
          (toProto3Json(encoded.document)! as Map<Object?, Object?>).cast();
      // The JS SDK always writes the create time, the zero time when it is not known (`toDocument`).
      json['createTime'] ??= '1970-01-01T00:00:00.000000000Z';
      row['document'] = json;
    } else if (document is NoDocument) {
      row['noDocument'] = <String, Object?>{
        'path': path,
        'readTime': toDbTimestamp(document.version),
      };
    } else if (document is UnknownDocument) {
      row['unknownDocument'] = <String, Object?>{
        'path': path,
        'version': toDbTimestamp(document.version),
      };
    } else {
      throw fail('Unknown document type ${document.runtimeType}');
    }
    return row;
  }

  /// The document of a row of `remoteDocumentsV14` and its read time (`fromDbRemoteDocument`).
  ReadDocument fromDbRemoteDocument(Map<String, Object?> row) {
    final bool hasCommittedMutations = row['hasCommittedMutations'] == true;
    final MaybeDocument document;
    final Object? remote = row['document'];
    final Object? deleted = row['noDocument'];
    final Object? unknown = row['unknownDocument'];
    if (remote != null) {
      document = localSerializer.decodeMaybeDocument(
        proto.MaybeDocument()
          ..document = (proto.Document()
            ..mergeFromProto3Json(
              fromJsProto3Json(remote),
              ignoreUnknownFields: true,
            ))
          ..hasCommittedMutations = hasCommittedMutations,
      );
    } else if (deleted is Map) {
      document = NoDocument(
        DocumentKey.fromSegments((deleted['path']! as List<Object?>).cast()),
        fromDbTimestamp(deleted['readTime']),
        hasCommittedMutations: hasCommittedMutations,
      );
    } else if (unknown is Map) {
      document = UnknownDocument(
        DocumentKey.fromSegments((unknown['path']! as List<Object?>).cast()),
        fromDbTimestamp(unknown['version']),
      );
    } else {
      throw const FormatException('no document, noDocument or unknownDocument');
    }
    return (document: document, readTime: fromDbTimestampKey(row['readTime']));
  }

  /// Whether [document], read from a row, is the "sentinel removal" the JS SDK writes to track removals (a deleted
  /// document of version zero, `maybeDecodeDocument`): it stands for no document.
  static bool isSentinelRemoval(MaybeDocument document) =>
      document is NoDocument && document.version == SnapshotVersion.none;

  // Mutation batches

  /// The row of `mutations` for [batch] of the user [userId] (`toDbMutationBatch`).
  Map<String, Object?> toDbMutationBatch(String userId, MutationBatch batch) {
    final Timestamp time = batch.localWriteTime;
    final int wholeMillis = time.seconds * 1000 + time.nanoseconds ~/ 1000000;
    final int nanosLeft = time.nanoseconds % 1000000;
    return <String, Object?>{
      'userId': userId,
      'batchId': batch.batchId,
      // `Timestamp.toMillis()`: fractional when the time has sub-millisecond precision.
      'localWriteTimeMs': nanosLeft == 0
          ? wholeMillis
          : wholeMillis + nanosLeft / 1000000,
      'baseMutations': <Object?>[
        for (final Mutation mutation in batch.baseMutations)
          toProto3Json(_rpc.encodeMutation(mutation)),
      ],
      'mutations': <Object?>[
        for (final Mutation mutation in batch.mutations)
          toProto3Json(_rpc.encodeMutation(mutation)),
      ],
    };
  }

  /// The batch of a row of `mutations` (`fromDbMutationBatch`).
  MutationBatch fromDbMutationBatch(Map<String, Object?> row) {
    final List<Object?> writes = row['mutations']! as List<Object?>;
    // Old JS SDKs stored a transform as a separate write after its set or patch: squash it into that write.
    final List<Object?> squashed = <Object?>[];
    for (int i = 0; i < writes.length; i++) {
      final Map<String, Object?> write = Map<String, Object?>.of(
        (writes[i]! as Map<Object?, Object?>).cast(),
      );
      final Object? next = i + 1 < writes.length ? writes[i + 1] : null;
      if (next is Map && next['transform'] is Map) {
        write['updateTransforms'] =
            (next['transform'] as Map<Object?, Object?>)['fieldTransforms'];
        i++;
      }
      squashed.add(write);
    }
    final proto.WriteBatch batch = proto.WriteBatch()
      ..batchId = (row['batchId']! as num).toInt()
      ..localWriteTime = _rpc.encodeTimestamp(
        _timestampFromMillis(row['localWriteTimeMs']! as num),
      );
    for (final Object? write
        in (row['baseMutations'] as List<Object?>?) ?? const <Object?>[]) {
      batch.baseWrites.add(
        proto.Write()..mergeFromProto3Json(
          fromJsProto3Json(write),
          ignoreUnknownFields: false,
        ),
      );
    }
    for (final Object? write in squashed) {
      batch.writes.add(
        proto.Write()..mergeFromProto3Json(
          fromJsProto3Json(write),
          ignoreUnknownFields: false,
        ),
      );
    }
    return localSerializer.decodeMutationBatch(batch);
  }

  static Timestamp _timestampFromMillis(num millis) {
    if (millis is int) {
      return Timestamp.fromMillisecondsSinceEpoch(millis);
    }
    final int seconds = (millis / 1000).floor();
    final int nanoseconds = ((millis - seconds * 1000) * 1000000).round();
    return nanoseconds >= 1000000000
        ? Timestamp(seconds + 1, nanoseconds - 1000000000)
        : Timestamp(seconds, nanoseconds);
  }

  // Targets

  /// The row of `targets` for [queryData] (`toDbTarget`).
  Map<String, Object?> toDbTarget(QueryData queryData) {
    hardAssertLazy(
      queryData.purpose == QueryPurpose.listen,
      () =>
          'Only queries with purpose ${QueryPurpose.listen} may be stored, got ${queryData.purpose}',
    );
    final Target target = queryData.target;
    return <String, Object?>{
      'targetId': queryData.targetId,
      'canonicalId': target.canonicalId,
      'readTime': toDbTimestamp(queryData.snapshotVersion),
      'resumeToken': base64.encode(queryData.resumeToken),
      'lastListenSequenceNumber': queryData.sequenceNumber,
      'lastLimboFreeSnapshotVersion': toDbTimestamp(
        queryData.lastLimboFreeSnapshotVersion,
      ),
      'query': target.isDocumentQuery
          ? toProto3Json(_rpc.encodeDocumentsTarget(target))
          : toProto3Json(_rpc.encodeQueryTarget(target)),
    };
  }

  /// The target of a row of `targets` (`fromDbTarget`). Throws a [FormatException] for a target this SDK can not read
  /// (a pipeline target of the JS SDK).
  QueryData fromDbTarget(Map<String, Object?> row) {
    final Map<Object?, Object?> query = row['query']! as Map<Object?, Object?>;
    final Target target;
    if (query['structuredPipeline'] != null) {
      throw const FormatException('a pipeline target');
    } else if (query['documents'] != null) {
      target = _rpc.decodeDocumentsTarget(
        proto.Target_DocumentsTarget()..mergeFromProto3Json(
          fromJsProto3Json(query),
          ignoreUnknownFields: true,
        ),
      );
    } else {
      target = _rpc.decodeQueryTarget(
        proto.Target_QueryTarget()..mergeFromProto3Json(
          fromJsProto3Json(query),
          ignoreUnknownFields: true,
        ),
      );
    }
    final Object? limboFree = row['lastLimboFreeSnapshotVersion'];
    final Object? resumeToken = row['resumeToken'];
    return QueryData(
      target,
      (row['targetId']! as num).toInt(),
      (row['lastListenSequenceNumber']! as num).toInt(),
      QueryPurpose.listen,
      fromDbTimestamp(row['readTime']),
      resumeToken is String && resumeToken.isNotEmpty
          ? base64.decode(resumeToken)
          : Uint8List(0),
      null,
      limboFree == null ? SnapshotVersion.none : fromDbTimestamp(limboFree),
    );
  }

  // Bundles

  /// The row of `bundles` for [metadata] (`toDbBundle`).
  ///
  /// NOT IN THE OFFICIAL SDKS: `totalDocuments` and `totalBytes` are kept too (the JS SDK's row has no such fields and
  /// ignores them; a row the JS SDK wrote reads them as 0).
  Map<String, Object?> toDbBundle(BundleMetadata metadata) => <String, Object?>{
    'bundleId': metadata.bundleId,
    'createTime': toDbTimestamp(metadata.createTime),
    'version': metadata.schemaVersion,
    'totalDocuments': metadata.totalDocuments,
    'totalBytes': metadata.totalBytes,
  };

  /// The metadata of a row of `bundles` (`fromDbBundle`).
  BundleMetadata fromDbBundle(Map<String, Object?> row) => BundleMetadata(
    row['bundleId']! as String,
    (row['version'] as num?)?.toInt() ?? 0,
    fromDbTimestamp(row['createTime']),
    (row['totalDocuments'] as num?)?.toInt() ?? 0,
    (row['totalBytes'] as num?)?.toInt() ?? 0,
  );

  /// The row of `namedQueries` for [query] (`toDbNamedQuery`): the bundled query as the proto3 JSON of a
  /// `BundledQuery`, as the JS SDK keeps it from the bundle.
  Map<String, Object?> toDbNamedQuery(NamedQuery query) => <String, Object?>{
    'name': query.name,
    'readTime': toDbTimestamp(query.readTime),
    'bundledQuery': toProto3Json(
      localSerializer.encodeBundledQuery(query.bundledQuery),
    ),
  };

  /// The named query of a row of `namedQueries` (`fromDbNamedQuery`). The JS SDK stores the bundled query as the
  /// bundle file had it, which may write an `Int32Value` limit as `{value: n}` (its reader accepts both).
  NamedQuery fromDbNamedQuery(Map<String, Object?> row) {
    // A new map of the JSON tree: [fromJsProto3Json] copies every map.
    final Map<String, Object?> json =
        fromJsProto3Json(row['bundledQuery'])! as Map<String, Object?>;
    final Object? structuredQuery = json['structuredQuery'];
    if (structuredQuery is Map) {
      final Map<String, Object?> query =
          structuredQuery as Map<String, Object?>;
      final Object? limit = query['limit'];
      if (limit is Map && limit.containsKey('value')) {
        query['limit'] = limit['value'];
      }
      json['structuredQuery'] = query;
    }
    return NamedQuery(
      row['name']! as String,
      localSerializer.decodeBundledQuery(
        proto.BundledQuery()
          ..mergeFromProto3Json(json, ignoreUnknownFields: true),
      ),
      fromDbTimestamp(row['readTime']),
    );
  }

  // Overlays

  /// The row of `documentOverlays` for [overlay] of the user [userId] (`toDbDocumentOverlay`).
  Map<String, Object?> toDbDocumentOverlay(String userId, Overlay overlay) {
    final DocumentKey key = overlay.key;
    return <String, Object?>{
      'userId': userId,
      'collectionPath': encodeJsResourcePath(key.path.popLast()),
      'documentId': key.path.getLastSegment(),
      'collectionGroup': key.collectionGroup,
      'largestBatchId': overlay.largestBatchId,
      'overlayMutation': toProto3Json(
        localSerializer.encodeOverlayMutation(overlay.mutation),
      ),
    };
  }

  /// The overlay of a row of `documentOverlays` (`fromDbDocumentOverlay`).
  Overlay fromDbDocumentOverlay(Map<String, Object?> row) {
    return Overlay(
      (row['largestBatchId']! as num).toInt(),
      localSerializer.decodeOverlayMutation(
        proto.Write()..mergeFromProto3Json(
          fromJsProto3Json(row['overlayMutation']),
          ignoreUnknownFields: false,
        ),
      ),
    );
  }
}
