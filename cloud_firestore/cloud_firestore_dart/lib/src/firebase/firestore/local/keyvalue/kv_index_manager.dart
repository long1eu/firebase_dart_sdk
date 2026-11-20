part of 'cache_store_persistence.dart';

/// The collection parent index (`collParent`) and the persistent cache indexes (field indexes) of the key-value cache.
/// The logic is that of the SQLite index manager (a port of `SQLiteIndexManager` of the Android SDK); the tables:
///
/// | table             | key after the table name                                     | value                     |
/// |-------------------|--------------------------------------------------------------|---------------------------|
/// | `indexConfig`     | index id                                                     | collection group, `Index` proto |
/// | `indexState`      | uid, index id                                                | sequence number, offset   |
/// | `indexEntry`      | index id, uid, array value, directional value, document key | (empty)                   |
/// | `docIndexEntry`   | index id, uid, document key, array value, directional value | (empty)                   |
///
/// The array and directional values are the bytes of the index value writer, written as [KvKeyWriter.bytesPart]
/// (ordered as SQLite orders BLOBs), so a bound of a query is a range of `indexEntry`.
///
/// The manager of the persistence ([CacheStorePersistence.indexManager]) only serves the collection parents; the
/// managers of the users ([CacheStorePersistence.getIndexManager]) serve both.
class _KvIndexManager implements IndexManager {
  _KvIndexManager(this._db, [this._uid]);

  static const String _tag = 'KvIndexManager';

  final CacheStorePersistence _db;

  /// The user of the field indexes; null for the manager of the persistence, which has none.
  final String? _uid;

  String get _user {
    final String? uid = _uid;
    hardAssert(
      uid != null,
      'The field indexes need the index manager of a user',
    );
    return uid!;
  }

  // The collection parents.

  /// The parents written by this session, so that a document write does not write its parent again.
  final Set<ResourcePath> _knownParents = <ResourcePath>{};

  /// The parents written by the running transaction: known once it committed.
  final Set<ResourcePath> _pendingParents = <ResourcePath>{};

  void _onCommitted() {
    _knownParents.addAll(_pendingParents);
    _pendingParents.clear();
  }

