import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/integration_test_util.dart';
import '../local/mock/database_mock.dart';

Future<Firestore> open(FirestoreSettings settings, TaskScheduler scheduler) {
  final String path =
      '${Directory.systemTemp.path}/gc_scheduler_${const Uuid().v4()}.db';
  return IntegrationTestUtil.forTests(
    DatabaseId.forDatabase('gc-test', DatabaseId.defaultDatabaseId),
    'gc-test-key',
    EmptyCredentialsProvider(),
    scheduler,
    (String p,
        {int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen}) async {
      final DatabaseMock db = await DatabaseMock.create(path,
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen);
      db.renamePath = false;
      return db;
    },
    settings,
  );
}

void main() {
  test('the LRU GC is scheduled with the default cache size', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final Firestore firestore = await open(FirestoreSettings(), scheduler);
    expect(scheduler.getTask(TaskId.garbageCollection), isNotNull);
    await firestore.shutdown();
  });

  test('the LRU GC is not scheduled when the cache size is unlimited',
      () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final Firestore firestore = await open(
        FirestoreSettings(cacheSizeBytes: FirestoreSettings.cacheSizeUnlimited),
        scheduler);
    expect(scheduler.getTask(TaskId.garbageCollection), isNull);
    await firestore.shutdown();
  });
}
