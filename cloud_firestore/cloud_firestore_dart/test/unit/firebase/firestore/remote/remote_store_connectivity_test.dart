// How the RemoteStore uses the built-in connectivity detector: it only looks
// for changes while a stream is failing, a hint restarts the streams at once,
// and an app that reports the connectivity itself switches it off.

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/fake_timers.dart';
import '../../../../util/test_util.dart';
import 'mock_datastore.dart';
import 'remote_store_test.dart' show MockRemoteStoreCallback;

void main() {
  const Duration poll = Duration(seconds: 2);

  late FakeTimers timers;
  late Set<String> addresses;
  late ConnectivityChangeDetector detector;
  late MockDatastore datastore;
  late BehaviorSubject<bool> onNetworkConnected;
  late LocalStore localStore;
  late RemoteStore remoteStore;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() async {
    timers = FakeTimers();
    addresses = <String>{};
    detector = ConnectivityChangeDetector(
      listAddresses: () async => Set<String>.of(addresses),
      pollInterval: poll,
      now: () => timers.now,
      createTimer: timers.create,
    );
    final TaskScheduler scheduler = TaskScheduler('');
    datastore = MockDatastore(scheduler);
    onNetworkConnected = BehaviorSubject<bool>.seeded(true);
    final Persistence persistence =
        MemoryPersistence.createEagerGcMemoryPersistence();
    await persistence.start();
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    remoteStore = RemoteStore(
      MockRemoteStoreCallback(),
      localStore,
      datastore,
      onNetworkConnected,
      scheduler,
      networkDebounce: const Duration(milliseconds: 1),
      connectivityDetector: detector,
    );
    await remoteStore.start();
    await remoteStore.listen(
      QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen),
    );
    await settle();
    addTearDown(() async {
      await remoteStore.shutdown();
      expect(timers.active, 0, reason: 'a timer outlived the remote store');
    });
  });

  /// The backend answers on the watch stream.
  Future<void> watchStreamWorks() async {
    await datastore.writeWatchChange(
      WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[
        remoteStore.getRemoteTargetId(2)!,
      ]),
      SnapshotVersion.none,
    );
    await settle();
  }

  test('a healthy client has no timer', () async {
    await watchStreamWorks();
    expect(remoteStore.isWatchingConnectivity, isFalse);
    expect(timers.timers, isEmpty);
  });

  test('watches the connectivity while the watch stream is failing', () async {
    await watchStreamWorks();
    datastore.failWatchStream(GrpcError.unavailable());
    await settle();
    expect(remoteStore.isWatchingConnectivity, isTrue);
    expect(timers.active, 1);

    // The stream works again: nothing is left to speed up.
    await watchStreamWorks();
    expect(remoteStore.isWatchingConnectivity, isFalse);
    expect(timers.active, 0);
  });

  test('watches the connectivity while the write stream is failing', () async {
    await watchStreamWorks();
    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b'])),
    ]);
    await remoteStore.fillWritePipeline();
    await settle();
    expect(remoteStore.isWatchingConnectivity, isFalse);

    expect(timers.timers, isEmpty);

    await datastore.failWrite(GrpcError.unavailable());
    await settle();
    // The detector was started by the failure. (The mock stream completes its
    // handshake as soon as it is restarted, which stops the detector again.)
    expect(timers.timers, hasLength(1));
    expect(remoteStore.isWatchingConnectivity, isFalse);
    expect(timers.active, 0);
  });

  test(
    'a hint restarts the failing streams at once, without their backoff',
    () async {
      await watchStreamWorks();
      datastore.failWatchStream(GrpcError.unavailable());
      await settle();
      final int requests = datastore.watchStreamRequestCount;
      final int inhibited = datastore.watchStreamInhibitBackoffCount;

      // An address appears.
      addresses = <String>{'en0/192.168.1.20'};
      await timers.elapse(poll);
      await settle();

      expect(datastore.watchStreamInhibitBackoffCount, inhibited + 1);
      expect(datastore.watchStreamRequestCount, greaterThan(requests));
      expect(datastore.isWatchStreamOpen, isTrue);
      // The restarted streams are not known to fail: the detector waits for the
      // next failure.
      expect(remoteStore.isWatchingConnectivity, isFalse);
    },
  );

  test('a hint never tears down streams that work', () async {
    await watchStreamWorks();
    final int requests = datastore.watchStreamRequestCount;
    final int inhibited = datastore.watchStreamInhibitBackoffCount;

    // The detector is not even running; force a hint anyway.
    detector.onChange!();
    await settle();

    expect(datastore.watchStreamInhibitBackoffCount, inhibited);
    expect(datastore.watchStreamRequestCount, requests);
    expect(datastore.isWatchStreamOpen, isTrue);
  });

  test('a hint does not enable a network that the user disabled', () async {
    await watchStreamWorks();
    datastore.failWatchStream(GrpcError.unavailable());
    await settle();
    expect(remoteStore.isWatchingConnectivity, isTrue);

    await remoteStore.disableNetwork();
    expect(remoteStore.isWatchingConnectivity, isFalse);
    expect(timers.active, 0);

    detector.onChange!();
    await settle();
    expect(remoteStore.canUseNetwork, isFalse);
    expect(datastore.isWatchStreamOpen, isFalse);
  });

  test('shutdown stops the detector for good', () async {
    await watchStreamWorks();
    datastore.failWatchStream(GrpcError.unavailable());
    await settle();
    expect(timers.active, 1);

    await remoteStore.shutdown();
    expect(timers.active, 0);
    expect(detector.isDisposed, isTrue);
  });

  test('an app that reports the connectivity itself switches it off', () async {
    await watchStreamWorks();
    datastore.failWatchStream(GrpcError.unavailable());
    await settle();
    expect(remoteStore.isWatchingConnectivity, isTrue);

    // For example connectivity_plus feeding PlatformDependencies.onNetworkConnected.
    onNetworkConnected.add(false);
    await settle();
    expect(remoteStore.isWatchingConnectivity, isFalse);
    expect(detector.isDisposed, isTrue);
    expect(timers.active, 0);

    // The events of the app keep working.
    final int inhibited = datastore.watchStreamInhibitBackoffCount;
    onNetworkConnected.add(true);
    await settle();
    expect(datastore.watchStreamInhibitBackoffCount, inhibited + 1);

    // And a later failure does not bring the detector back.
    datastore.failWatchStream(GrpcError.unavailable());
    await settle();
    expect(remoteStore.isWatchingConnectivity, isFalse);
    expect(timers.active, 0);
  });

  test('without a detector nothing changes', () async {
    final TaskScheduler scheduler = TaskScheduler('');
    final MockDatastore plainDatastore = MockDatastore(scheduler);
    final RemoteStore plain = RemoteStore(
      MockRemoteStoreCallback(),
      localStore,
      plainDatastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
    );
    await plain.start();
    await plain.listen(
      QueryData(query('bar').toTarget(), 4, 1, QueryPurpose.listen),
    );
    await settle();
    plainDatastore.failWatchStream(GrpcError.unavailable());
    await settle();
    expect(plain.isWatchingConnectivity, isFalse);
    await plain.shutdown();
  });
}
