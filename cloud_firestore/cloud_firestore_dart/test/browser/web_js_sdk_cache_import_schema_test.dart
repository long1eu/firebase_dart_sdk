// importJsSdkCache on the JS SDK's database at every schema version it claims to read (5 to 18), on older and newer
// ones (refused, the database untouched), and on rows in the shapes older JS SDKs wrote.
//
// The databases at versions 5 to 17 are HAND-BUILT from js_sdk_cache_fixture.json (schema 18, written by the real JS
// SDK) by the schema history of the JS SDK (indexeddb_schema_converter.ts, `createOrUpgrade`): the stores a version
// did not have yet are left out, the cached documents are in the legacy `remoteDocuments` store before version 13, and
// `documentOverlays` is empty at versions 12 and 13 (the migration to 14 fills it). The `mutations` and
// `documentMutations` stores and the shape of their rows did not change from version 4 on, so the rows are the real
// ones. The legacy rows of the last tests are hand-built too, in the shapes of `fromDbMutationBatch` of the JS SDK.
//
//   FIRESTORE_EMULATOR_PORT=8404 tool/test_browser.sh both test/browser/web_js_sdk_cache_import_schema_test.dart

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import 'js_sdk_cache_import_util.dart';

const String project = 'demo-idb';
const GetOptions cache = GetOptions(source: Source.cache);
const String documents = 'projects/$project/databases/(default)/documents';

/// [dump] (schema 18) as the JS SDK would have left it at schema [version]: see the header.
Json atVersion(Json dump, int version) {
  bool existsAt(String store) => switch (store) {
    'globals' => version >= 17,
    'indexConfiguration' || 'indexState' || 'indexEntries' => version >= 15,
    'remoteDocumentsV14' => version >= 13,
    'documentOverlays' => version >= 12,
    'bundles' || 'namedQueries' => version >= 11,
    'collectionParents' => version >= 8,
    'remoteDocumentGlobal' => version >= 6,
    'clientMetadata' => version >= 4,
    // owner, mutationQueues, mutations, documentMutations, targets, targetDocuments, targetGlobal: version 1 or 3.
    _ => true,
  };
  final List<Json> stores = <Json>[
    for (final Object? s in dump['stores']! as List<Object?>)
      if (existsAt((s! as Map<Object?, Object?>)['name']! as String))
        (s as Map<Object?, Object?>).cast(),
  ];
  if (version < 13) {
    // The legacy store: keyed by the path segments, rows without the key parts of remoteDocumentsV14.
    stores.add(<String, Object?>{
      'name': 'remoteDocuments',
      'keyPath': null,
      'autoIncrement': false,
      'indexes': <Object?>[],
      'records': <Object?>[
        for (final Json row in records(dump, 'remoteDocumentsV14'))
          <String, Object?>{
            'key': <Object?>[
              ...row['prefixPath']! as List<Object?>,
              row['collectionGroup'],
              row['documentId'],
            ],
            'value': <String, Object?>{
              for (final MapEntry<String, Object?> e in row.entries)
                if (!<String>{
                  'prefixPath',
                  'collectionGroup',
                  'documentId',
                }.contains(e.key))
                  e.key: e.value,
            },
          },
      ],
    });
  }
  if (version == 12 || version == 13) {
    for (final Json store in stores) {
      if (store['name'] == 'documentOverlays') {
        store['records'] = <Object?>[];
      }
    }
  }
  return <String, Object?>{...dump, 'version': version, 'stores': stores};
}

Future<ImportClient> client(String name) async => openClient(
  projectId: project,
  destination: Destination.sqliteIndexedDb,
  appName: uniqueName(name),
);

/// A batch row of the signed-out user, in the shape of [writes] (proto3 JSON writes).
Json batchRow(int batchId, List<Object?> writes) => <String, Object?>{
  'userId': '',
  'batchId': batchId,
  'localWriteTimeMs': 1700000000000 + batchId,
  'mutations': writes,
};

/// [dump] with [rows] as the only pending batches (and their documentMutations rows).
Json withBatches(Json dump, List<Json> rows) {
  for (final Object? s in dump['stores']! as List<Object?>) {
    final Json store = (s! as Map<Object?, Object?>).cast();
    switch (store['name']) {
      case 'mutations':
        store['records'] = <Object?>[
          for (final Json row in rows)
            <String, Object?>{'key': row['batchId'], 'value': row},
        ];
      case 'documentMutations':
      case 'documentOverlays':
      case 'remoteDocumentsV14':
        store['records'] = <Object?>[];
    }
  }
  return dump;
}

