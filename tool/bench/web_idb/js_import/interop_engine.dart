// The engine side of the interop check (interop_check.sh): the IndexedDB engine of this repository
// (IndexedDbCacheSettings), one step per page load, chosen by the JSON in the URL hash ({step, project, user, port}).
// Reports in window.interopResult like interop.js.
//
// Uses internals (the client, its local store and index manager) to assert that a query is served by an index.
// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

late final Map<String, Object?> params;
final List<Map<String, Object?>> checks = <Map<String, Object?>>[];

/// Whether the client stays open until the tab is closed.
bool hold = false;

void check(String name, bool pass, [Object? detail = '']) {
  checks.add(<String, Object?>{
    'name': name,
    'pass': pass,
    'detail': detail is String ? detail : '$detail',
  });
}

String get project => params['project']! as String;

Future<FirebaseFirestore> open() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(apiKey: 'fake', appId: 'fake', projectId: project),
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(cacheSettings: IndexedDbCacheSettings()).withEmulator(
      '127.0.0.1',
      params['port']! as int,
      mockUserToken: <String, Object?>{'sub': params['user']},
    ),
  );
  await firestore.initialized;
  return firestore;
}

const GetOptions cache = GetOptions(source: Source.cache);
const GetOptions server = GetOptions(source: Source.server);

List<String> ids(QuerySnapshot<Map<String, Object?>> snapshot) => <String>[
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot.docs)
    doc.id,
];

const String cityIndex =
    '{"indexes":[{"collectionGroup":"cities","queryScope":"COLLECTION","fields":['
    '{"fieldPath":"country","order":"ASCENDING"},{"fieldPath":"pop","order":"ASCENDING"}]}]}';
const String kindIndex =
    '{"indexes":[{"collectionGroup":"kinds","queryScope":"COLLECTION","fields":['
    '{"fieldPath":"v","order":"ASCENDING"}]}]}';

Map<String, Object?> kindValues(FirebaseFirestore firestore) =>
    <String, Object?>{
      'map': <String, Object?>{
        'b': 1,
        'a': 2,
        '10': 'ten',
        '2': 'two',
        'z': <String, Object?>{'y': 1, 'x': 2},
      },
      'timestamp': Timestamp.fromMillisecondsSinceEpoch(1700000000123),
      'timestamp0': const Timestamp(0, 5),
      'reference': firestore.doc('kinds/target'),
      'bytes': Blob(Uint8List.fromList(<int>[0, 1, 255, 0])),
      'array': <Object?>[
        1,
        'two',
        <String, Object?>{'k': true},
        null,
      ],
      'integer': 42,
      'double': 2.5,
      'negzero': -0.0,
      'nan': double.nan,
      'vector': VectorValue(const <double>[1, 2.5, -3]),
      'string': 'héllo \u{1F600}',
      'bool': true,
      'geopoint': const GeoPoint(-0.0, 12.5),
      'null': null,
    };

/// The keys the index of [query] returns, or null when no index serves it (`getDocumentsMatchingTarget`).
Future<List<String>?> indexKeys(
  FirebaseFirestore firestore,
  Query<Map<String, Object?>> query,
) async {
  final IndexManager indexManager =
      firestore.client.localStore.indexManagerForCurrentUser;
  final Target target = query.query.toTarget();
  if (indexManager.getIndexType(target) != IndexType.full) {
    return null;
  }
  final List<DocumentKey>? keys = await firestore.client.persistence
      .runTransactionAndReturn<List<DocumentKey>?>(
        'Read an index',
        () => indexManager.getDocumentsMatchingTarget(target),
      );
  return keys?.map((DocumentKey key) => key.path.getLastSegment()).toList()
    ?..sort();
}

String element(Object? json) {
  final String text = jsonEncode(json);
  return '${utf8.encode(text).length}$text';
}

