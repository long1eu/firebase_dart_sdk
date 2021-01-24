// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';
import '../../../../util/test_util.dart';

// ignore_for_file: unawaited_futures
class MockCredentialsProvider extends EmptyCredentialsProvider {
  final List<String> states = <String>[];

  @override
  Future<String> get token {
    states.add('getToken');
    return super.token;
  }

  @override
  void invalidateToken() {
    states.add('invalidateToken');
    super.invalidateToken();
  }
}

void main() {
  /// Single mutation to send to the write stream.
  final List<Mutation> mutations = <Mutation>[setMutation('foo/bar', map())];

  /// Waits for a WriteStream to get into a state that accepts mutations.
  Future<void> waitForWriteStreamOpen(WriteStream writeStream) async {
    await writeStream.start();
    writeStream.writeHandshake();
    await writeStream
        .where((StreamEvent event) => event is HandshakeCompleteEvent)
        .first;
  }

  /// Creates a WriteStream and gets it in a state that accepts mutations.
  Future<WriteStream> createAndOpenWriteStream(AsyncQueue scheduler) async {
    final Datastore datastore = Datastore(
      scheduler,
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WriteStream writeStream = datastore.writeStream;
    await waitForWriteStreamOpen(writeStream);
    return writeStream;
  }

  test('testWatchStreamStopBeforeHandshake', () async {
    final Datastore datastore = Datastore(
      AsyncQueue(''),
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WatchStream watchStream = datastore.watchStream;
    unawaited(watchStream.start());

    final Completer<void> completer = Completer<void>();
    final List<StreamEvent> events = <StreamEvent>[];
    StreamSubscription<StreamEvent> sub;
    sub = watchStream.listen((StreamEvent value) async {
      events.add(value);

      if (value is OpenEvent) {
        expect(events.length, 1);

        await watchStream.stop();
      } else if (value is CloseEvent) {
        expect(events.length, 2);

        completer.complete();
        sub.cancel();
      } else {
        fail('We should not received any other events.');
      }
    });

    await completer.future;
  });

  test('testWriteStreamStopAfterHandshake', () async {
    final Datastore datastore = Datastore(
      AsyncQueue(''),
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WriteStream writeStream = datastore.writeStream;
    unawaited(writeStream.start());

    final Completer<void> completer = Completer<void>();
    final List<StreamEvent> events = <StreamEvent>[];
    StreamSubscription<StreamEvent> sub;
    sub = writeStream.listen((StreamEvent event) async {
      if (event is OpenEvent) {
        // Writing before the handshake should throw
        expect(() => writeStream.writeMutations(mutations),
            throwsA(isA<AssertionError>()));

        // Handshake should always be called
        writeStream.writeHandshake();
      } else if (event is HandshakeCompleteEvent) {
        expect(writeStream.lastStreamToken, isNotEmpty);

        // Now writes should succeed
        writeStream.writeMutations(mutations);
      } else if (event is OnWriteResponse) {
        expect(event.results.length, 1);
        expect(writeStream.lastStreamToken, isNotEmpty);
        await writeStream.stop();
      } else if (event is CloseEvent) {
        completer.complete();
        sub.cancel();
      }

      events.add(event);
    });

    await completer.future;
  });

  /// Verifies that the stream issues an [CloseEvent] after a call to
  /// [WriteStream.stop].
  test('testWriteStreamStopPartial', () async {
    final Datastore datastore = Datastore(
      AsyncQueue(''),
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WriteStream writeStream = datastore.writeStream;
    unawaited(writeStream.start());

    final Completer<void> completer = Completer<void>();
    final List<StreamEvent> events = <StreamEvent>[];
    StreamSubscription<StreamEvent> sub;
    sub = writeStream.listen((StreamEvent value) async {
      events.add(value);

      if (value is OpenEvent) {
        expect(events.length, 1);

        await writeStream.stop();
      } else if (value is CloseEvent) {
        expect(events.length, 2);

        completer.complete();
        sub.cancel();
      } else {
        fail('We should not received any other events.');
      }
    });

    await completer.future;
  });

  test('testWriteStreamStop', () async {
    final AsyncQueue scheduler = AsyncQueue('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);

    writeStream.stop();
    expectLater(writeStream, emits(isA<CloseEvent>()));
  });

  test('testStreamClosesWhenIdle', () async {
    final AsyncQueue scheduler = AsyncQueue('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);
    writeStream.markIdle();
    expect(scheduler.getTask(TaskId.writeStreamIdle), isNotNull);

    scheduler.runUntil(TaskId.writeStreamIdle);
    await writeStream.where((StreamEvent event) => event is CloseEvent).first;
    expect(writeStream.isOpen, isFalse);
  });

  test('testStreamCancelsIdleOnWrite', () async {
    final AsyncQueue scheduler = AsyncQueue('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);

    writeStream
      ..markIdle()
      ..writeMutations(mutations);

    expect(scheduler.getTask(TaskId.writeStreamIdle), isNull);
  });

  test('testStreamStaysIdle', () async {
    final AsyncQueue scheduler = AsyncQueue('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);

    writeStream //
      ..markIdle()
      ..markIdle();

    expect(scheduler.getTask(TaskId.writeStreamIdle), isNotNull);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const writeAllDocs = IntegrationTestUtil.writeAllDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
