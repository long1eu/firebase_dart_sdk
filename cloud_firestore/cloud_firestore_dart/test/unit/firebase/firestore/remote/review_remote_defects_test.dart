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

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:test/test.dart';

import '../../../../util/test_util.dart' as util;
import '../test_util.dart' as unit;
import 'unused_transport.dart';

/// Tests for verified review findings in the remote area that are NOT being
/// fixed by the `remote-fixes` / `chunk0-features` branches (see
/// reviews/review_remote.md: L2, L3, L5, L6, M5). Each test currently FAILS
/// against the library and encodes the Java (upstream) behaviour.
class _FakeResponse implements Response {
  @override
  Future<Map<String, String>> get headers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<Map<String, String>> get trailers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<void> cancel() async {}
}

class _FakeClient extends FirestoreClient {
  _FakeClient(this.responses)
      : super(
          UnusedTransport(),
          ChannelOptionsProvider(
            databaseId: DatabaseId.forProject('p'),
            credentialsProvider: EmptyCredentialsProvider(),
          ),
        );

  final StreamController<proto.BatchGetDocumentsResponse> responses;

  @override
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(
    proto.BatchGetDocumentsRequest request, {
    CallOptions? options,
  }) =>
      ResponseStream<proto.BatchGetDocumentsResponse>(
          _FakeResponse(), responses.stream);
}

