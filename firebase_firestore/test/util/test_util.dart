// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/order_by.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/user_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_view_changes.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/unknown_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:firebase_firestore/src/firebase/firestore/user_data_converter.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import 'test_access_helper.dart';

/// A string sentinel that can be used with patchMutation() to mark a field
/// for deletion.
const String deleteSentinel = '<DELETE>';

const int arbitrarySequenceNumber = 2;

Map<String, T> map<T>([List<Object> entries = const <Object>[]]) {
  final Map<String, T> res = <String, T>{};
  for (int i = 0; i < entries.length; i += 2) {
    final String key = entries[i];
    final T value = entries[i + 1];
    res[key] = value;
  }
  return res;
}

Blob blob([List<int> bytes = const <int>[]]) => Blob(Uint8List.fromList(bytes));

final Map<String, Object> emptyMap = <String, Object>{};

FieldValue wrap(Object value) {
  final DatabaseId databaseId = DatabaseId.forProject('project');
  final UserDataConverter dataConverter = UserDataConverter(databaseId);
  // HACK: We use parseQueryValue() since it accepts scalars as well as
  // arrays / objects, and our tests currently use wrap() pretty generically
  // so we don't know the intent.
  return dataConverter.parseQueryValue(value);
}

ObjectValue wrapMap(Map<String, Object> value) {
  // Cast is safe here because value passed in is a map
  final ObjectValue object = wrap(value);
  return object;
}

ObjectValue wrapList(List<Object> entries) {
  return wrapMap(map(entries));
}

DocumentKey key(String key) {
  return DocumentKey.fromPathString(key);
}

ResourcePath path(String key) {
  return ResourcePath.fromString(key);
}

Query query(String thePath) {
  return Query.atPath(path(thePath));
}

FieldPath field(String path) {
  return FieldPath.fromSegments(path.split('.'));
}

DocumentReference ref(String theKey) {
  return TestAccessHelper.createDocumentReference(key(theKey));
}

DatabaseId dbId(String project, [String database]) {
  return database == null
      ? DatabaseId.forProject(project)
      : DatabaseId.forDatabase(project, database);
}

SnapshotVersion version(int versionMicros) {
  final int seconds = versionMicros ~/ 1000000;
  final int nanos = (versionMicros.remainder(1000000)) * 1000;
  return SnapshotVersion(Timestamp(seconds, nanos));
}

Document docForValue(
    /*String|DocumentKey*/ dynamic theKey,
    int theVersion,
    ObjectValue data,
    [DocumentState documentState = DocumentState.synced]) {
  assert(theKey is String || theKey is DocumentKey);

  if (theKey is String) {
    return Document(
      key(theKey),
      version(theVersion),
      data,
      documentState,
    );
  } else if (theKey is DocumentKey) {
    return Document(
      theKey,
      version(theVersion),
      data,
      documentState,
    );
  } else {
    throw StateError('key should be a String or a DocumentKey but it\'s'
        ' ${theKey.runtimeType}');
  }
}

Document doc(/*String|DocumentKey*/ dynamic theKey, int theVersion,
    Map<String, Object> data,
    [DocumentState documentState = DocumentState.synced]) {
  assert(theKey is String || theKey is DocumentKey);

  if (theKey is String) {
    return Document(
      key(theKey),
      version(theVersion),
      wrapMap(data),
      documentState,
    );
  } else if (theKey is DocumentKey) {
    return Document(
      theKey,
      version(theVersion),
      wrapMap(data),
      documentState,
    );
  } else {
    throw StateError('key should be a String or a DocumentKey but it\'s '
        '${theKey.runtimeType}');
  }
}

NoDocument deletedDoc(String theKey, int theVersion,
    [bool hasCommittedMutations = false]) {
  return NoDocument(key(theKey), version(theVersion), hasCommittedMutations);
}

UnknownDocument unknownDoc(String theKey, int theVersion) {
  return UnknownDocument(key(theKey), version(theVersion));
}