/// The bundle of interop.js, built the same way.
List<int> buildBundle() {
  final String parent = 'projects/$project/databases/(default)/documents';
  const Map<String, Object?> t = <String, Object?>{
    'seconds': '1700000000',
    'nanos': 123456000,
  };
  final List<String> body = <String>[
    element(<String, Object?>{
      'namedQuery': <String, Object?>{
        'name': 'nq',
        'readTime': t,
        'bundledQuery': <String, Object?>{
          'parent': parent,
          'structuredQuery': <String, Object?>{
            'from': <Object?>[
              <String, Object?>{'collectionId': 'bund'},
            ],
            'orderBy': <Object?>[
              <String, Object?>{
                'field': <String, Object?>{'fieldPath': 'n'},
                'direction': 'DESCENDING',
              },
            ],
            'limit': <String, Object?>{'value': 1},
          },
          'limitType': 'FIRST',
        },
      },
    }),
  ];
  for (final (String id, int n) in <(String, int)>[('x', 1), ('y', 2)]) {
    final String name = '$parent/bund/$id';
    body
      ..add(
        element(<String, Object?>{
          'documentMetadata': <String, Object?>{
            'name': name,
            'readTime': t,
            'exists': true,
            'queries': <String>['nq'],
          },
        }),
      )
      ..add(
        element(<String, Object?>{
          'document': <String, Object?>{
            'name': name,
            'createTime': t,
            'updateTime': t,
            'fields': <String, Object?>{
              'n': <String, Object?>{'integerValue': '$n'},
            },
          },
        }),
      );
  }
  final int total = body.fold(
    0,
    (int n, String e) => n + utf8.encode(e).length,
  );
  final String metadata = element(<String, Object?>{
    'metadata': <String, Object?>{
      'id': 'bundle',
      'createTime': t,
      'version': 1,
      'totalDocuments': 2,
      'totalBytes': total,
    },
  });
  return utf8.encode('$metadata${body.join()}');
}

Future<int> backfillAll(FirebaseFirestore firestore) async {
  int total = 0;
  for (
    int n = await firestore.client.backfillIndexes();
    n > 0;
    n = await firestore.client.backfillIndexes()
  ) {
    total += n;
  }
  return total;
}

