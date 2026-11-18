// The import of the official Firebase JS SDK's IndexedDB cache (see `importJsSdkCache`).
//
// Exactly-once protocol. The JS database and this cache can not share a transaction, so the import goes in steps,
// each of them atomic, and a record in this cache's globals store (`jsSdkCacheImport:<JS database name>`) says how far
// it got. The record holds `pending`, the JS batches that this cache imported but that may still be in the JS
// database (user id, JS batch id, local write time and number of writes of each), and `documentsImported`.
//
// 1. Read the record. If `pending` is not empty, a previous call stopped after step 4: remove those batches from the
//    JS database (step 5) and clear `pending` (step 6) first. A batch is removed only when its row still has the
//    recorded user, local write time and number of writes: the JS SDK never reuses a batch id in the same database,
//    and a database deleted and created again by a JS tab could, with other contents.
// 2. Check that no JS tab may use the database and that its schema is one this SDK reads.
// 3. Read the JS batches of every user and decode them; if documents are to be imported, import them in their own
//    transaction (they are a cache: importing them again does nothing, older versions never replace newer ones).
// 4. In one transaction of this cache: check that the queues of these users are empty, add the batches with new batch
//    ids, save their overlays, and write the record with `pending` = these batches. Either all of it commits or none.
// 5. In one IndexedDB transaction: remove these batches (and their `documentMutations` and `documentOverlays` rows)
//    from the JS database.
// 6. Write the record with `pending` empty.
//
// A crash before 4 commits leaves the JS database as it was and this cache without the batches: the next call imports
// them. A crash after 4 and before 6 leaves the batches in both: the next call removes them from the JS database in
// step 1 and does not import them again (they are gone from the JS database before step 3 reads it). The batches this
// cache sends in the meantime are not affected: the record names JS batches, not this cache's ones.
//
// The whole import runs as one operation on the queue of the client: no write of the app runs between its steps. The
// JS database is never deleted here (see `deleteJsSdkCache`).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/js_sdk_cache_import.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database_platform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:firebase_app_dart/internal.dart';

const String _tag = 'JsSdkCacheImport';

/// The newest schema version of the JS SDK's database that is read (`SCHEMA_VERSION` in `indexeddb_schema.ts`).
const int jsSdkNewestSchemaVersion = 18;

/// The oldest schema version that is read. Version 4 gave the `mutations` store its current key (an auto-incremented
/// `batchId`) and index; version 5 removed the acknowledged batches that older versions left in it. No later version
/// changed the store or the shape of its rows.
const int jsSdkOldestSchemaVersion = 5;

/// The oldest schema version whose cached documents are read: version 13 moved them to `remoteDocumentsV14`, with
/// their read time in the key.
const int jsSdkOldestSchemaVersionWithDocuments = 13;

/// `MAX_PRIMARY_ELIGIBLE_AGE_MS` of `indexeddb_persistence.ts`: the JS SDK's primary lease is valid for 5 s after its
/// last refresh (every 4 s, `CLIENT_METADATA_REFRESH_INTERVAL_MS`).
const int jsSdkPrimaryLeaseMs = 5000;

/// `MAX_CLIENT_AGE_MS` of `indexeddb_persistence.ts`: the JS SDK counts a client as active while it refreshed its row in
/// `clientMetadata` less than 30 minutes ago (and it did not mark itself as closed in LocalStorage). A tab in the
/// background refreshes less often than every 4 s.
const int jsSdkMaxClientAgeMs = 30 * 60 * 1000;

/// The bundle name under which the imported documents are kept in the cache (an umbrella target holds them, as the
/// documents of a bundle, so that they are not collected as garbage at once).
const String _documentsBundleName = 'js-sdk-cache-import';

/// The prefix of the JS SDK's IndexedDB database name and of its LocalStorage keys (`indexedDbStoragePrefix`).
String jsSdkStoragePrefix(String appName, DatabaseId databaseId) {
  final String database = databaseId.databaseId == DatabaseId.defaultDatabaseId
      ? databaseId.projectId
      : '${databaseId.projectId}.${databaseId.databaseId}';
  return 'firestore/$appName/$database/';
}

