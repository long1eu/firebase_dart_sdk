// File created by
// Lung Razvan <long1eu>
// on 26/09/2018

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/order_by.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/user_data_converter.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import 'test_access_helper.dart';

/// A set of utilities for tests
class TestUtil {
  /// A string sentinel that can be used with patchMutation() to mark a field
  /// for deletion.
  static const String DELETE_SENTINEL = '<DELETE>';

  static const int ARBITRARY_SEQUENCE_NUMBER = 2;

  static Map<String, T> map<T>(List<Object> entries) {
    final Map<String, T> res = <String, T>{};
    for (int i = 0; i < entries.length; i += 2) {
      res[entries[i] as String] = entries[i + 1] as T;
    }
    return res;
  }

  static Blob blob(List<int> bytes) => Blob(bytes);

  static final Map<String, Object> EMPTY_MAP = <String, Object>{};

  static FieldValue wrap(Object value) {
    final DatabaseId databaseId = DatabaseId.forProject('project');
    final UserDataConverter dataConverter = UserDataConverter(databaseId);
    // HACK: We use parseQueryValue() since it accepts scalars as well as
    // arrays / objects, and our tests currently use wrap() pretty generically
    // so we don't know the intent.
    return dataConverter.parseQueryValue(value);
  }

  static ObjectValue wrapMap(Map<String, Object> value) {
    // Cast is safe here because value passed in is a map
    return wrap(value) as ObjectValue;
  }

  static ObjectValue wrapList(List<Object> entries) {
    return wrapMap(map(entries));
  }

  static DocumentKey key(String key) {
    return DocumentKey.fromPathString(key);
  }

  static ResourcePath path(String key) {
    return ResourcePath.fromString(key);
  }

  static Query query(String path) {
    return Query.atPath(TestUtil.path(path));
  }

  static FieldPath field(String path) {
    return FieldPath.fromSegments(path.split('\\.'));
  }

  static DocumentReference ref(String key) {
    return TestAccessHelper.createDocumentReference(TestUtil.key(key));
  }

  static DatabaseId dbId(String project, String database) {
    return DatabaseId.forDatabase(project, database);
  }

  static DatabaseId dbIdForProject(String project) {
    return DatabaseId.forProject(project);
  }

  static SnapshotVersion version(int versionMicros) {
    final int seconds = versionMicros ~/ 1000000;
    final int nanos = (versionMicros % 1000000) * 1000;
    return SnapshotVersion(Timestamp(Int64(seconds), nanos));
  }

  static Document docForValue(
      /*String|DocumentKey*/ dynamic key, int version, ObjectValue data,
      [bool hasLocalMutations = false]) {
    assert(key is String || key is DocumentKey);

    if (key is String) {
      return Document(TestUtil.key(key), TestUtil.version(version), data,
          hasLocalMutations);
    } else if (key is DocumentKey) {
      return Document(key, TestUtil.version(version), data, hasLocalMutations);
    } else {
      throw StateError(
          'key should be a String or a DocumentKey but it\'s ${key.runtimeType}');
    }
  }

  static Document docForMap(
      /*String|DocumentKey*/ dynamic key, int version, Map<String, Object> data,
      [bool hasLocalMutations = false]) {
    assert(key is String || key is DocumentKey);

    if (key is String) {
      return Document(TestUtil.key(key), TestUtil.version(version),
          TestUtil.wrapMap(data), hasLocalMutations);
    } else if (key is DocumentKey) {
      return Document(key, TestUtil.version(version), TestUtil.wrapMap(data),
          hasLocalMutations);
    } else {
      throw StateError(
          'key should be a String or a DocumentKey but it\'s ${key.runtimeType}');
    }
  }

  static NoDocument deletedDoc(String key, int version) {
    return NoDocument(TestUtil.key(key), TestUtil.version(version));
  }

  static DocumentSet docSet(
      Comparator<Document> comparator, List<Document> documents) {
    DocumentSet set = DocumentSet.emptySet(comparator);
    for (Document document in documents) {
      set = set.add(document);
    }
    return set;
  }

  static ImmutableSortedSet<DocumentKey> keySet(List<DocumentKey> keys) {
    ImmutableSortedSet<DocumentKey> keySet = DocumentKey.emptyKeySet;
    for (DocumentKey key in keys) {
      keySet = keySet.insert(key);
    }
    return keySet;
  }