DocumentSet docSet(Comparator<Document> comparator,
    [List<Document> documents = const <Document>[]]) {
  DocumentSet set = DocumentSet.emptySet(comparator);
  for (Document document in documents) {
    set = set.add(document);
  }
  return set;
}

ImmutableSortedSet<DocumentKey> keySet(
    [List<DocumentKey> keys = const <DocumentKey>[]]) {
  ImmutableSortedSet<DocumentKey> keySet = DocumentKey.emptyKeySet;
  for (DocumentKey key in keys) {
    keySet = keySet.insert(key);
  }
  return keySet;
}

Filter filter(String key, String operator, Object value) {
  return Filter.create(field(key), operatorFromString(operator), wrap(value));
}

FilterOperator operatorFromString(String s) {
  if (s == '<') {
    return FilterOperator.lessThan;
  } else if (s == '<=') {
    return FilterOperator.lessThanOrEqual;
  } else if (s == '==') {
    return FilterOperator.equal;
  } else if (s == '>') {
    return FilterOperator.graterThan;
  } else if (s == '>=') {
    return FilterOperator.graterThanOrEqual;
  } else if (s == 'array-contains') {
    return FilterOperator.arrayContains;
  } else {
    throw StateError('Unknown operator: $s');
  }
}

OrderBy orderBy(String key, [String dir = 'asc']) {
  OrderByDirection direction;
  if (dir == 'asc') {
    direction = OrderByDirection.ascending;
  } else if (dir == 'desc') {
    direction = OrderByDirection.descending;
  } else {
    throw ArgumentError('Unknown direction: $direction');
  }
  return OrderBy.getInstance(direction, field(key));
}

void testEquality(List<List<int>> equalityGroups) {
  for (int i = 0; i < equalityGroups.length; i++) {
    final List<dynamic> group = equalityGroups[i];
    for (Object value in group) {
      for (List<dynamic> otherGroup in equalityGroups) {
        for (Object otherValue in otherGroup) {
          if (const DeepCollectionEquality().equals(otherGroup, group)) {
            expect(otherValue, value);
          } else {
            expect(otherValue, isNot(value));
          }
        }
      }
    }
  }
}

QueryData queryData(int targetId, QueryPurpose queryPurpose, String path) {
  return QueryData.init(
      query(path), targetId, arbitrarySequenceNumber, queryPurpose);
}

ImmutableSortedMap<DocumentKey, T> docUpdates<T extends MaybeDocument>(
    [List<MaybeDocument> docs = const <MaybeDocument>[]]) {
  ImmutableSortedMap<DocumentKey, T> res =
      ImmutableSortedMap<DocumentKey, T>.emptyMap(DocumentKey.comparator);
  for (T doc in docs) {
    res = res.insert(doc.key, doc);
  }
  return res;
}

TargetChange targetChange<T extends MaybeDocument>(
    Uint8List resumeToken,
    bool current,
    Iterable<Document> addedDocuments,
    Iterable<Document> modifiedDocuments,
    Iterable<T> removedDocuments) {
  ImmutableSortedSet<DocumentKey> addedDocumentKeys = DocumentKey.emptyKeySet;
  ImmutableSortedSet<DocumentKey> modifiedDocumentKeys =
      DocumentKey.emptyKeySet;
  ImmutableSortedSet<DocumentKey> removedDocumentKeys = DocumentKey.emptyKeySet;

  if (addedDocuments != null) {
    for (Document document in addedDocuments) {
      addedDocumentKeys = addedDocumentKeys.insert(document.key);
    }
  }

  if (modifiedDocuments != null) {
    for (Document document in modifiedDocuments) {
      modifiedDocumentKeys = modifiedDocumentKeys.insert(document.key);
    }
  }

  if (removedDocuments != null) {
    for (MaybeDocument document in removedDocuments) {
      removedDocumentKeys = removedDocumentKeys.insert(document.key);
    }
  }

  return TargetChange(resumeToken, current, addedDocumentKeys,
      modifiedDocumentKeys, removedDocumentKeys);
}

