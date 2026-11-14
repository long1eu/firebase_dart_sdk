// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

part of 'sqlite_persistence.dart';

/// A persisted implementation of IndexManager. Port of `SQLiteIndexManager` of the Android SDK.
class SqliteIndexManager extends IndexManager {
  SqliteIndexManager(this.db, [LocalSerializer? serializer, User? user])
    : _serializer = serializer ?? db.serializer,
      _uid = user?.uid ?? '',
      _collectionParentsIndex = MemoryCollectionParentIndex();

  static const String _tag = 'SQLiteIndexManager';

  final SQLitePersistence db;
  final LocalSerializer _serializer;
  final String _uid;

  /// Maps from a target to its equivalent list of sub-targets. Each sub-target contains only one term from the
  /// target's disjunctive normal form (DNF).
  // TODO(orquery): Find a way for the GC algorithm to remove the mapping once we remove a target.
  final Map<Target, List<Target>> _targetToDnfSubTargets =
      <Target, List<Target>>{};

  /// An in-memory copy of the index entries we've already written since the SDK
  /// launched. Used to avoid re-writing the same entry repeatedly.
  ///
  /// This is NOT a complete cache of what's in persistence and so can never be
  /// used to satisfy reads.
  final MemoryCollectionParentIndex _collectionParentsIndex;

  final Map<String, Map<int, FieldIndex>> _memoizedIndexes =
      <String, Map<int, FieldIndex>>{};

  /// The indexes ordered by when they were last updated (and by collection group, to make the order deterministic).
  final PriorityQueue<FieldIndex> _nextIndexToUpdate =
      PriorityQueue<FieldIndex>((FieldIndex l, FieldIndex r) {
        final int sequenceCmp = l.indexState.sequenceNumber.compareTo(
          r.indexState.sequenceNumber,
        );
        if (sequenceCmp == 0) {
          return l.collectionGroup.compareTo(r.collectionGroup);
        }
        return sequenceCmp;
      });

  bool _started = false;
  int _memoizedMaxIndexId = -1;
  int _memoizedMaxSequenceNumber = -1;

  /// Reads the indexes and their states again, after another connection changed the database.
  Future<void> _refresh() async {
    if (_started) {
      _memoizedIndexes.clear();
      _nextIndexToUpdate.clear();
      _memoizedMaxIndexId = -1;
      await start();
    }
  }

  @override
  Future<void> start() async {
    final Map<int, IndexState> indexStates = <int, IndexState>{};

    // Fetch all index states if persisted for the user. These states contain per user information on how up to date
    // the index is.
    final List<Map<String, dynamic>> stateRows = await db.query(
      'SELECT index_id, sequence_number, read_time_seconds, read_time_nanos, document_key, largest_batch_id '
      'FROM index_state WHERE uid = ?',
      <Object>[_uid],
    );
    for (final Map<String, dynamic> row in stateRows) {
      final int indexId = row['index_id'];
      final int sequenceNumber = row['sequence_number'];
      final SnapshotVersion readTime = SnapshotVersion(
        Timestamp(row['read_time_seconds'], row['read_time_nanos']),
      );
      final DocumentKey documentKey = DocumentKey.fromPath(
        EncodedPath.decodeResourcePath(row['document_key']),
      );
      final int largestBatchId = row['largest_batch_id'];
      indexStates[indexId] = IndexState(
        sequenceNumber,
        IndexOffset(readTime, documentKey, largestBatchId),
      );
    }

    // Fetch all indices and combine with user's index state if available.
    final List<Map<String, dynamic>> configRows = await db.query(
      'SELECT index_id, collection_group, index_proto FROM index_configuration',
    );
    for (final Map<String, dynamic> row in configRows) {
      final int indexId = row['index_id'];
      final String collectionGroup = row['collection_group'];
      final List<IndexSegment> segments = _serializer.decodeFieldIndexSegments(
        parseStoredProto(
          'Index',
          () => admin.Index.fromBuffer(row['index_proto']),
        ),
      );

      // If we fetched an index state for the user above, combine it with this index. We use the default state if we
      // don't have an index state (for example, if the index was created while a different user as logged in).
      final IndexState indexState =
          indexStates[indexId] ?? FieldIndex.initialState;
      final FieldIndex fieldIndex = FieldIndex(
        indexId,
        collectionGroup,
        segments,
        indexState,
      );

      // Store the index and update `_memoizedMaxIndexId` and `_memoizedMaxSequenceNumber`.
      _memoizeIndex(fieldIndex);
    }

    _started = true;
  }

