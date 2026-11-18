// Copyright 2017 Google LLC (the format of the JS SDK's IndexedDB cache: `indexeddb_schema.ts`,
// `indexeddb_sentinels.ts`, `indexeddb_schema_converter.ts` and `encoded_resource_path.ts` of firebase-js-sdk)
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

/// The schema of the official Firebase JS SDK's IndexedDB cache, version 18: the database name, the object stores,
/// their keys and indexes, the encoding of resource paths inside keys and the liveness rules of its clients. Shared by
/// the IndexedDB engine (`IndexedDbPersistence`) and the import of a JS SDK cache (`js_sdk_importer.dart`). Plain
/// Dart: the IndexedDB calls are in `web/`.
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// `SCHEMA_VERSION` of `indexeddb_schema.ts`: the only version the IndexedDB engine opens.
const int indexedDbSchemaVersion = 18;

/// `MAX_PRIMARY_ELIGIBLE_AGE_MS` of `indexeddb_persistence.ts`: the JS SDK's primary lease is valid for 5 s after its
/// last refresh (every 4 s, [indexedDbClientMetadataRefreshMs]).
const int indexedDbPrimaryLeaseMs = 5000;

/// `CLIENT_METADATA_REFRESH_INTERVAL_MS` of `indexeddb_persistence.ts`.
const int indexedDbClientMetadataRefreshMs = 4000;

/// `MAX_CLIENT_AGE_MS` of `indexeddb_persistence.ts`: the JS SDK counts a client as active while it refreshed its row in
/// `clientMetadata` less than 30 minutes ago (and it did not mark itself as closed in LocalStorage). A tab in the
/// background refreshes less often than every 4 s.
const int indexedDbMaxClientAgeMs = 30 * 60 * 1000;

/// `isWithinAge` of `indexeddb_persistence.ts`: whether [updateTimeMs] lies within the last [maxAgeMs] before [nowMs].
/// A time in the future is not within the age.
bool indexedDbIsWithinAge(Object? updateTimeMs, int maxAgeMs, int nowMs) =>
    updateTimeMs is num &&
    updateTimeMs >= nowMs - maxAgeMs &&
    updateTimeMs <= nowMs;

/// The prefix of the JS SDK's IndexedDB database name and of its LocalStorage keys (`indexedDbStoragePrefix`):
/// `firestore/<persistence key>/<project>[.<database>]/`. The persistence key is the app name, `[DEFAULT]` for the
/// default app.
String indexedDbStoragePrefix(String persistenceKey, DatabaseId databaseId) {
  final String database = databaseId.databaseId == DatabaseId.defaultDatabaseId
      ? databaseId.projectId
      : '${databaseId.projectId}.${databaseId.databaseId}';
  return 'firestore/$persistenceKey/$database/';
}

/// The name of the JS SDK's IndexedDB database (`persistenceKey + MAIN_DATABASE`).
String indexedDbDatabaseName(String persistenceKey, DatabaseId databaseId) =>
    '${indexedDbStoragePrefix(persistenceKey, databaseId)}main';

/// The LocalStorage key under which a JS client marks itself as closed (`zombiedClientLocalStorageKey`).
String indexedDbZombieKey(String storagePrefix, String clientId) =>
    'firestore_zombie_${storagePrefix}_$clientId';

/// The object stores of schema version 18 (`V18_STORES` of `indexeddb_sentinels.ts`), with their key paths and
/// indexes (`createOrUpgrade` of `indexeddb_schema_converter.ts`).
abstract final class DbStores {
  static const String owner = 'owner';
  static const String ownerKey = 'owner';

  static const String mutationQueues = 'mutationQueues';
  static const String mutationQueuesKeyPath = 'userId';

  static const String mutations = 'mutations';
  static const String mutationsKeyPath = 'batchId';
  static const String mutationsUserIndex = 'userMutationsIndex';
  static const List<String> mutationsUserIndexPath = <String>[
    'userId',
    'batchId',
  ];

  /// Out-of-line keys `[userId, encodedPath, batchId]`, values `{}`.
  static const String documentMutations = 'documentMutations';

  static const String remoteDocuments = 'remoteDocumentsV14';
  static const List<String> remoteDocumentsKeyPath = <String>[
    'prefixPath',
    'collectionGroup',
    'readTime',
    'documentId',
  ];
  static const String remoteDocumentsDocumentKeyIndex = 'documentKeyIndex';
  static const List<String> remoteDocumentsDocumentKeyIndexPath = <String>[
    'prefixPath',
    'collectionGroup',
    'documentId',
  ];
  static const String remoteDocumentsCollectionGroupIndex =
      'collectionGroupIndex';
  static const List<String> remoteDocumentsCollectionGroupIndexPath = <String>[
    'collectionGroup',
    'readTime',
    'prefixPath',
    'documentId',
  ];

