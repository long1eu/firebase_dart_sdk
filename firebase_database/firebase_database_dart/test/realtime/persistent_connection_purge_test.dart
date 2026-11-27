// Owner P. purgeOutstandingWrites and onDisconnect requests, as Android's
// PersistentConnectionImpl.purgeOutstandingWrites (:464-483): one queued while offline completes
// with write_canceled and is never sent; one already sent is kept and completes with the server's
// answer.
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:test/test.dart';

import '../util/persistent_connection_harness.dart';

void main() {
  test(
    'an onDisconnect request queued offline completes with write_canceled and is never sent',
    () async {
      final PRig rig = PRig();
      final List<String> statuses = <String>[];
      rig.connection.onDisconnectPut(
        '/presence',
        'offline',
        onComplete: (String status, _) => statuses.add(status),
      );
      rig.connection.onDisconnectCancel(
        '/other',
        onComplete: (String status, _) => statuses.add(status),
      );

      rig.connection.purgeOutstandingWrites();
      expect(statuses, isEmpty, reason: 'completed asynchronously');
      await rig.settle();
      // Breaks if purgeOutstandingWrites leaves _queues.onDisconnects alone.
      expect(statuses, <String>[
        DatabaseErrorCode.writeCanceled.wireStatus,
        DatabaseErrorCode.writeCanceled.wireStatus,
      ]);

      await rig.start();
      await rig.settle();
      expect(rig.sent('o'), isEmpty);
      expect(rig.sent('oc'), isEmpty);
      await rig.connection.shutdown();
    },
  );

  test(
    'an onDisconnect request already sent is kept and completes with the server answer',
    () async {
      final PRig rig = PRig(hold: true);
      await rig.start();
      final List<String> statuses = <String>[];
      rig.connection.onDisconnectPut(
        '/presence',
        'offline',
        onComplete: (String status, _) => statuses.add(status),
      );
      await rig.settle();
      expect(rig.sent('o'), hasLength(1));

      rig.connection.purgeOutstandingWrites();
      await rig.settle();
      expect(statuses, isEmpty);

      rig.server.releaseResponses();
      await rig.settle();
      expect(statuses, <String>['ok']);
      await rig.connection.shutdown();
    },
  );

  test('every write gets one completion: answered before the purge as the server said, after it '
      'write_canceled, and a later answer is dropped', () async {
    final PRig rig = PRig(hold: true);
    await rig.start();
    final List<String> statuses = <String>[];
    rig.connection
      ..put(
        '/a',
        1,
        onComplete: (String s, _) {
          statuses.add('a $s');
          // Purge from inside the first completion: /b is still waiting for its answer.
          rig.connection.purgeOutstandingWrites();
        },
      )
      ..put('/b', 2, onComplete: (String s, _) => statuses.add('b $s'));
    await rig.settle();
    final int a = rig.sent('p')[0].r!;
    final int b = rig.sent('p')[1].r!;

    rig.server.connector.last.serverResponse(a);
    await until(() => statuses.length == 2);
    // Breaks if the response callback of _sendWrite completes a write the purge removed.
    rig.server.connector.last.serverResponse(b, status: 'permission_denied');
    await rig.settle();
    expect(statuses, <String>[
      'a ok',
      'b ${DatabaseErrorCode.writeCanceled.wireStatus}',
    ]);
    await rig.connection.shutdown();
  });
}