  // PORTING NOTE: unlike upstream, the two collection parent methods do not need [start]: the port also uses them on
  // `Persistence.indexManager`, which is never started.

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) async {
    hardAssert(collectionPath.length % 2 == 1, 'Expected a collection path.');

    if (!_collectionParentsIndex.contains(collectionPath)) {
      final String collectionId = collectionPath.getLastSegment();
      final ResourcePath parentPath = collectionPath.popLast();
      await db.execute(
        'INSERT OR REPLACE INTO collection_parents (collection_id, parent) VALUES (?, ?)',
        <Object>[collectionId, EncodedPath.encode(parentPath)],
      );
      // Cache the entry only once it is stored: if the INSERT throws (and the transaction rolls back) the next call
      // must try again.
      _collectionParentsIndex.add(collectionPath);
    }
  }

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    final List<Map<String, dynamic>> data = await db.query(
      'SELECT parent FROM collection_parents WHERE collection_id = ?',
      <String>[collectionId],
    );

    return data
        .map(
          (Map<String, dynamic> row) =>
              EncodedPath.decodeResourcePath(row['parent']),
        )
        .toList();
  }

  @override
  Future<void> addFieldIndex(FieldIndex index) async {
    hardAssert(_started, 'IndexManager not started');

    final int nextIndexId = _memoizedMaxIndexId + 1;
    final FieldIndex newIndex = FieldIndex(
      nextIndexId,
      index.collectionGroup,
      index.segments,
      index.indexState,
    );

    await db.execute(
      'INSERT INTO index_configuration (index_id, collection_group, index_proto) VALUES(?, ?, ?)',
      <Object>[
        nextIndexId,
        newIndex.collectionGroup,
        _encodeSegments(newIndex),
      ],
    );

    // TODO(indexing): Use a 0-counter rather than the timestamp.
    _memoizeIndex(newIndex);
  }

  @override
  Future<void> deleteFieldIndex(FieldIndex index) async {
    await db.execute(
      'DELETE FROM index_configuration WHERE index_id = ?',
      <Object>[index.indexId],
    );
    await db.execute('DELETE FROM index_entries WHERE index_id = ?', <Object>[
      index.indexId,
    ]);
    await db.execute('DELETE FROM index_state WHERE index_id = ?', <Object>[
      index.indexId,
    ]);

    _nextIndexToUpdate.remove(index);
    _memoizedIndexes[index.collectionGroup]?.remove(index.indexId);
  }

  @override
  Future<void> deleteAllFieldIndexes() async {
    await db.execute('DELETE FROM index_configuration');
    await db.execute('DELETE FROM index_entries');
    await db.execute('DELETE FROM index_state');

    _nextIndexToUpdate.clear();
    _memoizedIndexes.clear();
  }

  @override
  Future<void> createTargetIndexes(Target target) async {
    hardAssert(_started, 'IndexManager not started');

    for (final Target subTarget in _getSubTargets(target)) {
      final IndexType type = getIndexType(subTarget);
      if (type == IndexType.none || type == IndexType.partial) {
        final TargetIndexMatcher targetIndexMatcher = TargetIndexMatcher(
          subTarget,
        );
        final FieldIndex? fieldIndex = targetIndexMatcher.buildTargetIndex();
        if (fieldIndex != null) {
          await addFieldIndex(fieldIndex);
        }
      }
    }
  }

  @override
  String? getNextCollectionGroupToUpdate() {
    hardAssert(_started, 'IndexManager not started');
    return _nextIndexToUpdate.isEmpty
        ? null
        : _nextIndexToUpdate.first.collectionGroup;
  }

  @override
  Future<void> updateIndexEntries(
    Map<DocumentKey, MaybeDocument?> documents,
  ) async {
    hardAssert(_started, 'IndexManager not started');

    for (final MapEntry<DocumentKey, MaybeDocument?> entry
        in documents.entries) {
      final List<FieldIndex> fieldIndexes = getFieldIndexes(
        entry.key.collectionGroup,
      );
      for (final FieldIndex fieldIndex in fieldIndexes) {
        final SplayTreeSet<IndexEntry> existingEntries =
            await _getExistingIndexEntries(entry.key, fieldIndex);
        final SplayTreeSet<IndexEntry> newEntries = _computeIndexEntries(
          entry.key,
          entry.value,
          fieldIndex,
        );
        if (!const IterableEquality<IndexEntry>().equals(
          existingEntries,
          newEntries,
        )) {
          await _updateEntries(entry.key, existingEntries, newEntries);
        }
      }
    }
  }

  /// Updates the index entries for the provided document by deleting entries that are no longer referenced in
  /// [newEntries] and adding all newly added entries.
  Future<void> _updateEntries(
    DocumentKey key,
    SplayTreeSet<IndexEntry> existingEntries,
    SplayTreeSet<IndexEntry> newEntries,
  ) async {
    Log.d(_tag, 'Updating index entries for document \'${key.path}\'');
    await diffCollections(
      existingEntries,
      newEntries,
      (IndexEntry left, IndexEntry right) => left.compareTo(right),
      (IndexEntry entry) => _addIndexEntry(key, entry),
      (IndexEntry entry) => _deleteIndexEntry(key, entry),
    );
  }

  @override
  List<FieldIndex> getFieldIndexes([String? collectionGroup]) {
    if (collectionGroup == null) {
      return <FieldIndex>[
        for (final Map<int, FieldIndex> indices in _memoizedIndexes.values)
          ...indices.values,
      ];
    }

    hardAssert(_started, 'IndexManager not started');
    final Map<int, FieldIndex>? indexes = _memoizedIndexes[collectionGroup];
    return indexes == null ? const <FieldIndex>[] : indexes.values.toList();
  }

  IndexOffset _getMinOffset(List<FieldIndex> fieldIndexes) {
    hardAssert(
      fieldIndexes.isNotEmpty,
      'Found empty index group when looking for least recent index offset.',
    );

    IndexOffset minOffset = fieldIndexes.first.indexState.offset;
    int maxBatchId = minOffset.largestBatchId;
    for (final FieldIndex fieldIndex in fieldIndexes.skip(1)) {
      final IndexOffset newOffset = fieldIndex.indexState.offset;
      if (newOffset.compareTo(minOffset) < 0) {
        minOffset = newOffset;
      }
      maxBatchId = max(newOffset.largestBatchId, maxBatchId);
    }

    return IndexOffset(minOffset.readTime, minOffset.documentKey, maxBatchId);
  }

  @override
  IndexOffset getMinOffset(String collectionGroup) {
    final List<FieldIndex> fieldIndexes = getFieldIndexes(collectionGroup);
    hardAssert(
      fieldIndexes.isNotEmpty,
      'minOffset was called for collection without indexes',
    );
    return _getMinOffset(fieldIndexes);
  }

  @override
  IndexType getIndexType(Target target) {
    IndexType result = IndexType.full;
    final List<Target> subTargets = _getSubTargets(target);

    for (final Target subTarget in subTargets) {
      final FieldIndex? index = _getFieldIndex(subTarget);
      if (index == null) {
        result = IndexType.none;
        break;
      }

      if (index.segments.length < subTarget.segmentCount) {
        result = IndexType.partial;
      }
    }

    // OR queries have more than one sub-target (one sub-target per DNF term). We currently consider OR queries that
    // have a `limit` to have a partial index. For such queries we perform sorting and apply the limit in memory as a
    // post-processing step.
    // TODO(orquery): If we have a FULL index *and* we have the index that can be used for sorting all DNF branches on
    //  the same value, we can improve performance by performing a JOIN in SQL. See b/235224019 for more information.
    if (target.hasLimit && subTargets.length > 1 && result == IndexType.full) {
      return IndexType.partial;
    }

    return result;
  }

  @override
  IndexOffset getMinOffsetForTarget(Target target) {
    final List<FieldIndex> fieldIndexes = <FieldIndex>[];
    for (final Target subTarget in _getSubTargets(target)) {
      final FieldIndex? index = _getFieldIndex(subTarget);
      if (index != null) {
        fieldIndexes.add(index);
      }
    }
    return _getMinOffset(fieldIndexes);
  }

  List<Target> _getSubTargets(Target target) {
    final List<Target>? memoized = _targetToDnfSubTargets[target];
    if (memoized != null) {
      return memoized;
    }
    final List<Target> subTargets = <Target>[];
    if (target.filters.isEmpty) {
      subTargets.add(target);
    } else {
      // There is an implicit AND operation between all the filters stored in the target.
      final List<Filter> dnf = LogicUtils.getDnfTerms(
        CompositeFilter(target.filters, CompositeFilterOperator.and),
      );
      for (final Filter term in dnf) {
        subTargets.add(
          Target(
            target.path,
            collectionGroup: target.collectionGroup,
            filters: term.filters,
            orderBy: target.orderBy,
            limit: target.limit,
            startAt: target.startAt,
            endAt: target.endAt,
          ),
        );
      }
    }
    _targetToDnfSubTargets[target] = subTargets;
    return subTargets;
  }

  /// Stores the index in the memoized indexes table and updates [_nextIndexToUpdate], [_memoizedMaxIndexId] and
  /// [_memoizedMaxSequenceNumber].
  void _memoizeIndex(FieldIndex fieldIndex) {
    final Map<int, FieldIndex> existingIndexes = _memoizedIndexes.putIfAbsent(
      fieldIndex.collectionGroup,
      () => <int, FieldIndex>{},
    );

    final FieldIndex? existingIndex = existingIndexes[fieldIndex.indexId];
    if (existingIndex != null) {
      _nextIndexToUpdate.remove(existingIndex);
    }

    existingIndexes[fieldIndex.indexId] = fieldIndex;
    _nextIndexToUpdate.add(fieldIndex);
    _memoizedMaxIndexId = max(_memoizedMaxIndexId, fieldIndex.indexId);
    _memoizedMaxSequenceNumber = max(
      _memoizedMaxSequenceNumber,
      fieldIndex.indexState.sequenceNumber,
    );
  }

  /// Creates the index entries for the given document. A missing document has none.
  SplayTreeSet<IndexEntry> _computeIndexEntries(
    DocumentKey key,
    MaybeDocument? maybeDocument,
    FieldIndex fieldIndex,
  ) {
    final SplayTreeSet<IndexEntry> result = SplayTreeSet<IndexEntry>();
    if (maybeDocument is! Document) {
      return result;
    }
    final Document document = maybeDocument;

    final Uint8List? directionalValue = _encodeDirectionalElements(
      fieldIndex,
      document,
    );
    if (directionalValue == null) {
      return result;
    }

    final IndexSegment? arraySegment = fieldIndex.arraySegment;
    if (arraySegment != null) {
      final FieldValue? value = document.getField(arraySegment.fieldPath);
      if (value is ArrayValue) {
        for (final FieldValue arrayValue in value.internalValue) {
          result.add(
            IndexEntry(
              fieldIndex.indexId,
              key,
              _encodeSingleElement(arrayValue),
              directionalValue,
            ),
          );
        }
      }
    } else {
      result.add(
        IndexEntry(fieldIndex.indexId, key, Uint8List(0), directionalValue),
      );
    }

    return result;
  }

  Future<void> _addIndexEntry(DocumentKey key, IndexEntry indexEntry) {
    return db.execute(
      'INSERT INTO index_entries (index_id, uid, array_value, directional_value, document_key) '
      'VALUES(?, ?, ?, ?, ?)',
      <Object>[
        indexEntry.indexId,
        _uid,
        indexEntry.arrayValue,
        indexEntry.directionalValue,
        key.path.canonicalString,
      ],
    );
  }

  Future<void> _deleteIndexEntry(DocumentKey key, IndexEntry indexEntry) {
    return db.execute(
      'DELETE FROM index_entries WHERE index_id = ? AND uid = ? AND array_value = ? '
      'AND directional_value = ? AND document_key = ?',
      <Object>[
        indexEntry.indexId,
        _uid,
        indexEntry.arrayValue,
        indexEntry.directionalValue,
        key.path.canonicalString,
      ],
    );
  }

  Future<SplayTreeSet<IndexEntry>> _getExistingIndexEntries(
    DocumentKey documentKey,
    FieldIndex fieldIndex,
  ) async {
    final SplayTreeSet<IndexEntry> results = SplayTreeSet<IndexEntry>();
    final List<Map<String, dynamic>> rows = await db.query(
      // The index of schema migration 14 is named, because SQLite prefers the (covering) primary key otherwise and
      // then walks all the entries of the index for every document.
      'SELECT array_value, directional_value FROM index_entries '
      'INDEXED BY index_entries_document_key '
      'WHERE index_id = ? AND document_key = ? AND uid = ?',
      <Object>[fieldIndex.indexId, documentKey.path.canonicalString, _uid],
    );
    for (final Map<String, dynamic> row in rows) {
      results.add(
        IndexEntry(
          fieldIndex.indexId,
          documentKey,
          Uint8List.fromList(row['array_value']),
          Uint8List.fromList(row['directional_value']),
        ),
      );
    }
    return results;
  }

  @override
  Future<List<DocumentKey>?> getDocumentsMatchingTarget(Target target) async {
    hardAssert(_started, 'IndexManager not started');

    final List<String> subQueries = <String>[];
    final List<Object> bindings = <Object>[];

    final List<(Target, FieldIndex)> indexes = <(Target, FieldIndex)>[];

    for (final Target subTarget in _getSubTargets(target)) {
      final FieldIndex? fieldIndex = _getFieldIndex(subTarget);
      if (fieldIndex == null) {
        return null;
      }
      indexes.add((subTarget, fieldIndex));
    }

    for (final (Target subTarget, FieldIndex fieldIndex) in indexes) {
      final List<FieldValue>? arrayValues = subTarget.getArrayValues(
        fieldIndex,
      );
      final List<FieldValue>? notInValues = subTarget.getNotInValues(
        fieldIndex,
      );
      final Bound lowerBound = subTarget.getLowerBound(fieldIndex);
      final Bound upperBound = subTarget.getUpperBound(fieldIndex);

      if (Log.isDebugEnabled) {
        Log.d(
          _tag,
          'Using index \'$fieldIndex\' to execute \'$subTarget\' (Arrays: $arrayValues, Lower bound: $lowerBound, '
          'Upper bound: $upperBound)',
        );
      }

      final List<Uint8List> lowerBoundEncoded = _encodeValues(
        fieldIndex,
        subTarget,
        lowerBound.position,
      )!;
      final String lowerBoundOp = lowerBound.inclusive ? '>=' : '>';
      final List<Uint8List> upperBoundEncoded = _encodeValues(
        fieldIndex,
        subTarget,
        upperBound.position,
      )!;
      final String upperBoundOp = upperBound.inclusive ? '<=' : '<';
      final List<Uint8List>? notInEncoded = _encodeValues(
        fieldIndex,
        subTarget,
        notInValues,
      );

      final (
        String subQuery,
        List<Object> subQueryBindings,
      ) = _generateQueryAndBindings(
        subTarget,
        fieldIndex.indexId,
        arrayValues,
        lowerBoundEncoded,
        lowerBoundOp,
        upperBoundEncoded,
        upperBoundOp,
        notInEncoded,
      );
      subQueries.add(subQuery);
      bindings.addAll(subQueryBindings);
    }

    // We are constructing:
    // SELECT DISTINCT document_key FROM (
    //   (SELECT ...) UNION (SELECT ...) UNION (SELECT ...)
    //   ORDER BY ...
    // )
    // LIMIT ...
    //
    // Note: SQLite does not allow performing ORDER BY on each union clause. The ORDER BY must come after the last
    // union clause. Also note that LIMIT must be applied *after* the DISTINCT operator has been performed. When
    // dealing with multiple sub-targets, it's possible that the same document_key appears multiple times.
    final String unionSubTargets =
        '${subQueries.join(' UNION ')}'
        'ORDER BY directional_value, document_key '
        '${target.keyOrder == OrderByDirection.ascending ? 'asc ' : 'desc '}';

    String queryString = 'SELECT DISTINCT document_key FROM ($unionSubTargets)';
    if (target.hasLimit) {
      queryString = '$queryString LIMIT ${target.limit}';
    }

    hardAssert(
      bindings.length < 1000,
      'Cannot perform query with more than 999 bind elements',
    );

    final List<Map<String, dynamic>> rows = await db.query(
      queryString,
      bindings,
    );

    final List<DocumentKey> result = <DocumentKey>[
      for (final Map<String, dynamic> row in rows)
        DocumentKey.fromPath(ResourcePath.fromString(row['document_key'])),
    ];

    Log.d(_tag, 'Index scan returned ${result.length} documents');
    return result;
  }

  /// Constructs a SQL query on 'index_entries' that unions all bounds. Returns the SQL query string and its binding
  /// arguments.
  (String, List<Object>) _generateQueryAndBindings(
    Target target,
    int indexId,
    List<FieldValue>? arrayValues,
    List<Uint8List> lowerBounds,
    String lowerBoundOp,
    List<Uint8List> upperBounds,
    String upperBoundOp,
    List<Uint8List>? notIn,
  ) {
    // The number of total statements we union together. This is similar to a distributed normal form, but adapted for
    // array values. We create a single statement per value in an ARRAY_CONTAINS or ARRAY_CONTAINS_ANY filter combined
    // with the values from the query bounds.
    final int statementCount =
        (arrayValues != null ? arrayValues.length : 1) *
        max(lowerBounds.length, upperBounds.length);

    // Build the statement. We always include the lower bound, and optionally include an array value and an upper
    // bound.
    final String statement =
        'SELECT document_key, directional_value FROM index_entries '
        'WHERE index_id = ? AND uid = ? '
        'AND array_value = ? '
        'AND directional_value $lowerBoundOp ? '
        'AND directional_value $upperBoundOp ? ';

    // Create the UNION statement by repeating the above generated statement.
    String sql = List<String>.filled(statementCount, statement).join(' UNION ');

    if (notIn != null) {
      // Wrap the statement in a NOT-IN call.
      sql =
          'SELECT document_key, directional_value FROM ($sql) '
          'WHERE directional_value NOT IN (${List<String>.filled(notIn.length, '?').join(', ')})';
    }

    // Fill in the bind ("question marks") variables.
    final List<Object> bindArgs = _fillBounds(
      statementCount,
      indexId,
      arrayValues,
      lowerBounds,
      upperBounds,
      notIn,
    );

    return (sql, bindArgs);
  }

  /// Returns the bind arguments for all [statementCount] statements.
  List<Object> _fillBounds(
    int statementCount,
    int indexId,
    List<FieldValue>? arrayValues,
    List<Uint8List> lowerBounds,
    List<Uint8List> upperBounds,
    List<Uint8List>? notInValues,
  ) {
    // Every SQL statement we union together have 5 binds, see [_generateQueryAndBindings].
    final int statementsPerArrayValue =
        statementCount ~/ (arrayValues != null ? arrayValues.length : 1);

    final List<Object> bindArgs = <Object>[];
    for (int i = 0; i < statementCount; ++i) {
      bindArgs
        ..add(indexId)
        ..add(_uid)
        ..add(
          arrayValues != null
              ? _encodeSingleElement(arrayValues[i ~/ statementsPerArrayValue])
              : Uint8List(0),
        )
        ..add(lowerBounds[i % statementsPerArrayValue])
        ..add(upperBounds[i % statementsPerArrayValue]);
    }

    if (notInValues != null) {
      bindArgs.addAll(notInValues);
    }

    return bindArgs;
  }

  /// Returns an index that can be used to serve the provided target. Returns null if no index is configured.
  FieldIndex? _getFieldIndex(Target target) {
    hardAssert(_started, 'IndexManager not started');

    final TargetIndexMatcher targetIndexMatcher = TargetIndexMatcher(target);
    final String collectionGroup =
        target.collectionGroup ?? target.path.getLastSegment();

    final List<FieldIndex> collectionIndexes = getFieldIndexes(collectionGroup);
    if (collectionIndexes.isEmpty) {
      return null;
    }

    // Return the index with the most number of segments.
    FieldIndex? matchingIndex;
    for (final FieldIndex fieldIndex in collectionIndexes) {
      final bool matches = targetIndexMatcher.servedByIndex(fieldIndex);
      if (matches &&
          (matchingIndex == null ||
              fieldIndex.segments.length > matchingIndex.segments.length)) {
        matchingIndex = fieldIndex;
      }
    }
    return matchingIndex;
  }

  /// Returns the byte encoded form of the directional values in the field index. Returns null if the document does
  /// not have all fields specified in the index.
  Uint8List? _encodeDirectionalElements(
    FieldIndex fieldIndex,
    Document document,
  ) {
    final IndexByteEncoder encoder = IndexByteEncoder();
    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      final FieldValue? field = document.getField(segment.fieldPath);
      if (field == null) {
        return null;
      }
      FirestoreIndexValueWriter.instance.writeIndexValue(
        field,
        encoder.forKind(segment.kind),
      );
    }
    return encoder.encodedBytes;
  }

  /// Encodes a single value to the ascending index format.
  Uint8List _encodeSingleElement(FieldValue value) {
    final IndexByteEncoder encoder = IndexByteEncoder();
    FirestoreIndexValueWriter.instance.writeIndexValue(
      value,
      encoder.forKind(SegmentKind.ascending),
    );
    return encoder.encodedBytes;
  }

  /// Encodes the given field values (the position of a bound, or the values of a != / not-in filter) according to the
  /// specification in [target]. For IN queries, a list of possible values is returned.
  List<Uint8List>? _encodeValues(
    FieldIndex fieldIndex,
    Target target,
    List<FieldValue>? values,
  ) {
    if (values == null) {
      return null;
    }

    List<IndexByteEncoder> encoders = <IndexByteEncoder>[IndexByteEncoder()];

    final Iterator<FieldValue> position = values.iterator;
    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      position.moveNext();
      final FieldValue value = position.current;
      // The list is replaced while its previous value is iterated, as upstream does.
      for (final IndexByteEncoder encoder in List<IndexByteEncoder>.of(
        encoders,
      )) {
        if (_isInFilter(target, segment.fieldPath) && value is ArrayValue) {
          encoders = _expandIndexValues(encoders, segment, value);
        } else {
          FirestoreIndexValueWriter.instance.writeIndexValue(
            value,
            encoder.forKind(segment.kind),
          );
        }
      }
    }
    return <Uint8List>[
      for (final IndexByteEncoder encoder in encoders) encoder.encodedBytes,
    ];
  }

  /// Creates a separate encoder for each element of an array.
  ///
  /// The method appends each value to all existing encoders (for example, filter("a", "==", "a1").filter("b", "in",
  /// ["b1", "b2"]) becomes ["a1,b1", "a1,b2"]). A list of new encoders is returned.
  List<IndexByteEncoder> _expandIndexValues(
    List<IndexByteEncoder> encoders,
    IndexSegment segment,
    ArrayValue value,
  ) {
    final List<IndexByteEncoder> prefixes = List<IndexByteEncoder>.of(encoders);
    final List<IndexByteEncoder> results = <IndexByteEncoder>[];
    for (final FieldValue arrayElement in value.internalValue) {
      for (final IndexByteEncoder prefix in prefixes) {
        final IndexByteEncoder clonedEncoder = IndexByteEncoder()
          ..seed(prefix.encodedBytes);
        FirestoreIndexValueWriter.instance.writeIndexValue(
          arrayElement,
          clonedEncoder.forKind(segment.kind),
        );
        results.add(clonedEncoder);
      }
    }
    return results;
  }

  bool _isInFilter(Target target, FieldPath fieldPath) {
    for (final Filter filter in target.filters) {
      if (filter is FieldFilter && filter.field == fieldPath) {
        final FilterOperator operator = filter.operator;
        if (operator == FilterOperator.IN ||
            operator == FilterOperator.NOT_IN) {
          return true;
        }
      }
    }
    return false;
  }

  Uint8List _encodeSegments(FieldIndex fieldIndex) {
    return _serializer
        .encodeFieldIndexSegments(fieldIndex.segments)
        .writeToBuffer();
  }

  @override
  Future<void> updateCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
  ) async {
    hardAssert(_started, 'IndexManager not started');

    ++_memoizedMaxSequenceNumber;
    for (final FieldIndex fieldIndex in getFieldIndexes(collectionGroup)) {
      final FieldIndex updatedIndex = FieldIndex(
        fieldIndex.indexId,
        fieldIndex.collectionGroup,
        fieldIndex.segments,
        IndexState(_memoizedMaxSequenceNumber, offset),
      );
      await db.execute(
        'REPLACE INTO index_state (index_id, uid,  sequence_number, '
        'read_time_seconds, read_time_nanos, document_key, largest_batch_id) '
        'VALUES(?, ?, ?, ?, ?, ?, ?)',
        <Object>[
          fieldIndex.indexId,
          _uid,
          _memoizedMaxSequenceNumber,
          offset.readTime.timestamp.seconds,
          offset.readTime.timestamp.nanoseconds,
          EncodedPath.encode(offset.documentKey.path),
          offset.largestBatchId,
        ],
      );
      _memoizeIndex(updatedIndex);
    }
  }
}
