// Copyright 2026 Google LLC
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

// Two isolates, each with a Firestore instance, on one SQLite cache, against the emulator: who sends which write
// (the primary sends only its own writes and those of clients that are gone; see SQLiteMutationQueue).
//
// Every write increments a counter (`n`) in its own document, so the emulator shows how often it was applied.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:isolate';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/prod_provider/firestore_provider.dart';
import '../../../util/test_backend.dart';

/// The age after which a client's writes are sent by the primary, in these tests: longer than the refresh interval
/// of the client metadata (4 s), or a live client would look gone between two refreshes.
const int _ownerAgeMs = 6000;

OpenDatabase _openFixed(String dbName) {
  return (
    String path, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    final DatabaseMock db = await DatabaseMock.create(
      dbName,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onDowngrade: onDowngrade,
      onOpen: onOpen,
    );
    db.renamePath = false;
    return db;
  };
}

FirestoreSettings _settings(String emulator) {
  final EmulatorAddress address = EmulatorAddress.parse(emulator);
  return FirestoreSettings().withEmulator(address.host, address.port);
}

/// The entry point of a worker isolate: a Firestore instance on the shared cache that runs the commands it is sent.
Future<void> _workerMain(Map<String, Object?> args) async {
  final SendPort replies = args['replies']! as SendPort;
  IntegrationTestUtil.useWebTransportIfRequested();
  SQLiteClientMetadata.batchOwnerAgeOverrideMs = _ownerAgeMs;
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'key',
      applicationId: 'appId',
      projectId: args['project']! as String,
    ),
    dependencies: null,
    name: args['name']! as String,
  );
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: _settings(args['emulator']! as String),
    openDatabase: _openFixed(args['db']! as String),
  );
  // Waits for the start of the client (it has no writes of its own yet).
  await firestore.waitForPendingWrites();

  final ReceivePort commands = ReceivePort();
  replies.send(commands.sendPort);
  await for (final Object? message in commands) {
    final List<Object?> command = message! as List<Object?>;
    switch (command[0]) {
      case 'isPrimary':
        replies.send(<Object?>['isPrimary', firestore.client.isPrimaryClient]);
      case 'write':
        final String path = command[1]! as String;
        final DocumentReference<Map<String, Object?>> doc = firestore.doc(path);
        // The write is stored once the local snapshot has it as a pending write.
        final Completer<void> stored = Completer<void>();
        final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
        subscription = doc.getSnapshots(MetadataChanges.include).listen((
          DocumentSnapshot<Map<String, Object?>> snapshot,
        ) {
          if (snapshot.metadata.hasPendingWrites && !stored.isCompleted) {
            stored.complete();
          }
        });
        unawaited(
          doc
              .set(<String, Object?>{
                'n': FieldValue.increment(1),
                'by': args['name'],
              })
              .then(
                (_) => replies.send(<Object?>['done', path]),
                onError: (Object e) =>
                    replies.send(<Object?>['failed', path, '$e']),
              ),
        );
        await stored.future;
        await subscription.cancel();
        replies.send(<Object?>['stored', path]);
      case 'terminate':
        await firestore.terminate();
        app.delete();
        replies.send(<Object?>['terminated']);
        commands.close();
    }
  }
}

/// A worker isolate seen from the test.
class _Worker {
  _Worker._(this.name, this._isolate, this._replies);

  static Future<_Worker> spawn(String name, String db, String emulator) async {
    final ReceivePort port = ReceivePort();
    final Isolate isolate = await Isolate.spawn(
      _workerMain,
      <String, Object?>{
        'replies': port.sendPort,
        'name': name,
        'db': db,
        'emulator': emulator,
        'project': FirestoreProvider.fallbackProjectId,
      },
      onError: port.sendPort,
      debugName: 'shared-cache-$name',
    );
    final _Worker worker = _Worker._(name, isolate, port);
    worker._commands = await worker._next() as SendPort;
    return worker;
  }

  final String name;
  final Isolate _isolate;
  final ReceivePort _replies;
  late final SendPort _commands;
  late final StreamIterator<Object?> _messages = StreamIterator<Object?>(
    _replies,
  );

  /// The writes whose futures completed, and those that failed, in this isolate.
  final Set<String> completed = <String>{};
  final Map<String, String> failed = <String, String>{};
  bool killed = false;

  Future<Object?> _next() async {
    if (!await _messages.moveNext()) {
      throw StateError('worker $name stopped');
    }
    return _messages.current;
  }

  /// Waits for the reply named [kind], recording the completions that arrive meanwhile.
  Future<List<Object?>> _expect(String kind) async {
    while (true) {
      final Object? message = await _next();
      if (message is List<Object?> && message.isNotEmpty) {
        switch (message[0]) {
          case 'done':
            completed.add(message[1]! as String);
            if (kind == 'done') {
              return message;
            }
            continue;
          case 'failed':
            failed[message[1]! as String] = message[2]! as String;
            continue;
        }
        if (message[0] == kind) {
          return message;
        }
      }
      throw StateError('worker $name: unexpected $message');
    }
  }

  Future<bool> isPrimary() async {
    _commands.send(<Object?>['isPrimary']);
    return (await _expect('isPrimary'))[1]! as bool;
  }

  /// Writes [path] and returns once the write is stored in the cache (its future completes later).
  Future<void> write(String path) async {
    _commands.send(<Object?>['write', path]);
    await _expect('stored');
  }

