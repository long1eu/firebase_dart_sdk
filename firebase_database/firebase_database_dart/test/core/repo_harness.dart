// Test support for the Repo tests: a Repo over FakeServerActions, registrations that log their
// events in the contract's notation (14_api_contract.md section 4.2), and a timer zone that lets
// a test move time forward without waiting. No main here.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/event_dispatcher.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

/// The four child event types.
const Set<EventType> childTypes = <EventType>{
  EventType.childAdded,
  EventType.childChanged,
  EventType.childMoved,
  EventType.childRemoved,
};

/// JSON of a node, as the contract writes it (compared by value).
String json(Node node) => jsonEncode(node.toJson());

/// An engine holding [serverCache] as server data with a complete, inactive default tracked
/// query per key (what `fakePersistence` of the contract does).
InMemoryPersistenceStorageEngine persistedEngine(
  Map<String, Object?> serverCache, {
  InMemoryPersistenceStorageEngine? engine,
}) {
  final InMemoryPersistenceStorageEngine result =
      engine ?? InMemoryPersistenceStorageEngine();
  result.disableTransactionCheck = true;
  int id = 0;
  for (final MapEntry<String, Object?> entry in serverCache.entries) {
    result
      ..overwriteServerCache(Path(entry.key), nodeFromJson(entry.value))
      ..saveTrackedQuery(
        TrackedQuery(
          id: id++,
          querySpec: QuerySpec.defaultAt(Path(entry.key)),
          lastUse: 0,
          complete: true,
          active: false,
        ),
      );
  }
  result.disableTransactionCheck = false;
  return result;
}

/// A persistence manager over [engine].
PersistenceManager managerOver(InMemoryPersistenceStorageEngine engine) =>
    DefaultPersistenceManager(
      engine,
      CachePolicy.none,
      () => DateTime.utc(2026),
    );

/// A Repo over a [FakeServerActions], with a log.
final class RepoHarness {
  /// Creates the Repo; [connected] reports the connection up at once.
  RepoHarness({
    PersistenceManager? persistence,
    EventDispatcher? dispatcher,
    bool connected = true,
  }) {
    repo = Repo(
      repoInfo: const RepoInfo(
        host: 'test.firebaseio.com',
        namespace: 'test',
        secure: true,
      ),
      connectionFactory: (delegate, logger) =>
          server = FakeServerActions(delegate),
      persistenceManager: persistence,
      clock: () => DateTime.utc(2026),
      dispatcher: dispatcher,
      logger: (level, message) => logs.add('${level.name}: $message'),
    );
    if (connected) {
      server.connect();
    }
  }

  /// The fake connection.
  late final FakeServerActions server;

  /// The Repo under test.
  late final Repo repo;

  /// What the registrations and the test wrote, in order.
  final List<String> log = <String>[];

  /// What Repo logged.
  final List<String> logs = <String>[];

  /// Registers [name] on [path] (with [params]) for [types]; events are logged as `name:V(json)`,
  /// `name:A(key,prev)`, `name:C(..)`, `name:M(..)`, `name:R(key)` and cancels as `name:E(code)`.
  /// [after] runs after each data event is logged.
  CallbackEventRegistration listen(
    String name,
    String path, {
    Set<EventType> types = const <EventType>{EventType.value},
    QueryParams? params,
    void Function(DataEvent event)? after,
  }) {
    final CallbackEventRegistration registration = CallbackEventRegistration(
      QuerySpec(Path(path), params ?? QueryParams.defaultParams),
      types,
      onEvent: (DataEvent event) {
        log.add('$name:${describe(event)}');
        after?.call(event);
      },
      onCancel: (DatabaseError error) => log.add('$name:E(${error.code.code})'),
    );
    repo.addEventCallback(registration);
    return registration;
  }

  /// The event in the contract's notation, without the name.
  static String describe(DataEvent event) {
    final String key = event.snapshotPath.back?.name ?? '';
    final String prev = event.previousName?.name ?? 'null';
    return switch (event.eventType) {
      EventType.value => 'V(${json(event.snapshot)})',
      EventType.childAdded => 'A($key,$prev)',
      EventType.childChanged => 'C($key,$prev)',
      EventType.childMoved => 'M($key,$prev)',
      EventType.childRemoved => 'R($key)',
    };
  }

