// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart' show GrpcError;
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';
import '../../../../util/test_util.dart';

class MockCredentialsProvider extends EmptyCredentialsProvider {
  final List<String> states = <String>[];

  @override
  Future<String?> get token {
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
  Future<WriteStream> createAndOpenWriteStream(TaskScheduler scheduler) async {
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
      TaskScheduler(''),
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WatchStream watchStream = datastore.watchStream;
    unawaited(watchStream.start());

    final Completer<void> completer = Completer<void>();
    final List<StreamEvent> events = <StreamEvent>[];
    late StreamSubscription<StreamEvent> sub;
    sub = watchStream.listen((StreamEvent value) async {
      events.add(value);

      if (value is OpenEvent) {
        expect(events.length, 1);

        await watchStream.stop();
      } else if (value is CloseEvent) {
        expect(events.length, 2);

        completer.complete();
        await sub.cancel();
      } else {
        fail('We should not received any other events.');
      }
    });

    await completer.future;
  });

  test('testWriteStreamStopAfterHandshake', () async {
    final Datastore datastore = Datastore(
      TaskScheduler(''),
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WriteStream writeStream = datastore.writeStream;
    unawaited(writeStream.start());

    final Completer<void> completer = Completer<void>();
    final List<StreamEvent> events = <StreamEvent>[];
    late StreamSubscription<StreamEvent> sub;
    sub = writeStream.listen((StreamEvent event) async {
      if (event is OpenEvent) {
        // There is no stream token before the handshake.
        expect(writeStream.lastStreamToken, isEmpty);

        // Writing before the handshake should throw
        expect(
          () => writeStream.writeMutations(mutations),
          throwsA(isA<AssertionError>()),
        );

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
        await sub.cancel();
      }

      events.add(event);
    });

    await completer.future;
  });

  /// Verifies that the stream issues an [CloseEvent] after a call to
  /// [WriteStream.stop].
  test('testWriteStreamStopPartial', () async {
    final Datastore datastore = Datastore(
      TaskScheduler(''),
      IntegrationTestUtil.testEnvDatabaseInfo(),
      EmptyCredentialsProvider(),
    );

    final WriteStream writeStream = datastore.writeStream;
    unawaited(writeStream.start());

    final Completer<void> completer = Completer<void>();
    final List<StreamEvent> events = <StreamEvent>[];
    late StreamSubscription<StreamEvent> sub;
    sub = writeStream.listen((StreamEvent value) async {
      events.add(value);

      if (value is OpenEvent) {
        expect(events.length, 1);

        await writeStream.stop();
      } else if (value is CloseEvent) {
        expect(events.length, 2);

        completer.complete();
        await sub.cancel();
      } else {
        fail('We should not received any other events.');
      }
    });

    await completer.future;
  });

  test('testWriteStreamStop', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);

    // Subscribed before the stream stops, awaited so that the expectation is checked before the test ends.
    final Future<void> closed = expectLater(
      writeStream,
      emits(isA<CloseEvent>()),
    );
    await writeStream.stop();
    await closed;
  });

  test('testStreamClosesWhenIdle', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);
    writeStream.markIdle();
    expect(scheduler.getTask(TaskId.writeStreamIdle), isNotNull);

    scheduler.runUntil(TaskId.writeStreamIdle);
    await writeStream.where((StreamEvent event) => event is CloseEvent).first;
    expect(writeStream.isOpen, isFalse);
  });

  test('testStreamCancelsIdleOnWrite', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);

    writeStream
      ..markIdle()
      ..writeMutations(mutations);

    expect(scheduler.getTask(TaskId.writeStreamIdle), isNull);
  });

  test('testStreamStaysIdle', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final WriteStream writeStream = await createAndOpenWriteStream(scheduler);

    writeStream //
      ..markIdle()
      ..markIdle();

    expect(scheduler.getTask(TaskId.writeStreamIdle), isNotNull);
  });

  /// Starts [writeStream] (after its backoff when it failed before) and waits
  /// until its handshake completed.
  Future<void> restartWriteStream(WriteStream writeStream) async {
    final Future<StreamEvent> opened = writeStream.firstWhere(
      (StreamEvent event) => event is OpenEvent,
    );
    await writeStream.start();
    await opened;
    final Future<StreamEvent> handshake = writeStream.firstWhere(
      (StreamEvent event) => event is HandshakeCompleteEvent,
    );
    writeStream.writeHandshake();
    await handshake;
  }

  test('testStreamRefreshesTokenUponExpiration', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockCredentialsProvider credentials = MockCredentialsProvider();
    final Datastore datastore = Datastore(
      scheduler,
      IntegrationTestUtil.testEnvDatabaseInfo(),
      credentials,
    );
    addTearDown(datastore.shutdown);
    final WriteStream writeStream = datastore.writeStream;
    await restartWriteStream(writeStream);

    // A server close with UNAUTHENTICATED: the token is invalidated.
    await writeStream.handleServerClose(const GrpcError.unauthenticated());
    await restartWriteStream(writeStream);

    // Another error: the token is not invalidated.
    await writeStream.handleServerClose(const GrpcError.unavailable());
    await restartWriteStream(writeStream);

    expect(credentials.states, <String>[
      'getToken',
      'invalidateToken',
      'getToken',
      'getToken',
    ]);
    await writeStream.stop();
  });

  test('testTokenIsNotInvalidatedOnceStreamIsHealthy', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockCredentialsProvider credentials = MockCredentialsProvider();
    final Datastore datastore = Datastore(
      scheduler,
      IntegrationTestUtil.testEnvDatabaseInfo(),
      credentials,
    );
    addTearDown(datastore.shutdown);
    final WriteStream writeStream = datastore.writeStream;
    await restartWriteStream(writeStream);
    scheduler.runUntil(TaskId.writeStreamHealthCheck);

    // A server close with UNAUTHENTICATED after the stream became healthy:
    // the token is kept.
    await writeStream.handleServerClose(const GrpcError.unauthenticated());
    expect(credentials.states, <String>['getToken']);
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
