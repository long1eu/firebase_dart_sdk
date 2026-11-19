part of 'indexeddb_persistence_web.dart';

/// Whether the JS SDK writes the bytes of index entries as strings in this browser (`encodeKeySafeBytes`): it does in
/// Safari and WebKit (https://bugs.webkit.org/show_bug.cgi?id=292721), with the user agent test of `isSafariOrWebkit`
/// of `@firebase/util`. Both SDKs have to make the same choice: a range over `Uint8Array` keys does not reach string
/// keys (IndexedDB sorts strings before binary keys).
final bool _keySafeStrings = () {
  try {
    final String agent = web.window.navigator.userAgent;
    return agent.isNotEmpty &&
        (agent.contains('Safari') || agent.contains('WebKit')) &&
        !agent.contains('Chrome');
  } catch (_) {
    return false;
  }
}();

/// `encodeKeySafeBytes`: [bytes] as a `Uint8Array`, or in Safari and WebKit as a string of one character per byte.
JSAny _keySafe(Uint8List bytes) =>
    _keySafeStrings ? String.fromCharCodes(bytes).toJS : bytes.toJS;

/// `decodeKeySafeBytes`: the bytes of a `Uint8Array` or of a string of one character per byte (written by a JS SDK in
/// Safari), whatever this browser is.
Uint8List _fromKeySafe(JSAny? value) {
  if (value.isUndefinedOrNull) {
    return Uint8List(0);
  }
  if (value.isA<JSString>()) {
    final String text = (value! as JSString).toDart;
    return Uint8List.fromList(<int>[
      for (int i = 0; i < text.length; i++) text.codeUnitAt(i) & 0xff,
    ]);
  }
  if (value.isA<JSUint8Array>()) {
    return Uint8List.fromList((value! as JSUint8Array).toDart);
  }
  if (value.isA<JSArrayBuffer>()) {
    return Uint8List.fromList((value! as JSArrayBuffer).toDart.asUint8List());
  }
  return Uint8List(0);
}

/// An index entry in the order of the JS SDK's `indexEntryComparator`: index id, array value, directional value, then
/// document key (the Android order, [IndexEntry], puts the document key second).
class _JsIndexEntry {
  _JsIndexEntry(
    this.indexId,
    this.documentKey,
    this.arrayValue,
    this.directionalValue,
  );

  final int indexId;
  final DocumentKey documentKey;
  final Uint8List arrayValue;
  final Uint8List directionalValue;

  static int compare(_JsIndexEntry left, _JsIndexEntry right) {
    int cmp = left.indexId.compareTo(right.indexId);
    if (cmp != 0) {
      return cmp;
    }
    cmp = compareByteArrays(left.arrayValue, right.arrayValue);
    if (cmp != 0) {
      return cmp;
    }
    cmp = compareByteArrays(left.directionalValue, right.directionalValue);
    if (cmp != 0) {
      return cmp;
    }
    return left.documentKey.compareTo(right.documentKey);
  }

  /// The entry that sorts right after this directional value (`successor`).
  _JsIndexEntry successor() {
    final int length = directionalValue.length;
    final bool grow = length == 0 || directionalValue[length - 1] == 255;
    final Uint8List next = Uint8List(grow ? length + 1 : length)
      ..setRange(0, length, directionalValue);
    if (grow) {
      next[length] = 0;
    } else {
      next[length - 1]++;
    }
    return _JsIndexEntry(indexId, documentKey, arrayValue, next);
  }

  /// `dbIndexEntryKey`: `[indexId, uid, arrayValue, directionalValue, orderedDocumentKey, documentKey]`.
  JSAny key(String uid, Uint8List orderedDocumentKey, DocumentKey key) =>
      <JSAny>[
        indexId.toJS,
        uid.toJS,
        _keySafe(arrayValue),
        _keySafe(directionalValue),
        _keySafe(orderedDocumentKey),
        <JSString>[
          for (final String segment in key.path.segments) segment.toJS,
        ].toJS,
      ].toJS;
}