  void _onRolledBack() => _pendingParents.clear();

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) async {
    if (_uid != null) {
      // One memo for all users.
      return _db.indexManager.addToCollectionParentIndex(collectionPath);
    }
    hardAssert(collectionPath.length.isOdd, 'Expected a collection path.');
    if (_knownParents.contains(collectionPath) ||
        _pendingParents.contains(collectionPath)) {
      return;
    }
    await _db._tx.put(
      _key(_Table.collParent)
          .string(collectionPath.getLastSegment())
          .path(collectionPath.popLast())
          .bytes,
      _empty,
    );
    _pendingParents.add(collectionPath);
  }

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    final Uint8List prefix = _key(_Table.collParent).string(collectionId).bytes;
    return <ResourcePath>[
      for (final CacheStoreEntry entry in await _db._scanAll(prefix))
        (KvKeyReader(entry.key)
              ..string()
              ..string())
            .path(),
    ];
  }

  // The field indexes.

  /// The sub-targets of a target, one per term of its disjunctive normal form.
  final Map<Target, List<Target>> _targetToDnfSubTargets =
      <Target, List<Target>>{};

  final Map<String, Map<int, FieldIndex>> _memoizedIndexes =
      <String, Map<int, FieldIndex>>{};

  /// The indexes ordered by when they were last updated (and by collection group, to make the order deterministic).
  final PriorityQueue<FieldIndex> _nextIndexToUpdate =
      PriorityQueue<FieldIndex>((FieldIndex l, FieldIndex r) {
        final int bySequence = l.indexState.sequenceNumber.compareTo(
          r.indexState.sequenceNumber,
        );
        return bySequence != 0
            ? bySequence
            : l.collectionGroup.compareTo(r.collectionGroup);
      });

  bool _started = false;
  int _memoizedMaxIndexId = -1;
  int _memoizedMaxSequenceNumber = -1;

  Uint8List _configKey(int indexId) =>
      _key(_Table.indexConfig).integer(indexId).bytes;

  Uint8List _stateKey(int indexId) =>
      _key(_Table.indexState).string(_user).integer(indexId).bytes;

  @override
  Future<void> start() async {
    final String uid = _user;
    _memoizedIndexes.clear();
    _nextIndexToUpdate.clear();
    _memoizedMaxIndexId = -1;
    _memoizedMaxSequenceNumber = -1;

    final Map<int, IndexState> indexStates = <int, IndexState>{};
    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.indexState).string(uid).bytes,
    )) {
      final int indexId =
          (KvKeyReader(entry.key)
                ..string()
                ..string())
              .integer();
      final KvKeyReader reader = KvKeyReader(entry.value);
      final int sequenceNumber = reader.integer();
      final SnapshotVersion readTime = _readVersion(reader);
      final DocumentKey documentKey = DocumentKey.fromPath(reader.path());
      final int largestBatchId = reader.integer();
      indexStates[indexId] = IndexState(
        sequenceNumber,
        IndexOffset(readTime, documentKey, largestBatchId),
      );
    }

    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.indexConfig).bytes,
    )) {
      final int indexId = (KvKeyReader(entry.key)..string()).integer();
      final KvKeyReader reader = KvKeyReader(entry.value);
      final String collectionGroup = reader.string();
      final Uint8List bytes = reader.rest();
      final List<IndexSegment> segments = _db.serializer
          .decodeFieldIndexSegments(
            parseStoredProto('Index', () => admin.Index.fromBuffer(bytes)),
          );
      // An index created while another user was signed in has the initial state for this one.
      _memoizeIndex(
        FieldIndex(
          indexId,
          collectionGroup,
          segments,
          indexStates[indexId] ?? FieldIndex.initialState,
        ),
      );
    }
    _started = true;
    _db._startedIndexManagers.add(this);
  }

  @override
  Future<void> addFieldIndex(FieldIndex index) async {
    hardAssert(_started, 'IndexManager not started');
    final int indexId = _memoizedMaxIndexId + 1;
    final FieldIndex newIndex = FieldIndex(
      indexId,
      index.collectionGroup,
      index.segments,
      index.indexState,
    );
    await _db._tx.put(
      _configKey(indexId),
      KvKeyWriter()
          .string(newIndex.collectionGroup)
          .raw(
            _db.serializer
                .encodeFieldIndexSegments(newIndex.segments)
                .writeToBuffer(),
          )
          .bytes,
    );
    _memoizeIndex(newIndex);
  }

  @override
  Future<void> deleteFieldIndex(FieldIndex index) async {
    await _db._tx.delete(_configKey(index.indexId));
    // The entries and states of every user.
    for (final String table in <String>[
      _Table.indexEntry,
      _Table.docIndexEntry,
    ]) {
      for (final CacheStoreEntry entry in await _db._scanAll(
        _key(table).integer(index.indexId).bytes,
      )) {
        await _db._tx.delete(entry.key);
      }
    }
    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.indexState).bytes,
    )) {
      final KvKeyReader reader = KvKeyReader(entry.key)
        ..string()
        ..string();
      if (reader.integer() == index.indexId) {
        await _db._tx.delete(entry.key);
      }
    }
    _nextIndexToUpdate.remove(index);
    _memoizedIndexes[index.collectionGroup]?.remove(index.indexId);
  }

  @override
  Future<void> deleteAllFieldIndexes() async {
    for (final String table in <String>[
      _Table.indexConfig,
      _Table.indexState,
      _Table.indexEntry,
      _Table.docIndexEntry,
    ]) {
      for (final CacheStoreEntry entry in await _db._scanAll(
        _key(table).bytes,
      )) {
        await _db._tx.delete(entry.key);
      }
    }
    _nextIndexToUpdate.clear();
    _memoizedIndexes.clear();
  }

  @override
  Future<void> createTargetIndexes(Target target) async {
    hardAssert(_started, 'IndexManager not started');
    for (final Target subTarget in _getSubTargets(target)) {
      final IndexType type = getIndexType(subTarget);
      if (type == IndexType.none || type == IndexType.partial) {
        final FieldIndex? fieldIndex = TargetIndexMatcher(
          subTarget,
        ).buildTargetIndex();
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
    if (!_started) {
      // The manager of the persistence, or of a user before the local store started it: no field indexes.
      return;
    }
    for (final MapEntry<DocumentKey, MaybeDocument?> entry
        in documents.entries) {
      for (final FieldIndex fieldIndex in getFieldIndexes(
        entry.key.collectionGroup,
      )) {
        final SplayTreeSet<IndexEntry> existing =
            await _getExistingIndexEntries(entry.key, fieldIndex);
        final SplayTreeSet<IndexEntry> computed = _computeIndexEntries(
          entry.key,
          entry.value,
          fieldIndex,
        );
        if (!const IterableEquality<IndexEntry>().equals(existing, computed)) {
          Log.d(_tag, "Updating index entries for document '${entry.key}'");
          await diffCollections(
            existing,
            computed,
            (IndexEntry left, IndexEntry right) => left.compareTo(right),
            (IndexEntry added) => _addIndexEntry(entry.key, added),
            (IndexEntry removed) => _deleteIndexEntry(entry.key, removed),
          );
        }
      }
    }
  }

  @override
  List<FieldIndex> getFieldIndexes([String? collectionGroup]) {
    if (collectionGroup == null) {
      return <FieldIndex>[
        for (final Map<int, FieldIndex> indexes in _memoizedIndexes.values)
          ...indexes.values,
      ];
    }
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
      final IndexOffset offset = fieldIndex.indexState.offset;
      if (offset.compareTo(minOffset) < 0) {
        minOffset = offset;
      }
      maxBatchId = max(offset.largestBatchId, maxBatchId);
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
    if (_memoizedIndexes.isEmpty) {
      return IndexType.none;
    }
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
    // An OR query with a limit sorts and limits in memory: a partial index.
    if (target.hasLimit && subTargets.length > 1 && result == IndexType.full) {
      return IndexType.partial;
    }
    return result;
  }

  @override
  IndexOffset getMinOffsetForTarget(Target target) {
    return _getMinOffset(<FieldIndex>[
      for (final Target subTarget in _getSubTargets(target))
        ?_getFieldIndex(subTarget),
    ]);
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
      for (final Filter term in LogicUtils.getDnfTerms(
        CompositeFilter(target.filters, CompositeFilterOperator.and),
      )) {
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
    return _targetToDnfSubTargets[target] = subTargets;
  }

  void _memoizeIndex(FieldIndex fieldIndex) {
    final Map<int, FieldIndex> existingIndexes = _memoizedIndexes.putIfAbsent(
      fieldIndex.collectionGroup,
      () => <int, FieldIndex>{},
    );
    final FieldIndex? existing = existingIndexes[fieldIndex.indexId];
    if (existing != null) {
      _nextIndexToUpdate.remove(existing);
    }
    existingIndexes[fieldIndex.indexId] = fieldIndex;
    _nextIndexToUpdate.add(fieldIndex);
    _memoizedMaxIndexId = max(_memoizedMaxIndexId, fieldIndex.indexId);
    _memoizedMaxSequenceNumber = max(
      _memoizedMaxSequenceNumber,
      fieldIndex.indexState.sequenceNumber,
    );
  }

  /// The index entries of a document for [fieldIndex]. A missing document has none.
  SplayTreeSet<IndexEntry> _computeIndexEntries(
    DocumentKey key,
    MaybeDocument? maybeDocument,
    FieldIndex fieldIndex,
  ) {
    final SplayTreeSet<IndexEntry> result = SplayTreeSet<IndexEntry>();
    if (maybeDocument is! Document) {
      return result;
    }
    final Uint8List? directionalValue = _encodeDirectionalElements(
      fieldIndex,
      maybeDocument,
    );
    if (directionalValue == null) {
      return result;
    }
    final IndexSegment? arraySegment = fieldIndex.arraySegment;
    if (arraySegment != null) {
      final FieldValue? value = maybeDocument.getField(arraySegment.fieldPath);
      if (value is ArrayValue) {
        for (final FieldValue element in value.internalValue) {
          result.add(
            IndexEntry(
              fieldIndex.indexId,
              key,
              _encodeSingleElement(element),
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

  Uint8List _entryKey(DocumentKey key, IndexEntry entry) =>
      _key(_Table.indexEntry)
          .integer(entry.indexId)
          .string(_user)
          .bytesPart(entry.arrayValue)
          .bytesPart(entry.directionalValue)
          .documentKey(key)
          .bytes;

  Uint8List _documentEntryKey(DocumentKey key, IndexEntry entry) =>
      _key(_Table.docIndexEntry)
          .integer(entry.indexId)
          .string(_user)
          .documentKey(key)
          .bytesPart(entry.arrayValue)
          .bytesPart(entry.directionalValue)
          .bytes;

  Future<void> _addIndexEntry(DocumentKey key, IndexEntry entry) async {
    await _db._tx.put(_entryKey(key, entry), _empty);
    await _db._tx.put(_documentEntryKey(key, entry), _empty);
  }

  Future<void> _deleteIndexEntry(DocumentKey key, IndexEntry entry) async {
    await _db._tx.delete(_entryKey(key, entry));
    await _db._tx.delete(_documentEntryKey(key, entry));
  }

  Future<SplayTreeSet<IndexEntry>> _getExistingIndexEntries(
    DocumentKey documentKey,
    FieldIndex fieldIndex,
  ) async {
    final SplayTreeSet<IndexEntry> results = SplayTreeSet<IndexEntry>();
    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.docIndexEntry)
          .integer(fieldIndex.indexId)
          .string(_user)
          .documentKey(documentKey)
          .bytes,
    )) {
      final KvKeyReader reader = KvKeyReader(entry.key)
        ..string()
        ..integer()
        ..string()
        ..documentKey();
      final Uint8List arrayValue = reader.bytesPart();
      final Uint8List directionalValue = reader.bytesPart();
      results.add(
        IndexEntry(
          fieldIndex.indexId,
          documentKey,
          arrayValue,
          directionalValue,
        ),
      );
    }
    return results;
  }

  @override
  Future<List<DocumentKey>?> getDocumentsMatchingTarget(Target target) async {
    hardAssert(_started, 'IndexManager not started');

    final List<(Target, FieldIndex)> indexes = <(Target, FieldIndex)>[];
    for (final Target subTarget in _getSubTargets(target)) {
      final FieldIndex? fieldIndex = _getFieldIndex(subTarget);
      if (fieldIndex == null) {
        return null;
      }
      indexes.add((subTarget, fieldIndex));
    }

    // The entries of every range, as the union of the SQLite index manager reads them.
    final List<(Uint8List, DocumentKey)> found = <(Uint8List, DocumentKey)>[];
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
          "Using index '$fieldIndex' to execute '$subTarget' (Arrays: $arrayValues, Lower bound: $lowerBound, "
          'Upper bound: $upperBound)',
        );
      }

      final List<Uint8List> lowerBounds = _encodeValues(
        fieldIndex,
        subTarget,
        lowerBound.position,
      )!;
      final List<Uint8List> upperBounds = _encodeValues(
        fieldIndex,
        subTarget,
        upperBound.position,
      )!;
      final Set<String>? notIn = _encodeValues(
        fieldIndex,
        subTarget,
        notInValues,
      )?.map(_hex).toSet();

      final List<Uint8List> arrays = arrayValues == null
          ? <Uint8List>[Uint8List(0)]
          : <Uint8List>[
              for (final FieldValue value in arrayValues)
                _encodeSingleElement(value),
            ];
      final int boundCount = max(lowerBounds.length, upperBounds.length);
      for (final Uint8List array in arrays) {
        for (int i = 0; i < boundCount; i++) {
          final KvKeyWriter prefix = _key(
            _Table.indexEntry,
          ).integer(fieldIndex.indexId).string(_user).bytesPart(array);
          final Uint8List prefixBytes = prefix.bytes;
          final Uint8List lower = KvKeyWriter()
              .raw(prefixBytes)
              .bytesPart(lowerBounds[i % lowerBounds.length])
              .bytes;
          final Uint8List upper = KvKeyWriter()
              .raw(prefixBytes)
              .bytesPart(upperBounds[i % upperBounds.length])
              .bytes;
          final Uint8List start = lowerBound.inclusive
              ? lower
              : prefixEnd(lower);
          final Uint8List end = upperBound.inclusive ? prefixEnd(upper) : upper;
          if (compareCacheStoreKeys(start, end) >= 0) {
            continue;
          }
          await _db._scanPrefix(prefixBytes, from: start, (
            List<CacheStoreEntry> page,
          ) {
            for (final CacheStoreEntry entry in page) {
              if (compareCacheStoreKeys(entry.key, end) >= 0) {
                return false;
              }
              final KvKeyReader reader = KvKeyReader(entry.key)
                ..string()
                ..integer()
                ..string()
                ..bytesPart();
              final Uint8List directionalValue = reader.bytesPart();
              if (notIn != null && notIn.contains(_hex(directionalValue))) {
                continue;
              }
              found.add((directionalValue, reader.documentKey()));
            }
            return true;
          });
        }
      }
    }

    // ORDER BY directional_value, document_key (the canonical path) ASC or DESC as the key order (the direction
    // applies to the document key only, the directional values encode their own); then the distinct keys, and the
    // limit.
    final bool ascending = target.keyOrder == OrderByDirection.ascending;
    found.sort(((Uint8List, DocumentKey) a, (Uint8List, DocumentKey) b) {
      final int byValue = compareCacheStoreKeys(a.$1, b.$1);
      if (byValue != 0) {
        return byValue;
      }
      final int byKey = a.$2.path.canonicalString.compareTo(
        b.$2.path.canonicalString,
      );
      return ascending ? byKey : -byKey;
    });
    final Set<DocumentKey> result = <DocumentKey>{};
    for (final (Uint8List _, DocumentKey key) in found) {
      if (target.hasLimit && result.length >= target.limit) {
        break;
      }
      result.add(key);
    }
    Log.d(_tag, 'Index scan returned ${result.length} documents');
    return result.toList();
  }

  static String _hex(Uint8List bytes) => bytes.join(',');

  @override
  Future<bool> hasCurrentIndexEntries(Target target, Document document) async {
    hardAssert(_started, 'IndexManager not started');
    final List<Target> subTargets = _getSubTargets(target);
    if (subTargets.length != 1) {
      return false;
    }
    final FieldIndex? fieldIndex = _getFieldIndex(subTargets.first);
    if (fieldIndex == null) {
      return false;
    }
    final SplayTreeSet<IndexEntry> existing = await _getExistingIndexEntries(
      document.key,
      fieldIndex,
    );
    return existing.isNotEmpty &&
        const IterableEquality<IndexEntry>().equals(
          existing,
          _computeIndexEntries(document.key, document, fieldIndex),
        );
  }

  /// The index that serves [target] with the most segments, or null.
  FieldIndex? _getFieldIndex(Target target) {
    final TargetIndexMatcher matcher = TargetIndexMatcher(target);
    final String collectionGroup =
        target.collectionGroup ?? target.path.getLastSegment();
    FieldIndex? matching;
    for (final FieldIndex fieldIndex in getFieldIndexes(collectionGroup)) {
      if (matcher.servedByIndex(fieldIndex) &&
          (matching == null ||
              fieldIndex.segments.length > matching.segments.length)) {
        matching = fieldIndex;
      }
    }
    return matching;
  }

  /// The encoded directional values of a document, or null when it does not have every field of the index.
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

  Uint8List _encodeSingleElement(FieldValue value) {
    final IndexByteEncoder encoder = IndexByteEncoder();
    FirestoreIndexValueWriter.instance.writeIndexValue(
      value,
      encoder.forKind(SegmentKind.ascending),
    );
    return encoder.encodedBytes;
  }

  /// Encodes the position of a bound (or the values of a != / not-in filter); for IN filters, one encoding per value.
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

  List<IndexByteEncoder> _expandIndexValues(
    List<IndexByteEncoder> encoders,
    IndexSegment segment,
    ArrayValue value,
  ) {
    final List<IndexByteEncoder> prefixes = List<IndexByteEncoder>.of(encoders);
    final List<IndexByteEncoder> results = <IndexByteEncoder>[];
    for (final FieldValue element in value.internalValue) {
      for (final IndexByteEncoder prefix in prefixes) {
        final IndexByteEncoder cloned = IndexByteEncoder()
          ..seed(prefix.encodedBytes);
        FirestoreIndexValueWriter.instance.writeIndexValue(
          element,
          cloned.forKind(segment.kind),
        );
        results.add(cloned);
      }
    }
    return results;
  }

  bool _isInFilter(Target target, FieldPath fieldPath) {
    for (final Filter filter in target.filters) {
      if (filter is FieldFilter &&
          filter.field == fieldPath &&
          (filter.operator == FilterOperator.IN ||
              filter.operator == FilterOperator.NOT_IN)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> updateCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
  ) async {
    hardAssert(_started, 'IndexManager not started');
    ++_memoizedMaxSequenceNumber;
    for (final FieldIndex fieldIndex in getFieldIndexes(collectionGroup)) {
      await _db._tx.put(
        _stateKey(fieldIndex.indexId),
        _writeVersion(
          KvKeyWriter().integer(_memoizedMaxSequenceNumber),
          offset.readTime,
        ).path(offset.documentKey.path).integer(offset.largestBatchId).bytes,
      );
      _memoizeIndex(
        FieldIndex(
          fieldIndex.indexId,
          fieldIndex.collectionGroup,
          fieldIndex.segments,
          IndexState(_memoizedMaxSequenceNumber, offset),
        ),
      );
    }
  }

  @override
  Future<void> moveOffsetsBefore(
    String collectionGroup,
    SnapshotVersion readTime,
    DocumentKey documentKey,
  ) async {
    hardAssert(_started, 'IndexManager not started');
    final List<FieldIndex> fieldIndexes = getFieldIndexes(collectionGroup);
    if (fieldIndexes.isEmpty) {
      return;
    }
    final Map<int, FieldIndex> byId = <int, FieldIndex>{
      for (final FieldIndex fieldIndex in fieldIndexes)
        fieldIndex.indexId: fieldIndex,
    };
    final IndexOffset document = IndexOffset(
      readTime,
      documentKey,
      FieldIndex.initialLargestBatchId,
    );
    // The offsets of all users: each one backfills its own.
    for (final CacheStoreEntry entry in await _db._scanAll(
      _key(_Table.indexState).bytes,
    )) {
      final KvKeyReader keyReader = KvKeyReader(entry.key)..string();
      final String uid = keyReader.string();
      final int indexId = keyReader.integer();
      final FieldIndex? fieldIndex = byId[indexId];
      if (fieldIndex == null) {
        continue;
      }
      final KvKeyReader reader = KvKeyReader(entry.value);
      final int sequenceNumber = reader.integer();
      final IndexOffset offset = IndexOffset(
        _readVersion(reader),
        DocumentKey.fromPath(reader.path()),
        FieldIndex.initialLargestBatchId,
      );
      final int largestBatchId = reader.integer();
      if (offset.compareTo(document) < 0) {
        continue;
      }
      final IndexOffset movedBack = IndexOffset(
        readTime,
        DocumentKey.empty(),
        largestBatchId,
      );
      await _db._tx.put(
        entry.key,
        _writeVersion(
          KvKeyWriter().integer(sequenceNumber),
          movedBack.readTime,
        ).path(movedBack.documentKey.path).integer(largestBatchId).bytes,
      );
      if (uid == _uid) {
        _memoizeIndex(
          FieldIndex(
            fieldIndex.indexId,
            fieldIndex.collectionGroup,
            fieldIndex.segments,
            IndexState(sequenceNumber, movedBack),
          ),
        );
      }
    }
  }
}