/// See `importJsSdkCache`.
Future<JsSdkCacheImportResult> runJsSdkCacheImport(
  FirebaseFirestore firestore, {
  required bool includeDocuments,
  required bool allowMemoryCache,
  String? jsAppName,
}) async {
  final _JsSdkCache cache = _JsSdkCache(firestore, jsAppName);
  if (!jsSdkDatabaseSupported) {
    return JsSdkCacheImportResult(
      status: JsSdkCacheImportStatus.notOnWeb,
      databaseName: cache.databaseName,
    );
  }
  final FirestoreClient client = firestore.client;
  return client.runExclusive(
    () => cache.import(
      client,
      includeDocuments: includeDocuments,
      allowMemoryCache: allowMemoryCache,
    ),
  );
}

/// See `deleteJsSdkCache`.
Future<bool> runJsSdkCacheDelete(
  FirebaseFirestore firestore, {
  required bool discardPendingWrites,
  String? jsAppName,
}) async {
  if (!jsSdkDatabaseSupported) {
    return false;
  }
  final _JsSdkCache cache = _JsSdkCache(firestore, jsAppName);
  final FirestoreClient client = firestore.client;
  return client.runExclusive(
    () => cache.delete(client, discardPendingWrites: discardPendingWrites),
  );
}

/// A JS batch that this cache imported (see the protocol above).
class _BatchRef {
  const _BatchRef(
    this.userId,
    this.batchId,
    this.localWriteTimeMs,
    this.writes,
  );

  factory _BatchRef.ofRow(Map<String, Object?> row) => _BatchRef(
    row['userId']! as String,
    (row['batchId']! as num).toInt(),
    (row['localWriteTimeMs']! as num).toInt(),
    (row['mutations']! as List<Object?>).length,
  );

  factory _BatchRef.fromJson(Map<String, Object?> json) => _BatchRef(
    json['u']! as String,
    (json['b']! as num).toInt(),
    (json['t']! as num).toInt(),
    (json['n']! as num).toInt(),
  );

  final String userId;
  final int batchId;
  final int localWriteTimeMs;
  final int writes;

  /// Whether [row] of the JS `mutations` store is this batch.
  bool matches(Map<String, Object?> row) {
    try {
      final _BatchRef other = _BatchRef.ofRow(row);
      return other.userId == userId &&
          other.batchId == batchId &&
          other.localWriteTimeMs == localWriteTimeMs &&
          other.writes == writes;
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'u': userId,
    'b': batchId,
    't': localWriteTimeMs,
    'n': writes,
  };
}

/// The record of the import in this cache's globals store (see the protocol above).
class _Record {
  const _Record({required this.documentsImported, required this.pending});

  factory _Record.decode(Uint8List? bytes) {
    if (bytes == null) {
      return const _Record(documentsImported: false, pending: <_BatchRef>[]);
    }
    final Map<String, Object?> json =
        (jsonDecode(utf8.decode(bytes)) as Map<Object?, Object?>).cast();
    return _Record(
      documentsImported: json['documentsImported'] == true,
      pending: <_BatchRef>[
        for (final Object? ref in json['pending']! as List<Object?>)
          _BatchRef.fromJson((ref! as Map<Object?, Object?>).cast()),
      ],
    );
  }

  final bool documentsImported;
  final List<_BatchRef> pending;

  _Record withPending(List<_BatchRef> pending) =>
      _Record(documentsImported: documentsImported, pending: pending);

  Uint8List encode() => utf8.encode(
    jsonEncode(<String, Object?>{
      'version': 1,
      'documentsImported': documentsImported,
      'pending': <Object?>[for (final _BatchRef ref in pending) ref.toJson()],
    }),
  );
}

class _JsSdkCache {
  _JsSdkCache(FirebaseFirestore firestore, String? jsAppName)
    : databaseId = firestore.modelDatabaseId,
      storagePrefix = jsSdkStoragePrefix(
        jsAppName ?? firestore.app.name,
        firestore.modelDatabaseId,
      );

  final DatabaseId databaseId;
  final String storagePrefix;

  String get databaseName => '${storagePrefix}main';

  String get _recordName => 'jsSdkCacheImport:$databaseName';

  JsSdkCacheImportException _refuse(
    JsSdkCacheImportRefusal reason,
    String message,
  ) {
    Log.w(_tag, message);
    return JsSdkCacheImportException(reason, message);
  }

