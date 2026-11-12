// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

/// The bundle related tests of the Android `LocalStoreTestCase`, to run against any [Persistence]. A new [LocalStore]
/// is created for every test.
class LocalStoreBundleTestCase {
  LocalStoreBundleTestCase(this._persistence);

  final Persistence _persistence;

  late LocalStore _localStore;
  ImmutableSortedMap<DocumentKey, MaybeDocument>? _lastChanges;
  late int _lastTargetId;

  Future<void> setUp() async {
    _lastChanges = null;
    _lastTargetId = 0;

    _localStore = LocalStore(_persistence, User.unauthenticated);
    await _localStore.start();
  }

  Future<void> tearDown() => _persistence.shutdown();

  Future<void> testHandlesSavingBundledDocuments() async {
    await _bundleDocuments(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337])),
      deletedDoc('foo/bar1', 1)
    ]);
    _expectChanged(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337])),
      deletedDoc('foo/bar1', 1)
    ]);
    await _expectContains(
        doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337])));
    await _expectContains(deletedDoc('foo/bar1', 1));

    await _expectQueryDocumentMapping(2, <DocumentKey>[key('foo/bar')]);
  }

  Future<void>
      testHandlesSavingBundlesDocumentsWithNewerExistingVersion() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 2, map<Object?>(<dynamic>['sum', 1337])),
        <int>[2],
        <int>[]));
    await _expectContains(
        doc('foo/bar', 2, map<Object?>(<dynamic>['sum', 1337])));

    await _bundleDocuments(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337])),
      deletedDoc('foo/bar1', 1)
    ]);
    _expectChanged(<MaybeDocument>[deletedDoc('foo/bar1', 1)]);
    await _expectContains(
        doc('foo/bar', 2, map<Object?>(<dynamic>['sum', 1337])));
    await _expectContains(deletedDoc('foo/bar1', 1));

    await _expectQueryDocumentMapping(4, <DocumentKey>[key('foo/bar')]);
  }

  Future<void>
      testHandlesSavingBundledDocumentsWithOlderExistingVersion() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map<Object?>(<dynamic>['val', 'to-delete'])),
        <int>[2],
        <int>[]));
    await _expectContains(
        doc('foo/bar', 1, map<Object?>(<dynamic>['val', 'to-delete'])));

    await _bundleDocuments(<MaybeDocument>[
      doc('foo/new', 1, map<Object?>(<dynamic>['sum', 1336])),
      deletedDoc('foo/bar', 2)
    ]);
    // The changes are sorted by key.
    _expectChanged(<MaybeDocument>[
      deletedDoc('foo/bar', 2),
      doc('foo/new', 1, map<Object?>(<dynamic>['sum', 1336])),
    ]);
    await _expectContains(
        doc('foo/new', 1, map<Object?>(<dynamic>['sum', 1336])));
    await _expectContains(deletedDoc('foo/bar', 2));

    await _expectQueryDocumentMapping(4, <DocumentKey>[key('foo/new')]);
  }

  Future<void>
      testSavingBundledDocumentsWithSameExistingVersionShouldNotOverwrite() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _applyRemoteEvent(addedRemoteEvent(
        doc('foo/bar', 1, map<Object?>(<dynamic>['val', 'old'])),
        <int>[2],
        <int>[]));
    await _expectContains(
        doc('foo/bar', 1, map<Object?>(<dynamic>['val', 'old'])));

    await _bundleDocuments(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['val', 'new']))
    ]);
    _expectChanged();
    await _expectContains(
        doc('foo/bar', 1, map<Object?>(<dynamic>['val', 'old'])));

    await _expectQueryDocumentMapping(4, <DocumentKey>[key('foo/bar')]);
  }

  Future<void>
      testHandlesMergeMutationWithTransformThenBundledDocuments() async {
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutations(<Mutation>[
      patchMutation('foo/bar', map(), <FieldPath>[]),
      transformMutation(
          'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)]))
    ]);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map<Object?>(<dynamic>['sum', 1]),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map<Object?>(<dynamic>['sum', 1]),
        DocumentState.localMutations));

    // Locally mutated documents carry SnapshotVersion.none (upstream's
    // setHasLocalMutations() resets the version), so the bundled version 1 is
    // not visible on the result.
    await _bundleDocuments(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337]))
    ]);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map<Object?>(<dynamic>['sum', 1]),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map<Object?>(<dynamic>['sum', 1]),
        DocumentState.localMutations));

    await _expectQueryDocumentMapping(4, <DocumentKey>[key('foo/bar')]);
  }

  Future<void>
      testHandlesPatchMutationWithTransformThenBundledDocuments() async {
    // See the comments in testHandlesPatchMutationWithTransformThenRemoteEvent: the behavior for this and a remote
    // event is the same.
    final Query query = Query(ResourcePath.fromString('foo'));
    await _allocateQuery(query);
    _expectTargetId(2);

    await _writeMutations(<Mutation>[
      patchMutation('foo/bar', map()),
      transformMutation(
          'foo/bar', map(<dynamic>['sum', FieldValue.increment(1)]))
    ]);
    _expectChanged(<NoDocument>[deletedDoc('foo/bar', 0)]);
    await _expectNotContains('foo/bar');

    // Locally mutated documents carry SnapshotVersion.none (upstream's
    // setHasLocalMutations() resets the version), so the bundled version 1 is
    // not visible on the result.
    await _bundleDocuments(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337]))
    ]);
    _expectChanged(<Document>[
      doc('foo/bar', 0, map<Object?>(<dynamic>['sum', 1]),
          DocumentState.localMutations)
    ]);
    await _expectContains(doc('foo/bar', 0, map<Object?>(<dynamic>['sum', 1]),
        DocumentState.localMutations));

    await _expectQueryDocumentMapping(4, <DocumentKey>[key('foo/bar')]);
  }

  Future<void> testHandlesSavingAndCheckingBundleMetadata() async {
    expect(await _localStore.hasNewerBundle(_metadata('test', 1)), isFalse);
    await _localStore.saveBundle(_metadata('test', 2));
    expect(await _localStore.hasNewerBundle(_metadata('test', 1)), isTrue);
    // Same create time counts as already loaded.
    expect(await _localStore.hasNewerBundle(_metadata('test', 2)), isTrue);
    expect(await _localStore.hasNewerBundle(_metadata('test', 3)), isFalse);
    expect(await _localStore.hasNewerBundle(_metadata('other', 1)), isFalse);
  }

  Future<void> testHandlesSavingAndLoadingNamedQueries() async {
    final NamedQuery namedQuery = NamedQuery(
        'testQuery',
        BundledQuery(
            Query(ResourcePath.fromString('foo')), BundledQueryLimitType.first),
        SnapshotVersion.none);
    await _localStore.saveNamedQuery(namedQuery, DocumentKey.emptyKeySet);
    expect(await _localStore.getNamedQuery('testQuery'), namedQuery);
    expect(await _localStore.getNamedQuery('unknown'), isNull);
  }

  Future<void>
      testLoadingNamedQueriesAllocatesTargetsAndUpdatesTargetDocumentMapping() async {
    await _bundleDocuments(<MaybeDocument>[
      doc('foo1/bar', 1, map<Object?>(<dynamic>['sum', 1337])),
      doc('foo2/bar', 1, map<Object?>(<dynamic>['sum', 42]))
    ]);
    _expectChanged(<MaybeDocument>[
      doc('foo1/bar', 1, map<Object?>(<dynamic>['sum', 1337])),
      doc('foo2/bar', 1, map<Object?>(<dynamic>['sum', 42]))
    ]);
    await _expectContains(
        doc('foo1/bar', 1, map<Object?>(<dynamic>['sum', 1337])));
    await _expectContains(
        doc('foo2/bar', 1, map<Object?>(<dynamic>['sum', 42])));

    final NamedQuery namedQuery1 = NamedQuery(
        'query-1',
        BundledQuery(Query(ResourcePath.fromString('foo1')),
            BundledQueryLimitType.first),
        SnapshotVersion(Timestamp.now()));
    await _localStore.saveNamedQuery(
        namedQuery1, keySet(<DocumentKey>[key('foo1/bar')]));
    expect(await _localStore.getNamedQuery('query-1'), namedQuery1);

    await _expectQueryDocumentMapping(4, <DocumentKey>[key('foo1/bar')]);

    final NamedQuery namedQuery2 = NamedQuery(
        'query-2',
        BundledQuery(Query(ResourcePath.fromString('foo2')),
            BundledQueryLimitType.first),
        SnapshotVersion(Timestamp.now()));
    await _localStore.saveNamedQuery(
        namedQuery2, keySet(<DocumentKey>[key('foo2/bar')]));
    expect(await _localStore.getNamedQuery('query-2'), namedQuery2);

    await _expectQueryDocumentMapping(6, <DocumentKey>[key('foo2/bar')]);
  }

  Future<void> testHandlesSavingAndLoadingLimitToLastQueries() async {
    final NamedQuery namedQuery = NamedQuery(
        'testQuery',
        BundledQuery(
            Query(ResourcePath.fromString('foo'),
                explicitSortOrder: <OrderBy>[orderBy('foo')], limit: 5),
            BundledQueryLimitType.last),
        SnapshotVersion.none);
    await _localStore.saveNamedQuery(namedQuery, DocumentKey.emptyKeySet);
    expect(await _localStore.getNamedQuery('testQuery'), namedQuery);
  }

  // Tests that are not part of the Android LocalStoreTestCase.

  Future<void> testNamedQueryTargetResumesFromTheReadTimeOfTheBundle() async {
    final Query foo = Query(ResourcePath.fromString('foo'));
    final SnapshotVersion readTime = version(400);
    await _localStore.saveNamedQuery(
        NamedQuery(
            'q', BundledQuery(foo, BundledQueryLimitType.first), readTime),
        DocumentKey.emptyKeySet);

    // Listening to the query later reuses the target, which resumes from the read time of the named query.
    final QueryData queryData = await _localStore.allocateTarget(foo.toTarget());
    expect(queryData.snapshotVersion, readTime);
    expect(queryData.resumeToken, isEmpty);
  }

  Future<void> testOlderNamedQueryDoesNotOverwriteTheTargetOfANewerOne() async {
    final Query foo = Query(ResourcePath.fromString('foo'));
    await _localStore.saveNamedQuery(
        NamedQuery(
            'q', BundledQuery(foo, BundledQueryLimitType.first), version(500)),
        keySet(<DocumentKey>[key('foo/new')]));
    await _localStore.saveNamedQuery(
        NamedQuery(
            'q', BundledQuery(foo, BundledQueryLimitType.first), version(400)),
        keySet(<DocumentKey>[key('foo/old')]));

    final QueryData queryData = await _localStore.allocateTarget(foo.toTarget());
    expect(queryData.snapshotVersion, version(500));
    final ImmutableSortedSet<DocumentKey> keys =
        await _localStore.getRemoteDocumentKeys(queryData.targetId);
    expect(keys, keySet(<DocumentKey>[key('foo/new')]));
  }

  Future<void> testBundleTargetsKeepDocumentsOnceTheQueryIsListenedTo() async {
    // The named query target stays allocated: a later listen on the same query reuses it instead of failing.
    final Query foo = Query(ResourcePath.fromString('foo'));
    await _bundleDocuments(<MaybeDocument>[
      doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337]))
    ]);
    await _localStore.saveNamedQuery(
        NamedQuery(
            'q', BundledQuery(foo, BundledQueryLimitType.first), version(400)),
        keySet(<DocumentKey>[key('foo/bar')]));

    final QueryData first = await _localStore.allocateTarget(foo.toTarget());
    final QueryData second = await _localStore.allocateTarget(foo.toTarget());
    expect(second.targetId, first.targetId);
    await _expectContains(
        doc('foo/bar', 1, map<Object?>(<dynamic>['sum', 1337])));
  }

  // Helpers

  BundleMetadata _metadata(String bundleId, int createTime) =>
      BundleMetadata(bundleId, 1, version(createTime), 1, 10);

  Future<void> _writeMutations(List<Mutation> mutations) async {
    _lastChanges = (await _localStore.writeLocally(mutations)).changes;
  }

  Future<void> _applyRemoteEvent(RemoteEvent event) async {
    _lastChanges = await _localStore.applyRemoteEvent(event);
  }

  Future<void> _bundleDocuments(List<MaybeDocument> documents) async {
    ImmutableSortedMap<DocumentKey, MaybeDocument> map =
        DocumentCollections.emptyMaybeDocumentMap();
    for (final MaybeDocument document in documents) {
      map = map.insert(document.key, document);
    }
    _lastChanges = await _localStore.applyBundledDocuments(map, '');
  }

  Future<int> _allocateQuery(Query query) async {
    final QueryData queryData = await _localStore.allocateTarget(query.toTarget());
    _lastTargetId = queryData.targetId;
    return queryData.targetId;
  }

  void _expectTargetId(int targetId) {
    expect(_lastTargetId, targetId);
  }

  /// Asserts that the last changes contain the given docs, in order.
  void _expectChanged(
      [List<MaybeDocument> expected = const <MaybeDocument>[]]) {
    expect(_lastChanges, isNotNull);

    final List<MaybeDocument> actualList = _lastChanges!
        .map((MapEntry<DocumentKey, MaybeDocument> entry) => entry.value)
        .toList();

    expect(actualList, expected);
    _lastChanges = null;
  }

  Future<void> _expectContains(MaybeDocument expected) async {
    final MaybeDocument? actual = await _localStore.readDocument(expected.key);
    expect(actual, expected);
  }

  Future<void> _expectNotContains(String keyPathString) async {
    final MaybeDocument? actual = await _localStore
        .readDocument(DocumentKey.fromPathString(keyPathString));
    expect(actual, isNull);
  }

  Future<void> _expectQueryDocumentMapping(
      int targetId, List<DocumentKey> keys) async {
    final ImmutableSortedSet<DocumentKey> actualKeys =
        await _localStore.getRemoteDocumentKeys(targetId);
    expect(actualKeys, keySet(keys));
  }
}
