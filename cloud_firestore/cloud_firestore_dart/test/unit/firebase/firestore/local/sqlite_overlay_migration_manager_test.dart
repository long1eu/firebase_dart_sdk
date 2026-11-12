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

// Port of the Android SDK's SQLiteOverlayMigrationManagerTest. The data is written with the current persistence, then
// the database is turned back into a schema version 10 database (no overlay tables) and opened again, which runs
// schema migration 11 and, when the local store starts, the overlay data migration.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_overlay_migration_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

const String _name = 'test-data-migration';

void main() {
  late SQLitePersistence persistence;
  late LocalStore localStore;

  Future<void> open(User user) async {
    persistence = await createSQLitePersistence(_name);
    (persistence.database as DatabaseMock).renamePath = false;
    localStore = LocalStore(persistence, user);
    await localStore.start();
  }

  /// Turns the database into a schema version 10 database (as written by a version of the SDK without overlays) and
  /// opens it again for [User.unauthenticated].
  Future<void> downgradeAndReopen() async {
    final DatabaseMock db = persistence.database as DatabaseMock;
    await db.execute('DROP TABLE document_overlays');
    await db.execute('DROP TABLE data_migrations');
    await db.execute('PRAGMA user_version = 10');
    await persistence.shutdown();
    await open(User.unauthenticated);
  }

  setUp(() async {
    DatabaseMock.deleteDatabaseFiles(_name);
    await open(User.unauthenticated);
  });

  tearDown(() async {
    await persistence.shutdown();
    DatabaseMock.deleteDatabaseFiles(_name);
  });

  Future<void> writeRemoteDocument(Document document) {
    return persistence.runTransaction('write remote document',
        () => persistence.remoteDocumentCache.add(document, document.version));
  }

  Future<void> writeMutations(List<Mutation> mutations) async {
    await localStore.writeLocally(mutations);
  }

  Future<Mutation?> overlay(String path,
      [User user = User.unauthenticated]) async {
    final DocumentOverlayCache cache =
        persistence.getDocumentOverlayCache(user);
    final Overlay? overlay = await cache.getOverlay(key(path));
    return overlay?.mutation;
  }

  Future<bool> hasPendingOverlayMigration() =>
      (persistence.overlayMigrationManager as SQLiteOverlayMigrationManager)
          .hasPendingOverlayMigration();

  Mutation patchWithTransforms(String path, Map<String, Object?> data) =>
      UserDataConverter(DatabaseId.forProject('projectId'))
          .parseUpdateData(data)
          .toMutation(key(path), Precondition(exists: true));

  Mutation mergeWithTransforms(String path, Map<String, Object?> data) =>
      UserDataConverter(DatabaseId.forProject('projectId'))
          .parseMergeData(data, null)
          .toMutation(key(path), Precondition.none);

  test('testCreateOverlayFromSet', () async {
    await writeRemoteDocument(
        doc('foo/bar', 2, map(<dynamic>['it', 'original'])));
    await writeMutations(<Mutation>[
      setMutation('foo/bar', map(<dynamic>['foo', 'bar']))
    ]);

    await downgradeAndReopen();

    expect(await overlay('foo/bar'),
        setMutation('foo/bar', map(<dynamic>['foo', 'bar'])));
    final MaybeDocument? read = await localStore.readDocument(key('foo/bar'));
    expect(
        read,
        doc('foo/bar', 0, map(<dynamic>['foo', 'bar']),
            DocumentState.localMutations));
    expect(await hasPendingOverlayMigration(), isFalse);
  });

  test('testSkipsIfAlreadyMigrated', () async {
    await writeRemoteDocument(
        doc('foo/bar', 2, map(<dynamic>['it', 'original'])));
    await writeMutations(<Mutation>[
      setMutation('foo/bar', map(<dynamic>['foo', 'bar']))
    ]);

    await downgradeAndReopen();
    expect(await overlay('foo/bar'),
        setMutation('foo/bar', map(<dynamic>['foo', 'bar'])));

    // Delete the overlay to verify migration is skipped the second time.
    await persistence
        .getDocumentOverlayCache(User.unauthenticated)
        .removeOverlaysForBatchId(1);

    // Open the persistence again, the migration does not run any more.
    await persistence.shutdown();
    await open(User.unauthenticated);

    expect(await hasPendingOverlayMigration(), isFalse);
    // We deleted the overlay earlier and the migration is not run again, so we get a null.
    expect(await overlay('foo/bar'), isNull);
  });

  test('testCreateOverlayFromDelete', () async {
    await writeRemoteDocument(
        doc('foo/bar', 2, map(<dynamic>['it', 'original'])));
    await writeMutations(<Mutation>[deleteMutation('foo/bar')]);

    await downgradeAndReopen();

    expect(await overlay('foo/bar'), deleteMutation('foo/bar'));
    expect(await localStore.readDocument(key('foo/bar')),
        deletedDoc('foo/bar', 0));
    expect(await hasPendingOverlayMigration(), isFalse);
  });

  test('testCreateOverlayFromPatches', () async {
    await writeRemoteDocument(
        doc('foo/bar', 2, map(<dynamic>['it', 'original'])));
    await writeMutations(<Mutation>[
      patchWithTransforms(
          'foo/bar', <String, Object?>{'it': firestore.FieldValue.increment(1)})
    ]);
    await writeMutations(<Mutation>[
      patchWithTransforms('foo/bar',
          <String, Object?>{'it': firestore.FieldValue.increment(1)}),
      mergeWithTransforms('foo/newBar', <String, Object?>{
        'it': firestore.FieldValue.arrayUnion(<Object?>[1])
      }),
    ]);

    await downgradeAndReopen();

    final Mutation? bar = await overlay('foo/bar');
    expect(bar, isA<PatchMutation>());
    expect(
        bar,
        patchMutation(
            'foo/bar', map(<dynamic>['it', 2]), <FieldPath>[field('it')]));
    // As upstream (SQLiteOverlayMigrationManagerTest): the merge on the new document stays a merge.
    expect(
        await overlay('foo/newBar'),
        patchMutation(
            'foo/newBar',
            map(<dynamic>[
              'it',
              <int>[1]
            ]),
            <FieldPath>[field('it')]));

    expect(
        await localStore.readDocument(key('foo/bar')),
        doc('foo/bar', 0, map(<dynamic>['it', 2]),
            DocumentState.localMutations));
    expect(
        await localStore.readDocument(key('foo/newBar')),
        doc(
            'foo/newBar',
            0,
            map(<dynamic>[
              'it',
              <int>[1]
            ]),
            DocumentState.localMutations));
    expect(await hasPendingOverlayMigration(), isFalse);
  });

  test('testCreateOverlayForDifferentUsers', () async {
    await writeRemoteDocument(
        doc('foo/bar', 2, map(<dynamic>['it', 'original'])));
    await writeMutations(<Mutation>[
      setMutation('foo/bar', map(<dynamic>['foo', 'set-by-unauthenticated']))
    ]);

    // Switch to a different user
    await localStore.handleUserChange(const User('another_user'));
    await writeMutations(<Mutation>[
      setMutation('foo/bar', map(<dynamic>['foo', 'set-by-another_user']))
    ]);

    await downgradeAndReopen();

    expect(
        await overlay('foo/bar'),
        setMutation(
            'foo/bar', map(<dynamic>['foo', 'set-by-unauthenticated'])));
    expect(await overlay('foo/bar', const User('another_user')),
        setMutation('foo/bar', map(<dynamic>['foo', 'set-by-another_user'])));
    expect(await hasPendingOverlayMigration(), isFalse);
  });

  test('testRebuildsStaleOverlaysAfterDowngrade', () async {
    // An overlay written before a downgrade whose batch was acknowledged by the older SDK must not survive the
    // re-upgrade (port addition: the migration rebuilds all overlays).
    await writeMutations(<Mutation>[
      setMutation('foo/bar', map(<dynamic>['foo', 'bar']))
    ]);
    final DatabaseMock db = persistence.database as DatabaseMock;
    // Simulate the older SDK: the batch is gone, the overlay row is still there.
    await db.execute('DELETE FROM mutations');
    await db.execute('DELETE FROM document_mutations');
    await db.execute('PRAGMA user_version = 10');
    await persistence.shutdown();
    await open(User.unauthenticated);

    expect(await overlay('foo/bar'), isNull);
    expect(await localStore.readDocument(key('foo/bar')), isNull);
  });
}
