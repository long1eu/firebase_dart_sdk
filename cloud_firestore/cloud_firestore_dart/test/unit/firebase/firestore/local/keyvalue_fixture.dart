// A small cache of every table of the key-value cache, written with fixed values, and the checks of what it holds:
// the stored-format fixtures under test/res/keyvalue are made with [writeFixtureCache], and every fixture, of any
// schema version, must read back as [expectFixtureCache] says.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/globals_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

const User fixtureUser = User('user1');

final List<Mutation> _batch1 = <Mutation>[
  setMutation('coll/a', map(<Object?>['n', 1, 's', 'x'])),
  patchMutation('coll/b', map(<Object?>['n', 2])),
];
final List<Mutation> _batch2 = <Mutation>[deleteMutation('coll/c')];

QueryData _target() => QueryData(
  query('coll').toTarget(),
  2,
  1,
  QueryPurpose.listen,
  version(5),
  Uint8List.fromList(<int>[9, 9]),
);

final BundleMetadata _bundle = BundleMetadata(
  'bundle-1',
  1,
  version(8),
  2,
  300,
);
final NamedQuery _namedQuery = NamedQuery(
  'named',
  BundledQuery(query('coll'), BundledQueryLimitType.first),
  version(8),
);

/// Writes the fixture cache into a started [persistence] over an empty store, in one transaction.
Future<void> writeFixtureCache(
  CacheStorePersistence persistence,
) => persistence.runTransaction('fixture', () async {
  final MutationQueue queue = persistence.getMutationQueue(fixtureUser);
  await queue.start();
  final MutationBatch b1 = await queue.addMutationBatch(
    Timestamp(1000, 0),
    const <Mutation>[],
    _batch1,
  );
  final MutationBatch b2 = await queue.addMutationBatch(
    Timestamp(1001, 0),
    const <Mutation>[],
    _batch2,
  );
  await queue.setLastStreamToken(Uint8List.fromList(<int>[1, 2, 3]));

  final DocumentOverlayCache overlays = persistence.getDocumentOverlayCache(
    fixtureUser,
  );
  await overlays.saveOverlays(b1.batchId, <DocumentKey, Mutation>{
    for (final Mutation m in _batch1) m.key: m,
  });
  await overlays.saveOverlays(b2.batchId, <DocumentKey, Mutation>{
    for (final Mutation m in _batch2) m.key: m,
  });

  await persistence.remoteDocumentCache.add(
    doc('coll/c', 5, map(<Object?>['n', 3])),
    version(5),
  );
  await persistence.remoteDocumentCache.add(
    deletedDoc('coll/d', 6),
    version(6),
  );
  await persistence.remoteDocumentCache.add(
    unknownDoc('other/e', 7),
    version(7),
  );
  await persistence.remoteDocumentCache.add(
    doc('coll/c/sub/s', 7, map(<Object?>['n', 4])),
    version(7),
  );

  await persistence.queryCache.addQueryData(_target());
  await persistence.queryCache.addMatchingKeys(
    keySet(<DocumentKey>[key('coll/c')]),
    2,
  );
  await persistence.queryCache.setLastRemoteSnapshotVersion(version(7));
  // A document that no target holds: only its sentinel.
  await persistence.referenceDelegate.removeMutationReference(key('other/e'));

  await persistence.bundleCache.saveBundleMetadata(_bundle);
  await persistence.bundleCache.saveNamedQuery(_namedQuery);

  final GlobalsCache globals = persistence.globalsCache;
  await globals.setSessionToken(Uint8List.fromList(<int>[4, 5]));
  await globals.setQueuedWritesMergeMark(
    fixtureUser.uid!,
    QueuedWritesMergeMark(b1.batchId, Timestamp(1000, 0)),
  );

  final IndexManager indexManager = persistence.getIndexManager(fixtureUser);
  await indexManager.start();
  await indexManager.addFieldIndex(
    fieldIndex('coll', fieldsAndKinds: <Object>['n', SegmentKind.ascending]),
  );
  await indexManager.updateIndexEntries(<DocumentKey, MaybeDocument?>{
    key('coll/c'): doc('coll/c', 5, map(<Object?>['n', 3])),
  });
  await indexManager.updateCollectionGroup(
    'coll',
    IndexOffset(version(5), key('coll/c'), 1),
  );
});

