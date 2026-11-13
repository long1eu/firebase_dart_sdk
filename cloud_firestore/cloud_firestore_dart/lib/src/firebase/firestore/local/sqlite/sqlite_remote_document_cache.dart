// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

part of 'sqlite_persistence.dart';

class SQLiteRemoteDocumentCache implements RemoteDocumentCache {
  /// The number of rows a collection scan reads per statement.
  static const int _scanPageSize = 1000;

  /// Up to this many documents read after an offset (in the whole cache), they are read through the `read_time`
  /// index rather than by a scan of the collection.
  static const int _readTimeIndexMaxRows = 5000;

  /// Whether the `read_time` index exists (it comes with the field index tables of schema 13).
  bool? _hasReadTimeIndex;

  SQLiteRemoteDocumentCache(this.db, this.serializer, this._statsCollector);

  final SQLitePersistence db;
  final LocalSerializer serializer;
  final StatsCollector _statsCollector;

  /// The index manager of the current user, once the local store set it.
  IndexManager? _indexManager;

  @override
  set indexManager(IndexManager indexManager) => _indexManager = indexManager;

  @override
  Future<void> add(
    MaybeDocument maybeDocument,
    SnapshotVersion readTime,
  ) async {
    hardAssert(
      readTime != SnapshotVersion.none,
      'Cannot add document to the RemoteDocumentCache with a read time of zero',
    );

    final String path = _pathForKey(maybeDocument.key);
    final Timestamp timestamp = readTime.timestamp;
    final GeneratedMessage message = serializer.encodeMaybeDocument(
      maybeDocument,
    );

    _statsCollector.recordRowsWritten(RemoteDocumentCache.statsTag, 1);
    await db.execute(
      // @formatter:off
      '''
          INSERT
          OR REPLACE INTO remote_documents (path, path_length, read_time_seconds, read_time_nanos, contents)
          VALUES (?, ?, ?, ?, ?);
        ''',
      // @formatter:on
      <dynamic>[
        path,
        maybeDocument.key.path.length,
        timestamp.seconds,
        timestamp.nanoseconds,
        message.writeToBuffer(),
      ],
    );

    await (_indexManager ?? db.indexManager).addToCollectionParentIndex(
      maybeDocument.key.path.popLast(),
    );
  }

  @override
  Future<void> remove(DocumentKey documentKey) async {
    final String path = _pathForKey(documentKey);
    _statsCollector.recordRowsDeleted(RemoteDocumentCache.statsTag, 1);

    await db.execute(
      // @formatter:off
      '''
          DELETE
          FROM remote_documents
          WHERE path = ?;
        ''',
      // @formatter:on
      <String>[path],
    );

    // A removed document has no index entries (upstream does this in `removeAll`).
    await _indexManager?.updateIndexEntries(<DocumentKey, MaybeDocument?>{
      documentKey: null,
    });
  }

  @override
  Future<void> removeAll(Iterable<DocumentKey> documentKeys) async {
    final List<Object?> paths = <Object?>[];
    final Map<DocumentKey, MaybeDocument?> deletedDocs =
        <DocumentKey, MaybeDocument?>{};
    for (DocumentKey key in documentKeys) {
      paths.add(_pathForKey(key));
      deletedDocs[key] = null;
    }
    if (paths.isEmpty) {
      return;
    }

    _statsCollector.recordRowsDeleted(
      RemoteDocumentCache.statsTag,
      paths.length,
    );
    final LongQuery longQuery = LongQuery(
      db,
      'DELETE FROM remote_documents WHERE path IN (',
      null,
      paths,
      ')',
    );
    while (longQuery.hasMoreSubqueries) {
      await longQuery.performNextSubquery();
    }

    // A removed document has no index entries.
    await _indexManager?.updateIndexEntries(deletedDocs);
  }

  @override
  Future<MaybeDocument?> get(DocumentKey documentKey) async {
    final String path = _pathForKey(documentKey);

    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, 1);
    final List<Map<String, dynamic>> result = await db.query(
      // @formatter:off
      '''
          SELECT contents
          FROM remote_documents
          WHERE path = ?;
        ''',
      // @formatter:on
      <String>[path],
    );