  /// Waits until the future of the write of [path] completed in this isolate.
  Future<void> waitForCompletion(String path, Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (!completed.contains(path)) {
      expect(failed[path], isNull, reason: 'the write of $path failed');
      final Duration left = deadline.difference(DateTime.now());
      if (left.isNegative) {
        fail('the future of the write of $path did not complete in $name');
      }
      await _expect('done').timeout(left);
    }
  }

  Future<void> terminate() async {
    _commands.send(<Object?>['terminate']);
    await _expect('terminated');
    _replies.close();
  }

  /// Kills the isolate without terminating its Firestore instance (a crash, or an app killed by the system).
  void kill() {
    killed = true;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

void main() {
  final String? emulator = IntegrationTestUtil.emulatorHost;
  final String? skip = emulator == null
      ? 'Needs the emulator (FIRESTORE_EMULATOR_HOST)'
      : null;

  late String db;
  late String collection;
  late Firestore observer;
  final List<_Worker> workers = <_Worker>[];

  setUp(() async {
    if (skip != null) {
      return;
    }
    IntegrationTestUtil.useWebTransportIfRequested();
    db = 'shared-cache-${const Uuid().v4()}.db';
    collection = 'shared-cache-${const Uuid().v4()}';
    workers.clear();
    // Reads what the emulator has, without a cache of its own.
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        applicationId: 'appId',
        projectId: FirestoreProvider.fallbackProjectId,
      ),
      dependencies: null,
      name: 'observer-${const Uuid().v4()}',
    );
    observer = Firestore.instanceFor(
      app: app,
      settings: _settings(
        emulator!,
      ).copyWith(cacheSettings: const MemoryCacheSettings()),
    );
    addTearDown(() async {
      await observer.terminate();
      app.delete();
    });
  });

  tearDown(() async {
    for (final _Worker worker in workers) {
      if (!worker.killed) {
        try {
          await worker.terminate().timeout(const Duration(seconds: 20));
        } catch (_) {
          worker.kill();
        }
      }
    }
    if (skip == null) {
      DatabaseMock.deleteDatabaseFiles(db);
    }
  });

  Future<_Worker> spawn(String name) async {
    final _Worker worker = await _Worker.spawn(name, db, emulator!);
    workers.add(worker);
    return worker;
  }

  /// How often the write of [id] was applied on the emulator (null: never).
  Future<int?> applied(String id) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await observer
        .doc('$collection/$id')
        .get(Source.server);
    return snapshot.data?['n'] as int?;
  }

  Future<void> eventually(
    Future<bool> Function() condition,
    String what, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $what');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Starts A, then B on the same cache: B takes the lease (the default forced ownership), A is secondary after its
  /// next refresh.
  Future<(_Worker, _Worker)> startTwo() async {
    final _Worker a = await spawn('A');
    final _Worker b = await spawn('B');
    await eventually(
      () async => !await a.isPrimary() && await b.isPrimary(),
      'B to be primary and A secondary',
    );
    return (a, b);
  }

  test(
    'each client sends its own writes; the secondary once it is primary',
    () async {
      final (_Worker a, _Worker b) = await startTwo();

      await b.write('$collection/b');
      await b.waitForCompletion('$collection/b', const Duration(seconds: 30));

      await a.write('$collection/a');
      // A is alive: B does not send its write (over several refreshes of both, past the owner age).
      await Future<void>.delayed(const Duration(milliseconds: 2 * _ownerAgeMs));
      expect(await applied('a'), isNull);
      expect(a.completed, isEmpty);

      // B terminates: A takes the lease, sends its write, and its future completes.
      await b.terminate();
      await a.waitForCompletion('$collection/a', const Duration(seconds: 40));
      expect(await a.isPrimary(), isTrue);

      expect(await applied('a'), 1);
      expect(await applied('b'), 1);
    },
    skip: skip,
  );

  test('the primary sends the write of a secondary that was killed', () async {
    final (_Worker a, _Worker b) = await startTwo();

    await a.write('$collection/a');
    a.kill();

    // Once A's metadata is older than the owner age, B sends A's write.
    await eventually(() async => await applied('a') == 1, 'A\'s write');
    // And only once.
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(await applied('a'), 1);
    expect(await b.isPrimary(), isTrue);
  }, skip: skip);

  test(
    'the secondary takes over from a primary that was killed and sends its write',
    () async {
      final (_Worker a, _Worker b) = await startTwo();

      await b.write('$collection/b');
      b.kill();

      // B's lease expires: A takes it and, once B's metadata is older than the owner age, sends B's write.
      await eventually(() => a.isPrimary(), 'A to take the lease');
      await eventually(
        () async => (await applied('b') ?? 0) >= 1,
        'B\'s write',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      final int? count = await applied('b');
      // At least once. B may have sent the write and been killed before it stored the acknowledgement; A then sends
      // it again and the backend applies it twice (final review, finding 5; stage 3 of the multi-client plan).
      expect(count, anyOf(1, 2));
      if (count == 2) {
        printOnFailure(
          'B\'s write was applied twice (sent again after B was killed)',
        );
        // ignore: avoid_print
        print(
          'NOTE: B\'s write was applied twice: sent by B before it was killed, and again by A',
        );
      }

      // A works as the primary.
      await a.write('$collection/a');
      await a.waitForCompletion('$collection/a', const Duration(seconds: 30));
      expect(await applied('a'), 1);
    },
    skip: skip,
  );
}