void main() {
  String? skip;
  setUpAll(() async => skip = await unavailable(Destination.sqliteIndexedDb));

  for (int version = 5; version <= 18; version++) {
    test(
      'schema version $version: the pending writes are imported and removed from the JS database',
      () async {
        if (skip != null) {
          markTestSkipped(skip!);
          return;
        }
        final Json dump = atVersion(await fixture('legacy'), version);
        final String jsApp = await loadAsJsApp(dump, projectId: project);
        final ImportClient c = await client('dart-v$version');
        final FirebaseFirestore firestore = c.firestore;
        await firestore.disableNetwork();
        final JsSdkCacheImportResult result = await importJsSdkCache(
          firestore,
          jsAppName: jsApp,
        );
        expect(result.status, JsSdkCacheImportStatus.imported);
        expect(result.users, 2);
        expect(result.batches, 6);
        if (version >= 13) {
          expect(result.documents, 2);
        } else {
          expect(result.documents, 0);
          expect(
            result.skipped,
            contains(contains('schema version $version keeps them in a store')),
          );
        }
        expect(await firestore.getPendingWriteCount(), 5);
        expect(
          (await firestore.doc('items/w2').get(cache)).data(),
          <String, Object?>{
            'count': 6,
            'nested': <String, Object?>{'field': 'v'},
            'tags': <String>['a', 'b'],
          },
        );
        expect(
          (await firestore.doc('items/b1').get(cache)).data(),
          <String, Object?>{'inBatch': true},
        );
        if (version >= 13) {
          expect(
            (await firestore.doc('items/cached1').get(cache)).data()!['title'],
            'updated offline',
          );
        }
        expect(
          await jsStoreCounts(jsDatabaseName(jsApp, project)),
          <String, int>{
            'version': version,
            'mutations': 0,
            'documentMutations': 0,
            if (version >= 12) 'documentOverlays': 0,
            if (version >= 13) 'remoteDocumentsV14': 2,
          },
        );
        // Imported once.
        expect(
          (await importJsSdkCache(firestore, jsAppName: jsApp)).status,
          JsSdkCacheImportStatus.nothingToImport,
        );
        expect(await firestore.getPendingWriteCount(), 5);
      },
    );
  }

  for (final int version in <int>[1, 3, 4, 19, 30]) {
    test(
      'schema version $version is refused and the JS database is left as it was',
      () async {
        if (skip != null) {
          markTestSkipped(skip!);
          return;
        }
        final Json dump = atVersion(
          await fixture('legacy'),
          version < 5 ? 5 : 18,
        )..['version'] = version;
        final String jsApp = await loadAsJsApp(dump, projectId: project);
        final String name = jsDatabaseName(jsApp, project);
        final Map<String, int>? before = await jsStoreCounts(name);
        final ImportClient c = await client('dart-v$version');
        await c.firestore.disableNetwork();
        await expectLater(
          importJsSdkCache(c.firestore, jsAppName: jsApp),
          refusal(JsSdkCacheImportRefusal.unsupportedSchemaVersion),
        );
        expect(await c.firestore.getPendingWriteCount(), 0);
        expect(await jsStoreCounts(name), before);
        expect(before!['version'], version);
        expect(before['mutations'], 6);
        // Not deleted either while it holds writes.
        await expectLater(
          deleteJsSdkCache(c.firestore, jsAppName: jsApp),
          refusal(JsSdkCacheImportRefusal.pendingWritesNotImported),
        );
      },
    );
  }

  test(
    'rows of older JS SDKs: a transform as a separate write, no baseMutations, 64-bit integers, -0',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      await clearProject(project);
      await seedProject(project, <String, Object?>{
        'legacyRows/counter': <String, Object?>{
          'n': <String, Object?>{'integerValue': '1'},
        },
      });
      final Json
      dump = withBatches(atVersion(await fixture('legacy'), 18), <Json>[
        // A set followed by its transform, as the JS SDK wrote them before `updateTransforms` (squashed when read).
        batchRow(1, <Object?>[
          <String, Object?>{
            'update': <String, Object?>{
              'name': '$documents/legacyRows/set',
              'fields': <String, Object?>{
                'a': <String, Object?>{'integerValue': '1'},
              },
            },
          },
          <String, Object?>{
            'transform': <String, Object?>{
              'document': '$documents/legacyRows/set',
              'fieldTransforms': <Object?>[
                <String, Object?>{
                  'fieldPath': 'st',
                  'setToServerValue': 'REQUEST_TIME',
                },
              ],
            },
          },
        ]),
        // An update with an empty mask followed by its transform.
        batchRow(2, <Object?>[
          <String, Object?>{
            'update': <String, Object?>{
              'name': '$documents/legacyRows/counter',
              'fields': <String, Object?>{},
            },
            'updateMask': <String, Object?>{'fieldPaths': <Object?>[]},
            'currentDocument': <String, Object?>{'exists': true},
          },
          <String, Object?>{
            'transform': <String, Object?>{
              'document': '$documents/legacyRows/counter',
              'fieldTransforms': <Object?>[
                <String, Object?>{
                  'fieldPath': 'n',
                  'increment': <String, Object?>{'integerValue': '2'},
                },
              ],
            },
          },
        ]),
        // Values the JS SDK can only hold from elsewhere (a 64-bit integer), and -0.
        batchRow(3, <Object?>[
          <String, Object?>{
            'update': <String, Object?>{
              'name': '$documents/legacyRows/numbers',
              'fields': <String, Object?>{
                'max': <String, Object?>{'integerValue': '9223372036854775807'},
                'min': <String, Object?>{
                  'integerValue': '-9223372036854775808',
                },
                'unsafe': <String, Object?>{'integerValue': '9007199254740993'},
                'negZero': <String, Object?>{'doubleValue': '-0'},
              },
            },
          },
        ]),
      ]);
      final String jsApp = await loadAsJsApp(dump, projectId: project);
      final ImportClient c = await client('dart-legacy-rows');
      final FirebaseFirestore firestore = c.firestore;
      await firestore.disableNetwork();
      final JsSdkCacheImportResult result = await importJsSdkCache(
        firestore,
        jsAppName: jsApp,
      );
      expect(result.batches, 3);
      final Json numbers =
          (await firestore.doc('legacyRows/numbers').get(cache)).data()!;
      if (const bool.fromEnvironment('dart.tool.dart2wasm')) {
        // 64-bit integers; with dart2js the app reads the nearest double, as with the JS SDK (sent exactly, below).
        expect('${numbers['max']}', '9223372036854775807');
        expect('${numbers['min']}', '-9223372036854775808');
        expect('${numbers['unsafe']}', '9007199254740993');
      }
      expect((numbers['negZero']! as double).isNegative, isTrue);
      await firestore.enableNetwork();
      await firestore.waitForPendingWrites();
      final Json backend = await readBackend(project, <String>[
        'legacyRows/set',
        'legacyRows/counter',
        'legacyRows/numbers',
      ]);
      expect(
        normalize(
          backend['legacyRows/set'],
          fromProject: project,
          toProject: project,
        ),
        <String, Object?>{
          'a': <String, Object?>{'integerValue': '1'},
          'st': <String, Object?>{'timestampValue': '<server time>'},
        },
      );
      expect(backend['legacyRows/counter'], <String, Object?>{
        'n': <String, Object?>{'integerValue': '3'},
      });
      if (const bool.fromEnvironment('dart.tool.dart2wasm')) {
        expect(backend['legacyRows/numbers'], <String, Object?>{
          'max': <String, Object?>{'integerValue': '9223372036854775807'},
          'min': <String, Object?>{'integerValue': '-9223372036854775808'},
          'unsafe': <String, Object?>{'integerValue': '9007199254740993'},
          // The emulator keeps -0 as 0, whoever sends it.
          'negZero': <String, Object?>{'doubleValue': 0.0},
        });
      } else {
        // dart2js holds an integer as a double: the value model of this SDK (not the import) rounds what is outside
        // the safe range, and 2^63 - 1 even comes out as -2^63. The JS SDK only writes safe integers (it has no other
        // numbers), so a JS database holds such a write only when it was built by hand.
        expect(
          (backend['legacyRows/numbers']! as Map<Object?, Object?>)['negZero'],
          <String, Object?>{'doubleValue': 0.0},
        );
      }
    },
  );

  test(
    'an unreadable pending write: refused, nothing imported, the JS database untouched',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final Json dump = withBatches(
        atVersion(await fixture('legacy'), 18),
        <Json>[
          batchRow(1, <Object?>[
            <String, Object?>{
              'update': <String, Object?>{
                'name': '$documents/legacyRows/ok',
                'fields': <String, Object?>{},
              },
            },
          ]),
          batchRow(2, <Object?>[
            <String, Object?>{
              'update': <String, Object?>{
                'name': 'not a document name',
                'fields': <String, Object?>{},
              },
            },
          ]),
        ],
      );
      final String jsApp = await loadAsJsApp(dump, projectId: project);
      final ImportClient c = await client('dart-unreadable');
      await c.firestore.disableNetwork();
      await expectLater(
        importJsSdkCache(c.firestore, jsAppName: jsApp),
        refusal(JsSdkCacheImportRefusal.unreadableWrites),
      );
      expect(await c.firestore.getPendingWriteCount(), 0);
      expect(
        (await jsStoreCounts(jsDatabaseName(jsApp, project)))!['mutations'],
        2,
      );
    },
  );

  test(
    'a database of another project is not read: the names of the writes do not match',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      // The fixture's writes name demo-idb; loaded as the database of a demo-other app.
      final Json dump = await fixture('legacy');
      final String jsApp = await loadAsJsApp(dump, projectId: 'demo-other');
      final ImportClient c = await openClient(
        projectId: 'demo-other',
        destination: Destination.sqliteIndexedDb,
        appName: uniqueName('dart-other'),
      );
      await c.firestore.disableNetwork();
      await expectLater(
        importJsSdkCache(c.firestore, jsAppName: jsApp),
        refusal(JsSdkCacheImportRefusal.unreadableWrites),
      );
      expect(await c.firestore.getPendingWriteCount(), 0);
      expect(
        (await jsStoreCounts(
          jsDatabaseName(jsApp, 'demo-other'),
        ))!['mutations'],
        6,
      );
    },
  );
}
