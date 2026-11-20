// importJsSdkCache sends each pending write of the JS SDK exactly once: an import stopped at every point of its
// protocol (a fault injected through jsSdkCacheImportFaultForTesting, as a crash of the page would) and run again
// after a reload (a new client on the same cache) loses no write and imports none twice; the backend ends up as when
// the JS SDK sent the writes itself (js_sdk_cache_fixtures/writes.json, whose writes increment counters: a write sent
// twice shows). Also the refusals: a JS tab that may still run (detected from the rows a running JS SDK keeps, the
// live_*.json fixtures, dumped while the JS client ran), and deleteJsSdkCache before the writes were imported.
//
//   FIRESTORE_EMULATOR_PORT=8404 tool/test_browser.sh both test/browser/web_js_sdk_cache_import_exactly_once_test.dart

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_importer.dart'
    show jsSdkCacheImportFaultForTesting;
import 'package:test/test.dart';

import 'js_sdk_cache_fixture.dart';
import 'js_sdk_cache_import_util.dart';

const String project = 'demo-jsimport';

class InjectedFault implements Exception {
  const InjectedFault(this.point);

  final String point;

  @override
  String toString() => 'InjectedFault($point)';
}

/// Fails the import once at [point].
void failAt(String point) {
  addTearDown(() => jsSdkCacheImportFaultForTesting = null);
  jsSdkCacheImportFaultForTesting = (String reached) {
    if (reached == point) {
      jsSdkCacheImportFaultForTesting = null;
      throw InjectedFault(point);
    }
  };
}

/// The writes fixture, its project seeded in the emulator, loaded as the database of a new JS app.
Future<(Json, String)> loadWrites() async {
  final Json writes = await fixture('writes');
  await clearProject(project);
  await seedProject(project, (writes['seed']! as Map<Object?, Object?>).cast());
  return (writes, await loadAsJsApp(writes, projectId: project));
}

Json expectedOf(Json writes) =>
    ((writes['expected']! as Json)['open']! as Map<Object?, Object?>).cast();

Future<ImportClient> client(String appName, {String? uid}) => openClient(
  projectId: project,
  destination: Destination.sqliteIndexedDb,
  appName: appName,
  uid: uid,
);

/// Sends what the client of [appName] has pending and checks that the backend holds what the JS SDK's own sending
/// left.
Future<void> sendAndCompare(ImportClient c, Json writes) async {
  await c.firestore.enableNetwork();
  await c.firestore.waitForPendingWrites();
  expect(await c.firestore.getPendingWriteCount(), 0);
  await expectBackend(
    project,
    expectedOf(writes),
    referenceProject: writes['referenceProject']! as String,
  );
}

/// A live fixture with the owner lease refreshed [ownerAge] ago and the client metadata [metadataAge] ago.
Future<(Json, String)> live(
  String name, {
  required Duration ownerAge,
  required Duration metadataAge,
}) async {
  final Json dump = await fixture(name);
  final int now = DateTime.now().millisecondsSinceEpoch;
  for (final Json owner in records(dump, 'owner')) {
    owner['leaseTimestampMs'] = now - ownerAge.inMilliseconds;
  }
  for (final Json client in records(dump, 'clientMetadata')) {
    client['updateTimeMs'] = now - metadataAge.inMilliseconds;
  }
  return (dump, await loadAsJsApp(dump, projectId: project));
}

String clientIdOf(Json dump) =>
    records(dump, 'clientMetadata').single['clientId']! as String;