  Future<_Record> _readRecord(Persistence persistence) {
    return persistence.runTransactionAndReturn<_Record>(
      'Read the record of the JS SDK cache import',
      () async =>
          _Record.decode(await persistence.globalsCache.getValue(_recordName)),
    );
  }

  Future<void> _writeRecord(Persistence persistence, _Record record) {
    return persistence.runTransaction(
      'Write the record of the JS SDK cache import',
      () => persistence.globalsCache.setValue(_recordName, record.encode()),
    );
  }

  /// Steps 5 and 6 of the protocol.
  Future<void> _finishRemoval(
    Persistence persistence,
    JsSdkDatabase db,
    _Record record,
  ) async {
    final Map<int, _BatchRef> byId = <int, _BatchRef>{
      for (final _BatchRef ref in record.pending) ref.batchId: ref,
    };
    final int removed = await db.removeMutationBatches(byId.keys, (
      Map<String, Object?> row,
    ) {
      final Object? batchId = row['batchId'];
      final _BatchRef? ref = batchId is num ? byId[batchId.toInt()] : null;
      return ref != null && ref.matches(row);
    });
    Log.d(
      _tag,
      'Removed $removed of ${byId.length} imported batches from $databaseName',
    );
    await _writeRecord(persistence, record.withPending(const <_BatchRef>[]));
  }

  void _checkSchemaVersion(int version) {
    if (version > jsSdkNewestSchemaVersion) {
      throw _refuse(
        JsSdkCacheImportRefusal.unsupportedSchemaVersion,
        'The JS SDK database $databaseName has schema version $version, written by a JS SDK newer than this SDK '
        'knows: versions $jsSdkOldestSchemaVersion to $jsSdkNewestSchemaVersion are read.',
      );
    }
    if (version < jsSdkOldestSchemaVersion) {
      throw _refuse(
        JsSdkCacheImportRefusal.unsupportedSchemaVersion,
        'The JS SDK database $databaseName has schema version $version (a JS SDK from before 2018): versions '
        '$jsSdkOldestSchemaVersion to $jsSdkNewestSchemaVersion are read. Opening the app once with a current JS SDK '
        'upgrades it.',
      );
    }
  }

  /// Throws when a JS tab may still use the database, by the JS SDK's own rules (`isWithinAge`, `isClientZombied` and
  /// `filterActiveClients` in `indexeddb_persistence.ts`).
  Future<void> _checkNoActiveClient(JsSdkDatabase db) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    // As the JS SDK: a time in the future is not within the age.
    bool isWithinAge(Object? updateTimeMs, int maxAgeMs) =>
        updateTimeMs is num &&
        updateTimeMs >= now - maxAgeMs &&
        updateTimeMs <= now;
    bool isZombied(Object? clientId) =>
        clientId is String && isJsSdkClientZombied(storagePrefix, clientId);

    if (db.hasStore('owner')) {
      for (final Map<String, Object?> owner in await db.readAll('owner')) {
        if (isWithinAge(owner['leaseTimestampMs'], jsSdkPrimaryLeaseMs) &&
            !isZombied(owner['ownerId'])) {
          throw _refuse(
            JsSdkCacheImportRefusal.jsClientActive,
            'A JS SDK tab holds the primary lease of $databaseName (refreshed '
            '${now - (owner['leaseTimestampMs']! as num)} ms ago): close the tabs that run the JS SDK and try again.',
          );
        }
      }
    }
    if (db.hasStore('clientMetadata')) {
      for (final Map<String, Object?> client in await db.readAll(
        'clientMetadata',
      )) {
        if (isWithinAge(client['updateTimeMs'], jsSdkMaxClientAgeMs) &&
            !isZombied(client['clientId'])) {
          final int age = now - (client['updateTimeMs']! as num).toInt();
          throw _refuse(
            JsSdkCacheImportRefusal.jsClientActive,
            'A JS SDK client of $databaseName refreshed its metadata ${age ~/ 1000} s ago and did not mark itself as '
            'closed: close the tabs that run the JS SDK and try again. A tab that ended without closing (a crash) '
            'counts as active for 30 minutes after its last refresh, as in the JS SDK '
            '(${(jsSdkMaxClientAgeMs - age) ~/ 1000} s left).',
          );
        }
      }
    }
  }