  /// Out-of-line key [remoteDocumentGlobalKey], value `{byteSize}`.
  static const String remoteDocumentGlobal = 'remoteDocumentGlobal';
  static const String remoteDocumentGlobalKey = 'remoteDocumentGlobalKey';

  static const String targets = 'targets';
  static const String targetsKeyPath = 'targetId';
  static const String targetsQueryIndex = 'queryTargetsIndex';
  static const List<String> targetsQueryIndexPath = <String>[
    'canonicalId',
    'targetId',
  ];

  static const String targetDocuments = 'targetDocuments';
  static const List<String> targetDocumentsKeyPath = <String>[
    'targetId',
    'path',
  ];
  static const String targetDocumentsDocumentIndex = 'documentTargetsIndex';
  static const List<String> targetDocumentsDocumentIndexPath = <String>[
    'path',
    'targetId',
  ];

  /// Out-of-line key [targetGlobalKey].
  static const String targetGlobal = 'targetGlobal';
  static const String targetGlobalKey = 'targetGlobalKey';

  static const String collectionParents = 'collectionParents';
  static const List<String> collectionParentsKeyPath = <String>[
    'collectionId',
    'parent',
  ];

  static const String clientMetadata = 'clientMetadata';
  static const String clientMetadataKeyPath = 'clientId';

  static const String bundles = 'bundles';
  static const String bundlesKeyPath = 'bundleId';

  static const String namedQueries = 'namedQueries';
  static const String namedQueriesKeyPath = 'name';

  static const String documentOverlays = 'documentOverlays';
  static const List<String> documentOverlaysKeyPath = <String>[
    'userId',
    'collectionPath',
    'documentId',
  ];
  static const String documentOverlaysCollectionPathIndex =
      'collectionPathOverlayIndex';
  static const List<String> documentOverlaysCollectionPathIndexPath = <String>[
    'userId',
    'collectionPath',
    'largestBatchId',
  ];
  static const String documentOverlaysCollectionGroupIndex =
      'collectionGroupOverlayIndex';
  static const List<String> documentOverlaysCollectionGroupIndexPath = <String>[
    'userId',
    'collectionGroup',
    'largestBatchId',
  ];

  static const String indexConfiguration = 'indexConfiguration';
  static const String indexConfigurationKeyPath = 'indexId';
  static const String indexConfigurationCollectionGroupIndex =
      'collectionGroupIndex';
  static const String indexConfigurationCollectionGroupIndexPath =
      'collectionGroup';

  static const String indexState = 'indexState';
  static const List<String> indexStateKeyPath = <String>['indexId', 'uid'];
  static const String indexStateSequenceNumberIndex = 'sequenceNumberIndex';
  static const List<String> indexStateSequenceNumberIndexPath = <String>[
    'uid',
    'sequenceNumber',
  ];

  static const String indexEntries = 'indexEntries';
  static const List<String> indexEntriesKeyPath = <String>[
    'indexId',
    'uid',
    'arrayValue',
    'directionalValue',
    'orderedDocumentKey',
    'documentKey',
  ];
  static const String indexEntriesDocumentKeyIndex = 'documentKeyIndex';
  static const List<String> indexEntriesDocumentKeyIndexPath = <String>[
    'indexId',
    'uid',
    'orderedDocumentKey',
  ];

  static const String globals = 'globals';
  static const String globalsKeyPath = 'name';

  /// Every store of version 18, in the order of `V18_STORES`. Each transaction of the engine spans all of them (as the
  /// JS SDK's do).
  static const List<String> all = <String>[
    mutationQueues,
    mutations,
    documentMutations,
    remoteDocuments,
    targets,
    owner,
    targetGlobal,
    targetDocuments,
    clientMetadata,
    remoteDocumentGlobal,
    collectionParents,
    bundles,
    namedQueries,
    documentOverlays,
    indexConfiguration,
    indexState,
    indexEntries,
    globals,
  ];
}

const String _escapeChar = '\u0001';
const String _encodedSeparatorChar = '\u0001';
const String _encodedNul = '\u0010';
const String _encodedEscape = '\u0011';

