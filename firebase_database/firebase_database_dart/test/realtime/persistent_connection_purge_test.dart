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
      final PRig rig = PRig();
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
}
