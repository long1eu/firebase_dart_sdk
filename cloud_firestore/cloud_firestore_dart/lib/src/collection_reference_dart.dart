// File created by
// Lung Razvan <long1eu>
// on 17/04/2020

part of cloud_firestore_dart_implementation;

/// Dart implementation for Firestore [CollectionReferencePlatform]
class CollectionReferenceDart extends CollectionReferencePlatform {
  /// Creates an instance of [CollectionReferenceDart] which represents path
  /// at [pathComponents] and uses implementation of [_dartFirestore]
  CollectionReferenceDart(
      this._firestorePlatform, this._dartFirestore, List<String> pathComponents)
      : queryDelegate = QueryDart(
          _firestorePlatform,
          pathComponents.join('/'),
          _dartFirestore.collection(pathComponents.join('/')),
        ),
        super(_firestorePlatform, pathComponents);

  /// instance of Firestore from the dart plugin
  final dart.Firestore _dartFirestore;
  final FirestorePlatform _firestorePlatform;

  // disabling lint as it's only visible for testing
  @visibleForTesting
  QueryDart queryDelegate; // ignore: public_member_api_docs

  @override
  DocumentReferencePlatform parent() {
    if (pathComponents.length < 2) {
      return null;
    }
    return DocumentReferenceDart(
      _dartFirestore,
      firestore,
      (List<String>.from(pathComponents)..removeLast()),
    );
  }

  @override
  DocumentReferencePlatform document([String path]) {
    List<String> childPath;
    if (path == null) {
      final dart.DocumentReference doc =
          _dartFirestore.collection(pathComponents.join('/')).document();
      childPath = doc.path.split('/');
    } else {
      childPath = List<String>.from(pathComponents)..addAll(path.split(('/')));
    }
    return DocumentReferenceDart(
      _dartFirestore,
      firestore,
      childPath,
    );
  }

  @override
  Future<DocumentReferencePlatform> add(Map<String, dynamic> data) async {
    final DocumentReferencePlatform newDocument = document();
    await newDocument.setData(data);
    return newDocument;
  }

  @override
  Map<String, dynamic> buildArguments() => queryDelegate.buildArguments();

  @override
  QueryPlatform endAt(List<dynamic> values) {
    _resetQueryDelegate();
    return queryDelegate.endAt(values);
  }

  @override
  QueryPlatform endAtDocument(DocumentSnapshotPlatform documentSnapshot) {
    _resetQueryDelegate();
    return queryDelegate.endAtDocument(documentSnapshot);
  }

  @override
  QueryPlatform endBefore(List<dynamic> values) {
    _resetQueryDelegate();
    return queryDelegate.endBefore(values);
  }

  @override
  QueryPlatform endBeforeDocument(DocumentSnapshotPlatform documentSnapshot) {
    _resetQueryDelegate();
    return queryDelegate.endBeforeDocument(documentSnapshot);
  }

  @override
  FirestorePlatform get firestore => _firestorePlatform;

  @override
  Future<QuerySnapshotPlatform> getDocuments({
    Source source = Source.serverAndCache,
  }) =>
      queryDelegate.getDocuments(source: source);

  @override
  String get id => pathComponents.isEmpty ? null : pathComponents.last;

  @override
  bool get isCollectionGroup => false;

  @override
  QueryPlatform limit(int length) {
    _resetQueryDelegate();
    return queryDelegate.limit(length);
  }

  @override
  QueryPlatform orderBy(
    dynamic field, {
    bool descending = false,
  }) {
    _resetQueryDelegate();
    return queryDelegate.orderBy(field, descending: descending);
  }

  @override
  Map<String, dynamic> get parameters => queryDelegate.parameters;

  @override
  String get path => pathComponents.join('/');

  @override
  CollectionReferencePlatform reference() => queryDelegate.reference();

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
  }) =>
      queryDelegate.snapshots(includeMetadataChanges: includeMetadataChanges);

  @override
  QueryPlatform startAfter(List<dynamic> values) {
    _resetQueryDelegate();
    return queryDelegate.startAfter(values);
  }

  @override
  QueryPlatform startAfterDocument(DocumentSnapshotPlatform documentSnapshot) {
    _resetQueryDelegate();
    return queryDelegate.startAfterDocument(documentSnapshot);
  }

  @override
  QueryPlatform startAt(List<dynamic> values) {
    _resetQueryDelegate();
    return queryDelegate.startAt(values);
  }

  @override
  QueryPlatform startAtDocument(DocumentSnapshotPlatform documentSnapshot) {
    _resetQueryDelegate();
    return queryDelegate.startAtDocument(documentSnapshot);
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
    _resetQueryDelegate();
    return queryDelegate.where(field,
        isEqualTo: isEqualTo,
        isLessThan: isLessThan,
        isLessThanOrEqualTo: isLessThanOrEqualTo,
        isGreaterThan: isGreaterThan,
        isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
        arrayContains: arrayContains,
        arrayContainsAny: arrayContainsAny,
        whereIn: whereIn,
        isNull: isNull);
  }

  void _resetQueryDelegate() =>
      queryDelegate = queryDelegate.resetQueryDelegate();
}
