// Replays one client of a failed run of the chaos soak test without the emulator.
//
// The failure output of test/integration/firebase/firestore/chaos/soak_chaos_test.dart holds, on one clock, the
// operations of every client and what every client sent and received (WireRecorder). This test takes one client out
// of such a log and drives a real RemoteStore, SyncEngine, LocalStore and EventManager with it, in the recorded
// order: the writes, listens and network toggles of the user, and what the backend answered (watch changes, write
// acknowledgements and rejections, stream starts and ends), through MockDatastore. The seed of the soak test does
// not fix its timing, so this is the way to look at a failure inside a client again, with a debugger or with the
// debug log, and to turn it into a deterministic test.
//
//   SOAK_REPLAY_LOG     the log of the failed run (required; the test is skipped without it)
//   SOAK_REPLAY_CLIENT  the client to replay (default c0)
//   SOAK_REPLAY_TRACE   1 to print every step and every snapshot of the listener
//   SOAK_REPLAY_SDK_LOG the time of the log (ms) from which the client logs at debug level
//
// The replay ends with the check the soak test failed: the listener on the whole collection is in sync, has no
// pending writes and shows the documents watch sent last. What the replay could not do as recorded (an
// acknowledgement for a write the replayed client had not sent, a watch change for a target it does not have) is
// counted and printed: the timing inside the client is not recorded, so a replay can differ from the run.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as api;
import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:grpc/grpc.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import '../local/persistence_test_helpers.dart';
import '../remote/mock_datastore.dart';

/// Forwards the callbacks of the remote store to the sync engine, which is created after it.
class _Callback implements RemoteStoreCallback {
  late SyncEngine syncEngine;

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) =>
      syncEngine.handleRemoteEvent(remoteEvent);

  @override
  Future<void> handleRejectedListen(int targetId, GrpcError error) =>
      syncEngine.handleRejectedListen(targetId, error);

  @override
  Future<void> handleSuccessfulWrite(MutationBatchResult result) =>
      syncEngine.handleSuccessfulWrite(result);

  @override
  Future<void> handleRejectedWrite(int batchId, GrpcError error) =>
      syncEngine.handleRejectedWrite(batchId, error);

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) =>
      syncEngine.handleOnlineStateChange(onlineState);

  @override
  ImmutableSortedSet<DocumentKey> Function(int) get getRemoteKeysForTarget =>
      syncEngine.getRemoteKeysForTarget;
}

/// One line of the log of the client: an operation of the user or something on the wire.
class Step {
  Step(this.ms, this.order, this.wire, this.text);

  final int ms;
  final int order;
  final bool wire;
  final String text;

  @override
  String toString() =>
      '${ms.toString().padLeft(6)} ${wire ? 'wire' : 'user'} $text';
}

/// The steps of [client] in the soak log [lines], in the order they happened.
List<Step> stepsOf(List<String> lines, String client) {
  final RegExp entry = RegExp(r'^\s*(\d+) (c\d+|---) (.*)$');
  final List<Step> steps = <Step>[];
  bool inOperations = false;
  bool inWire = false;
  for (final String line in lines) {
    if (line.startsWith('SOAK FAILED')) {
      inOperations = true;
      continue;
    } else if (line.startsWith('--- diagnostics')) {
      inOperations = false;
      continue;
    } else if (line.startsWith('--- wire: everything')) {
      inWire = true;
      continue;
    } else if (line.startsWith('--- debug log')) {
      inWire = false;
      continue;
    }
    if (!inOperations && !inWire) {
      continue;
    }
    final RegExpMatch? match = entry.firstMatch(line);
    if (match == null) {
      continue;
    }
    final String who = match[2]!;
    final String text = match[3]!;
    if (who == client || (who == '---' && text == 'quiesce')) {
      steps.add(Step(int.parse(match[1]!), steps.length, inWire, text));
    }
  }
  // By time; at the same millisecond the operations of the user come first.
  steps.sort((Step a, Step b) {
    if (a.ms != b.ms) {
      return a.ms.compareTo(b.ms);
    }
    if (a.wire != b.wire) {
      return a.wire ? 1 : -1;
    }
    return a.order.compareTo(b.order);
  });
  return steps;
}