TargetChange ackTarget([List<Document> docs]) {
  return targetChange(Uint8List.fromList(<int>[]), true,
      docs ?? const <Document>[], null, null);
}

Map<int, QueryData> activeQueries([List<int> targets = const <int>[]]) {
  final Query theQuery = query('foo');
  final Map<int, QueryData> listenMap = <int, QueryData>{};
  for (int targetId in targets) {
    final QueryData queryData = QueryData.init(
        theQuery, targetId, arbitrarySequenceNumber, QueryPurpose.listen);
    listenMap[targetId] = queryData;
  }
  return listenMap;
}

Map<int, QueryData> activeLimboQueries(String docKey, Iterable<int> targets) {
  final Query theQuery = query(docKey);
  final Map<int, QueryData> listenMap = <int, QueryData>{};
  for (int targetId in targets) {
    final QueryData queryData = QueryData.init(theQuery, targetId,
        arbitrarySequenceNumber, QueryPurpose.limboResolution);
    listenMap[targetId] = queryData;
  }
  return listenMap;
}

RemoteEvent addedRemoteEvent(MaybeDocument doc, List<int> updatedInTargets,
    List<int> removedFromTargets) {
  final WatchChangeDocumentChange change = WatchChangeDocumentChange(
      updatedInTargets, removedFromTargets, doc.key, doc);
  final WatchChangeAggregator aggregator =
      WatchChangeAggregator(TargetMetadataProvider(
    getRemoteKeysForTarget: (int targetId) => DocumentKey.emptyKeySet,
    getQueryDataForTarget: (int targetId) =>
        queryData(targetId, QueryPurpose.listen, doc.key.toString()),
  ))
        ..handleDocumentChange(change);
  return aggregator.createRemoteEvent(doc.version);
}

RemoteEvent updateRemoteEvent(
    MaybeDocument doc, List<int> updatedInTargets, List<int> removedFromTargets,
    [List<int> limboTargets = const <int>[]]) {
  final WatchChangeDocumentChange change = WatchChangeDocumentChange(
      updatedInTargets, removedFromTargets, doc.key, doc);
  final WatchChangeAggregator aggregator =
      WatchChangeAggregator(TargetMetadataProvider(
    getRemoteKeysForTarget: (int targetId) {
      return DocumentKey.emptyKeySet.insert(doc.key);
    },
    getQueryDataForTarget: (int targetId) {
      final bool isLimbo = !(updatedInTargets.contains(targetId) ||
          removedFromTargets.contains(targetId));
      final QueryPurpose purpose =
          isLimbo ? QueryPurpose.limboResolution : QueryPurpose.listen;
      return queryData(targetId, purpose, doc.key.toString());
    },
  ))
        ..handleDocumentChange(change);
  return aggregator.createRemoteEvent(doc.version);
}

SetMutation setMutation(String path, Map<String, Object> values) {
  return SetMutation(key(path), wrapMap(values), Precondition.none);
}

PatchMutation patchMutation(String path, Map<String, Object> values,
    [List<FieldPath> updateMask]) {
  ObjectValue objectValue = ObjectValue.empty;
  final List<FieldPath> objectMask = <FieldPath>[];
  for (MapEntry<String, Object> entry in values.entries) {
    final FieldPath fieldPath = field(entry.key);
    objectMask.add(fieldPath);
    if (entry.value != deleteSentinel) {
      final FieldValue parsedValue = wrap(entry.value);
      objectValue = objectValue.set(fieldPath, parsedValue);
    }
  }

  final bool merge = updateMask != null;

  // We sort the fieldMaskPaths to make the order deterministic in tests.
  objectMask.sort();

  return PatchMutation(
      key(path),
      objectValue,
      FieldMask(merge ? updateMask : objectMask),
      merge ? Precondition.none : Precondition(exists: true));
}