  /// "answered [value]": pushes the data of the active listen at [path] and completes it.
  void answer(String path, Object? value, {QueryParams? params}) {
    final QuerySpec query = QuerySpec(
      Path(path),
      params ?? QueryParams.defaultParams,
    );
    final ServerCall call = server.activeListens[query.toListenSpec()]!;
    server.deliverDataUpdate(path, value, tag: call.tag);
    if (!call.answered) {
      server.respond(call);
    }
  }

  /// Writes [value] at [path]; the completion logs `name:ok` or `name:E(code)`.
  void set(String path, Object? value, {String? name}) => repo.setValue(
    Path(path),
    nodeFromJson(value),
    onComplete: name == null ? null : completion(name),
  );

  /// A write completion that logs `name:ok` or `name:E(code)`.
  void Function(DatabaseError? error) completion(String name) =>
      (DatabaseError? error) =>
          log.add(error == null ? '$name:ok' : '$name:E(${error.code.code})');

  /// Starts a transaction at [path] whose handler logs `H(json)` and returns [update]'s outcome;
  /// the completion logs `T:committed(json)`, `T:aborted(json)` or `T:E(code)`.
  void transaction(
    String path,
    TransactionOutcome Function(Object? value) update, {
    bool applyLocally = true,
  }) => repo.startTransaction(
    Path(path),
    (Object? value) {
      log.add('H(${jsonEncode(value)})');
      return update(value);
    },
    applyLocally: applyLocally,
    onComplete: (DatabaseError? error, bool committed, Node? snapshot) {
      if (error != null) {
        log.add('T:E(${error.code.code})');
      } else {
        log.add(
          '${committed ? 'T:committed' : 'T:aborted'}'
          '(${snapshot == null ? 'null' : json(snapshot)})',
        );
      }
    },
  );

  /// Starts a get of [path] (with [params]); the answer logs `name:=json` or `name:E(code)`.
  void get(String path, {String name = 'G', QueryParams? params}) => repo
      .getValue(QuerySpec(Path(path), params ?? QueryParams.defaultParams))
      .then(
        (Node node) => log.add('$name:=${json(node)}'),
        onError: (Object error) =>
            log.add('$name:E(${(error as DatabaseError).code.code})'),
      );

  /// The open get calls at [path], oldest first.
  List<ServerCall> openGets(String path) => server
      .callsOf('get')
      .where((ServerCall c) => c.spec!.path == path && !c.answered)
      .toList();

  /// The calls of [action] at [path] (by write path or spec path).
  List<ServerCall> callsAt(String action, String path) => server
      .callsOf(action)
      .where((ServerCall c) => (c.path ?? c.spec?.path) == path)
      .toList();
}

/// Lets everything scheduled run: microtasks and zero timers.
Future<void> settle() => pumpEventQueue();

/// A timer zone: timers with a delay are held until [elapse] moves time past them; zero timers
/// (`Timer.run`) run as usual.
final class FakeTime {
  final List<_HeldTimer> _timers = <_HeldTimer>[];
  Duration _now = Duration.zero;

  /// Runs [body] in a zone where timers with a delay are held.
  Future<T> run<T>(Future<T> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration duration,
            void Function() callback,
          ) {
            if (duration <= Duration.zero) {
              return parent.createTimer(zone, duration, callback);
            }
            final _HeldTimer timer = _HeldTimer(
              _now + duration,
              zone.bindCallback(callback),
            );
            _timers.add(timer);
            return timer;
          },
    ),
  );

  /// Moves time forward by [duration], firing the held timers that fall due, in order.
  Future<void> elapse(Duration duration) async {
    final Duration end = _now + duration;
    while (true) {
      await settle();
      final List<_HeldTimer> due =
          _timers.where((_HeldTimer t) => t.isActive && t.dueAt <= end).toList()
            ..sort((_HeldTimer a, _HeldTimer b) => a.dueAt.compareTo(b.dueAt));
      if (due.isEmpty) {
        break;
      }
      final _HeldTimer next = due.first;
      _now = next.dueAt;
      next.fire();
    }
    _now = end;
    await settle();
  }
}

final class _HeldTimer implements Timer {
  _HeldTimer(this.dueAt, this._callback);

  final Duration dueAt;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}