final Map<String, Future<void> Function()>
steps = <String, Future<void> Function()>{
  // A: reads what the JS SDK wrote, as alice, then sends alice's writes.
  'a-read': () async {
    final FirebaseFirestore firestore = await open();
    await firestore.disableNetwork();
    final QuerySnapshot<Map<String, Object?>> docs = await firestore
        .collection('docs')
        .get(cache);
    check(
      'A3 the documents of the JS listen, offline',
      ids(docs).join(',') == 'd1,d2,d3' &&
          docs.docs.first['title'] == 'changed by alice' &&
          docs.docs.first.metadata.hasPendingWrites &&
          docs.docs[1]['title'] == 'doc d2',
      ids(docs),
    );
    final Query<Map<String, Object?>> ro = firestore
        .collection('cities')
        .where('country', isEqualTo: 'RO')
        .orderBy('pop');
    final List<String>? keys = await indexKeys(firestore, ro);
    check(
      'A3 the JS index serves the query (index lookup, not a scan)',
      keys?.join(',') == 'c0,c1,c2,c3',
      'indexes=${firestore.client.localStore.getFieldIndexes().length} keys=$keys',
    );
    check(
      'A3 the query result',
      ids(await ro.get(cache)).join(',') == 'c0,c1,c2,c3',
    );
    final Query<Map<String, Object?>>? nq = await firestore.namedQuery('nq');
    final List<String>? nqIds = nq == null ? null : ids(await nq.get(cache));
    check(
      'A3 the named query of the JS bundle',
      nqIds?.join(',') == 'y',
      nqIds,
    );
    final int pending = await firestore.getPendingWriteCount();
    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    final Map<String, Object?>? sent =
        (await firestore.doc('pend/a1').get(server)).data();
    check(
      'A3 the engine sent the pending writes of the JS SDK (alice)',
      pending == 2 && sent?['by'] == 'alice',
      'pending=$pending sent=$sent',
    );
    await firestore.terminate();
  },
  'a-read-bob': () async {
    final FirebaseFirestore firestore = await open();
    final int pending = await firestore.getPendingWriteCount();
    await firestore.waitForPendingWrites();
    final Map<String, Object?>? sent =
        (await firestore.doc('pend/b1').get(server)).data();
    check(
      'A4 the engine sent the pending write of the JS SDK (bob)',
      pending == 1 && sent?['by'] == 'bob',
      'pending=$pending sent=$sent',
    );
    await firestore.terminate();
  },

  // B: the engine writes, as alice.
  'b-write': () async {
    final FirebaseFirestore firestore = await open();
    await firestore.setIndexConfigurationFromJSON(cityIndex);
    // Over 1 MB of documents with no target, written first: the oldest sequence numbers.
    final String pad = 'x' * 40000;
    for (int i = 0; i < 32; i++) {
      await firestore.doc('bulk/$i').set(<String, Object?>{
        'mark': null,
        'pad': pad,
      });
    }
    for (int i = 0; i < 20; i++) {
      await firestore.doc('cities/c$i').set(<String, Object?>{
        'country': i < 4 ? 'RO' : 'other',
        'pop': 1000 * i,
      });
    }
    for (final String id in <String>['d1', 'd2', 'd3']) {
      await firestore.doc('docs/$id').set(<String, Object?>{
        'title': 'doc $id',
      });
    }
    await firestore
        .collection('docs')
        .snapshots(includeMetadataChanges: true)
        .firstWhere(
          (QuerySnapshot<Map<String, Object?>> s) =>
              !s.metadata.isFromCache && s.size == 3,
        );
    await firestore.collection('cities').get(server);
    await firestore.loadBundle(buildBundle()).future;
    final int filled = await backfillAll(firestore);
    check('B1 the engine filled its index', filled >= 20, 'documents=$filled');
    await firestore.disableNetwork();
    firestore.doc('pend/a1').set(<String, Object?>{'by': 'alice'}).ignore();
    firestore.doc('docs/d1').update(<String, Object?>{
      'title': 'changed by alice',
    }).ignore();
    firestore.doc('bulk/0').update(<String, Object?>{'mark': 'alice'}).ignore();
    await firestore.doc('bulk/0').get(cache);
    check(
      'B1 three pending writes of alice',
      await firestore.getPendingWriteCount() == 3,
    );
    await firestore.terminate();
  },
  'b-write-bob': () async {
    final FirebaseFirestore firestore = await open();
    await firestore.disableNetwork();
    firestore.doc('pend/b1').set(<String, Object?>{'by': 'bob'}).ignore();
    firestore.doc('bulk/1').update(<String, Object?>{'mark': 'bob'}).ignore();
    await firestore.doc('bulk/1').get(cache);
    check(
      'B2 two pending writes of bob',
      await firestore.getPendingWriteCount() == 2,
    );
    await firestore.terminate();
  },

  // C: the lease.
  'c-refused': () async {
    try {
      await open();
      check(
        'C the engine is refused while a JS client holds the lease',
        false,
        'it opened',
      );
    } on FirestoreException catch (e) {
      check(
        'C the engine is refused while a JS client holds the lease',
        e.errorCode == FirestoreErrorCode.failedPrecondition,
        e.message,
      );
    }
  },
  'c-open': () async {
    final FirebaseFirestore firestore = await open();
    await firestore.disableNetwork();
    final DocumentSnapshot<Map<String, Object?>> js = await firestore
        .doc('lease/js')
        .get(cache);
    check(
      'C the engine opens after the JS tab closed, and reads its write',
      js['by'] == 'js',
      js.data(),
    );
    firestore.doc('lease/engine').set(<String, Object?>{
      'by': 'engine',
    }).ignore();
    await firestore.doc('lease/engine').get(cache);
    web.document.title = 'holding';
  },

  // D: the engine's index on `v`, then equality queries on the JS SDK's one.
  'd-write': () async {
    final FirebaseFirestore firestore = await open();
    await firestore.setIndexConfigurationFromJSON(kindIndex);
    final Map<String, Object?> values = kindValues(firestore);
    for (final MapEntry<String, Object?> entry in values.entries) {
      await firestore.doc('kinds/${entry.key}').set(<String, Object?>{
        'v': entry.value,
      });
    }
    await firestore.collection('kinds').get(server);
    final int filled = await backfillAll(firestore);
    check(
      'D3 the engine filled its index',
      filled >= values.length,
      'documents=$filled',
    );
    await firestore.terminate();
  },
  'd-read': () async {
    final FirebaseFirestore firestore = await open();
    await firestore.disableNetwork();
    for (final MapEntry<String, Object?> entry in kindValues(
      firestore,
    ).entries) {
      final Query<Map<String, Object?>> query = entry.value == null
          ? firestore.collection('kinds').where('v', isNull: true)
          : firestore.collection('kinds').where('v', isEqualTo: entry.value);
      List<String>? keys;
      List<String>? result;
      String error = '';
      try {
        keys = await indexKeys(firestore, query);
        result = ids(await query.get(cache));
      } catch (e) {
        error = '$e';
      }
      check(
        'D2 ${entry.key}: the engine finds the JS entry',
        keys?.join(',') == entry.key && result?.join(',') == entry.key,
        'index=$keys result=$result $error',
      );
    }
    await firestore.terminate();
  },
};

Future<void> main() async {
  params =
      jsonDecode(Uri.decodeComponent(web.window.location.hash.substring(1)))
          as Map<String, Object?>;
  try {
    await steps[params['step']]!();
  } catch (e, st) {
    check('${params['step']} ran without error', false, '$e\n$st');
  }
  globalContext['interopResult'] = jsonEncode(<String, Object?>{
    'state': hold ? 'holding' : 'result',
    'checks': checks,
  }).toJS;
  web.document.title = hold ? 'holding' : 'result';
}
