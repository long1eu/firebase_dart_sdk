// File created by
// Lung Razvan <long1eu>
// on 17/04/2020

part of cloud_firestore_dart_implementation;

/// Dart implementation for firestore [QueryPlatform]
class QueryDart extends QueryPlatform {
  /// Builds an instance of [QueryDart] delegating to a package:cloud_firestore
  /// [Query] to delegate queries to underlying firestore dart plugin
  QueryDart(
    this._firestore,
    this._path,
    this._dartQuery, {
    bool isCollectionGroup,
    List<dynamic> orderByKeys,
  })  : _isCollectionGroup = isCollectionGroup ?? false,
        _orderByKeys = orderByKeys ?? <dynamic>[],
        super(
          firestore: _firestore,
          pathComponents: _path.split('/'),
          isCollectionGroup: isCollectionGroup,
        );

  final dart.Query _dartQuery;
  final FirestorePlatform _firestore;
  final bool _isCollectionGroup;
  final String _path;
  final List<dynamic> _orderByKeys;

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
  }) {
    assert(_dartQuery != null);
    return _dartQuery
        .getSnapshots(includeMetadataChanges
            ? dart.MetadataChanges.include
            : dart.MetadataChanges.exclude)
        .map(_dartQuerySnapshotToQuerySnapshot);
  }

  @override
  Future<QuerySnapshotPlatform> getDocuments({
    Source source = Source.serverAndCache,
  }) async {
    assert(_dartQuery != null);
    return _dartQuerySnapshotToQuerySnapshot(await _dartQuery.get());
  }

  @override
  Map<String, dynamic> buildArguments() => <String, dynamic>{};

  @override
  QueryPlatform endAt(List<dynamic> values) => QueryDart(
        _firestore,
        _path,
        _dartQuery != null
            ? _dartQuery.endAt(CodecUtility.valueEncode(values))
            : null,
        isCollectionGroup: _isCollectionGroup,
      );

  @override
  QueryPlatform endAtDocument(DocumentSnapshotPlatform documentSnapshot) {
    assert(_dartQuery != null && _orderByKeys.isNotEmpty);
    return QueryDart(
        _firestore,
        _path,
        _dartQuery.endAt(
          CodecUtility.valueEncode(
            _orderByKeys
                .map<dynamic>((dynamic key) => documentSnapshot.data[key])
                .toList(),
          ),
        ),
        isCollectionGroup: _isCollectionGroup);
  }

  @override
  QueryPlatform endBefore(List<dynamic> values) => QueryDart(
        _firestore,
        _path,
        _dartQuery != null
            ? _dartQuery.endBefore(CodecUtility.valueEncode(values))
            : null,
        isCollectionGroup: _isCollectionGroup,
      );

  @override
  QueryPlatform endBeforeDocument(DocumentSnapshotPlatform documentSnapshot) {
    assert(_dartQuery != null && _orderByKeys.isNotEmpty);
    return QueryDart(
        _firestore,
        _path,
        _dartQuery.endBefore(
          CodecUtility.valueEncode(
            _orderByKeys
                .map<dynamic>((dynamic key) => documentSnapshot.data[key])
                .toList(),
          ),
        ),
        isCollectionGroup: _isCollectionGroup);
  }

  @override
  FirestorePlatform get firestore => _firestore;

  @override
  bool get isCollectionGroup => _isCollectionGroup;

  @override
  QueryPlatform limit(int length) => QueryDart(
        _firestore,
        _path,
        _dartQuery != null ? _dartQuery.limit(length) : null,
        orderByKeys: _orderByKeys,
        isCollectionGroup: _isCollectionGroup,
      );

  @override
  QueryPlatform orderBy(
    dynamic field, {
    bool descending = false,
  }) {
    dynamic usableField = field;
    if (field == FieldPath.documentId) {
      usableField = dart.FieldPath.documentId();
    }
    return QueryDart(
      _firestore,
      _path,
      _dartQuery.orderBy(usableField,
          descending ? dart.Direction.descending : dart.Direction.ascending),
      orderByKeys: _orderByKeys..add(usableField),
      isCollectionGroup: _isCollectionGroup,
    );
  }

  @override
  String get path => _path;

  @override
  List<String> get pathComponents => _path.split('/');

  @override
  CollectionReferencePlatform reference() => firestore.collection(_path);

  @override
  QueryPlatform startAfter(List<dynamic> values) => QueryDart(
        _firestore,
        _path,
        _dartQuery.startAfter(CodecUtility.valueEncode(values)),
        orderByKeys: _orderByKeys,
        isCollectionGroup: _isCollectionGroup,
      );

  @override
  QueryPlatform startAfterDocument(DocumentSnapshotPlatform documentSnapshot) {
    assert(_dartQuery != null && _orderByKeys.isNotEmpty);
    return QueryDart(
        _firestore,
        _path,
        _dartQuery.startAfter(
          CodecUtility.valueEncode(
            _orderByKeys
                .map<dynamic>((dynamic key) => documentSnapshot.data[key])
                .toList(),
          ),
        ),
        orderByKeys: _orderByKeys,
        isCollectionGroup: _isCollectionGroup);
  }

  @override
  QueryPlatform startAt(List<dynamic> values) => QueryDart(
        _firestore,
        _path,
        _dartQuery.startAt(CodecUtility.valueEncode(values)),
        orderByKeys: _orderByKeys,
        isCollectionGroup: _isCollectionGroup,
      );

  @override
  QueryPlatform startAtDocument(DocumentSnapshotPlatform documentSnapshot) {
    assert(_dartQuery != null && _orderByKeys.isNotEmpty);
    return QueryDart(
      _firestore,
      _path,
      _dartQuery.startAt(
        CodecUtility.valueEncode(
          _orderByKeys
              .map<dynamic>((dynamic key) => documentSnapshot.data[key])
              .toList(),
        ),
      ),
      orderByKeys: _orderByKeys,
      isCollectionGroup: _isCollectionGroup,
    );
  }

  @override
  QueryPlatform where(
    dynamic field, {
    dynamic isEqualTo,
    dynamic isLessThan,
    dynamic isLessThanOrEqualTo,
    dynamic isGreaterThan,
    dynamic isGreaterThanOrEqualTo,
    dynamic arrayContains,
    List<dynamic> arrayContainsAny,
    List<dynamic> whereIn,
    bool isNull,
  }) {
    assert(field is String || field is FieldPath,
        'Supported [field] types are [String] and [FieldPath].');
    assert(_dartQuery != null);
    dynamic usableField = CodecUtility.valueEncode(field);
    if (field == FieldPath.documentId) {
      usableField = dart.FieldPath.documentId();
    }
    dart.Query query = _dartQuery;

    if (isEqualTo != null) {
      query =
          query.whereEqualTo(usableField, CodecUtility.valueEncode(isEqualTo));
    }
    if (isLessThan != null) {
      query = query.whereLessThan(
          usableField, CodecUtility.valueEncode(isLessThan));
    }
    if (isLessThanOrEqualTo != null) {
      query = query.whereLessThanOrEqualTo(
          usableField, CodecUtility.valueEncode(isLessThanOrEqualTo));
    }
    if (isGreaterThan != null) {
      query = query.whereGreaterThan(
          usableField, CodecUtility.valueEncode(isGreaterThan));
    }
    if (isGreaterThanOrEqualTo != null) {
      query = query.whereGreaterThanOrEqualTo(
          usableField, CodecUtility.valueEncode(isGreaterThanOrEqualTo));
    }
    if (arrayContains != null) {
      query = query.whereArrayContains(
          usableField, CodecUtility.valueEncode(arrayContains));
    }
    if (arrayContainsAny != null) {
      assert(arrayContainsAny.length <= 10,
          'array contains can have maximum of 10 items');
      query = query.whereArrayContainsAny(
          usableField, CodecUtility.valueEncode(arrayContainsAny));
    }
    if (whereIn != null) {
      assert(
          whereIn.length <= 10, 'array contains can have maximum of 10 items');
      query = query.whereIn(usableField, CodecUtility.valueEncode(whereIn));
    }
    if (isNull != null) {
      assert(
          isNull,
          'isNull can only be set to true. '
          'Use isEqualTo to filter on non-null values.');
      query = query.whereEqualTo(usableField, null);
    }
    return QueryDart(_firestore, _path, query,
        orderByKeys: _orderByKeys, isCollectionGroup: _isCollectionGroup);
  }

  QuerySnapshotPlatform _dartQuerySnapshotToQuerySnapshot(
    dart.QuerySnapshot dartSnapshot,
  ) {
    return QuerySnapshotPlatform(
        dartSnapshot.documents
            .map((dart.DocumentSnapshot dartSnapshot) =>
                fromDartDocumentSnapshotToPlatformDocumentSnapshot(
                    dartSnapshot, _firestore))
            .toList(),
        dartSnapshot.documentChanges.map(_dartChangeToChange).toList(),
        _dartMetadataToMetadata(dartSnapshot.metadata));
  }

  DocumentChangePlatform _dartChangeToChange(dart.DocumentChange dartChange) {
    return DocumentChangePlatform(
        _fromDart(dartChange.type),
        dartChange.oldIndex,
        dartChange.newIndex,
        fromDartDocumentSnapshotToPlatformDocumentSnapshot(
            dartChange.document, _firestore));
  }

  DocumentChangeType _fromDart(dart.DocumentChangeType item) {
    switch (item) {
      case dart.DocumentChangeType.added:
        return DocumentChangeType.added;
      case dart.DocumentChangeType.modified:
        return DocumentChangeType.modified;
      case dart.DocumentChangeType.removed:
        return DocumentChangeType.removed;
      default:
        throw ArgumentError('Invalid type');
    }
  }

  SnapshotMetadataPlatform _dartMetadataToMetadata(
      dart.SnapshotMetadata dartMetadata) {
    return SnapshotMetadataPlatform(
      dartMetadata.hasPendingWrites,
      dartMetadata.isFromCache,
    );
  }

  @override
  Map<String, dynamic> get parameters => <String, dynamic>{};

  /// Returns a clean clone of this QueryDart.
  QueryDart resetQueryDelegate() =>
      QueryDart(firestore, pathComponents.join('/'), _dartQuery);
}