/// Checks that a started [persistence] holds the fixture cache, read through every cache.
Future<void> expectFixtureCache(
  CacheStorePersistence persistence,
) => persistence.runTransaction('check fixture', () async {
  final MutationQueue queue = persistence.getMutationQueue(fixtureUser);
  await queue.start();
  final List<MutationBatch> batches = await queue.getAllMutationBatches();
  expect(batches.map((MutationBatch b) => b.batchId), <int>[1, 2]);
  expect(batches[0].mutations, _batch1);
  expect(batches[0].localWriteTime, Timestamp(1000, 0));
  expect(batches[1].mutations, _batch2);
  expect(await queue.getMutationBatchCount(), 2);
  expect(await queue.getHighestUnacknowledgedBatchId(), 2);
  expect(queue.lastStreamToken, <int>[1, 2, 3]);
  expect(
    (await queue.getAllMutationBatchesAffectingDocumentKey(
      key('coll/c'),
    )).map((MutationBatch b) => b.batchId),
    <int>[2],
  );

  final DocumentOverlayCache overlays = persistence.getDocumentOverlayCache(
    fixtureUser,
  );
  expect(await overlays.getOverlay(key('coll/a')), Overlay(1, _batch1[0]));
  expect(await overlays.getOverlay(key('coll/c')), Overlay(2, _batch2[0]));
  expect(
    (await overlays.getOverlaysForCollection(path('coll'), 1)).keys,
    <DocumentKey>[key('coll/c')],
  );

  expect(
    await persistence.remoteDocumentCache.get(key('coll/c')),
    doc('coll/c', 5, map(<Object?>['n', 3])),
  );
  expect(
    await persistence.remoteDocumentCache.get(key('coll/d')),
    deletedDoc('coll/d', 6),
  );
  expect(
    await persistence.remoteDocumentCache.get(key('other/e')),
    unknownDoc('other/e', 7),
  );
  expect(
    (await persistence.remoteDocumentCache.getAllDocumentsMatchingQuery(
      query('coll'),
      IndexOffset.none,
    )).map((MapEntry<DocumentKey, Document> e) => e.key).toList(),
    <DocumentKey>[key('coll/c')],
  );

  expect(
    await persistence.queryCache.getQueryData(query('coll').toTarget()),
    _target(),
  );
  expect(
    (await persistence.queryCache.getMatchingKeysForTargetId(2)).toList(),
    <DocumentKey>[key('coll/c')],
  );
  expect(persistence.queryCache.highestTargetId, 2);
  expect(persistence.queryCache.highestListenSequenceNumber, 1);
  expect(persistence.queryCache.lastRemoteSnapshotVersion, version(7));
  expect(persistence.queryCache.targetCount, 1);
  expect(await persistence.queryCache.containsKey(key('coll/c')), isTrue);
  expect(await persistence.queryCache.containsKey(key('other/e')), isFalse);
  // The target and the documents with only a sentinel: other/e (and the documents of the mutations, whose
  // sentinels are written when their batches are removed: none here).
  expect(await persistence.referenceDelegate.getSequenceNumberCount(), 2);

  expect(await persistence.bundleCache.getBundleMetadata('bundle-1'), _bundle);
  expect(await persistence.bundleCache.getNamedQuery('named'), _namedQuery);

  final GlobalsCache globals = persistence.globalsCache;
  expect(await globals.getSessionToken(), <int>[4, 5]);
  final QueuedWritesMergeMark? mark = await globals.getQueuedWritesMergeMark(
    fixtureUser.uid!,
  );
  expect(mark?.batchId, 1);
  expect(mark?.localWriteTime, Timestamp(1000, 0));

  expect(
    await persistence.indexManager.getCollectionParents('coll'),
    <ResourcePath>[ResourcePath.empty],
  );
  expect(
    await persistence.indexManager.getCollectionParents('sub'),
    <ResourcePath>[path('coll/c')],
  );
  final IndexManager indexManager = persistence.getIndexManager(fixtureUser);
  await indexManager.start();
  final List<FieldIndex> indexes = indexManager.getFieldIndexes('coll');
  expect(indexes, hasLength(1));
  expect(
    indexes.single.indexState.offset,
    IndexOffset(version(5), key('coll/c'), 1),
  );
  expect(
    await indexManager.getDocumentsMatchingTarget(
      query('coll').filter(filter('n', '==', 3)).toTarget(),
    ),
    <DocumentKey>[key('coll/c')],
  );
});

/// Every key and value of [store], as hex strings, in key order.
Future<List<List<String>>> dumpStore(CacheStore store) async {
  final List<CacheStoreEntry> entries = await store.scan(
    Uint8List(0),
    Uint8List.fromList(<int>[0xff, 0xff, 0xff, 0xff]),
  );
  return <List<String>>[
    for (final CacheStoreEntry entry in entries)
      <String>[_hex(entry.key), _hex(entry.value)],
  ];
}

/// The entries of a fixture file written by [writeFixtureFile].
List<CacheStoreEntry> readFixtureFile(File file) {
  final List<Object?> rows =
      (jsonDecode(file.readAsStringSync()) as Map<String, Object?>)['entries']!
          as List<Object?>;
  return <CacheStoreEntry>[
    for (final List<Object?> row in rows.cast<List<Object?>>())
      CacheStoreEntry(_unhex(row[0]! as String), _unhex(row[1]! as String)),
  ];
}

/// Writes [entries] (from [dumpStore]) as the fixture of [schemaVersion].
void writeFixtureFile(
  File file,
  int schemaVersion,
  List<List<String>> entries,
) {
  file.parent.createSync(recursive: true);
  final StringBuffer out = StringBuffer()
    ..writeln('{')
    ..writeln('  "schemaVersion": $schemaVersion,')
    ..writeln(
      '  "comment": "Written by writeFixtureCache of '
      'test/unit/firebase/firestore/local/keyvalue_fixture.dart. Never edit or regenerate a fixture of an older '
      'version: it is what the SDK of that version wrote.",',
    )
    ..writeln('  "entries": [');
  for (int i = 0; i < entries.length; i++) {
    out.writeln(
      '    ${jsonEncode(entries[i])}${i == entries.length - 1 ? '' : ','}',
    );
  }
  out
    ..writeln('  ]')
    ..writeln('}');
  file.writeAsStringSync(out.toString());
}

String _hex(Uint8List bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList(<int>[
  for (int i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