/// Parses the compact values of the wire log: `{a:1,b:"x",c:[1,2],d:null}`.
class _ValueParser {
  _ValueParser(this.text);

  final String text;
  int at = 0;

  Object? value() {
    final String c = text[at];
    if (c == '{') {
      at++;
      final Map<String, Object?> map = <String, Object?>{};
      while (text[at] != '}') {
        final int colon = text.indexOf(':', at);
        final String key = text.substring(at, colon);
        at = colon + 1;
        map[key] = value();
        if (text[at] == ',') {
          at++;
        }
      }
      at++;
      return map;
    } else if (c == '[') {
      at++;
      final List<Object?> list = <Object?>[];
      while (text[at] != ']') {
        list.add(value());
        if (text[at] == ',') {
          at++;
        }
      }
      at++;
      return list;
    } else if (c == '"') {
      final int end = text.indexOf('"', at + 1);
      final String string = text.substring(at + 1, end);
      at = end + 1;
      return string;
    }
    int end = at;
    while (end < text.length && !',]}'.contains(text[end])) {
      end++;
    }
    final String token = text.substring(at, end);
    at = end;
    return switch (token) {
      'null' => null,
      'true' => true,
      'false' => false,
      _ => int.tryParse(token) ?? double.parse(token),
    };
  }
}

Map<String, Object?> parseFields(String text) =>
    _ValueParser(text).value()! as Map<String, Object?>;

/// The version of a time of the wire log (`seconds.microseconds`), in microseconds.
int micros(String time) {
  final List<String> parts = time.split('.');
  return int.parse(parts[0]) * 1000000 + int.parse(parts[1]);
}

/// A real client without a network, and the replay of a log on it.
class Replay {
  Replay(this.trace);

  final bool trace;

  static const String collection = 'c';

  late final Persistence persistence;
  late final SerialQueue queue;
  late final MockDatastore datastore;
  late final RemoteStore remoteStore;
  late final SyncEngine syncEngine;
  late final EventManager eventManager;
  final UserDataConverter converter = UserDataConverter(
    DatabaseId.forProject('project'),
  );

  /// The snapshots of the listener on the whole collection, with the time of the step they came after.
  final List<(int, ViewSnapshot)> snapshots = <(int, ViewSnapshot)>[];

  /// The targets the replayed client has, by what they are for (`main`, `v>=280`, `doc k3`).
  final Map<String, int> replayTargets = <String, int>{};

  /// The targets of the recorded client, by their id.
  final Map<int, String> recordedTargets = <int, String>{};

  QueryStream? _transient;
  StreamSubscription<ViewSnapshot>? _transientSubscription;
  String? _transientName;
  int now = 0;

  /// What could not be replayed as recorded.
  final Map<String, int> divergences = <String, int>{};
  int applied = 0;

  void diverged(String what) =>
      divergences[what] = (divergences[what] ?? 0) + 1;

  void log(String message) {
    if (trace) {
      // ignore: avoid_print
      print('REPLAY ${now.toString().padLeft(6)} $message');
    }
  }

  Future<T> onQueue<T>(Future<T> Function() task) => queue.run<T>(task);

