// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';

/// Represents cached documents received from the remote backend.
///
/// The cache is keyed by [DocumentKey] and entries in the cache are
/// [MaybeDocument] instances, meaning we can cache both [Document] instances
/// (an actual document with data) as well as [NoDocument] instances (indicating
/// that the document is known to not exist).
/// A cached document together with the time at which it was read.
///
/// PORTING NOTE: upstream keeps the read time on the document itself (`MutableDocument.getReadTime`). The documents of
/// the port have no read time, so the scans that are ordered by read time return it next to the document.
typedef ReadDocument = ({MaybeDocument document, SnapshotVersion readTime});

abstract class RemoteDocumentCache {
  static const String statsTag = 'remote_documents';

  /// Sets the index manager of the current user. It is used to keep the collection parent index up to date and to
  /// drop the field index entries of the documents that are removed from the cache. Until it is set, the shared
  /// `Persistence.indexManager` maintains the collection parent index and field index entries are left alone.
  set indexManager(IndexManager indexManager);

  /// Adds or replaces an entry in the cache.
  ///
  /// The cache key is extracted from [MaybeDocument.key]. If there is already a
  /// cache entry for the key, it will be replaced.
  ///
  /// [readTime] is the time at which the document was read or committed. It must not be [SnapshotVersion.none]:
  /// index-free queries rely on every cache write after a target's last limbo free snapshot version carrying a read
  /// time.
  Future<void> add(MaybeDocument maybeDocument, SnapshotVersion readTime);

  /// Removes the cached entry for the given key (no-op if no entry exists).
  Future<void> remove(DocumentKey documentKey);

  /// Removes the cached entries for the given keys (keys without an entry are ignored).
  Future<void> removeAll(Iterable<DocumentKey> documentKeys);

  /// Looks up an entry by [documentKey] in the cache
  ///
  /// Returns the cached [Document] or [NoDocument] entry, or null if we have
  /// nothing cached.
  Future<MaybeDocument?> get(DocumentKey documentKey);

  /// Looks up a set of entries in the cache.
  ///
  /// Returns the cached [Document] or [NoDocument] entries indexed by key. If
  /// an entry is not cached, the corresponding key will be mapped to a null
  /// value.
  Future<Map<DocumentKey, MaybeDocument?>> getAll(
    Iterable<DocumentKey> documentKeys,
  );

  /// Looks up the next [limit] documents for a collection group based on the provided [offset]. The ordering is based
  /// on the document's read time and key.
  ///
  /// The result includes the cached [NoDocument] entries. Only supported by the SQLite implementation (it is used to
  /// backfill field indexes, which memory persistence does not have).
  Future<Map<DocumentKey, ReadDocument>> getAllForCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
    int limit,
  );

  /// Executes a query against the cached [Document] entries
  ///
  /// Implementations may return extra documents if convenient. The results
  /// should be re-filtered by the consumer before presenting them to the user.
  ///
  /// Cached [NoDocument] entries have no bearing on query results.
  ///
  /// [offset] is the read time and document key to start scanning at (exclusive): only documents that were read after
  /// its read time, or at its read time with a key after its key, are returned. [IndexOffset.none] returns all
  /// documents; `IndexOffset.createSuccessor(version, ...)` the documents read after `version`.
  ///
  /// [mutatedKeys] are the keys of the documents that have local mutations: they are returned even if their cached
  /// version does not match the query, because a mutation can make them match.
  ///
  /// [context] is an optional tracker that records the number of documents the scan went through (SQLite only, as
  /// upstream).
  Future<ImmutableSortedMap<DocumentKey, Document>>
  getAllDocumentsMatchingQuery(
    Query query,
    IndexOffset offset, {
    Set<DocumentKey> mutatedKeys = const <DocumentKey>{},
    QueryContext? context,
  });
}
