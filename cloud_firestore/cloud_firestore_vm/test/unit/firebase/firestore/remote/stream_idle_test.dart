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

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:test/test.dart';

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
  _FakeClient()
      : super(
          ClientChannel('localhost', port: 1),
          ChannelOptionsProvider(
            databaseId: DatabaseId.forProject('p'),
            credentialsProvider: EmptyCredentialsProvider(),
          ),
        );

  final StreamController<proto.WriteResponse> responses =
      StreamController<proto.WriteResponse>();

  @override
  Future<ResponseStream<proto.WriteResponse>> write(
          Stream<proto.WriteRequest> request) async =>
      ResponseStream<proto.WriteResponse>(_FakeResponse(), responses.stream);
}

void main() {
  test('an idle stream is closed after one minute, as on Android', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final _FakeClient client = _FakeClient();
    final WriteStream stream = WriteStream(
      client: client,
      scheduler: scheduler,
      serializer: RemoteSerializer(DatabaseId.forProject('p')),
    );
    await stream.start();
    expect(stream.isOpen, isTrue);

    // The delay itself is a constant (the scheduler no longer prints it).
    expect(BaseStream.idleTimeout, const Duration(minutes: 1));

    stream.markIdle();
    expect(scheduler.getTask(TaskId.writeStreamIdle), isNotNull);

    // Fire the idle timer without waiting a real minute: the stream closes.
    scheduler.runUntil(TaskId.writeStreamIdle);
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.getTask(TaskId.writeStreamIdle), isNull);
    expect(stream.isOpen, isFalse);

    await stream.stop();
    await client.responses.close();
  });
}