  Future<void> settle() async {
    // The mock streams deliver their events on timers.
    for (int i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> start() async {
    persistence = await createEagerGCMemoryPersistence();
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    final TaskScheduler scheduler = TaskScheduler('soak-replay');
    datastore = MockDatastore(scheduler)..onWatchQuery = _onWatchQuery;
    final _Callback callback = _Callback();
    queue = SerialQueue();
    remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
      queue: queue,
    );
    syncEngine = SyncEngine(localStore, remoteStore, User.unauthenticated);
    callback.syncEngine = syncEngine;
    eventManager = EventManager(syncEngine);
    await onQueue<void>(() async {
      await localStore.start();
      await remoteStore.start();
    });
    final QueryStream main = QueryStream(
      query(collection),
      const ListenOptions(
        includeDocumentMetadataChanges: true,
        includeQueryMetadataChanges: true,
      ),
    );
    main.listen((ViewSnapshot snapshot) {
      snapshots.add((now, snapshot));
      log('SNAPSHOT ${describe(snapshot)}');
    });
    await onQueue<int>(() => eventManager.addQueryListener(main));
    await settle();
  }

  Future<void> shutdown() async {
    await _transientSubscription?.cancel();
    await remoteStore.shutdown();
    await persistence.shutdown();
  }

  static String describe(ViewSnapshot snapshot) =>
      'fromCache=${snapshot.isFromCache} pending=${snapshot.hasPendingWrites} '
      '${snapshot.documents.toList().map((Document d) => '${d.key.path.last}${d.data}${d.hasLocalMutations ? '*' : ''}').toList()}';

  /// What the target of [queryData] is for.
  void _onWatchQuery(QueryData queryData) {
    final String canonicalId = queryData.target.canonicalId;
    final String name;
    if (queryData.target.isDocumentQuery) {
      name = 'doc ${queryData.target.path.last}';
    } else if (canonicalId.contains('v>=')) {
      name = 'v>=${RegExp(r'v>=(\d+)').firstMatch(canonicalId)![1]}';
    } else {
      name = 'main';
    }
    replayTargets[name] = queryData.targetId;
    log('the client listens to $name as target ${queryData.targetId}');
  }

  // ------------------------------------------------------------- the user

  Future<void> write(List<Mutation> mutations) async {
    final Completer<void> userTask = Completer<void>();
    unawaited(userTask.future.catchError((Object _) {}));
    await onQueue<void>(() => syncEngine.writeMutations(mutations, userTask));
  }

  DocumentKey _key(String id) => key('$collection/$id');

  /// The mutations of a write of the soak test (see `_SoakClient._step` there), or null for a transaction.
  List<Mutation>? mutationsOf(String operation, int clientId) {
    RegExpMatch? m;
    if ((m = RegExp(r'^set (k\d) v=(\d+)$').firstMatch(operation)) != null) {
      return <Mutation>[
        converter
            .parseSetData(<String, Object?>{
              'v': int.parse(m![2]!),
              'by': clientId,
            })
            .toMutation(_key(m[1]!), Precondition.none),
      ];
    } else if ((m = RegExp(r'^merge (k\d) v=(\d+)$').firstMatch(operation)) !=
        null) {
      return <Mutation>[
        converter
            .parseMergeData(<String, Object?>{'v': int.parse(m![2]!)}, null)
            .toMutation(_key(m[1]!), Precondition.none),
      ];
    } else if ((m = RegExp(r'^update (k\d) v=(\d+)$').firstMatch(operation)) !=
        null) {
      return <Mutation>[
        converter
            .parseUpdateData(<String, Object?>{'v': int.parse(m![2]!)})
            .toMutation(_key(m[1]!), Precondition(exists: true)),
      ];
    } else if ((m = RegExp(r'^increment (k\d)$').firstMatch(operation)) !=
        null) {
      return <Mutation>[
        converter
            .parseMergeData(<String, Object?>{
              'c': api.FieldValue.increment(1),
            }, null)
            .toMutation(_key(m![1]!), Precondition.none),
      ];
    } else if ((m = RegExp(
          r'^array(Union|Remove) (k\d) (\d+)$',
        ).firstMatch(operation)) !=
        null) {
      final List<Object?> tags = <Object?>[int.parse(m![3]!)];
      return <Mutation>[
        converter
            .parseMergeData(<String, Object?>{
              'tags': m[1] == 'Union'
                  ? api.FieldValue.arrayUnion(tags)
                  : api.FieldValue.arrayRemove(tags),
            }, null)
            .toMutation(_key(m[2]!), Precondition.none),
      ];
    } else if ((m = RegExp(r'^delete (k\d)$').firstMatch(operation)) != null) {
      return <Mutation>[deleteMutation('$collection/${m![1]}')];
    } else if ((m = RegExp(
          r'^batch set (k\d) v=(\d+), delete (k\d)$',
        ).firstMatch(operation)) !=
        null) {
      return <Mutation>[
        converter
            .parseSetData(<String, Object?>{
              'v': int.parse(m![2]!),
              'batch': true,
            })
            .toMutation(_key(m[1]!), Precondition.none),
        deleteMutation('$collection/${m[3]}'),
      ];
    } else if (operation.startsWith('transaction ')) {
      // A transaction commits on its own call: the client sees it through watch.
      return null;
    }
    throw StateError('Unknown write of the soak test: $operation');
  }

  Future<void> stopTransient() async {
    final QueryStream? transient = _transient;
    if (transient != null) {
      _transient = null;
      await onQueue<void>(() => eventManager.removeQueryListener(transient));
      await _transientSubscription?.cancel();
      _transientSubscription = null;
      _transientName = null;
    }
  }

  Future<void> user(String operation, int clientId) async {
    RegExpMatch? m;
    if ((m = RegExp(r'^#\d+ (.*)$').firstMatch(operation)) != null) {
      final String what = m![1]!;
      if (what == 'ok' || what.startsWith('failed')) {
        // The result of a write: what the wire delivered decides it here.
        return;
      }
      final List<Mutation>? mutations = mutationsOf(what, clientId);
      if (mutations != null) {
        log('the user writes $what');
        await write(mutations);
      }
    } else if ((m = RegExp(
          r'^listen v>=(\d+) limit 3$',
        ).firstMatch(operation)) !=
        null) {
      await stopTransient();
      final int value = int.parse(m![1]!);
      log('the user listens to v>=$value limit 3');
      final QueryStream transient = QueryStream(
        query(collection)
            .filter(filter('v', '>=', value))
            .orderBy(orderBy('v'))
            .limitToFirst(3),
        const ListenOptions(
          includeDocumentMetadataChanges: true,
          includeQueryMetadataChanges: true,
        ),
      );
      _transient = transient;
      _transientName = 'v>=$value';
      _transientSubscription = transient.listen((_) {});
      await onQueue<int>(() => eventManager.addQueryListener(transient));
    } else if (operation == 'stop listening') {
      log('the user stops the short-lived listener');
      await stopTransient();
    } else if (operation == 'enableNetwork' || operation == 'quiesce') {
      log('the user enables the network');
      await onQueue<void>(remoteStore.enableNetwork);
    } else if (operation == 'disableNetwork') {
      log('the user disables the network');
      await onQueue<void>(remoteStore.disableNetwork);
    }
    // Everything else is what the test did to the network: the wire shows its effects.
  }

  // ------------------------------------------------------------- the wire

  /// The ids the replayed client uses for the recorded targets [ids] (`all`, or `1002,1005`).
  List<int>? _targets(String ids) {
    if (ids == 'all' || ids.isEmpty) {
      return <int>[];
    }
    final List<int> result = <int>[];
    for (final String id in ids.split(',')) {
      final int? replayed = replayTargets[recordedTargets[int.parse(id)]];
      if (replayed != null) {
        result.add(replayed);
      }
    }
    return result.isEmpty ? null : result;
  }

  Future<void> _watch(WatchChange change, [String? snapshotTime]) async {
    if (!datastore.isWatchStreamOpen) {
      diverged('a watch change while the replayed client has no watch stream');
      return;
    }
    try {
      await datastore.writeWatchChange(
        change,
        snapshotTime == null
            ? SnapshotVersion.none
            : version(micros(snapshotTime)),
      );
      applied++;
    } on StateError catch (e) {
      diverged('watch change refused by the mock: ${e.message}');
    }
  }

  Future<void> wire(String text) async {
    RegExpMatch? m;
    if ((m = RegExp(r'^Listen#\d+ (start|end)( with .*)?$').firstMatch(text)) !=
        null) {
      if (m![1] == 'start') {
        if (!datastore.isWatchStreamOpen && datastore.isWatchStreamInBackoff) {
          log('the watch stream opens after its backoff');
          datastore.runWatchStreamBackoff();
        }
      } else if (m[2] != null && datastore.isWatchStreamOpen) {
        log('the watch stream fails');
        datastore.failWatchStream(GrpcError.unavailable('recorded: ${m[2]}'));
      }
    } else if ((m = RegExp(
          r'^Listen#\d+ > addTarget (\d+) (query|documents (k\d))',
        ).firstMatch(text)) !=
        null) {
      // What the recorded target is for.
      final int id = int.parse(m![1]!);
      if (m[3] != null) {
        recordedTargets[id] = 'doc ${m[3]}';
      } else if (recordedTargets.isEmpty) {
        recordedTargets[id] = 'main';
      } else if (!recordedTargets.containsKey(id) && _transientName != null) {
        recordedTargets[id] = _transientName!;
      }
    } else if ((m = RegExp(
          r'^Listen#\d+ < target (\w+) (\S+)(?: readTime=([\d.]+))?( token)?',
        ).firstMatch(text)) !=
        null) {
      final List<int>? targets = _targets(m![2]!);
      if (targets == null) {
        diverged(
          'a target change for a target the replayed client does not have',
        );
        return;
      }
      final WatchTargetChangeType type = switch (m[1]) {
        'NO_CHANGE' => WatchTargetChangeType.noChange,
        'ADD' => WatchTargetChangeType.added,
        'REMOVE' => WatchTargetChangeType.removed,
        'CURRENT' => WatchTargetChangeType.current,
        _ => WatchTargetChangeType.reset,
      };
      log('watch: ${m[1]} $targets${m[3] == null ? '' : ' at ${m[3]}'}');
      await _watch(
        WatchChangeWatchTargetChange(
          type,
          targets,
          m[4] == null
              ? Uint8List(0)
              : Uint8List.fromList('token-${m[3] ?? now}'.codeUnits),
        ),
        // Only a change for all the targets is a global snapshot.
        targets.isEmpty ? m[3] : null,
      );
    } else if ((m = RegExp(
          r'^Listen#\d+ < doc (k\d)(\{.*\}) updateTime=([\d.]+) targets=(\S*) removed=(\S*)$',
        ).firstMatch(text)) !=
        null) {
      final List<int> updated = _targets(m![4]!) ?? <int>[];
      final List<int> removed = _targets(m[5]!) ?? <int>[];
      if (updated.isEmpty && removed.isEmpty) {
        diverged(
          'a document change for targets the replayed client does not have',
        );
        return;
      }
      log('watch: ${m[1]}${m[2]} at ${m[3]} for $updated, out of $removed');
      await _watch(
        WatchChangeDocumentChange(
          updated,
          removed,
          _key(m[1]!),
          doc('$collection/${m[1]}', micros(m[3]!), parseFields(m[2]!)),
        ),
      );
    } else if ((m = RegExp(
          r'^Listen#\d+ < deleted (k\d) readTime=([\d.]+) removed=(\S*)$',
        ).firstMatch(text)) !=
        null) {
      final List<int>? removed = _targets(m![3]!);
      if (removed == null) {
        diverged(
          'a deleted document for targets the replayed client does not have',
        );
        return;
      }
      log('watch: ${m[1]} deleted at ${m[2]}, out of $removed');
      await _watch(
        WatchChangeDocumentChange(
          <int>[],
          removed,
          _key(m[1]!),
          deletedDoc('$collection/${m[1]}', micros(m[2]!)),
        ),
      );
    } else if ((m = RegExp(
          r'^Listen#\d+ < removed (k\d) removed=(\S*)$',
        ).firstMatch(text)) !=
        null) {
      final List<int>? removed = _targets(m![2]!);
      if (removed == null) {
        diverged(
          'a removed document for targets the replayed client does not have',
        );
        return;
      }
      log('watch: ${m[1]} out of $removed');
      await _watch(
        WatchChangeDocumentChange(<int>[], removed, _key(m[1]!), null),
      );
    } else if ((m = RegExp(
          r'^Listen#\d+ < filter target=(\d+) count=(\d+)$',
        ).firstMatch(text)) !=
        null) {
      final List<int>? targets = _targets(m![1]!);
      if (targets == null) {
        diverged(
          'an existence filter for a target the replayed client does not have',
        );
        return;
      }
      log('watch: existence filter ${m[2]} for $targets');
      await _watch(
        WatchChangeExistenceFilterWatchChange(
          targets.single,
          ExistenceFilter(int.parse(m[2]!)),
        ),
      );
    } else if ((m = RegExp(
          r'^Write#\d+ < ack commit=([\d.]+) updates: (.*)$',
        ).firstMatch(text)) !=
        null) {
      if (datastore.writesSent == 0) {
        diverged(
          'an acknowledgement while the replayed client has no write in flight',
        );
        return;
      }
      final List<Mutation> sent = datastore.waitForWriteSend();
      final int commit = micros(m![1]!);
      final List<String> updates = m[2]!.split('; ');
      final List<MutationResult> results = <MutationResult>[
        for (int i = 0; i < sent.length; i++)
          _result(i < updates.length ? updates[i] : '-', commit),
      ];
      log('the backend acknowledges ${sent.length} mutation(s) at ${m[1]}');
      await datastore.ackWrite(version(commit), results);
      applied++;
    } else if ((m = RegExp(r'^Write#\d+ end with (\w+)').firstMatch(text)) != null) {
      final String code = m![1]!;
      if (code == 'UNAVAILABLE' || datastore.writesSent == 0) {
        // The stream was lost: the client sends its writes again by itself.
        return;
      }
      datastore.waitForWriteSend();
      log('the backend rejects a write with $code');
      await datastore.failWrite(
        code == 'NOT_FOUND'
            ? GrpcError.notFound('recorded')
            : GrpcError.failedPrecondition('recorded: $code'),
      );
      applied++;
    }
  }

  /// The result of one mutation of an acknowledgement: `time` or `time transformResults 1,[2]` or `-`.
  MutationResult _result(String update, int commit) {
    final RegExpMatch? m = RegExp(
      r'^([\d.]+|-)(?: transformResults (.*))?$',
    ).firstMatch(update);
    final int time = m == null || m[1] == '-' ? commit : micros(m[1]!);
    final List<FieldValue> transformResults = <FieldValue>[];
    final String? values = m?[2];
    if (values != null) {
      final _ValueParser parser = _ValueParser(values);
      while (parser.at < values.length) {
        transformResults.add(wrap(parser.value()));
        if (parser.at < values.length && values[parser.at] == ',') {
          parser.at++;
        }
      }
    }
    return MutationResult(version(time), transformResults);
  }
}

/// Replays [client] out of the soak log [lines] and returns the replay, shut down.
Future<Replay> replayClient(
  List<String> lines,
  String client, {
  bool trace = false,
  int? sdkLogFrom,
}) async {
  final List<Step> steps = stepsOf(lines, client);
  expect(steps, isNotEmpty, reason: 'no steps of $client in the log');
  final Replay replay = Replay(trace);
  await replay.start();
  final int clientId = int.parse(client.substring(1));
  try {
    for (final Step step in steps) {
      replay.now = step.ms;
      if (sdkLogFrom != null && step.ms >= sdkLogFrom) {
        Log.level = InternalLogLevel.d;
      }
      if (step.wire) {
        await replay.wire(step.text);
      } else {
        await replay.user(step.text, clientId);
      }
      await replay.settle();
    }
    // As the soak test does once the writes are acknowledged.
    await replay.stopTransient();
    await replay.settle();
  } finally {
    Log.level = InternalLogLevel.w;
    await replay.shutdown();
  }
  return replay;
}

/// The stuck listener of seed 328635, reduced to one document. The listener is in sync, the user writes while the
/// network is disabled, the network comes back, the write is acknowledged and watch sends the document, CURRENT and
/// a global snapshot for the target the client added again. [confirmed] is whether the backend first confirmed that
/// target (`target ADD`), which is the one message the client of the failed run never received.
List<String> stuckListenerTrace({required bool confirmed}) => <String>[
  'SOAK FAILED',
  '   100 c0 #1 set k0 v=1',
  '   300 c0 disableNetwork',
  '   310 c0 #2 set k0 v=2',
  '   400 c0 enableNetwork',
  '--- diagnostics',
  '--- wire: everything',
  '    10 c0 Listen#0 start',
  '    10 c0 Listen#0 > addTarget 1002 query',
  '    20 c0 Listen#0 < target ADD 1002',
  '    20 c0 Listen#0 < target CURRENT 1002 readTime=1.000100 token',
  '    20 c0 Listen#0 < target NO_CHANGE all readTime=1.000100 token',
  '   120 c0 Write#1 < ack commit=1.000200 updates: 1.000200',
  '   130 c0 Listen#0 < doc k0{by:0,v:1} updateTime=1.000200 targets=1002 removed=',
  '   130 c0 Listen#0 < target NO_CHANGE all readTime=1.000200 token',
  '   410 c0 Listen#2 start',
  '   410 c0 Listen#2 > addTarget 1002 query resume expectedCount=1',
  '   420 c0 Write#3 < ack commit=1.000300 updates: 1.000300',
  if (confirmed) '   430 c0 Listen#2 < target ADD 1002',
  '   430 c0 Listen#2 < target RESET 1002 token',
  '   430 c0 Listen#2 < doc k0{by:0,v:2} updateTime=1.000300 targets=1002 removed=',
  '   430 c0 Listen#2 < target CURRENT 1002 readTime=1.000300 token',
  '   430 c0 Listen#2 < target NO_CHANGE all readTime=1.000300 token',
  '--- debug log',
];

void main() {
  final String? path = Platform.environment['SOAK_REPLAY_LOG'];
  final String client = Platform.environment['SOAK_REPLAY_CLIENT'] ?? 'c0';
  final bool trace = Platform.environment['SOAK_REPLAY_TRACE'] == '1';

  group('a listener that wrote while offline, once the network is back', () {
    test(
      'is in sync when the backend confirms the target it added again',
      () async {
        final Replay replay = await replayClient(
          stuckListenerTrace(confirmed: true),
          'c0',
          trace: trace,
        );
        expect(replay.divergences, isEmpty);
        final ViewSnapshot end = replay.snapshots.last.$2;
        expect(
          Replay.describe(end),
          'fromCache=false pending=false [k0ObjectValue{internalValue={by:0,v:2}}]',
        );
      },
    );

    // What the failed run of seed 328635 showed: the `target ADD` never reached the client, so the watch change
    // aggregator kept the target as not confirmed and dropped everything watch sent for it (the documents, CURRENT
    // and the global snapshot raise no remote event for the view). The write is acknowledged, but the view holds
    // the acknowledged document back until watch delivers it: the last snapshot stays the one raised offline. The
    // other SDKs drop the changes of a target that is not confirmed in the same way; the message must not be lost
    // below the client.
    test(
      'gets no snapshot while the backend does not confirm that target',
      () async {
        final Replay replay = await replayClient(
          stuckListenerTrace(confirmed: false),
          'c0',
          trace: trace,
        );
        expect(replay.divergences, isEmpty);
        final (int at, ViewSnapshot end) = replay.snapshots.last;
        expect(
          Replay.describe(end),
          'fromCache=true pending=true [k0ObjectValue{internalValue={by:0,v:2}}*]',
        );
        expect(
          at,
          lessThan(400),
          reason: 'no snapshot after the network came back',
        );
      },
    );
  });

  test(
    'the replayed client ends with a listener in sync',
    () async {
      final Replay replay = await replayClient(
        File(path!).readAsLinesSync(),
        client,
        trace: trace,
        sdkLogFrom: int.tryParse(
          Platform.environment['SOAK_REPLAY_SDK_LOG'] ?? '',
        ),
      );
      // ignore: avoid_print
      print(
        'replayed $client: ${replay.applied} answers of the backend applied, '
        '${replay.snapshots.length} snapshots; not as recorded: ${replay.divergences}',
      );
      final List<(int, ViewSnapshot)> last = replay.snapshots.length > 8
          ? replay.snapshots.sublist(replay.snapshots.length - 8)
          : replay.snapshots;
      final String tail = last
          .map(
            ((int, ViewSnapshot) s) =>
                '${s.$1.toString().padLeft(6)} ${Replay.describe(s.$2)}',
          )
          .join('\n');
      // ignore: avoid_print
      print('the last snapshots of the listener:\n$tail');

      final ViewSnapshot end = replay.snapshots.last.$2;
      expect(
        end.isFromCache,
        isFalse,
        reason: 'the listener is not in sync\n$tail',
      );
      expect(end.hasPendingWrites, isFalse, reason: tail);
    },
    skip: path == null
        ? 'Set SOAK_REPLAY_LOG to the log of a failed soak run to replay one of its clients'
        : null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
