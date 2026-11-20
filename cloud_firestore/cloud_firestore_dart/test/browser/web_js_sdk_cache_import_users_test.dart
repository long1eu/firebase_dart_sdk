// importJsSdkCache with the pending writes of several users (js_sdk_cache_fixtures/users.json: alice, bob and the
// signed-out user, interleaved, written by the real JS SDK signed in through the emulator's mockUserToken): every
// user's writes are imported, in their order, and each user's writes are sent only while that user is signed in, under
// that user.
//
// Against the private emulator (open rules), and against the emulator of tool/start_auth_emulators.sh, whose rules
// (tool/auth_emulators/firestore.rules) let a user write only below users/<uid> and signed_in/, and the signed-out user
// nothing: there a write sent under the wrong user would be accepted or rejected where the JS SDK's was not. That part
// is skipped without test/browser/auth_emulators.txt (tool/test_browser.sh writes it).
//
//   FIRESTORE_EMULATOR_PORT=8404 tool/test_browser.sh both test/browser/web_js_sdk_cache_import_users_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'js_sdk_cache_import_util.dart';

const String project = 'demo-jsimport-users';

/// The Firestore emulator with the rules of tool/auth_emulators, from auth_emulators.txt, or null.
Future<String?> rulesEmulator() async {
  try {
    final web.Response response = await web.window
        .fetch(Uri.base.resolve('auth_emulators.txt').toString().toJS)
        .toDart;
    if (!response.ok) {
      return null;
    }
    for (final String line in (await response.text().toDart).toDart.split(
      '\n',
    )) {
      if (line.startsWith('firestore=')) {
        return line.substring('firestore='.length).trim();
      }
    }
  } catch (_) {
    // No file.
  }
  return null;
}

/// The users of the fixture in the order of their first write, '' for the signed-out user.
List<String> usersOf(Json dump) => <String>{
  for (final Json row in records(dump, 'mutations')) row['userId']! as String,
}.toList();

/// The number of batches of [user] in [dump].
int batchesOf(Json dump, String user) => records(
  dump,
  'mutations',
).where((Json row) => row['userId'] == user).length;

void main() {
  for (final String target in <String>['open', 'rules']) {
    test(
      'every user\'s writes are sent under that user only: $target rules',
      () async {
        final String? skip = await unavailable(Destination.sqliteIndexedDb);
        if (skip != null) {
          markTestSkipped(skip);
          return;
        }
        final String? host = target == 'rules' ? await rulesEmulator() : null;
        if (target == 'rules' && host == null) {
          markTestSkipped(
            'no auth_emulators.txt: the emulator with rules is not running',
          );
          return;
        }
        final Json users = await fixture('users');
        final Json expected =
            ((users['expected']! as Json)[target]! as Map<Object?, Object?>)
                .cast();
        final List<String> paths = expected.keys.toList();
        await clearProject(project, host: host);
        final String jsApp = await loadAsJsApp(users, projectId: project);
        final String appName = uniqueName('dart-users');
        expect(usersOf(users), <String>['alice', '', 'bob']);

        // Signed out: the import takes every user's writes, and this user's are the only ones pending.
        ImportClient client = await openClient(
          projectId: project,
          destination: Destination.sqliteIndexedDb,
          appName: appName,
          host: host,
        );
        await client.firestore.disableNetwork();
        final JsSdkCacheImportResult result = await importJsSdkCache(
          client.firestore,
          jsAppName: jsApp,
        );
        expect(result.users, 3);
        expect(result.batches, records(users, 'mutations').length);
        expect(
          (await jsStoreCounts(jsDatabaseName(jsApp, project)))!['mutations'],
          0,
        );
        expect(
          await client.firestore.getPendingWriteCount(),
          batchesOf(users, ''),
        );
        // The local view of the signed-out user does not include the writes of the others.
        final QuerySnapshot<Json> aliceNotes = await client.firestore
            .collection('users/alice/notes')
            .get(const GetOptions(source: Source.cache));
        // Only the signed-out user's own write there, not alice's note.
        expect(
          aliceNotes.docs.map((DocumentSnapshot<Json> d) => d.id),
          <String>['anon'],
        );
        final QuerySnapshot<Json> open = await client.firestore
            .collection('open')
            .get(const GetOptions(source: Source.cache));
        expect(open.docs.map((DocumentSnapshot<Json> d) => d.id), <String>[
          'anon1',
        ]);
        await client.firestore.enableNetwork();
        await client.firestore.waitForPendingWrites();
        expect(await client.firestore.getPendingWriteCount(), 0);
        // Only the signed-out user's writes reached the backend.
        final Json afterSignedOut = await readBackend(
          project,
          paths,
          host: host,
        );
        expect(afterSignedOut['users/alice/notes/n1'], isNull);
        expect(afterSignedOut['users/bob/notes/n1'], isNull);
        expect(afterSignedOut['signed_in/alice'], isNull);
        expect(
          afterSignedOut['open/anon1'],
          expected['open/anon1'] == null ? isNull : isNotNull,
        );
        expect(
          afterSignedOut['users/alice/notes/anon'],
          expected['users/alice/notes/anon'] == null ? isNull : isNotNull,
        );
        await client.close();

        // Then each user signs in on the same cache, and their writes go, in their order.
        for (final String user in <String>['alice', 'bob']) {
          client = await openClient(
            projectId: project,
            destination: Destination.sqliteIndexedDb,
            appName: appName,
            uid: user,
            host: host,
          );
          await client.firestore.disableNetwork();
          expect(
            await client.firestore.getPendingWriteCount(),
            batchesOf(users, user),
            reason: user,
          );
          await client.firestore.enableNetwork();
          await client.firestore.waitForPendingWrites();
          expect(
            await client.firestore.getPendingWriteCount(),
            0,
            reason: user,
          );
          await client.close();
          if (user == 'alice') {
            // bob has not signed in yet: none of his writes went with alice's.
            final Json afterAlice = await readBackend(
              project,
              paths,
              host: host,
            );
            expect(afterAlice['users/bob/notes/n1'], isNull);
            expect(afterAlice['users/bob/notes/n2'], isNull);
            expect(afterAlice['users/alice/notes/n1'], isNotNull);
          }
        }
        await expectBackend(
          project,
          expected,
          referenceProject: users['referenceProject']! as String,
          host: host,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