void main() {
  String? skip;
  setUpAll(() async => skip = await unavailable(Destination.sqliteIndexedDb));

  group('stopped and run again after a reload, exactly once:', () {
    // The point, and whether the first call fails (the others finish the import and report the failed removal).
    const Map<String, bool> points = <String, bool>{
      'documents': true,
      'step4': true,
      'step4Committed': true,
      'removal:1': false,
      'removal:7': false,
      'step5Committed': false,
    };
    for (final MapEntry<String, bool> point in points.entries) {
      test(point.key, () async {
        if (skip != null) {
          markTestSkipped(skip!);
          return;
        }
        final (Json writes, String jsApp) = await loadWrites();
        final String dbName = jsDatabaseName(jsApp, project);
        final int batches = records(writes, 'mutations').length;
        final Map<String, int>? full = await jsStoreCounts(dbName);
        final String appName = uniqueName('dart-fault');
        ImportClient c = await client(appName);
        await c.firestore.disableNetwork();
        failAt(point.key);
        final bool imported;
        if (point.value) {
          await expectLater(
            importJsSdkCache(c.firestore, jsAppName: jsApp),
            throwsA(isA<InjectedFault>()),
          );
          imported = point.key == 'step4Committed';
        } else {
          final JsSdkCacheImportResult result = await importJsSdkCache(
            c.firestore,
            jsAppName: jsApp,
          );
          expect(result.batches, batches);
          expect(
            result.skipped,
            contains(
              startsWith(
                'removal of the imported writes from the JS database: failed',
              ),
            ),
          );
          imported = true;
        }
        expect(
          await c.firestore.getPendingWriteCount(),
          imported ? batches : 0,
        );
        if (point.key.startsWith('removal:') || !imported) {
          // The removal is one transaction: all of it or none.
          expect(await jsStoreCounts(dbName), full);
        } else if (point.key == 'step5Committed') {
          expect((await jsStoreCounts(dbName))!['mutations'], 0);
        }

        // The reload.
        await c.close();
        c = await client(appName);
        await c.firestore.disableNetwork();
        expect(
          await c.firestore.getPendingWriteCount(),
          imported ? batches : 0,
        );
        final JsSdkCacheImportResult again = await importJsSdkCache(
          c.firestore,
          jsAppName: jsApp,
        );
        expect(again.batches, imported ? 0 : batches);
        expect(
          again.status,
          imported
              ? JsSdkCacheImportStatus.nothingToImport
              : JsSdkCacheImportStatus.imported,
        );
        expect(await c.firestore.getPendingWriteCount(), batches);
        expect(await jsStoreCounts(dbName), <String, int>{
          'version': 18,
          'mutations': 0,
          'documentMutations': 0,
          'documentOverlays': 0,
          'remoteDocumentsV14': 0,
        });
        // A third call has nothing left.
        expect(
          (await importJsSdkCache(c.firestore, jsAppName: jsApp)).batches,
          0,
        );
        await sendAndCompare(c, writes);
        expect(await deleteJsSdkCache(c.firestore, jsAppName: jsApp), isTrue);
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  test(
    'stopped inside the transaction of step 4 and run again on the same client',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final (Json writes, String jsApp) = await loadWrites();
      final int batches = records(writes, 'mutations').length;
      final ImportClient c = await client(uniqueName('dart-step4'));
      await c.firestore.disableNetwork();
      failAt('step4');
      await expectLater(
        importJsSdkCache(c.firestore, jsAppName: jsApp),
        throwsA(isA<InjectedFault>()),
      );
      expect(await c.firestore.getPendingWriteCount(), 0);
      expect(
        (await importJsSdkCache(c.firestore, jsAppName: jsApp)).batches,
        batches,
      );
      expect(await c.firestore.getPendingWriteCount(), batches);
      // The client writes on after the import, its batches after the imported ones.
      c.firestore.doc('docs/after').set(<String, Object?>{
        'after': true,
      }).ignore();
      expect(await c.firestore.getPendingWriteCount(), batches + 1);
      await sendAndCompare(c, writes);
      expect(
        (await readBackend(project, <String>['docs/after']))['docs/after'],
        isNotNull,
      );
    },
  );

  test(
    'the JS database deleted while the removal was pending: nothing lost',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final (Json writes, String jsApp) = await loadWrites();
      final int batches = records(writes, 'mutations').length;
      final String appName = uniqueName('dart-deleted');
      ImportClient c = await client(appName);
      await c.firestore.disableNetwork();
      failAt('step4Committed');
      await expectLater(
        importJsSdkCache(c.firestore, jsAppName: jsApp),
        throwsA(isA<InjectedFault>()),
      );
      await c.close();
      await deleteJsDatabase(jsDatabaseName(jsApp, project));
      c = await client(appName);
      await c.firestore.disableNetwork();
      expect(
        (await importJsSdkCache(c.firestore, jsAppName: jsApp)).status,
        JsSdkCacheImportStatus.noJsDatabase,
      );
      expect(await c.firestore.getPendingWriteCount(), batches);
      await sendAndCompare(c, writes);
    },
  );

  test(
    'a JS database made again with other batches under the same ids: they are not removed',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final (Json writes, String jsApp) = await loadWrites();
      final String dbName = jsDatabaseName(jsApp, project);
      final String appName = uniqueName('dart-recreated');
      ImportClient c = await client(appName);
      await c.firestore.disableNetwork();
      failAt('step4Committed');
      await expectLater(
        importJsSdkCache(c.firestore, jsAppName: jsApp),
        throwsA(isA<InjectedFault>()),
      );
      await c.close();
      // A JS tab deleted the database and wrote other batches, which got the same ids.
      final Json other = await fixture('writes');
      for (final Json row in records(other, 'mutations')) {
        row['localWriteTimeMs'] = (row['localWriteTimeMs']! as num) + 1;
      }
      await loadJsSdkCacheDump(other, databaseName: dbName);
      c = await client(appName);
      await c.firestore.disableNetwork();
      // They are not removed, and not imported behind the imported ones of the same user.
      await expectLater(
        importJsSdkCache(c.firestore, jsAppName: jsApp),
        refusal(JsSdkCacheImportRefusal.pendingWritesInCache),
      );
      expect(
        (await jsStoreCounts(dbName))!['mutations'],
        records(other, 'mutations').length,
      );
    },
  );

  test(
    'the pending writes of another user in this cache do not block the import',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final (Json writes, String jsApp) = await loadWrites();
      final int batches = records(writes, 'mutations').length;
      final String appName = uniqueName('dart-carol');
      ImportClient c = await client(appName, uid: 'carol');
      await c.firestore.disableNetwork();
      c.firestore.doc('carol/doc').set(<String, Object?>{
        'by': 'carol',
      }).ignore();
      expect(await c.firestore.getPendingWriteCount(), 1);
      final JsSdkCacheImportResult result = await importJsSdkCache(
        c.firestore,
        jsAppName: jsApp,
      );
      expect(result.users, 1);
      expect(result.batches, batches);
      // carol is signed in: the imported writes are the signed-out user's.
      expect(await c.firestore.getPendingWriteCount(), 1);
      await c.close();
      c = await client(appName);
      await c.firestore.disableNetwork();
      expect(await c.firestore.getPendingWriteCount(), batches);
      await sendAndCompare(c, writes);
    },
  );

  group('a JS tab that may still run:', () {
    const Duration fresh = Duration.zero;
    const Duration stale = Duration(seconds: 6);
    // (fixture, owner lease age, client metadata age, zombied, refused)
    final List<(String, Duration, Duration, bool, bool)>
    cases = <(String, Duration, Duration, bool, bool)>[
      ('live_single_tab', fresh, fresh, false, true),
      ('live_multi_tab', fresh, fresh, false, true),
      ('live_single_tab', stale, fresh, false, true),
      ('live_single_tab', stale, const Duration(minutes: 29), false, true),
      ('live_single_tab', stale, const Duration(minutes: 31), false, false),
      ('live_multi_tab', stale, const Duration(minutes: 31), false, false),
      ('live_single_tab', fresh, fresh, true, false),
      ('live_multi_tab', fresh, fresh, true, false),
      // A time in the future is not a live client, as in the JS SDK (`isWithinAge`).
      (
        'live_single_tab',
        const Duration(hours: -1),
        const Duration(hours: -1),
        false,
        false,
      ),
    ];
    for (final (
          String name,
          Duration ownerAge,
          Duration metadataAge,
          bool zombied,
          bool refused,
        )
        in cases) {
      test(
        '$name, lease ${ownerAge.inSeconds} s and metadata ${metadataAge.inSeconds} s old'
        '${zombied ? ', marked as gone' : ''}: ${refused ? 'refused' : 'imported'}',
        () async {
          if (skip != null) {
            markTestSkipped(skip!);
            return;
          }
          final (Json dump, String jsApp) = await live(
            name,
            ownerAge: ownerAge,
            metadataAge: metadataAge,
          );
          final String dbName = jsDatabaseName(jsApp, project);
          if (zombied) {
            markJsClientZombied(dbName, clientIdOf(dump));
          }
          final Map<String, int>? before = await jsStoreCounts(dbName);
          final ImportClient c = await client(uniqueName('dart-live'));
          await c.firestore.disableNetwork();
          if (refused) {
            await expectLater(
              importJsSdkCache(c.firestore, jsAppName: jsApp),
              refusal(JsSdkCacheImportRefusal.jsClientActive),
            );
            expect(await c.firestore.getPendingWriteCount(), 0);
            expect(await jsStoreCounts(dbName), before);
            // Not deleted either, even when its writes may go.
            await expectLater(
              deleteJsSdkCache(
                c.firestore,
                jsAppName: jsApp,
                discardPendingWrites: true,
              ),
              refusal(JsSdkCacheImportRefusal.jsClientActive),
            );
            expect(await jsStoreCounts(dbName), before);
          } else {
            expect(
              (await importJsSdkCache(c.firestore, jsAppName: jsApp)).batches,
              1,
            );
            expect(await c.firestore.getPendingWriteCount(), 1);
          }
        },
      );
    }
  });

  group('deleteJsSdkCache', () {
    test(
      'refuses while the writes were not imported, deletes when told to discard them',
      () async {
        if (skip != null) {
          markTestSkipped(skip!);
          return;
        }
        final (Json writes, String jsApp) = await loadWrites();
        final String dbName = jsDatabaseName(jsApp, project);
        final Map<String, int>? before = await jsStoreCounts(dbName);
        final ImportClient c = await client(uniqueName('dart-delete'));
        await expectLater(
          deleteJsSdkCache(c.firestore, jsAppName: jsApp),
          refusal(JsSdkCacheImportRefusal.pendingWritesNotImported),
        );
        expect(await jsStoreCounts(dbName), before);
        expect(
          await deleteJsSdkCache(
            c.firestore,
            jsAppName: jsApp,
            discardPendingWrites: true,
          ),
          isTrue,
        );
        expect(await jsStoreCounts(dbName), isNull);
        expect(await deleteJsSdkCache(c.firestore, jsAppName: jsApp), isFalse);
      },
    );

    test(
      'deletes after an import whose removal failed: the writes are in this cache',
      () async {
        if (skip != null) {
          markTestSkipped(skip!);
          return;
        }
        final (Json writes, String jsApp) = await loadWrites();
        final String dbName = jsDatabaseName(jsApp, project);
        final int batches = records(writes, 'mutations').length;
        final ImportClient c = await client(uniqueName('dart-delete-pending'));
        await c.firestore.disableNetwork();
        failAt('removal:1');
        expect(
          (await importJsSdkCache(c.firestore, jsAppName: jsApp)).batches,
          batches,
        );
        expect((await jsStoreCounts(dbName))!['mutations'], batches);
        expect(await deleteJsSdkCache(c.firestore, jsAppName: jsApp), isTrue);
        expect(await jsStoreCounts(dbName), isNull);
        expect(
          (await importJsSdkCache(c.firestore, jsAppName: jsApp)).status,
          JsSdkCacheImportStatus.noJsDatabase,
        );
        expect(await c.firestore.getPendingWriteCount(), batches);
        await sendAndCompare(c, writes);
      },
    );

    test(
      'a JS database with documents only is deleted without an import',
      () async {
        if (skip != null) {
          markTestSkipped(skip!);
          return;
        }
        final Json dump = await fixture('legacy');
        for (final Object? s in dump['stores']! as List<Object?>) {
          final Json store = (s! as Map<Object?, Object?>).cast();
          if (store['name'] == 'mutations' ||
              store['name'] == 'documentMutations') {
            store['records'] = <Object?>[];
          }
        }
        final String jsApp = await loadAsJsApp(dump, projectId: 'demo-idb');
        final ImportClient c = await openClient(
          projectId: 'demo-idb',
          destination: Destination.sqliteIndexedDb,
          appName: uniqueName('dart-docs-only'),
        );
        expect(await deleteJsSdkCache(c.firestore, jsAppName: jsApp), isTrue);
      },
    );
  });
}
