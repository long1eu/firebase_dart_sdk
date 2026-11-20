// `mergeUnsentWrites` against security rules on the emulator: the two documented costs of the setting that rules can
// see, each next to the same writes without the setting.
//
//  * A rejection rejects all the merged writes with the same error, and the local view goes back to the document on
//    the backend.
//  * Writes to other documents made in between reach the backend before the merged write: a rule that reads the
//    document with get() sees its older state.
//
// The rules are loaded into the emulator for a project of their own (demo-merge-rules), so they do not affect the
// other tests. Against a private emulator:
//
//   tool/start_private_emulator.sh 8405
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8405 dart test test/integration/firebase/firestore/merge_unsent_writes_rules_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

const String _projectId = 'demo-merge-rules';

const String _rules = r'''
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // At most 9.
    match /runs/{run}/guarded/{id} {
      allow read: if true;
      allow write: if request.resource.data.v < 10;
    }
    // b only once a is ready, read with get().
    match /runs/{run}/ordered/{id} {
      allow read: if true;
      allow write: if id != 'b'
          || get(/databases/$(database)/documents/runs/$(run)/ordered/a).data.state == 'ready';
    }
  }
}
''';

Future<void> _loadRules() async {
  final String host = IntegrationTestUtil.emulatorHost ?? '127.0.0.1:8080';
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.putUrl(
      Uri.parse('http://$host/emulator/v1/projects/$_projectId:securityRules'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'rules': <String, Object?>{
          'files': <Object?>[
            <String, Object?>{'name': 'firestore.rules', 'content': _rules},
          ],
        },
      }),
    );
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('Loading the rules failed: $body');
    }
  } finally {
    client.close();
  }
}

/// 'ok', or the code of the error the write failed with.
Future<String> _outcome(Future<void> write) => write.then(
  (_) => 'ok',
  onError: (Object e) => e is FirestoreException ? e.code : '$e',
);

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/merge_rules';

  setUpAll(_loadRules);
  tearDown(() => IntegrationTestUtil.tearDown());

  Future<FirebaseFirestore> client(bool merge) =>
      IntegrationTestUtil.testFirestoreInstance(
        _projectId,
        InternalLogLevel.w,
        IntegrationTestUtil.newTestSettings().copyWith(
          cacheSettings: PersistentCacheSettings(mergeUnsentWrites: merge),
        ),
        'integration/merge_rules_$merge',
      );

  DocumentReference<Map<String, Object?>> run(
    FirebaseFirestore firestore,
    String path,
  ) => firestore.doc(
    'runs/${DateTime.now().microsecondsSinceEpoch}_${firestore.hashCode}/$path',
  );

  /// Three edits of one document made offline, the last one rejected by the rules; returns the outcome of each
  /// write, and what the cache and the backend hold afterwards.
  Future<(List<String>, Object?, Object?, bool)> rejectedEdits(
    bool merge,
  ) async {
    final FirebaseFirestore firestore = await client(merge);
    final DocumentReference<Map<String, Object?>> ref = run(
      firestore,
      'guarded/x',
    );
    await ref.set(<String, Object?>{'v': 0, 'name': 'start'});

    await firestore.disableNetwork();
    final List<Future<String>> outcomes = <Future<String>>[
      _outcome(ref.set(<String, Object?>{'v': 1, 'name': 'first'})),
      _outcome(ref.update(<String, Object?>{'v': 5})),
      _outcome(ref.update(<String, Object?>{'v': 20})),
    ];
    final DocumentSnapshot<Map<String, Object?>> offline = await ref.get(
      const GetOptions(source: Source.cache),
    );
    expect(offline.data(), <String, Object?>{'v': 20, 'name': 'first'});
    expect(offline.metadata.hasPendingWrites, isTrue);
    expect(await firestore.getPendingWriteCount(), merge ? 1 : 3);

    await firestore.enableNetwork();
    final List<String> results = await Future.wait(outcomes);
    await firestore.waitForPendingWrites();
    final DocumentSnapshot<Map<String, Object?>> cached = await ref.get(
      const GetOptions(source: Source.cache),
    );
    final DocumentSnapshot<Map<String, Object?>> server = await ref.get(
      const GetOptions(source: Source.server),
    );
    return (
      results,
      cached.data(),
      server.data(),
      cached.metadata.hasPendingWrites,
    );
  }

  test(
    'a rejection rejects every merged write with the same error, and the local view goes back to the backend',
    () async {
      final (
        List<String> merged,
        Object? mergedCache,
        Object? mergedServer,
        bool mergedPending,
      ) = await rejectedEdits(
        true,
      );
      // One write reached the backend: {v: 20, name: first}, rejected.
      expect(merged, <String>[
        'permission-denied',
        'permission-denied',
        'permission-denied',
      ]);
      expect(mergedServer, <String, Object?>{'v': 0, 'name': 'start'});
      expect(mergedCache, mergedServer);
      expect(mergedPending, isFalse);

      // Without the setting the first two edits are accepted, and only the last one is rejected.
      final (
        List<String> separate,
        Object? separateCache,
        Object? separateServer,
        bool separatePending,
      ) = await rejectedEdits(
        false,
      );
      expect(separate, <String>['ok', 'ok', 'permission-denied']);
      expect(separateServer, <String, Object?>{'v': 5, 'name': 'first'});
      expect(separateCache, separateServer);
      expect(separatePending, isFalse);
    },
  );

  /// a is made ready, then b is written (allowed only while a is ready), then a is changed again, all offline.
  Future<(List<String>, Object?, Object?)> orderedWrites(bool merge) async {
    final FirebaseFirestore firestore = await client(merge);
    final DocumentReference<Map<String, Object?>> a = run(
      firestore,
      'ordered/a',
    );
    final DocumentReference<Map<String, Object?>> b = a.parent.doc('b');
    await firestore.disableNetwork();
    final List<Future<String>> outcomes = <Future<String>>[
      _outcome(a.set(<String, Object?>{'state': 'draft'})),
      _outcome(a.update(<String, Object?>{'state': 'ready'})),
      _outcome(b.set(<String, Object?>{'made': 'while a was ready'})),
      _outcome(a.update(<String, Object?>{'state': 'done'})),
    ];
    // With the setting a is one write, queued after b.
    expect(await firestore.getPendingWriteCount(), merge ? 2 : 4);
    await firestore.enableNetwork();
    final List<String> results = await Future.wait(outcomes);
    return (
      results,
      (await a.get(const GetOptions(source: Source.server))).data(),
      (await b.get(const GetOptions(source: Source.server))).data(),
    );
  }

  test(
    'writes to other documents in between reach the backend first: a rule that reads the document with get() sees '
    'its older state',
    () async {
      final (List<String> separate, Object? separateA, Object? separateB) =
          await orderedWrites(false);
      expect(separate, <String>['ok', 'ok', 'ok', 'ok']);
      expect(separateA, <String, Object?>{'state': 'done'});
      expect(separateB, <String, Object?>{'made': 'while a was ready'});

      // With the setting, b reaches the backend before a exists there: the rule's get() fails and b is rejected,
      // although the app wrote it while a was ready.
      final (List<String> merged, Object? mergedA, Object? mergedB) =
          await orderedWrites(true);
      expect(merged, <String>['ok', 'ok', 'permission-denied', 'ok']);
      expect(mergedA, <String, Object?>{'state': 'done'});
      expect(mergedB, isNull);
    },
  );
}