void main() {
  group('L2: unknown gRPC status codes', () {
    test('FirestoreErrorCode.fromValue clamps unknown codes to unknown', () {
      expect(FirestoreErrorCode.fromValue(const GrpcError.custom(99, 'x')),
          FirestoreErrorCode.unknown);
    });

    test('exceptionFromStatus does not throw for unknown codes', () {
      final FirestoreError error =
          exceptionFromStatus(const GrpcError.custom(99, 'forward compatible'));
      expect(error.code, FirestoreErrorCode.unknown);
      expect(error.message, 'forward compatible');
    });
  });

  group('L3: write stream empty token', () {
    test('emptyStreamToken is the empty byte string, as in Java', () {
      expect(WriteStream.emptyStreamToken, isEmpty);
    });
  });

  group('L5: TransactionClient.lookup', () {
    test('a stream that closes early does not report an empty result',
        () async {
      final StreamController<proto.BatchGetDocumentsResponse> responses =
          StreamController<proto.BatchGetDocumentsResponse>();
      final TransactionClient client = TransactionClient(
          _FakeClient(responses), RemoteSerializer(DatabaseId.forProject('p')));
      final DocumentKey a = DocumentKey.fromPathString('rooms/a');
      final DocumentKey b = DocumentKey.fromPathString('rooms/b');

      final Future<List<MaybeDocument>> result =
          client.lookup(<DocumentKey>[a, b]);
      responses.add(proto.BatchGetDocumentsResponse(
        missing: 'projects/p/databases/(default)/documents/rooms/a',
        readTime: proto.Timestamp(seconds: Int64(1)),
      ));
      // The server closes the stream before sending the second document.
      unawaited(responses.close());

      List<MaybeDocument>? docs;
      Object? error;
      try {
        docs = await result.timeout(const Duration(seconds: 2));
      } catch (e) {
        error = e;
      }
      // Either the documents received so far or an error is acceptable, but
      // silently returning no documents makes Transaction.get fail with an
      // internal assertion.
      expect(docs != null ? docs.isNotEmpty : error != null, isTrue,
          reason: 'lookup returned $docs / $error');
    });
  });

  group('L6: TaskScheduler.runUntil', () {
    late TaskScheduler scheduler;
    const Duration later = Duration(hours: 1);

    setUp(() => scheduler = TaskScheduler('runUntil'));

    tearDown(() {
      for (final TaskId id in <TaskId>[
        TaskId.listenStreamIdle,
        TaskId.writeStreamIdle,
        TaskId.onlineStateTimeout
      ]) {
        scheduler.getTask(id)?.cancel();
      }
    });

    test('runUntil(all) runs every pending task', () {
      final List<TaskId> ran = <TaskId>[];
      scheduler
        ..add(TaskId.listenStreamIdle, later,
            () => ran.add(TaskId.listenStreamIdle))
        ..add(TaskId.writeStreamIdle, later,
            () => ran.add(TaskId.writeStreamIdle))
        ..add(TaskId.onlineStateTimeout, later,
            () => ran.add(TaskId.onlineStateTimeout))
        ..runUntil(TaskId.all);

      expect(ran, <TaskId>[
        TaskId.listenStreamIdle,
        TaskId.writeStreamIdle,
        TaskId.onlineStateTimeout
      ]);
    });

    test(
        'runUntil(id) runs the tasks scheduled before id and id itself, '
        'but not later ones', () {
      final List<TaskId> ran = <TaskId>[];
      scheduler
        ..add(TaskId.listenStreamIdle, later,
            () => ran.add(TaskId.listenStreamIdle))
        ..add(TaskId.writeStreamIdle, later,
            () => ran.add(TaskId.writeStreamIdle))
        ..add(TaskId.onlineStateTimeout, later,
            () => ran.add(TaskId.onlineStateTimeout))
        ..runUntil(TaskId.writeStreamIdle);

      expect(ran, <TaskId>[TaskId.listenStreamIdle, TaskId.writeStreamIdle]);
      expect(scheduler.getTask(TaskId.onlineStateTimeout), isNotNull);
    });
  });

  group('M5: server timestamp behaviours', () {
    DocumentSnapshot snapshotWith(FieldValue value) {
      return DocumentSnapshot.fromDocument(
        unit.firestore,
        Document(
          util.key('rooms/foo'),
          util.version(1),
          DocumentState.synced,
          ObjectValue.fromMap(<String, FieldValue>{'ts': value}),
        ),
        isFromCache: false,
        hasPendingWrites: true,
      );
    }

    test('estimate returns the local write time as a Timestamp', () {
      final DocumentSnapshot snap =
          snapshotWith(ServerTimestampValue(const Timestamp(100, 0), null));
      expect(snap.get('ts', ServerTimestampBehavior.estimate),
          const Timestamp(100, 0));
      expect(snap.getTimestamp('ts', ServerTimestampBehavior.estimate),
          const Timestamp(100, 0));
    });

    test('estimate can be read as a DateTime', () {
      final DocumentSnapshot snap =
          snapshotWith(ServerTimestampValue(const Timestamp(100, 0), null));
      expect(snap.getDate('ts', ServerTimestampBehavior.estimate),
          DateTime.fromMillisecondsSinceEpoch(100 * 1000));
    });

    test('previous returns the previous Timestamp value as a DateTime', () {
      final DocumentSnapshot snap = snapshotWith(ServerTimestampValue(
          const Timestamp(100, 0), util.wrap(const Timestamp(50, 0))));
      expect(snap.getDate('ts', ServerTimestampBehavior.previous),
          DateTime.fromMillisecondsSinceEpoch(50 * 1000));
      expect(snap.getTimestamp('ts', ServerTimestampBehavior.previous),
          const Timestamp(50, 0));
    });

    test('previous converts a previous map value like a regular map', () {
      final DocumentSnapshot snap = snapshotWith(ServerTimestampValue(
          const Timestamp(100, 0),
          util.wrap(<String, Object>{'a': const Timestamp(50, 0)})));
      expect(snap.get('ts', ServerTimestampBehavior.previous),
          <String, Object>{'a': const Timestamp(50, 0)});
    });

    test('none returns null', () {
      final DocumentSnapshot snap =
          snapshotWith(ServerTimestampValue(const Timestamp(100, 0), null));
      expect(snap.get('ts', ServerTimestampBehavior.none), isNull);
      expect(snap.get('ts'), isNull);
    });
  });
}
