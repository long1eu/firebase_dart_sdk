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
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:protobuf/protobuf.dart';

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

  /// The proto3 JSON of [message], with every timestamp written with nine fraction digits as `toTimestamp` of the JS
  /// SDK does.
  static Object? toProto3Json(GeneratedMessage message) =>
      _normalizeTimestamps(message.toProto3Json());

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

  static Object? _normalizeTimestamps(Object? node) {
    if (node is Map) {
      final Map<String, Object?> result = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in node.entries) {
        final String key = entry.key! as String;
        final Object? value = entry.value;
        if (value is String && _timestampFields.contains(key)) {
          result[key] = _nineDigits(value);
        } else {
          result[key] = _normalizeTimestamps(value);
        }
      }
      return result;
    } else if (node is List) {
      return <Object?>[
        for (final Object? item in node) _normalizeTimestamps(item),
      ];
    }
    return node;
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
            ..mergeFromProto3Json(remote, ignoreUnknownFields: true))
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
        proto.Write()..mergeFromProto3Json(write, ignoreUnknownFields: false),
      );
    }
    for (final Object? write in squashed) {
      batch.writes.add(
        proto.Write()..mergeFromProto3Json(write, ignoreUnknownFields: false),
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
        proto.Target_DocumentsTarget()
          ..mergeFromProto3Json(query, ignoreUnknownFields: true),
      );
    } else {
      target = _rpc.decodeQueryTarget(
        proto.Target_QueryTarget()
          ..mergeFromProto3Json(query, ignoreUnknownFields: true),
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
          row['overlayMutation'],
          ignoreUnknownFields: false,
        ),
      ),
    );
  }
}