  static Filter filter(String key, String operator, Object value) {
    return Filter.create(field(key), operatorFromString(operator), wrap(value));
  }

  static FilterOperator operatorFromString(String s) {
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

  static OrderBy orderBy(String key, [String dir = 'asc']) {
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

  static void testEquality(List<List<int>> equalityGroups) {
    for (int i = 0; i < equalityGroups.length; i++) {
      final List<dynamic> group = equalityGroups[i];
      for (Object value in group) {
        for (List<dynamic> otherGroup in equalityGroups) {
          for (Object otherValue in otherGroup) {
            if (otherGroup == group) {
              expect(otherValue, value);
            } else {
              expect(otherValue, isNot(value));
            }
          }
        }
      }
    }
  }

  static QueryData queryData(
      int targetId, QueryPurpose queryPurpose, String path) {
    return QueryData.init(TestUtil.query(path), targetId,
        ARBITRARY_SEQUENCE_NUMBER, queryPurpose);
  }

  static ImmutableSortedMap<DocumentKey, T> docUpdates<T extends MaybeDocument>(
      List<MaybeDocument> docs) {
    ImmutableSortedMap<DocumentKey, T> res =
        ImmutableSortedMap<DocumentKey, T>.emptyMap(DocumentKey.comparator);
    for (T doc in docs) {
      res = res.insert(doc.key, doc);
    }
    return res;
  }

  static TargetChange targetChange<T extends MaybeDocument>(
      List<int> resumeToken,
      bool current,
      Iterable<Document> addedDocuments,
      Iterable<Document> modifiedDocuments,
      Iterable<T> removedDocuments) {
    ImmutableSortedSet<DocumentKey> addedDocumentKeys = DocumentKey.emptyKeySet;
    ImmutableSortedSet<DocumentKey> modifiedDocumentKeys =
        DocumentKey.emptyKeySet;
    ImmutableSortedSet<DocumentKey> removedDocumentKeys =
        DocumentKey.emptyKeySet;

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

/*
   static TargetChange ackTarget(Document/*...*/ docs) {
    return targetChange(ByteString.EMPTY, true, Arrays.asList(docs), null, null);
  }

   static Map<int, QueryData> activeQueries(Iterable<int> targets) {
    Query query = query("foo");
    Map<int, QueryData> listenMap = new HashMap<>();
    for (int targetId : targets) {
      QueryData queryData =
          new QueryData(query, targetId, ARBITRARY_SEQUENCE_NUMBER, QueryPurpose.LISTEN);
      listenMap.put(targetId, queryData);
    }
    return listenMap;
  }

   static Map<int, QueryData> activeQueries(int/*...*/ targets) {
    return activeQueries(asList(targets));
  }

   static Map<int, QueryData> activeLimboQueries(
      String docKey, Iterable<int> targets) {
    Query query = query(docKey);
    Map<int, QueryData> listenMap = new HashMap<>();
    for (int targetId : targets) {
      QueryData queryData =
          new QueryData(query, targetId, ARBITRARY_SEQUENCE_NUMBER, QueryPurpose.LIMBO_RESOLUTION);
      listenMap.put(targetId, queryData);
    }
    return listenMap;
  }

   static Map<int, QueryData> activeLimboQueries(String docKey, int/*...*/ targets) {
    return activeLimboQueries(docKey, asList(targets));
  }

   static RemoteEvent addedRemoteEvent(
      MaybeDocument doc, List<int> updatedInTargets, List<int> removedFromTargets) {
    DocumentChange change =
        new DocumentChange(updatedInTargets, removedFromTargets, doc.getKey(), doc);
    WatchChangeAggregator aggregator =
        new WatchChangeAggregator(
            new WatchChangeAggregator.TargetMetadataProvider() {
              @Override
               ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
                return DocumentKey.emptyKeySet();
              }

              @Override
               QueryData getQueryDataForTarget(int targetId) {
                return queryData(targetId, QueryPurpose.LISTEN, doc.getKey().toString());
              }
            });
    aggregator.handleDocumentChange(change);
    return aggregator.createRemoteEvent(doc.getVersion());
  }

   static RemoteEvent updateRemoteEvent(
      MaybeDocument doc, List<int> updatedInTargets, List<int> removedFromTargets) {
    return updateRemoteEvent(doc, updatedInTargets, removedFromTargets, Collections.emptyList());
  }

   static RemoteEvent updateRemoteEvent(
      MaybeDocument doc,
      List<int> updatedInTargets,
      List<int> removedFromTargets,
      List<int> limboTargets) {
    DocumentChange change =
        new DocumentChange(updatedInTargets, removedFromTargets, doc.getKey(), doc);
    WatchChangeAggregator aggregator =
        new WatchChangeAggregator(
            new WatchChangeAggregator.TargetMetadataProvider() {
              @Override
               ImmutableSortedSet<DocumentKey> getRemoteKeysForTarget(int targetId) {
                return DocumentKey.emptyKeySet().insert(doc.getKey());
              }

              @Override
               QueryData getQueryDataForTarget(int targetId) {
                bool isLimbo =
                    !(updatedInTargets.contains(targetId) || removedFromTargets.contains(targetId));
                QueryPurpose purpose =
                    isLimbo ? QueryPurpose.LIMBO_RESOLUTION : QueryPurpose.LISTEN;
                return queryData(targetId, purpose, doc.getKey().toString());
              }
            });
    aggregator.handleDocumentChange(change);
    return aggregator.createRemoteEvent(doc.getVersion());
  }

   static SetMutation setMutation(String path, Map<String, Object> values) {
    return new SetMutation(key(path), wrapObject(values), Precondition.NONE);
  }

   static PatchMutation patchMutation(String path, Map<String, Object> values) {
    return patchMutation(path, values, null);
  }

   static PatchMutation patchMutation(
      String path, Map<String, Object> values,  List<FieldPath> updateMask) {
    ObjectValue objectValue = ObjectValue.emptyObject();
    ArrayList<FieldPath> objectMask = new ArrayList<>();
    for (Entry<String, Object> entry : values.entrySet()) {
      FieldPath fieldPath = field(entry.getKey());
      objectMask.add(fieldPath);
      if (!entry.getValue().equals(DELETE_SENTINEL)) {
        FieldValue parsedValue = wrap(entry.getValue());
        objectValue = objectValue.set(fieldPath, parsedValue);
      }
    }

    bool merge = updateMask != null;

    // We sort the fieldMaskPaths to make the order deterministic in tests.
    Collections.sort(objectMask);

    return new PatchMutation(
        key(path),
        objectValue,
        FieldMask.fromCollection(merge ? updateMask : objectMask),
        merge ? Precondition.NONE : Precondition.exists(true));
  }

   static DeleteMutation deleteMutation(String path) {
    return new DeleteMutation(key(path), Precondition.NONE);
  }

  /**
   * Creates a TransformMutation by parsing any FieldValue sentinels in the provided data. The data
   * is expected to use dotted-notation for nested fields (i.e. { "foo.bar": FieldValue.foo() } and
   * must not contain any non-sentinel data.
   */
   static TransformMutation transformMutation(String path, Map<String, Object> data) {
    UserDataConverter dataConverter = new UserDataConverter(DatabaseId.forProject("project"));
    ParsedUpdateData result = dataConverter.parseUpdateData(data);

    // The order of the transforms doesn't matter, but we sort them so tests can assume a particular
    // order.
    ArrayList<FieldTransform> fieldTransforms = new ArrayList<>(result.getFieldTransforms());
    Collections.sort(
        fieldTransforms, (ft1, ft2) -> ft1.getFieldPath().compareTo(ft2.getFieldPath()));

    return new TransformMutation(key(path), fieldTransforms);
  }

   static MutationResult mutationResult(int version) {
    return new MutationResult(version(version), null);
  }

   static LocalViewChanges viewChanges(
      int targetId, List<String> addedKeys, List<String> removedKeys) {
    ImmutableSortedSet<DocumentKey> added = DocumentKey.emptyKeySet();
    for (String keyPath : addedKeys) {
      added = added.insert(key(keyPath));
    }
    ImmutableSortedSet<DocumentKey> removed = DocumentKey.emptyKeySet();
    for (String keyPath : removedKeys) {
      removed = removed.insert(key(keyPath));
    }
    return new LocalViewChanges(targetId, added, removed);
  }

  /** Creates a resume token to match the given snapshot version. */
  
   static ByteString resumeToken(int snapshotVersion) {
    if (snapshotVersion == 0) {
      return null;
    }

    String snapshotString = "snapshot-" + snapshotVersion;
    return ByteString.copyFrom(snapshotString, Charsets.UTF_8);
  }

  @NonNull
  private static ByteString resumeToken(SnapshotVersion snapshotVersion) {
    if (snapshotVersion.equals(SnapshotVersion.NONE)) {
      return ByteString.EMPTY;
    } else {
      return ByteString.copyFromUtf8(snapshotVersion.toString());
    }
  }

   static ByteString streamToken(String contents) {
    return ByteString.copyFrom(contents, Charsets.UTF_8);
  }

  private static Map<String, Object> fromJsonString(String json) {
    try {
      ObjectMapper mapper = new ObjectMapper();
      return mapper.readValue(json, new TypeReference<Map<String, Object>>() {});
    } catch (IOException e) {
      throw new RuntimeException(e);
    }
  }

   static Map<String, Object> fromSingleQuotedString(String json) {
    return fromJsonString(json.replace("'", "\""));
  }

  /** Converts the values of an ImmutableSortedMap into a list, preserving key order. */
   static <T> List<T> values(ImmutableSortedMap<?, T> map) {
    List<T> result = new ArrayList<>();
    for (Map.Entry<?, T> entry : map) {
      result.add(entry.getValue());
    }
    return result;
  }

  /**
   * Asserts that the actual set is equal to the expected one.
   *
   * @param expected A list of the expected contents of the set, in order.
   * @param actual The set to compare against.
   * @param <T> The type of the values of in common between the expected list and actual set.
   */
  // PORTING NOTE: JUnit and XCTest use reversed conventions on expected and actual values :-(.
   static <T> void assertSetEquals(List<T> expected, ImmutableSortedSet<T> actual) {
    List<T> actualList = Lists.newArrayList(actual);
    assertEquals(expected, actualList);
  }

  /**
   * Asserts that the actual set is equal to the expected one.
   *
   * @param expected A list of the expected contents of the set, in order.
   * @param actual The set to compare against.
   * @param <T> The type of the values of in common between the expected list and actual set.
   */
  // PORTING NOTE: JUnit and XCTest use reversed conventions on expected and actual values :-(.
   static <T> void assertSetEquals(List<T> expected, Set<T> actual) {
    Set<T> expectedSet = Sets.newHashSet(expected);
    assertEquals(expectedSet, actual);
  }

  /** Asserts that the given runnable block fails with an internal error. */
   static void assertFails(Runnable block) {
    try {
      block.run();
    } catch (AssertionError e) {
      assertThat(e).hasMessageThat().startsWith("INTERNAL ASSERTION FAILED:");
      // Otherwise success
      return;
    }
    fail("Should have failed");
  }

   static void assertDoesNotThrow(Runnable block) {
    try {
      block.run();
    } catch (Exception e) {
      fail("Should not have thrown " + e);
    }
  }

  // TODO: We could probably do some de-duplication between assertFails / expectError.
  /** Expects runnable to throw an exception with a specific error message. */
   static void expectError(Runnable runnable, String exceptionMessage) {
    expectError(runnable, exceptionMessage, /*context=*/ null);
  }

  /**
   * Expects runnable to throw an exception with a specific error message. An optional context (e.g.
   * "for bad_data") can be provided which will be displayed in any resulting failure message.
   */
   static void expectError(Runnable runnable, String exceptionMessage, String context) {
    bool exceptionThrown = false;
    try {
      runnable.run();
    } catch (Throwable throwable) {
      exceptionThrown = true;
      String contextMessage = "Expected exception message was incorrect";
      if (context != null) {
        contextMessage += " (" + context + ")";
      }
      assertEquals(contextMessage, exceptionMessage, throwable.getMessage());
    }
    if (!exceptionThrown) {
      context = (context == null) ? "" : context;
      fail(
          "Expected exception with message '"
              + exceptionMessage
              + "' but no exception was thrown"
              + context);
    }
  }*/
}