  /// The batch of a row of the JS `mutations` store (`fromDbMutationBatch` of `local_serializer.ts`).
  MutationBatch _decodeBatch(
    LocalSerializer serializer,
    Map<String, Object?> row,
  ) {
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
      ..localWriteTime = serializer.rpcSerializer.encodeTimestamp(
        Timestamp.fromMillisecondsSinceEpoch(
          (row['localWriteTimeMs']! as num).toInt(),
        ),
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
    return serializer.decodeMutationBatch(batch);
  }

  /// A `{seconds, nanoseconds}` timestamp of the JS SDK's rows (`DbTimestamp`).
  static SnapshotVersion _dbTimestamp(Object? value) {
    final Map<Object?, Object?> timestamp = value! as Map<Object?, Object?>;
    return SnapshotVersion(
      Timestamp(
        (timestamp['seconds']! as num).toInt(),
        (timestamp['nanoseconds']! as num).toInt(),
      ),
    );
  }

  /// The document of a row of the JS `remoteDocumentsV14` store (`fromDbRemoteDocument` of `local_serializer.ts`) and
  /// its read time.
  ({MaybeDocument document, SnapshotVersion readTime}) _decodeDocument(
    LocalSerializer serializer,
    Map<String, Object?> row,
  ) {
    final bool hasCommittedMutations = row['hasCommittedMutations'] == true;
    final MaybeDocument document;
    final Object? remote = row['document'];
    final Object? deleted = row['noDocument'];
    final Object? unknown = row['unknownDocument'];
    if (remote != null) {
      document = serializer.decodeMaybeDocument(
        proto.MaybeDocument()
          ..document = (proto.Document()
            ..mergeFromProto3Json(remote, ignoreUnknownFields: true))
          ..hasCommittedMutations = hasCommittedMutations,
      );
    } else if (deleted is Map) {
      document = NoDocument(
        DocumentKey.fromSegments((deleted['path']! as List<Object?>).cast()),
        _dbTimestamp(deleted['readTime']),
        hasCommittedMutations: hasCommittedMutations,
      );
    } else if (unknown is Map) {
      document = UnknownDocument(
        DocumentKey.fromSegments((unknown['path']! as List<Object?>).cast()),
        _dbTimestamp(unknown['version']),
      );
    } else {
      throw const FormatException('no document, noDocument or unknownDocument');
    }
    // The key's read time: [seconds, nanoseconds].
    final List<Object?> readTime = row['readTime']! as List<Object?>;
    return (
      document: document,
      readTime: SnapshotVersion(
        Timestamp((readTime[0]! as num).toInt(), (readTime[1]! as num).toInt()),
      ),
    );
  }

  static User _user(String userId) =>
      userId.isEmpty ? User.unauthenticated : User(userId);

  /// The steps of the protocol above.
  Future<JsSdkCacheImportResult> import(
    FirestoreClient client, {
    required bool includeDocuments,
    required bool allowMemoryCache,
  }) async {
    final Persistence persistence = client.persistence;
    final LocalStore localStore = client.localStore;
    final SyncEngine syncEngine = client.syncEngine;
    final LocalSerializer serializer = LocalSerializer(
      RemoteSerializer(databaseId),
    );

    // Step 1.
    _Record record = await _readRecord(persistence);
    final JsSdkDatabase? db = await openJsSdkDatabase(databaseName);
    if (db == null) {
      if (record.pending.isNotEmpty) {
        // The JS database was deleted: nothing is left to remove.
        await _writeRecord(
          persistence,
          record.withPending(const <_BatchRef>[]),
        );
      }
      return JsSdkCacheImportResult(
        status: JsSdkCacheImportStatus.noJsDatabase,
        databaseName: databaseName,
      );
    }
    try {
      // Step 2.
      _checkSchemaVersion(db.version);
      await _checkNoActiveClient(db);
      if (record.pending.isNotEmpty) {
        await _finishRemoval(persistence, db, record);
        record = record.withPending(const <_BatchRef>[]);
      }

      // Step 3.
      final List<String> skipped = <String>[
        'targets, resume tokens, index configuration, bundles and named queries: not imported, listeners read from '
            'the backend again',
      ];
      final Map<String, List<(Map<String, Object?>, MutationBatch)>> byUser =
          <String, List<(Map<String, Object?>, MutationBatch)>>{};
      for (final Map<String, Object?> row in await db.readAll('mutations')) {
        final MutationBatch batch;
        try {
          batch = _decodeBatch(serializer, row);
        } catch (e) {
          throw _refuse(
            JsSdkCacheImportRefusal.unreadableWrites,
            'The pending write batch ${row['batchId']} of user "${row['userId']}" in $databaseName can not be read '
            '($e): nothing was imported.',
          );
        }
        (byUser[row['userId']! as String] ??=
                <(Map<String, Object?>, MutationBatch)>[])
            .add((row, batch));
      }
      for (final List<(Map<String, Object?>, MutationBatch)> batches
          in byUser.values) {
        batches.sort(
          (
            (Map<String, Object?>, MutationBatch) a,
            (Map<String, Object?>, MutationBatch) b,
          ) => a.$2.batchId.compareTo(b.$2.batchId),
        );
      }
      // A memory cache loses the writes at the next reload, and the JS database no longer has them after step 5.
      if (byUser.isNotEmpty &&
          persistence is MemoryPersistence &&
          !allowMemoryCache) {
        final int count = byUser.values.fold<int>(
          0,
          (int n, List<(Map<String, Object?>, MutationBatch)> b) =>
              n + b.length,
        );
        throw _refuse(
          JsSdkCacheImportRefusal.memoryCache,
          '$databaseName has $count pending write batches and this cache is in memory: after the import they would '
          'be lost at the next reload of the page. Use a persistent cache, or pass allowMemoryCache: true. Nothing '
          'was imported.',
        );
      }
      // Checked again in step 4; checked here so that a refused import does not import the documents either.
      final User currentUser = syncEngine.currentUser;
      for (final String userId in byUser.keys) {
        final User user = _user(userId);
        final bool empty = await persistence.runTransactionAndReturn<bool>(
          'Check the mutation queue before the JS SDK cache import',
          () => persistence.getMutationQueue(user).isEmpty(),
        );
        if (!empty) {
          throw _pendingWritesInCache(<User>[user], currentUser);
        }
      }

      bool documentsImported = record.documentsImported;
      int documents = 0;
      if (!includeDocuments) {
        skipped.add('documents: not requested (includeDocuments is false)');
      } else if (record.documentsImported) {
        skipped.add('documents: imported by an earlier call (only once)');
      } else if (db.version < jsSdkOldestSchemaVersionWithDocuments ||
          !db.hasStore('remoteDocumentsV14')) {
        skipped.add(
          'documents: schema version ${db.version} keeps them in a store this SDK does not read (version '
          '$jsSdkOldestSchemaVersionWithDocuments and later are read)',
        );
      } else {
        ImmutableSortedMap<DocumentKey, MaybeDocument> docs =
            DocumentCollections.emptyMaybeDocumentMap();
        final Map<DocumentKey, SnapshotVersion> readTimes =
            <DocumentKey, SnapshotVersion>{};
        int unreadable = 0;
        int withoutVersion = 0;
        for (final Map<String, Object?> row in await db.readAll(
          'remoteDocumentsV14',
        )) {
          final ({MaybeDocument document, SnapshotVersion readTime}) decoded;
          try {
            decoded = _decodeDocument(serializer, row);
          } catch (e) {
            unreadable++;
            Log.d(_tag, 'Skipping an unreadable document of $databaseName: $e');
            continue;
          }
          final MaybeDocument document = decoded.document;
          if (document.version == SnapshotVersion.none) {
            withoutVersion++;
            continue;
          }
          final MaybeDocument? earlier = docs[document.key];
          if (earlier == null ||
              earlier.version.compareTo(document.version) < 0) {
            docs = docs.insert(document.key, document);
            readTimes[document.key] = decoded.readTime;
          }
        }
        if (unreadable > 0) {
          skipped.add('documents: $unreadable could not be read');
        }
        if (withoutVersion > 0) {
          skipped.add('documents: $withoutVersion without a version');
        }
        if (docs.isNotEmpty) {
          final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
              await localStore.applyBundledDocuments(
                docs,
                _documentsBundleName,
                readTimes: readTimes,
              );
          documents = changes.length;
          if (documents < docs.length) {
            skipped.add(
              'documents: ${docs.length - documents} held by this cache in the same or a newer version',
            );
          }
          await syncEngine.handleImportedChanges(changes, const <int>[]);
        }
        documentsImported = true;
      }

      // Step 4.
      final List<_BatchRef> refs = <_BatchRef>[
        for (final List<(Map<String, Object?>, MutationBatch)> batches
            in byUser.values)
          for (final (Map<String, Object?> row, MutationBatch _) in batches)
            _BatchRef.ofRow(row),
      ];
      final _Record imported = _Record(
        documentsImported: documentsImported,
        pending: refs,
      );
      if (refs.isNotEmpty || documentsImported != record.documentsImported) {
        final ImportedMutationBatches result = await localStore
            .importMutationBatches(
              <User, List<MutationBatch>>{
                for (final MapEntry<
                      String,
                      List<(Map<String, Object?>, MutationBatch)>
                    >
                    entry
                    in byUser.entries)
                  _user(entry.key): <MutationBatch>[
                    for (final (Map<String, Object?>, MutationBatch) e
                        in entry.value)
                      e.$2,
                  ],
              },
              currentUser,
              () => persistence.globalsCache.setValue(
                _recordName,
                imported.encode(),
              ),
            );
        if (result.nonEmptyQueues.isNotEmpty) {
          throw _pendingWritesInCache(result.nonEmptyQueues, currentUser);
        }
        await syncEngine.handleImportedChanges(
          result.currentUserChanges,
          result.currentUserBatchIds,
        );
      }

      // Steps 5 and 6. The writes are imported: a failure here is finished by the next call.
      if (refs.isNotEmpty) {
        try {
          await _finishRemoval(persistence, db, imported);
        } catch (e) {
          Log.w(
            _tag,
            'Removing the imported writes from $databaseName failed: $e',
          );
          skipped.add(
            'removal of the imported writes from the JS database: failed ($e), the next call finishes it',
          );
        }
      }

      final JsSdkCacheImportResult result = JsSdkCacheImportResult(
        status: refs.isEmpty && documents == 0
            ? JsSdkCacheImportStatus.nothingToImport
            : JsSdkCacheImportStatus.imported,
        databaseName: databaseName,
        users: byUser.length,
        batches: refs.length,
        documents: documents,
        skipped: List<String>.unmodifiable(skipped),
      );
      Log.d(_tag, '$result');
      return result;
    } finally {
      db.close();
    }
  }

  JsSdkCacheImportException _pendingWritesInCache(
    List<User> users,
    User currentUser,
  ) {
    final String names = users
        .map(
          (User user) => user.uid == null
              ? 'the signed-out user'
              : 'user "${user.uid}"${user == currentUser ? ' (signed in)' : ''}',
        )
        .join(', ');
    return _refuse(
      JsSdkCacheImportRefusal.pendingWritesInCache,
      'This cache already holds pending writes of $names, who also has pending writes in $databaseName: the JS '
      'writes are older and would be sent after them. Call importJsSdkCache before the first write. Nothing was '
      'imported.',
    );
  }

  /// See `deleteJsSdkCache`.
  Future<bool> delete(
    FirestoreClient client, {
    required bool discardPendingWrites,
  }) async {
    final Persistence persistence = client.persistence;
    final JsSdkDatabase? db = await openJsSdkDatabase(databaseName);
    if (db == null) {
      return false;
    }
    final _Record record;
    try {
      await _checkNoActiveClient(db);
      record = await _readRecord(persistence);
      if (!discardPendingWrites && db.hasStore('mutations')) {
        final int notImported = (await db.readAll('mutations'))
            .where(
              (Map<String, Object?> row) =>
                  !record.pending.any((_BatchRef ref) => ref.matches(row)),
            )
            .length;
        if (notImported > 0) {
          throw _refuse(
            JsSdkCacheImportRefusal.pendingWritesNotImported,
            '$databaseName holds $notImported pending write batches that were not imported: call importJsSdkCache '
            'first, or pass discardPendingWrites: true to lose them.',
          );
        }
      }
    } finally {
      db.close();
    }
    await deleteJsSdkDatabase(databaseName);
    if (record.pending.isNotEmpty) {
      await _writeRecord(persistence, record.withPending(const <_BatchRef>[]));
    }
    Log.d(_tag, 'Deleted $databaseName');
    return true;
  }
}