DeleteMutation deleteMutation(String path) {
  return DeleteMutation(key(path), Precondition.none);
}

/// Creates a [TransformMutation] by parsing any [FieldValue] sentinels in the
/// provided data. The data is expected to use dotted-notation for nested
/// fields (i.e. { 'foo.bar': FieldValue.foo() } and must not contain any
/// non-sentinel data.
TransformMutation transformMutation(String path, Map<String, Object> data) {
  final UserDataConverter dataConverter =
      UserDataConverter(DatabaseId.forProject('project'));
  final UserDataParsedUpdateData result = dataConverter.parseUpdateData(data);

  // The order of the transforms doesn't matter, but we sort them so tests can
  // assume a particular order.
  final List<FieldTransform> fieldTransforms =
      List<FieldTransform>.from(result.fieldTransforms)
        ..sort((FieldTransform ft1, FieldTransform ft2) {
          return ft1.fieldPath.compareTo(ft2.fieldPath);
        });

  return TransformMutation(key(path), fieldTransforms);
}

MutationResult mutationResult(int theVersion) {
  return MutationResult(version(theVersion), null);
}

LocalViewChanges viewChanges(
    int targetId, List<String> addedKeys, List<String> removedKeys) {
  ImmutableSortedSet<DocumentKey> added = DocumentKey.emptyKeySet;
  for (String keyPath in addedKeys) {
    added = added.insert(key(keyPath));
  }
  ImmutableSortedSet<DocumentKey> removed = DocumentKey.emptyKeySet;
  for (String keyPath in removedKeys) {
    removed = removed.insert(key(keyPath));
  }
  return LocalViewChanges(targetId, added, removed);
}

/// Creates a resume token to match the given snapshot version.

Uint8List resumeToken(
    /*int|SnapshotVersion|String*/
    dynamic snapshotVersion) {
  if (snapshotVersion is int) {
    if (snapshotVersion == 0) {
      return null;
    }

    final String snapshotString = 'snapshot-$snapshotVersion';
    return Uint8List.fromList(utf8.encode(snapshotString));
  } else if (snapshotVersion is SnapshotVersion) {
    if (snapshotVersion == SnapshotVersion.none) {
      return Uint8List.fromList(<int>[]);
    } else {
      return Uint8List.fromList(utf8.encode(snapshotVersion.toString()));
    }
  } else if (snapshotVersion is String) {
    return Uint8List.fromList(utf8.encode(snapshotVersion));
  } else {
    throw StateError(
        'snapshotVersion should be int|SnapshotVersion|String but it\'s'
        ' ${snapshotVersion.runtimeType}');
  }
}

Map<String, Object> fromJsonString(String json) {
  final Map<String, Object> data = jsonDecode(json);
  return data;
}

Map<String, Object> fromSingleQuotedString(String json) {
  return fromJsonString(json.replaceAll("'", '"'));
}

/// Converts the values of an ImmutableSortedMap into a list, preserving key
/// order.
List<T> values<T>(ImmutableSortedMap<dynamic, T> map) {
  final List<T> result = <T>[];
  for (MapEntry<dynamic, T> entry in map) {
    result.add(entry.value);
  }
  return result;
}

/// Expects runnable to throw an exception with a specific error message. An
/// optional context (e.g. 'for bad_data') can be provided which will be
/// displayed in any resulting failure message.
Future<void> expectError(
    FutureOr<dynamic> Function() runnable, String exceptionMessage,
    [String context]) async {
  bool exceptionThrown = false;
  try {
    await runnable.call();
  } catch (error) {
    exceptionThrown = true;
    String contextMessage = 'Expected exception message was incorrect';
    if (context != null) {
      contextMessage += ' ($context)';
    }
    expect(error.message, exceptionMessage, reason: contextMessage);
  }
  if (!exceptionThrown) {
    fail('Expected exception with message \'$exceptionMessage\' but no '
        'exception was thrown ${context ?? ''}.');
  }
}