    if (result.isEmpty) {
      return null;
    }
    final Map<String, dynamic> row = result.first;
    final Uint8List contents = row['contents'];
    return decodeMaybeDocument(contents);
  }

  @override
  Future<Map<DocumentKey, MaybeDocument?>> getAll(
    Iterable<DocumentKey> documentKeys,
  ) async {
    final List<Object?> args = <Object?>[];
    for (DocumentKey key in documentKeys) {
      args.add(EncodedPath.encode(key.path));
    }

    final Map<DocumentKey, MaybeDocument?> results =
        <DocumentKey, MaybeDocument?>{};
    for (DocumentKey key in documentKeys) {
      // Make sure each key has a corresponding entry, which is null in case the document is not found.
      results[key] = null;
    }

    final LongQuery longQuery = LongQuery(
      db,
      'SELECT contents FROM remote_documents WHERE path IN (',
      null,
      args,
      ') ORDER BY path',
    );

    int rowsProcessed = 0;
    while (longQuery.hasMoreSubqueries) {
      final List<Map<String, dynamic>> rows = await longQuery
          .performNextSubquery();
      for (Map<String, dynamic> row in rows) {
        final MaybeDocument decoded = decodeMaybeDocument(row['contents']);
        results[decoded.key] = decoded;
      }
      rowsProcessed += rows.length;
    }

    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, rowsProcessed);
    return results;
  }

  /// The number of bind arguments of the statement for one collection in [_getAllForCollections].
  @visibleForTesting
  static const int bindsPerStatement = 9;

  /// The number of bind arguments a statement may have (SQLite supports 999).
  static const int _maxArgs = 900;

  @override
  Future<Map<DocumentKey, ReadDocument>> getAllForCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
    int limit,
  ) async {
    final List<ResourcePath> collectionParents = await db.indexManager
        .getCollectionParents(collectionGroup);
    final List<ResourcePath> collections = <ResourcePath>[
      for (final ResourcePath collectionParent in collectionParents)
        collectionParent.appendSegment(collectionGroup),
    ];

    if (collections.isEmpty) {
      return <DocumentKey, ReadDocument>{};
    } else if (bindsPerStatement * collections.length < _maxArgs) {
      return _getAllForCollections(collections, offset, limit);
    } else {
      // We need to fan out our collection scan since SQLite only supports 999 binds per statement.
      final Map<DocumentKey, ReadDocument> results =
          <DocumentKey, ReadDocument>{};
      const int pageSize = _maxArgs ~/ bindsPerStatement;
      for (int i = 0; i < collections.length; i += pageSize) {
        results.addAll(
          await _getAllForCollections(
            collections.sublist(i, min(collections.length, i + pageSize)),
            offset,
            limit,
          ),
        );
      }
      // The first [limit] entries, by read time and key.
      final List<MapEntry<DocumentKey, ReadDocument>> entries =
          results.entries.toList()..sort((
            MapEntry<DocumentKey, ReadDocument> l,
            MapEntry<DocumentKey, ReadDocument> r,
          ) {
            final int cmp = l.value.readTime.compareTo(r.value.readTime);
            return cmp != 0 ? cmp : l.key.compareTo(r.key);
          });
      return Map<DocumentKey, ReadDocument>.fromEntries(entries.take(limit));
    }
  }

  /// Returns the next [count] documents from the provided collections, ordered by read time.
  Future<Map<DocumentKey, ReadDocument>> _getAllForCollections(
    List<ResourcePath> collections,
    IndexOffset offset,
    int count,
  ) async {
    final Timestamp readTime = offset.readTime.timestamp;
    final DocumentKey documentKey = offset.documentKey;

    final String sql =
        '${List<String>.filled(collections.length, '''
          SELECT contents, read_time_seconds, read_time_nanos, path
          FROM remote_documents
          WHERE path >= ? AND path < ? AND path_length = ?
            AND (read_time_seconds > ?
              OR (read_time_seconds = ? AND read_time_nanos > ?)
              OR (read_time_seconds = ? AND read_time_nanos = ? AND path > ?))
        ''').join(' UNION ')}'
        'ORDER BY read_time_seconds, read_time_nanos, path LIMIT ?';

    final List<Object> bindVars = <Object>[];
    for (final ResourcePath collection in collections) {
      final String prefixPath = EncodedPath.encode(collection);
      bindVars
        ..add(prefixPath)
        ..add(EncodedPath.prefixSuccessor(prefixPath))
        ..add(collection.length + 1)
        ..add(readTime.seconds)
        ..add(readTime.seconds)
        ..add(readTime.nanoseconds)
        ..add(readTime.seconds)
        ..add(readTime.nanoseconds)
        ..add(EncodedPath.encode(documentKey.path));
    }
    bindVars.add(count);

    final List<Map<String, dynamic>> rows = await db.query(sql, bindVars);

    final Map<DocumentKey, ReadDocument> results =
        <DocumentKey, ReadDocument>{};
    for (final Map<String, dynamic> row in rows) {
      final MaybeDocument document = decodeMaybeDocument(row['contents']);
      results[document.key] = (
        document: document,
        readTime: SnapshotVersion(
          Timestamp(row['read_time_seconds'], row['read_time_nanos']),
        ),
      );
    }

    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, rows.length);
    return results;
  }

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>>
  getAllDocumentsMatchingQuery(
    Query query,
    IndexOffset offset, {
    Set<DocumentKey> mutatedKeys = const <DocumentKey>{},
    QueryContext? context,
  }) async {
    hardAssert(
      !query.isCollectionGroupQuery,
      'CollectionGroup queries should be handled in LocalDocumentsView',
    );

    // Use the query path as a prefix for testing if a document matches the query.
    final ResourcePath prefix = query.path;
    final int immediateChildrenPathLength = prefix.length + 1;

    final String prefixPath = EncodedPath.encode(prefix);
    final String prefixSuccessorPath = EncodedPath.prefixSuccessor(prefixPath);

    final Map<DocumentKey, Document> results = <DocumentKey, Document>{};

    // The read time condition of a query with an offset: the documents read after the offset's read time, and those
    // read at that read time with a larger key. This is safe since all document changes to queries that have a
    // lastLimboFreeSnapshotVersion have a read time set.
    final bool sinceOffset = offset != IndexOffset.none;
    final Timestamp readTime = offset.readTime.timestamp;
    final List<Object> readTimeBindings = sinceOffset
        ? <Object>[
            readTime.seconds,
            readTime.seconds,
            readTime.nanoseconds,
            readTime.seconds,
            readTime.nanoseconds,
            EncodedPath.encode(offset.documentKey.path),
          ]
        : const <Object>[];

    int rowsRead = 0;
    void addRows(List<Map<String, dynamic>> rows) {
      rowsRead += rows.length;
      for (Map<String, dynamic> row in rows) {
        // `path_length` keeps the documents of subcollections out (as upstream does), so that they are neither copied
        // out of the database nor their paths decoded.
        final Uint8List contents = row['contents'];
        final MaybeDocument maybeDoc = decodeMaybeDocument(contents);
        if (maybeDoc is Document &&
            (mutatedKeys.contains(maybeDoc.key) || query.matches(maybeDoc))) {
          results[maybeDoc.key] = maybeDoc;
        }
      }
    }

    const String readTimeCondition = '''
        AND (read_time_seconds > ?
          OR (read_time_seconds = ? AND read_time_nanos > ?)
          OR (read_time_seconds = ? AND read_time_nanos = ? AND path > ?))''';

    // DEVIATION FROM UPSTREAM: upstream reads the documents changed after an offset (those not yet in a field index,
    // or changed since a query was last in sync) by walking the whole collection by path and comparing read times,
    // so an indexed query costs a scan of the collection however few documents changed (170 ms for 1M documents).
    // When few documents of the whole cache were read after the offset (counted on the `read_time` index, stopping at
    // [_readTimeIndexMaxRows]), they are read through that index instead.
    if (sinceOffset &&
        (_hasReadTimeIndex ??= (await db.query(
          "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'read_time'",
        )).isNotEmpty)) {
      final List<Map<String, dynamic>> newer = await db.query(
        'SELECT COUNT(*) AS count FROM (SELECT 1 FROM remote_documents INDEXED BY read_time '
        'WHERE (read_time_seconds, read_time_nanos) >= (?, ?) LIMIT ?)',
        <Object>[readTime.seconds, readTime.nanoseconds, _readTimeIndexMaxRows],
      );
      if ((newer.single['count'] as int) < _readTimeIndexMaxRows) {
        addRows(
          await db.query(
            'SELECT contents FROM remote_documents INDEXED BY read_time '
            'WHERE (read_time_seconds, read_time_nanos) >= (?, ?) '
            'AND path >= ? AND path < ? AND path_length = ? $readTimeCondition',
            <Object>[
              readTime.seconds,
              readTime.nanoseconds,
              prefixPath,
              prefixSuccessorPath,
              immediateChildrenPathLength,
              ...readTimeBindings,
            ],
          ),
        );
        _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, rowsRead);
        context?.incrementDocumentReadCount(rowsRead);
        return ImmutableSortedMap<DocumentKey, Document>.fromMap(
          results,
          DocumentKey.comparator,
        );
      }
    }

    // PORTING NOTE: upstream walks a cursor over the rows. The `Database` adapter returns all the rows of a statement
    // at once, so a scan of a large collection would hold the contents of every document in memory (about 570 MB for
    // a collection of 1M documents) although few of them match. The rows are read in pages of [_scanPageSize] by
    // path (the primary key) instead.
    String lastPath = prefixPath;
    bool firstPage = true;
    while (true) {
      final List<Map<String, dynamic>> page = await db.query(
        'SELECT path, contents FROM remote_documents '
        'WHERE path ${firstPage ? '>=' : '>'} ? AND path < ? AND path_length = ? '
        '${sinceOffset ? readTimeCondition : ''} '
        'ORDER BY path LIMIT $_scanPageSize',
        <Object>[
          lastPath,
          prefixSuccessorPath,
          immediateChildrenPathLength,
          ...readTimeBindings,
        ],
      );
      firstPage = false;
      addRows(page);
      if (page.length < _scanPageSize) {
        break;
      }
      lastPath = page.last['path'] as String;
    }

    _statsCollector.recordRowsRead(RemoteDocumentCache.statsTag, rowsRead);
    context?.incrementDocumentReadCount(rowsRead);
    return ImmutableSortedMap<DocumentKey, Document>.fromMap(
      results,
      DocumentKey.comparator,
    );
  }

  String _pathForKey(DocumentKey key) {
    return EncodedPath.encode(key.path);
  }

  MaybeDocument decodeMaybeDocument(Uint8List bytes) {
    try {
      return serializer.decodeMaybeDocument(
        proto.MaybeDocument.fromBuffer(bytes),
      );
    } on InvalidProtocolBufferException catch (e) {
      throw fail('MaybeDocument failed to parse: $e');
    }
  }
}