/// `encodeResourcePath` of `encoded_resource_path.ts`: every segment followed by `\u0001\u0001`, with `\u0000` written
/// as `\u0001\u0010` and `\u0001` as `\u0001\u0011`. The empty path is `\u0001\u0001`. Strings encoded this way sort
/// as their paths do segment by segment, and a path sorts right before its descendants.
///
/// The SQLite cache uses another encoding (`EncodedPath`).
String encodeJsResourcePath(ResourcePath path) {
  final StringBuffer buffer = StringBuffer();
  for (final String segment in path.segments) {
    for (int i = 0; i < segment.length; i++) {
      final String c = segment[i];
      if (c == '\u0000') {
        buffer
          ..write(_escapeChar)
          ..write(_encodedNul);
      } else if (c == _escapeChar) {
        buffer
          ..write(_escapeChar)
          ..write(_encodedEscape);
      } else {
        buffer.write(c);
      }
    }
    buffer
      ..write(_escapeChar)
      ..write(_encodedSeparatorChar);
  }
  if (path.isEmpty) {
    buffer
      ..write(_escapeChar)
      ..write(_encodedSeparatorChar);
  }
  return buffer.toString();
}

/// `decodeResourcePath` of `encoded_resource_path.ts`, the inverse of [encodeJsResourcePath].
ResourcePath decodeJsResourcePath(String path) {
  final int length = path.length;
  hardAssert(length >= 2, 'Invalid encoded resource path: "$path"');
  if (length == 2) {
    hardAssert(
      path[0] == _escapeChar && path[1] == _encodedSeparatorChar,
      'Non-empty encoded resource path of length 2: "$path"',
    );
    return ResourcePath.empty;
  }
  final int lastReasonableEscapeIndex = length - 2;
  final List<String> segments = <String>[];
  final StringBuffer segment = StringBuffer();
  for (int start = 0; start < length;) {
    final int end = path.indexOf(_escapeChar, start);
    if (end < 0 || end > lastReasonableEscapeIndex) {
      throw FormatException('Invalid encoded resource path', path);
    }
    final String next = path[end + 1];
    if (next == _encodedSeparatorChar) {
      segment.write(path.substring(start, end));
      segments.add(segment.toString());
      segment.clear();
    } else if (next == _encodedNul) {
      segment
        ..write(path.substring(start, end))
        ..write('\u0000');
    } else if (next == _encodedEscape) {
      segment.write(path.substring(start, end + 1));
    } else {
      throw FormatException('Invalid encoded resource path', path);
    }
    start = end + 2;
  }
  return ResourcePath.fromSegments(segments);
}

/// `immediateSuccessor` of the JS SDK for strings: the smallest string after [value].
String immediateSuccessorOf(String value) => '$value\u0000';

/// The key of [key] in the `documentKeyIndex` of `remoteDocumentsV14`: `[prefixPath, collectionGroup, documentId]`.
List<Object?> dbRemoteDocumentKey(DocumentKey key) {
  final List<String> path = key.path.segments;
  return <Object?>[
    path.sublist(0, path.length - 2),
    path[path.length - 2],
    path[path.length - 1],
  ];
}

/// A `[seconds, nanoseconds]` read time, as in the keys of `remoteDocumentsV14` (`DbTimestampKey`).
List<Object?> dbTimestampKey(SnapshotVersion version) => <Object?>[
  version.timestamp.seconds,
  version.timestamp.nanoseconds,
];

/// The read time of a `[seconds, nanoseconds]` key.
SnapshotVersion fromDbTimestampKey(Object? key) {
  final List<Object?> pair = key! as List<Object?>;
  return SnapshotVersion(
    Timestamp((pair[0]! as num).toInt(), (pair[1]! as num).toInt()),
  );
}

/// A `{seconds, nanoseconds}` timestamp of the JS SDK's rows (`DbTimestamp`).
Map<String, Object?> toDbTimestamp(SnapshotVersion version) =>
    <String, Object?>{
      'seconds': version.timestamp.seconds,
      'nanoseconds': version.timestamp.nanoseconds,
    };

/// The version of a `{seconds, nanoseconds}` timestamp of the JS SDK's rows.
SnapshotVersion fromDbTimestamp(Object? value) {
  final Map<Object?, Object?> timestamp = value! as Map<Object?, Object?>;
  return SnapshotVersion(
    Timestamp(
      (timestamp['seconds']! as num).toInt(),
      (timestamp['nanoseconds']! as num).toInt(),
    ),
  );
}

/// `Number.MAX_SAFE_INTEGER`, the largest number in the keys the JS SDK builds for open-ended ranges.
const int jsMaxSafeInteger = 9007199254740991;