/// The index manager on `collectionParents`, `indexConfiguration`, `indexState` and `indexEntries`
/// (`indexeddb_index_manager.ts`), with the JS SDK's rows and index value encoding ([JsIndexValueWriter]): indexes
/// configured, filled or created by either SDK are used by the other.
///
/// PORTING NOTE: the JS SDK reads the configuration and states in every call because other tabs change them. One
/// client at a time has this database, so the indexes and this user's states are read at [start] and kept in memory,
/// as in the Android SDK (`SQLiteIndexManager`), whose synchronous methods this interface has.
class IndexedDbIndexManager extends IndexManager {
  IndexedDbIndexManager._(this._persistence, User? user)
    : _uid = user?.uid ?? '';

  static const String _tag = 'IndexedDbIndexManager';

  final WebIndexedDbPersistence _persistence;

  final String _uid;

  /// The entries already written, so that each one is written once per client (`collectionParentsCache` of the JS
  /// SDK).
  final MemoryCollectionParentIndex _written = MemoryCollectionParentIndex();

  final Map<Target, List<Target>> _targetToDnfSubTargets =
      <Target, List<Target>>{};

  final Map<String, Map<int, FieldIndex>> _memoizedIndexes =
      <String, Map<int, FieldIndex>>{};

  /// The indexes ordered by when they were last updated (and by collection group), as `getNextCollectionGroupToUpdate`
  /// of the JS SDK sorts them.
  final PriorityQueue<FieldIndex> _nextIndexToUpdate =
      PriorityQueue<FieldIndex>((FieldIndex l, FieldIndex r) {
        final int cmp = l.indexState.sequenceNumber.compareTo(
          r.indexState.sequenceNumber,
        );
        return cmp != 0 ? cmp : l.collectionGroup.compareTo(r.collectionGroup);
      });

  bool _started = false;
  int _memoizedMaxSequenceNumber = 0;

  _IdbTransaction get _transaction => _persistence._current;

