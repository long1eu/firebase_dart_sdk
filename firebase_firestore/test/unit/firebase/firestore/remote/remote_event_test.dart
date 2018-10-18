// File created by
// Lung Razvan <long1eu>
// on 03/10/2018

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/existence_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_event.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart' as util;
import '../test_util.dart';

void main() {
  TestTargetMetadataProvider targetMetadataProvider;
  final Map<int, int> noOutstandingResponses = <int, int>{};
  final ImmutableSortedSet<DocumentKey> noExistingKeys =
      DocumentKey.emptyKeySet;
  final Uint8List resumeToken = Uint8List.fromList(utf8.encode('resume'));

  setUp(() => targetMetadataProvider = testTargetMetadataProvider);

  /// Creates an aggregator initialized with the set of provided [WatchChanges].
  /// Tests can add further changes via [handleDocumentChange],
  /// [handleTargetChange] and [handleExistenceFilterChange].
  ///
  /// [targetMap] a map of query data for all active targets. The map must
  /// include an entry for every target referenced by any of the watch changes.
  /// [outstandingResponses] the number of outstanding ACKs a target has to
  /// receive before it is considered active, or [noOutstandingResponses] if all
  /// targets are already active.
  /// [existingKeys] the set of documents that are considered synced with the
  /// test targets as part of a previous listen. To modify this set during test
  /// execution, invoke [targetMetadataProvider.setSyncedKeys].
  /// [watchChanges] the watch changes to apply before returning the aggregator.
  /// Supported changes are [WatchChangeDocumentWatchChange] and
  /// [WatchChangeWatchTargetChange].
  WatchChangeAggregator createAggregator(
      Map<int, QueryData> targetMap,
      Map<int, int> outstandingResponses,
      ImmutableSortedSet<DocumentKey> existingKeys,
      List<WatchChange> watchChanges) {
    final WatchChangeAggregator aggregator =
        WatchChangeAggregator(targetMetadataProvider);

    final List<int> targetIds = <int>[];

    for (MapEntry<int, QueryData> entry in targetMap.entries) {
      targetIds.add(entry.key);
      targetMetadataProvider.setSyncedKeys(entry.value, existingKeys);
    }

    for (MapEntry<int, int> entry in outstandingResponses.entries) {
      for (int i = 0; i < entry.value; ++i) {
        aggregator.recordPendingTargetRequest(entry.key);
      }
    }

    for (WatchChange watchChange in watchChanges) {
      if (watchChange is WatchChangeDocumentChange) {
        aggregator.handleDocumentChange(watchChange);
      } else if (watchChange is WatchChangeWatchTargetChange) {
        aggregator.handleTargetChange(watchChange);
      } else {
        Assert.fail('Encountered unexpected type of WatchChange');
      }
    }

    aggregator.handleTargetChange(WatchChangeWatchTargetChange(
      WatchTargetChangeType.noChange,
      targetIds,
      resumeToken,
    ));
    return aggregator;
  }

  /// Creates a single remote event that includes target changes for all
  /// provided [WatchChanges].
  ///
  /// [snapshotVersion] the version at which to create the remote event. This
  /// corresponds to the snapshot version provided by the [NO_CHANGE] event.
  /// [targetMap] a map of query data for all active targets. The map must
  /// include an entry for every target referenced by any of the watch changes.
  /// [outstandingResponses] the number of outstanding ACKs a target has to
  /// receive before it is considered active, or [noOutstandingResponses] if all
  /// targets are already active.
  /// [existingKeys] the set of documents that are considered synced with the
  /// test targets as part of a previous listen. To modify this set during test
  /// execution, invoke [targetMetadataProvider.setSyncedKeys].
  /// [watchChanges] the watch changes to apply before returning the aggregator.
  /// Supported changes are [WatchChangeDocumentWatchChange] and
  /// [WatchChangeWatchTargetChange].
  RemoteEvent createRemoteEvent(
      int snapshotVersion,
      Map<int, QueryData> targetMap,
      Map<int, int> outstandingResponses,
      ImmutableSortedSet<DocumentKey> existingKeys,
      List<WatchChange> watchChanges) {
    final WatchChangeAggregator aggregator = createAggregator(
        targetMap, outstandingResponses, existingKeys, watchChanges);
    return aggregator.createRemoteEvent(util.version(snapshotVersion));
  }

  test('testWillAccumulateDocumentAddedAndRemovedEvents', () {
    final Map<int, QueryData> targetMap =
        util.activeQueries(<int>[1, 2, 3, 4, 5, 6]);

    final Document existingDoc =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final Document newDoc =
        util.doc('docs/2', 2, util.map(<dynamic>['value', 2]));

    final WatchChange change1 = WatchChangeDocumentChange(
        <int>[1, 2, 3], <int>[4, 5, 6], existingDoc.key, existingDoc);
    final WatchChange change2 =
        WatchChangeDocumentChange(<int>[1, 4], <int>[2, 6], newDoc.key, newDoc);

    final RemoteEvent event = createRemoteEvent(
      3,
      targetMap,
      noOutstandingResponses,
      util.keySet(<DocumentKey>[existingDoc.key]),
      <WatchChange>[change1, change2],
    );
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 2);
    expect(event.documentUpdates[existingDoc.key], existingDoc);
    expect(event.documentUpdates[newDoc.key], newDoc);

    expect(event.targetChanges.length, 6);

    final TargetChange mapping1 = util.targetChange(
        resumeToken, false, <Document>[newDoc], <Document>[existingDoc], null);
    expect(event.targetChanges[1], mapping1);

    final TargetChange mapping2 = util.targetChange(
        resumeToken, false, null, <Document>[existingDoc], null);
    expect(event.targetChanges[2], mapping2);

    final TargetChange mapping3 = util.targetChange(
        resumeToken, false, null, <Document>[existingDoc], null);
    expect(event.targetChanges[3], mapping3);

    final TargetChange mapping4 = util.targetChange(
        resumeToken, false, <Document>[newDoc], null, <Document>[existingDoc]);
    expect(event.targetChanges[4], mapping4);

    final TargetChange mapping5 = util
        .targetChange(resumeToken, false, null, null, <Document>[existingDoc]);
    expect(event.targetChanges[5], mapping5);

    final TargetChange mapping6 = util
        .targetChange(resumeToken, false, null, null, <Document>[existingDoc]);
    expect(event.targetChanges[6], mapping6);
  });

  test('testWillIgnoreEventsForPendingTargets', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final Document doc2 =
        util.doc('docs/2', 2, util.map(<dynamic>['value', 2]));

    // We're waiting for the watch and unwatch ack
    final Map<int, int> outstanding = <int, int>{};
    outstanding[1] = 2;

    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc1.key, doc1);
    final WatchChange change2 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[1]);
    final WatchChange change3 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[1]);
    final WatchChange change4 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc2.key, doc2);

    final RemoteEvent event = createRemoteEvent(
      3,
      targetMap,
      outstanding,
      noExistingKeys,
      <WatchChange>[
        change1,
        change2,
        change3,
        change4,
      ],
    );
    expect(event.snapshotVersion, util.version(3));
    // doc1 is ignored because the target was not active at the time, but for
    // doc2 the target is active.
    expect(event.documentUpdates.length, 1);
    expect(event.documentUpdates[doc2.key], doc2);

    expect(event.targetChanges.length, 1);
  });

  test('testWillIgnoreEventsForRemovedTargets', () {
    final Map<int, QueryData> targetMap = util.activeQueries();

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));

    // We're waiting for the unwatch ack
    final Map<int, int> outstanding = <int, int>{};
    outstanding[1] = 1;

    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc1.key, doc1);
    final WatchChange change2 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[1]);

    final RemoteEvent event = createRemoteEvent(
      3,
      targetMap,
      outstanding,
      noExistingKeys,
      <WatchChange>[
        change1,
        change2,
      ],
    );
    expect(event.snapshotVersion, util.version(3));
    // doc1 is ignored because it was not apart of an active target.
    expect(event.documentUpdates.length, 0);
    // Target 1 is ignored because it was removed
    expect(event.targetChanges.length, 0);
  });

  test('testWillKeepResetMappingEvenWithUpdates', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final Document doc2 =
        util.doc('docs/2', 2, util.map(<dynamic>['value', 2]));
    final Document doc3 =
        util.doc('docs/3', 3, util.map(<dynamic>['value', 3]));

    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc1.key, doc1);
    // Reset stream, ignoring doc1
    final WatchChange change2 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.reset, <int>[1]);

    // Add doc2, doc3
    final WatchChange change3 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc2.key, doc2);
    final WatchChange change4 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc3.key, doc3);

    // Remove doc2 again, should not show up in reset mapping.
    final WatchChange change5 =
        WatchChangeDocumentChange(<int>[], <int>[1], doc2.key, doc2);

    final RemoteEvent event = createRemoteEvent(
      3,
      targetMap,
      noOutstandingResponses,
      util.keySet(<DocumentKey>[doc1.key]),
      <WatchChange>[
        change1,
        change2,
        change3,
        change4,
        change5,
      ],
    );
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 3);
    expect(event.documentUpdates[doc1.key], doc1);
    expect(event.documentUpdates[doc2.key], doc2);
    expect(event.documentUpdates[doc3.key], doc3);

    expect(event.targetChanges.length, 1);

    // Only doc3 is part of the new mapping.
    final TargetChange expected = util.targetChange(
        resumeToken, false, <Document>[doc3], null, <Document>[doc1]);
    expect(event.targetChanges[1], expected);
  });

  test('testWillHandleSingleReset', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap, noOutstandingResponses, noExistingKeys, <WatchChange>[]);

    // Reset target
    final WatchChangeWatchTargetChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.reset, <int>[1]);
    aggregator.handleTargetChange(change);

    final RemoteEvent event = aggregator.createRemoteEvent(util.version(3));
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 0);

    expect(event.targetChanges.length, 1);

    // Reset mapping is empty.
    final TargetChange expected =
        util.targetChange(Uint8List.fromList(<int>[]), false, null, null, null);
    expect(event.targetChanges[1], expected);
  });

  test('testWillHandleTargetAddAndRemovalInSameBatch', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1, 2]);

    final Document doc1a =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final Document doc1b =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 2]));

    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1], <int>[2], doc1a.key, doc1a);
    final WatchChange change2 =
        WatchChangeDocumentChange(<int>[2], <int>[1], doc1b.key, doc1b);

    final RemoteEvent event = createRemoteEvent(
        3,
        targetMap,
        noOutstandingResponses,
        util.keySet(<DocumentKey>[doc1a.key]),
        <WatchChange>[change1, change2]);
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 1);
    expect(event.documentUpdates[doc1b.key], doc1b);

    expect(event.targetChanges.length, 2);

    final TargetChange mapping1 =
        util.targetChange(resumeToken, false, null, null, <Document>[doc1b]);
    expect(event.targetChanges[1], mapping1);

    final TargetChange mapping2 =
        util.targetChange(resumeToken, false, null, <Document>[doc1b], null);
    expect(event.targetChanges[2], mapping2);
  });

  test('testTargetCurrentChangeWillMarkTheTargetCurrent', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final WatchChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);

    final RemoteEvent event = createRemoteEvent(3, targetMap,
        noOutstandingResponses, noExistingKeys, <WatchChange>[change]);
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 0);
    expect(event.targetChanges.length, 1);

    final TargetChange mapping =
        util.targetChange(resumeToken, true, null, null, null);
    expect(event.targetChanges[1], mapping);
  });

  test('testTargetAddedChangeWillResetPreviousState', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1, 3]);

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final Document doc2 =
        util.doc('docs/2', 2, util.map(<dynamic>['value', 2]));

    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1, 3], <int>[2], doc1.key, doc1);
    final WatchChange change2 = WatchChangeWatchTargetChange(
        WatchTargetChangeType.current, <int>[1, 2, 3]);
    final WatchChange change3 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[1]);
    final WatchChange change4 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.removed, <int>[2]);
    final WatchChange change5 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[1]);
    final WatchChange change6 =
        WatchChangeDocumentChange(<int>[1], <int>[3], doc2.key, doc2);

    final Map<int, int> outstanding = <int, int>{};
    outstanding[1] = 2;
    outstanding[2] = 1;

    final RemoteEvent event = createRemoteEvent(
        3,
        targetMap,
        outstanding,
        util.keySet(<DocumentKey>[doc2.key]),
        <WatchChange>[change1, change2, change3, change4, change5, change6]);
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 2);
    expect(event.documentUpdates[doc1.key], doc1);
    expect(event.documentUpdates[doc2.key], doc2);

    // target 1 and 3 are affected (1 because of re-add), target 2 is not
    // because of remove.
    expect(event.targetChanges.length, 2);

    // doc1 was before the remove, so it does not show up in the mapping.
    // Current was before the remove.
    final TargetChange mapping1 =
        util.targetChange(resumeToken, false, null, <Document>[doc2], null);
    expect(event.targetChanges[1], mapping1);

    // Doc1 was before the remove.
    // Current was after the remove
    final TargetChange mapping3 = util.targetChange(
        resumeToken, true, <Document>[doc1], null, <Document>[doc2]);
    expect(event.targetChanges[3], mapping3);
  });

  test('testNoChangeWillStillMarkTheAffectedTargets', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap, noOutstandingResponses, noExistingKeys, <WatchChange>[]);

    final WatchChangeWatchTargetChange change =
        WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[1]);
    aggregator.handleTargetChange(change);

    final RemoteEvent event = aggregator.createRemoteEvent(util.version(3));
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 0);
    expect(event.targetChanges.length, 1);

    final TargetChange expected =
        util.targetChange(resumeToken, false, null, null, null);
    expect(event.targetChanges[1], expected);
  });

  test('testExistenceFilterMismatchClearsTarget', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1, 2]);

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final Document doc2 =
        util.doc('docs/2', 2, util.map(<dynamic>['value', 2]));

    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc1.key, doc1);
    final WatchChange change2 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc2.key, doc2);
    final WatchChange change3 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap,
        noOutstandingResponses,
        util.keySet(<DocumentKey>[doc1.key, doc2.key]),
        <WatchChange>[change1, change2, change3]);

    RemoteEvent event = aggregator.createRemoteEvent(util.version(3));

    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 2);
    expect(event.documentUpdates[doc1.key], doc1);
    expect(event.documentUpdates[doc2.key], doc2);

    expect(event.targetChanges.length, 2);

    final TargetChange mapping1 = util.targetChange(
        resumeToken, true, null, <Document>[doc1, doc2], null);
    expect(event.targetChanges[1], mapping1);

    final TargetChange mapping2 =
        util.targetChange(resumeToken, false, null, null, null);
    expect(event.targetChanges[2], mapping2);

    final WatchChangeExistenceFilterWatchChange watchChange =
        WatchChangeExistenceFilterWatchChange(1, ExistenceFilter(1));
    aggregator.handleExistenceFilter(watchChange);

    event = aggregator.createRemoteEvent(util.version(3));

    final TargetChange mapping3 = util.targetChange(
        Uint8List.fromList(<int>[]), false, null, null, <Document>[doc1, doc2]);
    expect(event.targetChanges.length, 1);
    expect(event.targetChanges[1], mapping3);
    expect(event.targetMismatches.length, 1);
    expect(event.documentUpdates.length, 0);
  });

  test('testExistenceFilterMismatchRemovesCurrentChanges', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap, noOutstandingResponses, noExistingKeys, <WatchChange>[]);
    final WatchChangeWatchTargetChange markCurrent =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);
    aggregator.handleTargetChange(markCurrent);

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final WatchChangeDocumentChange addDoc =
        WatchChangeDocumentChange(<int>[1], <int>[], doc1.key, doc1);
    aggregator.handleDocumentChange(addDoc);

    // The existence filter mismatch will remove the document from target 1, but
    // not synthesize a document delete.
    final WatchChangeExistenceFilterWatchChange existenceFilter =
        WatchChangeExistenceFilterWatchChange(1, ExistenceFilter(0));
    aggregator.handleExistenceFilter(existenceFilter);

    final RemoteEvent event = aggregator.createRemoteEvent(util.version(3));

    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 1);
    expect(event.targetMismatches.length, 1);
    expect(event.documentUpdates[doc1.key], doc1);

    expect(event.targetChanges.length, 1);

    final TargetChange mapping1 =
        util.targetChange(Uint8List.fromList(<int>[]), false, null, null, null);
    expect(event.targetChanges[1], mapping1);
  });

  test('testDocumentUpdate', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['value', 1]));
    final WatchChange change1 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc1.key, doc1);

    final Document doc2 =
        util.doc('docs/2', 2, util.map(<dynamic>['value', 2]));
    final WatchChange change2 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc2.key, doc2);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap,
        noOutstandingResponses,
        noExistingKeys,
        <WatchChange>[change1, change2]);
    RemoteEvent event = aggregator.createRemoteEvent(util.version(3));
    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 2);
    expect(event.documentUpdates[doc1.key], doc1);
    expect(event.documentUpdates[doc2.key], doc2);

    targetMetadataProvider.setSyncedKeys(
        targetMap[1], util.keySet(<DocumentKey>[doc1.key, doc2.key]));

    final NoDocument deletedDoc1 = util.deletedDoc('docs/1', 3);
    final WatchChangeDocumentChange change3 = WatchChangeDocumentChange(
        <int>[1], <int>[], deletedDoc1.key, deletedDoc1);
    aggregator.handleDocumentChange(change3);

    final Document updatedDoc2 =
        util.doc('docs/2', 3, util.map(<dynamic>['value', 3]));
    final WatchChangeDocumentChange change4 = WatchChangeDocumentChange(
        <int>[1], <int>[], updatedDoc2.key, updatedDoc2);
    aggregator.handleDocumentChange(change4);

    final Document doc3 =
        util.doc('docs/3', 3, util.map(<dynamic>['value', 3]));
    final WatchChangeDocumentChange change5 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc3.key, doc3);
    aggregator.handleDocumentChange(change5);

    event = aggregator.createRemoteEvent(util.version(3));

    expect(event.snapshotVersion, util.version(3));
    expect(event.documentUpdates.length, 3);
    // doc1 is replaced
    expect(event.documentUpdates[doc1.key], deletedDoc1);
    // doc2 is updated
    expect(event.documentUpdates[doc2.key], updatedDoc2);
    // doc3 is new
    expect(event.documentUpdates[doc3.key], doc3);

    // Target is unchanged
    expect(event.targetChanges.length, 1);

    final TargetChange mapping1 = util.targetChange(resumeToken, false,
        <Document>[doc3], <Document>[updatedDoc2], <NoDocument>[deletedDoc1]);
    expect(event.targetChanges[1], mapping1);
  });

  test('testResumeTokenHandledPerTarget', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1, 2]);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap, noOutstandingResponses, noExistingKeys, <WatchChange>[]);

    final WatchChangeWatchTargetChange change1 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);
    aggregator.handleTargetChange(change1);

    final Uint8List resumeToken2 = utf8.encode('resumeToken2');
    final WatchChangeWatchTargetChange change2 = WatchChangeWatchTargetChange(
        WatchTargetChangeType.current, <int>[2], resumeToken2);
    aggregator.handleTargetChange(change2);

    final RemoteEvent event = aggregator.createRemoteEvent(util.version(3));

    expect(event.targetChanges.length, 2);

    final TargetChange mapping1 =
        util.targetChange(resumeToken, true, null, null, null);
    expect(event.targetChanges[1], mapping1);

    final TargetChange mapping2 =
        util.targetChange(resumeToken2, true, null, null, null);
    expect(event.targetChanges[2], mapping2);
  });

  test('testLastResumeTokenWins', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1, 2]);

    final WatchChangeAggregator aggregator = createAggregator(
        targetMap, noOutstandingResponses, noExistingKeys, <WatchChange>[]);

    final WatchChangeWatchTargetChange change1 =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);
    aggregator.handleTargetChange(change1);

    final Uint8List resumeToken2 = utf8.encode('resumeToken2');
    final WatchChangeWatchTargetChange change2 = WatchChangeWatchTargetChange(
        WatchTargetChangeType.current, <int>[1], resumeToken2);
    aggregator.handleTargetChange(change2);

    final Uint8List resumeToken3 = utf8.encode('resumeToken3');
    final WatchChangeWatchTargetChange change3 = WatchChangeWatchTargetChange(
        WatchTargetChangeType.current, <int>[2], resumeToken3);
    aggregator.handleTargetChange(change3);

    final RemoteEvent event = aggregator.createRemoteEvent(util.version(3));

    expect(event.targetChanges.length, 2);

    final TargetChange mapping1 =
        util.targetChange(resumeToken2, true, null, null, null);
    expect(event.targetChanges[1], mapping1);

    final TargetChange mapping2 =
        util.targetChange(resumeToken3, true, null, null, null);
    expect(event.targetChanges[2], mapping2);
  });

  test('testSynthesizeDeletes', () {
    final Map<int, QueryData> targetMap =
        util.activeLimboQueries('foo/doc', <int>[1]);

    final WatchChangeWatchTargetChange shouldSynthesize =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);
    final RemoteEvent event = createRemoteEvent(
        3,
        targetMap,
        noOutstandingResponses,
        noExistingKeys,
        <WatchChange>[shouldSynthesize]);

    final DocumentKey synthesized = util.key('docs/2');
    expect(event.documentUpdates[synthesized], isNull);

    final NoDocument expected = util.deletedDoc('foo/doc', 3);
    expect(event.documentUpdates[expected.key], expected);
    expect(event.resolvedLimboDocuments.contains(expected.key), isTrue);
  });

  test('testDoesNotSynthesizeDeleteInWrongState', () {
    final Map<int, QueryData> targetMap =
        util.activeLimboQueries('foo/doc', <int>[1]);

    final WatchChangeWatchTargetChange wrongState =
        WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[1]);

    final RemoteEvent event = createRemoteEvent(3, targetMap,
        noOutstandingResponses, noExistingKeys, <WatchChange>[wrongState]);
    expect(event.documentUpdates.length, 0);
    expect(event.resolvedLimboDocuments.length, 0);
  });

  test('testDoesNotSynthesizeDeleteWithExistingDocument', () {
    final Map<int, QueryData> targetMap =
        util.activeLimboQueries('foo/doc', <int>[1]);

    final WatchChangeWatchTargetChange hasDocument =
        WatchChangeWatchTargetChange(WatchTargetChangeType.current, <int>[1]);

    final RemoteEvent event = createRemoteEvent(
        3,
        targetMap,
        noOutstandingResponses,
        util.keySet(<DocumentKey>[util.key('foo/doc')]),
        <WatchChange>[hasDocument]);
    expect(event.documentUpdates.length, 0);
    expect(event.resolvedLimboDocuments.length, 0);
  });

  test('testSeparatesUpdates', () {
    final Map<int, QueryData> targetMap = util.activeQueries(<int>[1]);

    final Document newDoc =
        util.doc('docs/new', 1, util.map(<dynamic>['key', 'value']));
    final WatchChangeDocumentChange newDocChange =
        WatchChangeDocumentChange(<int>[1], <int>[], newDoc.key, newDoc);

    final Document existingDoc =
        util.doc('docs/existing', 1, util.map(<dynamic>['some', 'data']));
    final WatchChangeDocumentChange existingDocChange =
        WatchChangeDocumentChange(
            <int>[1], <int>[], existingDoc.key, existingDoc);

    final NoDocument deletedDoc = util.deletedDoc('docs/deleted', 1);
    final WatchChangeDocumentChange deletedDocChange =
        WatchChangeDocumentChange(
            <int>[1], <int>[], deletedDoc.key, deletedDoc);

    final NoDocument missingDoc = util.deletedDoc('docs/missing  ', 1);
    final WatchChangeDocumentChange missingDocChange =
        WatchChangeDocumentChange(
            <int>[1], <int>[], missingDoc.key, missingDoc);

    final RemoteEvent event = createRemoteEvent(
      3,
      targetMap,
      noOutstandingResponses,
      util.keySet(<DocumentKey>[existingDoc.key, deletedDoc.key]),
      <WatchChange>[
        newDocChange,
        existingDocChange,
        deletedDocChange,
        missingDocChange,
      ],
    );

    final TargetChange mapping = util.targetChange(resumeToken, false,
        <Document>[newDoc], <Document>[existingDoc], <NoDocument>[deletedDoc]);
    expect(event.targetChanges[1], mapping);
  });

  test('testTracksLimboDocuments', () {
    final Map<int, QueryData> listens = util.activeQueries(<int>[1])
      ..addAll(util.activeLimboQueries('doc/2', <int>[2]));

    // Add 3 docs: 1 is limbo and non-limbo, 2 is limbo-only, 3 is non-limbo
    final Document doc1 =
        util.doc('docs/1', 1, util.map(<dynamic>['key', 'value']));
    final Document doc2 =
        util.doc('docs/2', 1, util.map(<dynamic>['key', 'value']));
    final Document doc3 =
        util.doc('docs/3', 1, util.map(<dynamic>['key', 'value']));

    // Target 2 is a limbo target
    final WatchChangeDocumentChange docChange1 =
        WatchChangeDocumentChange(<int>[1, 2], <int>[], doc1.key, doc1);
    final WatchChangeDocumentChange docChange2 =
        WatchChangeDocumentChange(<int>[2], <int>[], doc2.key, doc2);
    final WatchChangeDocumentChange docChange3 =
        WatchChangeDocumentChange(<int>[1], <int>[], doc3.key, doc3);

    final WatchChangeWatchTargetChange targetsChange =
        WatchChangeWatchTargetChange(
            WatchTargetChangeType.current, <int>[1, 2]);

    final RemoteEvent event = createRemoteEvent(
      3,
      listens,
      noOutstandingResponses,
      noExistingKeys,
      <WatchChange>[
        docChange1,
        docChange2,
        docChange3,
        targetsChange,
      ],
    );
    final Set<DocumentKey> limboDocuments = event.resolvedLimboDocuments;
    // Doc1 is in both limbo and non-limbo targets, therefore not tracked as
    // limbo
    expect(limboDocuments.contains(doc1.key), isFalse);
    // Doc2 is only in the limbo target, so is tracked as a limbo document
    expect(limboDocuments.contains(doc2.key), isTrue);
    // Doc3 is only in the non-limbo target, therefore not tracked as limbo
    expect(limboDocuments.contains(doc3.key), isFalse);
  });
}