  @override
  Future<void> start() async {
    final _IdbTransaction transaction = _transaction;
    _memoizedIndexes.clear();
    _nextIndexToUpdate.clear();
    _memoizedMaxSequenceNumber = 0;
    final List<Object?> states =
        (await transaction.read(
              'get the index states of "$_uid"',
              () => transaction
                  .store(DbStores.indexState)
                  .index(DbStores.indexStateSequenceNumberIndex)
                  .getAll(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[_uid, double.negativeInfinity]),
                      idbKey(<Object>[_uid, double.infinity]),
                    ),
                  ),
            ))!
            as List<Object?>;
    final Map<int, IndexState> indexStates = <int, IndexState>{
      for (final Object? row in states)
        if (row is Map && row['indexId'] is num)
          (row['indexId']! as num).toInt(): _decodeState(
            row.cast<String, Object?>(),
          ),
    };
    final List<Object?> configs =
        (await transaction.read(
              'get the index configuration',
              () => transaction.store(DbStores.indexConfiguration).getAll(),
            ))!
            as List<Object?>;
    for (final Object? row in configs) {
      if (row is! Map) {
        continue;
      }
      final FieldIndex? index = _decodeConfiguration(
        row.cast<String, Object?>(),
        indexStates,
      );
      if (index != null) {
        _memoizeIndex(index);
      }
    }
    _started = true;
  }

  /// `fromDbIndexConfiguration`, or null for a row this SDK can not read.
  static FieldIndex? _decodeConfiguration(
    Map<String, Object?> row,
    Map<int, IndexState> states,
  ) {
    final Object? id = row['indexId'];
    final Object? collectionGroup = row['collectionGroup'];
    final Object? fields = row['fields'];
    if (id is! num || collectionGroup is! String || fields is! List) {
      return null;
    }
    final List<IndexSegment> segments = <IndexSegment>[];
    for (final Object? field in fields) {
      if (field is! List ||
          field.length != 2 ||
          field[0] is! String ||
          field[1] is! num) {
        return null;
      }
      final int kind = (field[1]! as num).toInt();
      if (kind < 0 || kind >= SegmentKind.values.length) {
        return null;
      }
      segments.add(
        IndexSegment(
          FieldPath.fromServerFormat(field[0]! as String),
          SegmentKind.values[kind],
        ),
      );
    }
    return FieldIndex(
      id.toInt(),
      collectionGroup,
      segments,
      states[id.toInt()] ?? FieldIndex.initialState,
    );
  }

  static IndexState _decodeState(Map<String, Object?> row) {
    final Object? documentKey = row['documentKey'];
    return IndexState(
      (row['sequenceNumber'] as num?)?.toInt() ?? 0,
      IndexOffset(
        row['readTime'] is Map
            ? fromDbTimestamp(row['readTime'])
            : SnapshotVersion.none,
        documentKey is String
            ? DocumentKey.fromPath(decodeJsResourcePath(documentKey))
            : DocumentKey.empty(),
        (row['largestBatchId'] as num?)?.toInt() ??
            FieldIndex.initialLargestBatchId,
      ),
    );
  }

  /// `toDbIndexState`.
  Map<String, Object?> _stateRow(int indexId, IndexState state) =>
      <String, Object?>{
        'indexId': indexId,
        'uid': _uid,
        'sequenceNumber': state.sequenceNumber,
        'readTime': toDbTimestamp(state.offset.readTime),
        'documentKey': encodeJsResourcePath(state.offset.documentKey.path),
        'largestBatchId': state.offset.largestBatchId,
      };

  Future<void> _putState(
    _IdbTransaction transaction,
    int indexId,
    IndexState state,
  ) async {
    await transaction.request(
      'put the state of index $indexId',
      () => transaction
          .store(DbStores.indexState)
          .put(idbToJs(_stateRow(indexId, state))),
    );
  }

  void _memoizeIndex(FieldIndex fieldIndex) {
    final Map<int, FieldIndex> existing = _memoizedIndexes.putIfAbsent(
      fieldIndex.collectionGroup,
      () => <int, FieldIndex>{},
    );
    final FieldIndex? previous = existing[fieldIndex.indexId];
    if (previous != null) {
      _nextIndexToUpdate.remove(previous);
    }
    existing[fieldIndex.indexId] = fieldIndex;
    _nextIndexToUpdate.add(fieldIndex);
    _memoizedMaxSequenceNumber = max(
      _memoizedMaxSequenceNumber,
      fieldIndex.indexState.sequenceNumber,
    );
  }

  // Collection parents

  @override
  Future<void> addToCollectionParentIndex(ResourcePath collectionPath) =>
      _persistence._write(
        'Add a collection parent',
        () => _addToCollectionParentIndex(collectionPath),
      );

  Future<void> _addToCollectionParentIndex(ResourcePath collectionPath) async {
    hardAssert(collectionPath.length % 2 == 1, 'Expected a collection path.');
    if (_written.contains(collectionPath)) {
      return;
    }
    final _IdbTransaction transaction = _transaction;
    final JSAny? row = idbToJs(<String, Object?>{
      'collectionId': collectionPath.getLastSegment(),
      'parent': encodeJsResourcePath(collectionPath.popLast()),
    });
    await transaction.request(
      'put the collection parent of $collectionPath',
      () => transaction.store(DbStores.collectionParents).put(row),
    );
    _written.add(collectionPath);
  }

  @override
  Future<List<ResourcePath>> getCollectionParents(String collectionId) async {
    final _IdbTransaction transaction = _transaction;
    final List<Object?> rows =
        (await transaction.read(
              'get the parents of $collectionId',
              () => transaction
                  .store(DbStores.collectionParents)
                  .getAll(
                    web.IDBKeyRange.bound(
                      idbKey(<Object>[collectionId, '']),
                      idbKey(<Object>[immediateSuccessorOf(collectionId), '']),
                      false,
                      true,
                    ),
                  ),
            ))!
            as List<Object?>;
    return <ResourcePath>[
      for (final Object? row in rows)
        if (row is Map && row['collectionId'] == collectionId)
          decodeJsResourcePath(row['parent']! as String),
    ];
  }

  // Index configuration

  @override
  Future<void> addFieldIndex(FieldIndex index) =>
      _persistence._write('Add a field index', () => _addFieldIndex(index));

  Future<void> _addFieldIndex(FieldIndex index) async {
    hardAssert(_started, 'IndexManager not started');
    final _IdbTransaction transaction = _transaction;
    // `indexId` is left out: the key generator of the store assigns it, as in the JS SDK.
    final JSAny? id = await transaction.request(
      'add an index on ${index.collectionGroup}',
      () => transaction
          .store(DbStores.indexConfiguration)
          .add(
            idbToJs(<String, Object?>{
              'collectionGroup': index.collectionGroup,
              'fields': <Object?>[
                for (final IndexSegment segment in index.segments)
                  <Object?>[
                    segment.fieldPath.canonicalString,
                    segment.kind.index,
                  ],
              ],
            }),
          ),
    );
    final int indexId = (id! as JSNumber).toDartInt;
    // As the JS SDK: the state of the new index is stored for this user.
    await _putState(transaction, indexId, index.indexState);
    _memoizeIndex(
      FieldIndex(
        indexId,
        index.collectionGroup,
        index.segments,
        index.indexState,
      ),
    );
  }

  /// The keys `[indexId]` to `[indexId + 1]` of the stores keyed by index id first.
  static JSAny _indexRange(int indexId) => web.IDBKeyRange.bound(
    idbKey(<Object>[indexId]),
    idbKey(<Object>[indexId + 1]),
    false,
    true,
  );

  @override
  Future<void> deleteFieldIndex(FieldIndex index) => _persistence._write(
    'Delete a field index',
    () => _deleteFieldIndex(index),
  );

  Future<void> _deleteFieldIndex(FieldIndex index) async {
    final _IdbTransaction transaction = _transaction;
    await Future.wait(<Future<Object?>>[
      transaction.request(
        'delete index ${index.indexId}',
        () => transaction
            .store(DbStores.indexConfiguration)
            .delete(index.indexId.toJS),
      ),
      transaction.request(
        'delete the states of index ${index.indexId}',
        () => transaction
            .store(DbStores.indexState)
            .delete(_indexRange(index.indexId)),
      ),
      transaction.request(
        'delete the entries of index ${index.indexId}',
        () => transaction
            .store(DbStores.indexEntries)
            .delete(_indexRange(index.indexId)),
      ),
    ]);
    final FieldIndex? memoized = _memoizedIndexes[index.collectionGroup]
        ?.remove(index.indexId);
    if (memoized != null) {
      _nextIndexToUpdate.remove(memoized);
    }
  }

  @override
  Future<void> deleteAllFieldIndexes() => _persistence._write(
    'Delete all field indexes',
    () => _deleteAllFieldIndexes(),
  );

  Future<void> _deleteAllFieldIndexes() async {
    final _IdbTransaction transaction = _transaction;
    await Future.wait(<Future<Object?>>[
      for (final String store in const <String>[
        DbStores.indexConfiguration,
        DbStores.indexEntries,
        DbStores.indexState,
      ])
        transaction.request(
          'clear $store',
          () => transaction.store(store).clear(),
        ),
    ]);
    _memoizedIndexes.clear();
    _nextIndexToUpdate.clear();
  }

  @override
  Future<void> createTargetIndexes(Target target) => _persistence._write(
    'Create target indexes',
    () => _createTargetIndexes(target),
  );

  Future<void> _createTargetIndexes(Target target) async {
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
  List<FieldIndex> getFieldIndexes([String? collectionGroup]) {
    if (collectionGroup == null) {
      return <FieldIndex>[
        for (final Map<int, FieldIndex> indexes in _memoizedIndexes.values)
          ...indexes.values,
      ];
    }
    hardAssert(_started, 'IndexManager not started');
    final Map<int, FieldIndex>? indexes = _memoizedIndexes[collectionGroup];
    return indexes == null ? const <FieldIndex>[] : indexes.values.toList();
  }

  @override
  String? getNextCollectionGroupToUpdate() {
    hardAssert(_started, 'IndexManager not started');
    return _nextIndexToUpdate.isEmpty
        ? null
        : _nextIndexToUpdate.first.collectionGroup;
  }

  @override
  Future<void> updateCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
  ) => _persistence._write(
    'Update the index state of a collection group',
    () => _updateCollectionGroup(collectionGroup, offset),
  );

  Future<void> _updateCollectionGroup(
    String collectionGroup,
    IndexOffset offset,
  ) async {
    hardAssert(_started, 'IndexManager not started');
    final _IdbTransaction transaction = _transaction;
    // `getNextSequenceNumber`: one more than the highest sequence number of this user's states.
    final int sequenceNumber = ++_memoizedMaxSequenceNumber;
    for (final FieldIndex fieldIndex in getFieldIndexes(collectionGroup)) {
      final IndexState state = IndexState(sequenceNumber, offset);
      await _putState(transaction, fieldIndex.indexId, state);
      _memoizeIndex(
        FieldIndex(
          fieldIndex.indexId,
          fieldIndex.collectionGroup,
          fieldIndex.segments,
          state,
        ),
      );
    }
  }

  // Targets

  List<Target> _getSubTargets(Target target) {
    final List<Target>? memoized = _targetToDnfSubTargets[target];
    if (memoized != null) {
      return memoized;
    }
    final List<Target> subTargets = <Target>[];
    if (target.filters.isEmpty) {
      subTargets.add(target);
    } else {
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

  /// The index with the most segments that serves [target], or null.
  FieldIndex? _getFieldIndex(Target target) {
    hardAssert(_started, 'IndexManager not started');
    final TargetIndexMatcher matcher = TargetIndexMatcher(target);
    final String collectionGroup =
        target.collectionGroup ?? target.path.getLastSegment();
    FieldIndex? result;
    for (final FieldIndex candidate in getFieldIndexes(collectionGroup)) {
      if (matcher.servedByIndex(candidate) &&
          (result == null ||
              candidate.segments.length > result.segments.length)) {
        result = candidate;
      }
    }
    return result;
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
    if (target.hasLimit && subTargets.length > 1 && result == IndexType.full) {
      return IndexType.partial;
    }
    return result;
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
  IndexOffset getMinOffsetForTarget(Target target) {
    return _getMinOffset(<FieldIndex>[
      for (final Target subTarget in _getSubTargets(target))
        ?_getFieldIndex(subTarget),
    ]);
  }

  // Encoding

  /// The directional values of [document] for [fieldIndex], or null when the document lacks one of the fields
  /// (`encodeDirectionalElements`).
  static Uint8List? _encodeDirectionalElements(
    FieldIndex fieldIndex,
    Document document,
  ) {
    final JsIndexByteEncoder encoder = JsIndexByteEncoder();
    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      final FieldValue? field = document.getField(segment.fieldPath);
      if (field == null) {
        return null;
      }
      JsIndexValueWriter.instance.writeIndexValue(
        field,
        encoder.forKind(segment.kind),
      );
    }
    return encoder.encodedBytes;
  }

  static Uint8List _encodeSingleElement(FieldValue value) {
    final JsIndexByteEncoder encoder = JsIndexByteEncoder();
    JsIndexValueWriter.instance.writeIndexValue(
      value,
      encoder.forKind(SegmentKind.ascending),
    );
    return encoder.encodedBytes;
  }

  /// `fieldIndexGetKeyOrder`: the direction of the last directional segment, ascending without one.
  static SegmentKind _keyOrder(FieldIndex fieldIndex) {
    final List<IndexSegment> segments = fieldIndex.directionalSegments;
    return segments.isEmpty ? SegmentKind.ascending : segments.last.kind;
  }

  /// The document key encoded in the order of the index (`encodeDirectionalKey`).
  static Uint8List _encodeDirectionalKey(
    FieldIndex fieldIndex,
    DocumentKey key,
  ) {
    final JsIndexByteEncoder encoder = JsIndexByteEncoder();
    JsIndexValueWriter.instance.writeDocumentKey(
      key,
      encoder.forKind(_keyOrder(fieldIndex)),
    );
    return encoder.encodedBytes;
  }

  /// `encodeValues`: the encoded [values] for the directional segments of [fieldIndex]; for an `in` or `not-in`
  /// filter, one per element. Empty for no values.
  List<Uint8List> _encodeValues(
    FieldIndex fieldIndex,
    Target target,
    List<FieldValue>? values,
  ) {
    if (values == null) {
      return const <Uint8List>[];
    }
    List<JsIndexByteEncoder> encoders = <JsIndexByteEncoder>[
      JsIndexByteEncoder(),
    ];
    int valueIndex = 0;
    for (final IndexSegment segment in fieldIndex.directionalSegments) {
      final FieldValue value = values[valueIndex++];
      // The list is replaced while the previous one is iterated, as upstream does.
      for (final JsIndexByteEncoder encoder in List<JsIndexByteEncoder>.of(
        encoders,
      )) {
        if (_isInFilter(target, segment.fieldPath) && value is ArrayValue) {
          encoders = _expandIndexValues(encoders, segment, value);
        } else {
          JsIndexValueWriter.instance.writeIndexValue(
            value,
            encoder.forKind(segment.kind),
          );
        }
      }
    }
    return <Uint8List>[
      for (final JsIndexByteEncoder encoder in encoders) encoder.encodedBytes,
    ];
  }

  static List<JsIndexByteEncoder> _expandIndexValues(
    List<JsIndexByteEncoder> encoders,
    IndexSegment segment,
    ArrayValue value,
  ) {
    final List<JsIndexByteEncoder> prefixes = List<JsIndexByteEncoder>.of(
      encoders,
    );
    final List<JsIndexByteEncoder> results = <JsIndexByteEncoder>[];
    for (final FieldValue element in value.internalValue) {
      for (final JsIndexByteEncoder prefix in prefixes) {
        final JsIndexByteEncoder cloned = JsIndexByteEncoder()
          ..seed(prefix.encodedBytes);
        JsIndexValueWriter.instance.writeIndexValue(
          element,
          cloned.forKind(segment.kind),
        );
        results.add(cloned);
      }
    }
    return results;
  }

  static bool _isInFilter(Target target, FieldPath fieldPath) {
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

  // Entries

  /// `computeIndexEntries`: none for a missing document or one without every field of the index.
  static SplayTreeSet<_JsIndexEntry> _computeIndexEntries(
    DocumentKey key,
    MaybeDocument? maybeDocument,
    FieldIndex fieldIndex,
  ) {
    final SplayTreeSet<_JsIndexEntry> result = SplayTreeSet<_JsIndexEntry>(
      _JsIndexEntry.compare,
    );
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
            _JsIndexEntry(
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
        _JsIndexEntry(fieldIndex.indexId, key, Uint8List(0), directionalValue),
      );
    }
    return result;
  }

  Future<SplayTreeSet<_JsIndexEntry>> _getExistingIndexEntries(
    _IdbTransaction transaction,
    DocumentKey key,
    FieldIndex fieldIndex,
  ) async {
    final SplayTreeSet<_JsIndexEntry> result = SplayTreeSet<_JsIndexEntry>(
      _JsIndexEntry.compare,
    );
    final JSAny? rows = await transaction.request(
      'get the index entries of $key',
      () => transaction
          .store(DbStores.indexEntries)
          .index(DbStores.indexEntriesDocumentKeyIndex)
          .getAll(
            web.IDBKeyRange.only(
              <JSAny>[
                fieldIndex.indexId.toJS,
                _uid.toJS,
                _keySafe(_encodeDirectionalKey(fieldIndex, key)),
              ].toJS,
            ),
          ),
    );
    for (final JSAny? row in (rows! as JSArray<JSAny?>).toDart) {
      final JSObject entry = row! as JSObject;
      result.add(
        _JsIndexEntry(
          fieldIndex.indexId,
          key,
          _fromKeySafe(entry.getProperty('arrayValue'.toJS)),
          _fromKeySafe(entry.getProperty('directionalValue'.toJS)),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> updateIndexEntries(Map<DocumentKey, MaybeDocument?> documents) =>
      _persistence._write(
        'Update index entries',
        () => _updateIndexEntries(documents),
      );

  Future<void> _updateIndexEntries(
    Map<DocumentKey, MaybeDocument?> documents,
  ) async {
    hardAssert(_started, 'IndexManager not started');
    final _IdbTransaction transaction = _transaction;
    for (final MapEntry<DocumentKey, MaybeDocument?> entry
        in documents.entries) {
      for (final FieldIndex fieldIndex in getFieldIndexes(
        entry.key.collectionGroup,
      )) {
        final SplayTreeSet<_JsIndexEntry> existing =
            await _getExistingIndexEntries(transaction, entry.key, fieldIndex);
        final SplayTreeSet<_JsIndexEntry> updated = _computeIndexEntries(
          entry.key,
          entry.value,
          fieldIndex,
        );
        await _updateEntries(
          transaction,
          entry.key,
          fieldIndex,
          existing,
          updated,
        );
      }
    }
  }

  /// Deletes the entries of [existing] that are not in [updated] and adds the others (`updateEntries`).
  Future<void> _updateEntries(
    _IdbTransaction transaction,
    DocumentKey key,
    FieldIndex fieldIndex,
    SplayTreeSet<_JsIndexEntry> existing,
    SplayTreeSet<_JsIndexEntry> updated,
  ) async {
    final List<_JsIndexEntry> removed = <_JsIndexEntry>[
      for (final _JsIndexEntry entry in existing)
        if (!updated.contains(entry)) entry,
    ];
    final List<_JsIndexEntry> added = <_JsIndexEntry>[
      for (final _JsIndexEntry entry in updated)
        if (!existing.contains(entry)) entry,
    ];
    if (removed.isEmpty && added.isEmpty) {
      return;
    }
    Log.d(_tag, "Updating index entries for document '$key'");
    final Uint8List orderedKey = _encodeDirectionalKey(fieldIndex, key);
    final JSArray<JSString> segments = <JSString>[
      for (final String segment in key.path.segments) segment.toJS,
    ].toJS;
    await Future.wait(<Future<Object?>>[
      for (final _JsIndexEntry entry in removed)
        transaction.request(
          'delete an index entry of $key',
          () => transaction
              .store(DbStores.indexEntries)
              .delete(entry.key(_uid, orderedKey, key)),
        ),
      for (final _JsIndexEntry entry in added)
        transaction.request(
          'put an index entry of $key',
          () => transaction
              .store(DbStores.indexEntries)
              .put(
                JSObject()
                  ..setProperty('indexId'.toJS, entry.indexId.toJS)
                  ..setProperty('uid'.toJS, _uid.toJS)
                  ..setProperty('arrayValue'.toJS, _keySafe(entry.arrayValue))
                  ..setProperty(
                    'directionalValue'.toJS,
                    _keySafe(entry.directionalValue),
                  )
                  ..setProperty('orderedDocumentKey'.toJS, _keySafe(orderedKey))
                  ..setProperty('documentKey'.toJS, segments),
              ),
        ),
    ]);
  }

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
    final SplayTreeSet<_JsIndexEntry> existing = await _getExistingIndexEntries(
      _transaction,
      document.key,
      fieldIndex,
    );
    final SplayTreeSet<_JsIndexEntry> computed = _computeIndexEntries(
      document.key,
      document,
      fieldIndex,
    );
    return existing.isNotEmpty &&
        existing.length == computed.length &&
        existing.every(computed.contains);
  }

  // Queries

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
    final _IdbTransaction transaction = _transaction;
    final Set<DocumentKey> found = <DocumentKey>{};
    final List<DocumentKey> result = <DocumentKey>[];
    for (final (Target subTarget, FieldIndex fieldIndex) in indexes) {
      if (Log.isDebugEnabled) {
        Log.d(_tag, "Using index '$fieldIndex' to execute '$subTarget'");
      }
      final Bound lowerBound = subTarget.getLowerBound(fieldIndex);
      final Bound upperBound = subTarget.getUpperBound(fieldIndex);
      final List<JSAny> ranges = _generateIndexRanges(
        fieldIndex.indexId,
        subTarget.getArrayValues(fieldIndex),
        _encodeValues(fieldIndex, subTarget, lowerBound.position),
        lowerBound.inclusive,
        _encodeValues(fieldIndex, subTarget, upperBound.position),
        upperBound.inclusive,
        _encodeValues(
          fieldIndex,
          subTarget,
          subTarget.getNotInValues(fieldIndex),
        ),
      );
      for (final JSAny range in ranges) {
        // `loadFirst(range, target.limit)`.
        final JSAny? rows = await transaction.request(
          'scan index ${fieldIndex.indexId}',
          () => target.hasLimit
              ? transaction
                    .store(DbStores.indexEntries)
                    .getAll(range, target.limit)
              : transaction.store(DbStores.indexEntries).getAll(range),
        );
        for (final JSAny? row in (rows! as JSArray<JSAny?>).toDart) {
          final JSAny? path = (row! as JSObject).getProperty(
            'documentKey'.toJS,
          );
          final DocumentKey key = DocumentKey.fromSegments(<String>[
            for (final JSAny? segment in (path! as JSArray<JSAny?>).toDart)
              (segment! as JSString).toDart,
          ]);
          if (found.add(key)) {
            result.add(key);
          }
        }
      }
    }
    Log.d(_tag, 'Index scan returned ${result.length} documents');
    return result;
  }

  /// `generateIndexRanges`: one scan per array value and bound, each split around the `not-in` values.
  ///
  /// PORTING NOTE: the JS SDK picks the array value of scan `i` with `i / scansPerArrayElement`, a fraction when there
  /// is more than one bound per array value (an array-contains-any combined with an `in`), and fails then; the index
  /// is an integer division here, as in the Android SDK.
  List<JSAny> _generateIndexRanges(
    int indexId,
    List<FieldValue>? arrayValues,
    List<Uint8List> lowerBounds,
    bool lowerInclusive,
    List<Uint8List> upperBounds,
    bool upperInclusive,
    List<Uint8List> notInValues,
  ) {
    final int arrayCount = arrayValues?.length ?? 1;
    final int totalScans =
        arrayCount * max(lowerBounds.length, upperBounds.length);
    final int scansPerArrayElement = totalScans ~/ arrayCount;
    final List<JSAny> ranges = <JSAny>[];
    for (int i = 0; i < totalScans; ++i) {
      final Uint8List arrayValue = arrayValues != null
          ? _encodeSingleElement(arrayValues[i ~/ scansPerArrayElement])
          : Uint8List(0);
      final _JsIndexEntry lower = _boundEntry(
        indexId,
        arrayValue,
        lowerBounds[i % scansPerArrayElement],
      );
      final _JsIndexEntry upper = _boundEntry(
        indexId,
        arrayValue,
        upperBounds[i % scansPerArrayElement],
      );
      ranges.addAll(
        _createRange(
          lowerInclusive ? lower : lower.successor(),
          upperInclusive ? upper.successor() : upper,
          <_JsIndexEntry>[
            for (final Uint8List notIn in notInValues)
              _boundEntry(indexId, arrayValue, notIn),
          ],
        ),
      );
    }
    return ranges;
  }

  static _JsIndexEntry _boundEntry(
    int indexId,
    Uint8List arrayValue,
    Uint8List directionalValue,
  ) =>
      _JsIndexEntry(indexId, DocumentKey.empty(), arrayValue, directionalValue);

  /// `createRange`: the range from [lower] to [upper] without the [notInValues]. No range at all when two bounds
  /// cross, as in the JS SDK.
  List<JSAny> _createRange(
    _JsIndexEntry lower,
    _JsIndexEntry upper,
    List<_JsIndexEntry> notInValues,
  ) {
    final List<_JsIndexEntry> sorted = List<_JsIndexEntry>.of(notInValues)
      ..sort(_JsIndexEntry.compare);
    final List<_JsIndexEntry> unique = <_JsIndexEntry>[
      for (int i = 0; i < sorted.length; i++)
        if (i == 0 || _JsIndexEntry.compare(sorted[i], sorted[i - 1]) != 0)
          sorted[i],
    ];
    final List<_JsIndexEntry> bounds = <_JsIndexEntry>[lower];
    for (final _JsIndexEntry notIn in unique) {
      final int cmpToLower = _JsIndexEntry.compare(notIn, lower);
      final int cmpToUpper = _JsIndexEntry.compare(notIn, upper);
      if (cmpToLower == 0) {
        bounds[0] = lower.successor();
      } else if (cmpToLower > 0 && cmpToUpper < 0) {
        bounds
          ..add(notIn)
          ..add(notIn.successor());
      } else if (cmpToUpper > 0) {
        break;
      }
    }
    bounds.add(upper);
    final List<JSAny> ranges = <JSAny>[];
    final Uint8List empty = Uint8List(0);
    for (int i = 0; i < bounds.length; i += 2) {
      if (_JsIndexEntry.compare(bounds[i], bounds[i + 1]) > 0) {
        return const <JSAny>[];
      }
      ranges.add(
        web.IDBKeyRange.bound(
          bounds[i].key(_uid, empty, DocumentKey.empty()),
          bounds[i + 1].key(_uid, empty, DocumentKey.empty()),
        ),
      );
    }
    return ranges;
  }
}
