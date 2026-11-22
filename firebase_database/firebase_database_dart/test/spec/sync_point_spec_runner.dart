// Runner of syncPointSpec.json against SyncTree. Port of JS
// `packages/database/test/helpers/syncpoint-util.ts` and Android
// `firebase-database/src/test/java/com/google/firebase/database/core/SyncPointTest.java`; where they
// differ, the stricter check of the two is applied (see the comments at each check).
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:test/test.dart';

import 'spec_listen_provider.dart';

/// The spec file, relative to the package root (the working directory of `dart test`).
const String syncPointSpecFile = 'test/spec/syncPointSpec.json';

/// Every scenario is run once at the root and once below this path, as both upstream runners do.
const String deepBasePath = 'foo/bar/baz';

/// One scenario of the spec file.
final class SyncPointScenario {
  /// Creates a scenario.
  const SyncPointScenario(this.name, this.steps);

  /// The scenario name (unique in the file).
  final String name;

  /// The steps, as decoded JSON.
  final List<Map<String, Object?>> steps;
}

/// Loads the scenarios of [file], checking that names are unique.
List<SyncPointScenario> loadSyncPointScenarios([
  String file = syncPointSpecFile,
]) {
  final List<Object?> json =
      jsonDecode(File(file).readAsStringSync()) as List<Object?>;
  final Set<String> names = <String>{};
  final List<SyncPointScenario> scenarios = <SyncPointScenario>[];
  for (final Object? raw in json) {
    final Map<String, Object?> spec = raw! as Map<String, Object?>;
    _checkKeys(spec, const <String>{'name', 'steps', '.comment'}, 'scenario');
    final String name = spec['name']! as String;
    if (!names.add(name)) {
      throw StateError('Duplicate scenario name in $file: "$name"');
    }
    scenarios.add(
      SyncPointScenario(name, <Map<String, Object?>>[
        for (final Object? step in spec['steps']! as List<Object?>)
          step! as Map<String, Object?>,
      ]),
    );
  }
  return scenarios;
}

/// Runs [scenario] at the root and again at [deepBasePath]; fails the current test on the first
/// mismatch.
void runSyncPointScenario(SyncPointScenario scenario) {
  _ScenarioRun(scenario, Path.empty).run();
  _ScenarioRun(scenario, Path(deepBasePath)).run();
}

/// The identity of one test callback; registrations with the same `callbackId` share it.
final class _Listener {
  _Listener(this.callbackId);

  final Object? callbackId;

  @override
  String toString() => 'listener(${callbackId ?? 'anonymous'})';
}

/// A registration that responds to every event type and is never fired (Android
/// `TestEventRegistration`; JS `TestEventRegistration`).
final class _SpecEventRegistration extends EventRegistration {
  /// Creates a registration of the listener on [querySpec].
  _SpecEventRegistration(this.querySpec, this._listener);

  @override
  final QuerySpec querySpec;

  final _Listener _listener;

  @override
  bool respondsTo(EventType type) => true;

  @override
  DataEvent createEvent(Change change, QuerySpec query) {
    final ChildKey? childKey = change.childKey;
    return DataEvent(
      change.eventType,
      this,
      childKey == null || change.eventType == EventType.value
          ? query.path
          : query.path.child(childKey),
      change.node,
      previousName: change.prevName,
    );
  }

  @override
  void fireEvent(DataEvent event) =>
      throw UnsupportedError("Can't raise test events");

  @override
  void fireCancelEvent(DatabaseError error) =>
      throw UnsupportedError("Can't raise test events");

  @override
  EventRegistration clone(QuerySpec newQuery) =>
      _SpecEventRegistration(newQuery, _listener);

  @override
  bool isSameListener(EventRegistration other) =>
      other is _SpecEventRegistration && identical(other._listener, _listener);

  @override
  String toString() => '_SpecEventRegistration($_listener)';
}

/// An event of the spec.
final class _ExpectedEvent {
  _ExpectedEvent(this.type, this.path, this.name, this.prevName, this.data);

  factory _ExpectedEvent.parse(Map<String, Object?> json, Path basePath) {
    _checkKeys(json, const <String>{
      'type',
      'path',
      'name',
      'prevName',
      'data',
    }, 'event');
    return _ExpectedEvent(
      _eventType(json['type']! as String),
      basePath.childPath(Path(json['path']! as String)),
      json['name'] as String?,
      json['prevName'] as String?,
      json['data'],
    );
  }

  final EventType type;
  final Path path;
  final String? name;
  final String? prevName;
  final Object? data;

  late final String hash = nodeFromJson(data).hash();

  @override
  String toString() =>
      '${type.name} path=$path name=$name prevName=$prevName '
      'data=${jsonEncode(data)}';
}

/// One run of a scenario under [basePath].
final class _ScenarioRun {
  _ScenarioRun(this.scenario, this.basePath);

  final SyncPointScenario scenario;
  final Path basePath;
  final SpecListenProvider provider = SpecListenProvider();
  late final SyncTree tree = SyncTree(
    listenProvider: provider,
    persistenceManager: NoopPersistenceManager(),
  );
  final Map<Object, _Listener> listeners = <Object, _Listener>{};
  final ServerClock serverClock = ServerClock(
    () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  /// JS and Android both number writes from 0; the spec's `writeId`s refer to these.
  WriteId nextWriteId = 0;

  int stepIndex = -1;

  void run() {
    for (stepIndex = 0; stepIndex < scenario.steps.length; stepIndex++) {
      try {
        _runStep(scenario.steps[stepIndex]);
      } catch (_) {
        printOnFailure(_context());
        rethrow;
      }
    }
  }

  String _context() {
    final Map<String, Object?> step = scenario.steps[stepIndex];
    return 'Scenario "${scenario.name}", base path "$basePath", '
        'step $stepIndex (${step['type']})'
        '${step.containsKey('.comment') ? ': ${step['.comment']}' : ''}\n'
        'Step: ${jsonEncode(step)}\n'
        'Listens started/stopped so far: ${provider.log}';
  }

  Path _path(Map<String, Object?> step) =>
      basePath.childPath(Path(step['path']! as String));

  void _runStep(Map<String, Object?> step) {
    final String type = step['type']! as String;
    final List<_ExpectedEvent> expected = <_ExpectedEvent>[
      for (final Object? e in step['events']! as List<Object?>)
        _ExpectedEvent.parse(e! as Map<String, Object?>, basePath),
    ];
    switch (type) {
      case 'listen':
        _checkStep(step, const <String>{
          'path',
          'params',
          'events',
          'callbackId',
        });
        final QuerySpec query = _query(
          _path(step),
          step['params'] as Map<String, Object?>?,
        );
        final Object? callbackId = step['callbackId'];
        final _Listener listener = callbackId == null
            ? _Listener(null)
            : listeners.putIfAbsent(callbackId, () => _Listener(callbackId));
        _exactMatch(
          expected,
          tree.addEventRegistration(_SpecEventRegistration(query, listener)),
        );
      case 'unlisten':
        _checkStep(step, const <String>{'path', 'callbackId', 'events'});
        final Object? callbackId = step['callbackId'];
        final _Listener? listener = callbackId == null
            ? null
            : listeners[callbackId];
        if (listener == null) {
          fail("Couldn't find previous listen with callbackId $callbackId");
        }
        // JS removes the listener from the query at the unlisten path (params are not allowed).
        _exactMatch(
          expected,
          tree.removeEventRegistration(
            _SpecEventRegistration(QuerySpec.defaultAt(_path(step)), listener),
          ),
        );
      case 'serverUpdate':
        _checkStep(step, const <String>{'path', 'data', 'tag', 'events'});
        final Node update = nodeFromJson(step['data']);
        final Object? tag = step['tag'];
        _setMatch(
          expected,
          tag == null
              ? tree.applyServerOverwrite(_path(step), update)
              : tree.applyTaggedQueryOverwrite(
                  _path(step),
                  update,
                  Tag(tag as int),
                ),
        );
      case 'serverMerge':
        _checkStep(step, const <String>{'path', 'data', 'tag', 'events'});
        final Map<Path, Node> merge = <Path, Node>{
          for (final MapEntry<String, Object?> e
              in (step['data']! as Map<String, Object?>).entries)
            Path(e.key): nodeFromJson(e.value),
        };
        final Object? tag = step['tag'];
        _setMatch(
          expected,
          tag == null
              ? tree.applyServerMerge(_path(step), merge)
              : tree.applyTaggedQueryMerge(_path(step), merge, Tag(tag as int)),
        );
      case 'set':
        _checkStep(step, const <String>{'path', 'data', 'visible', 'events'});
        final Node node = nodeFromJson(step['data']);
        final bool visible = step['visible'] as bool? ?? true;
        // Android: anything visible is persisted (a no-op here).
        _setMatch(
          expected,
          tree.applyUserOverwrite(
            _path(step),
            node,
            node,
            nextWriteId++,
            visible: visible,
            persist: visible,
          ),
        );
      case 'update':
        _checkStep(step, const <String>{'path', 'data', 'events'});
        final CompoundWrite merge = CompoundWrite.fromValue(
          step['data']! as Map<String, Object?>,
        );
        _setMatch(
          expected,
          tree.applyUserMerge(
            _path(step),
            merge,
            merge,
            nextWriteId++,
            persist: true,
          ),
        );
      case 'ackUserWrite':
        _checkStep(step, const <String>{'writeId', 'revert', 'events'});
        _setMatch(
          expected,
          tree.ackUserWrite(
            step['writeId']! as int,
            revert: step['revert'] as bool? ?? false,
            persist: true,
            serverClock: serverClock,
          ),
        );
      case 'suppressWarning':
        // JS: keeps Jasmine quiet for scenarios that only expect no errors.
        _checkStep(step, const <String>{'events'});
      default:
        fail('Unknown step: $type');
    }
  }

  /// The query of a `listen` step. Applied in Android's order (index, bounds, limits) whatever
  /// the key order of the JSON; every parameter both runners know is supported, any other one
  /// fails. A query with params must have a `tag` (both runners); its value is not checked.
  QuerySpec _query(Path path, Map<String, Object?>? params) {
    if (params == null) {
      return QuerySpec.defaultAt(path);
    }
    if (!params.containsKey('tag')) {
      fail('Non-default queries must have a tag');
    }
    final Map<String, Object?> remaining = Map<String, Object?>.of(params)
      ..remove('tag');
    QueryParams q = QueryParams.defaultParams;
    if (remaining.containsKey('orderBy')) {
      q = q.orderBy(PathIndex(Path(remaining.remove('orderBy')! as String)));
    } else if (remaining.remove('orderByKey') != null) {
      q = q.orderBy(keyIndex);
    } else if (remaining.remove('orderByPriority') != null) {
      q = q.orderBy(priorityIndex);
    }
    if (remaining.containsKey('startAt')) {
      final (Node value, ChildKey? name) = _bound(remaining.remove('startAt'));
      q = q.startAt(value, name);
    }
    if (remaining.containsKey('startAfter')) {
      final (Node value, ChildKey? name) = _bound(
        remaining.remove('startAfter'),
      );
      q = q.startAfter(value, name);
    }
    if (remaining.containsKey('endAt')) {
      final (Node value, ChildKey? name) = _bound(remaining.remove('endAt'));
      q = q.endAt(value, name);
    }
    if (remaining.containsKey('endBefore')) {
      final (Node value, ChildKey? name) = _bound(
        remaining.remove('endBefore'),
      );
      q = q.endBefore(value, name);
    }
    if (remaining.containsKey('equalTo')) {
      // JS `equalTo` is `startAt` and `endAt` at the same bound.
      final (Node value, ChildKey? name) = _bound(remaining.remove('equalTo'));
      q = q.startAt(value, name).endAt(value, name);
    }
    if (remaining.containsKey('limitToFirst')) {
      q = q.limitToFirst(remaining.remove('limitToFirst')! as int);
    }
    if (remaining.containsKey('limitToLast')) {
      q = q.limitToLast(remaining.remove('limitToLast')! as int);
    }
    if (remaining.isNotEmpty) {
      fail('Unsupported query parameters: ${remaining.keys}');
    }
    return QuerySpec(path, q);
  }

  (Node, ChildKey?) _bound(Object? json) {
    final Map<String, Object?> bound = json! as Map<String, Object?>;
    _checkKeys(bound, const <String>{'index', 'name'}, 'query bound');
    final String? name = bound['name'] as String?;
    return (nodeFromJson(bound['index']), name == null ? null : ChildKey(name));
  }

  /// `listen` and `unlisten`: the same events in the same order (both runners).
  void _exactMatch(List<_ExpectedEvent> expected, List<Event> actual) {
    if (expected.length != actual.length) {
      fail(
        '${expected.length < actual.length ? 'Got extra' : 'Missing'} events.\n'
        '${_lists(expected, actual)}',
      );
    }
    for (int i = 0; i < expected.length; i++) {
      final Event event = actual[i];
      if (event is! DataEvent || !_matches(expected[i], event)) {
        fail(
          'Event $i differs: expected ${expected[i]}, got ${_describe(event)}.\n'
          '${_lists(expected, actual)}',
        );
      }
    }
  }

  /// Other steps: the same events, compared as JS does: actual events come in groups by path in
  /// the order of the expected groups (JS), within a group any order matches, but the events of one
  /// registration keep the order child_removed, child_added, child_moved, child_changed, value
  /// (JS and Android). Android's whole-set match is implied.
  void _setMatch(List<_ExpectedEvent> expected, List<Event> actual) {
    if (expected.length != actual.length) {
      fail(
        'Expected ${expected.length} events, got ${actual.length}.\n'
        '${_lists(expected, actual)}',
      );
    }
    int start = 0;
    while (start < expected.length) {
      final Path groupPath = expected[start].path;
      int end = start + 1;
      while (end < expected.length && expected[end].path == groupPath) {
        end++;
      }
      final List<_ExpectedEvent> remaining = expected.sublist(start, end);
      final Map<EventRegistration, EventType> lastType =
          Map<EventRegistration, EventType>.identity();
      for (int j = start; j < end; j++) {
        final Event event = actual[j];
        if (event is! DataEvent) {
          fail(
            'Event $j is not a data event: ${_describe(event)}.\n'
            '${_lists(expected, actual)}',
          );
        }
        if (event.path != groupPath) {
          fail(
            'Event $j is at ${event.path}, expected an event at $groupPath in '
            'this position.\n${_lists(expected, actual)}',
          );
        }
        final EventType? previous = lastType[event.eventRegistration];
        if (previous != null && previous.index > event.eventType.index) {
          fail(
            'Event $j: received ${event.eventType.name} after '
            '${previous.name} for the same registration.\n'
            '${_lists(expected, actual)}',
          );
        }
        lastType[event.eventRegistration] = event.eventType;
        final int found = remaining.indexWhere(
          (_ExpectedEvent e) => _matches(e, event),
        );
        if (found < 0) {
          fail(
            'Could not find a matching expected event for event $j: '
            '${_describe(event)}.\n${_lists(expected, actual)}',
          );
        }
        remaining.removeAt(found);
      }
      start = end;
    }
  }

  /// Type, path, child name, previous name and data (by hash, so priorities count). The previous
  /// name of a child_removed event must be absent (Android; JS skips it).
  static bool _matches(_ExpectedEvent expected, DataEvent actual) {
    if (expected.type != actual.eventType || expected.path != actual.path) {
      return false;
    }
    if (expected.type != EventType.value) {
      if (expected.name != actual.snapshotPath.back?.name ||
          expected.prevName != actual.previousName?.name) {
        return false;
      }
    }
    return expected.hash == actual.snapshot.hash();
  }

  static String _lists(List<_ExpectedEvent> expected, List<Event> actual) =>
      'Expected:\n${expected.map((_ExpectedEvent e) => '  $e').join('\n')}\n'
      'Actual:\n${actual.map((Event e) => '  ${_describe(e)}').join('\n')}';
}

String _describe(Event event) {
  try {
    return switch (event) {
      DataEvent() =>
        '${event.eventType.name} path=${event.path} '
            'name=${event.eventType == EventType.value ? null : event.snapshotPath.back?.name} '
            'prevName=${event.previousName?.name} '
            'data=${jsonEncode(event.snapshot.toJson(exportFormat: true))}',
      CancelEvent() => 'cancel path=${event.path} error=${event.error}',
    };
  } on Object catch (e) {
    return '<${event.runtimeType}: cannot describe: $e>';
  }
}

void _checkStep(Map<String, Object?> step, Set<String> allowed) =>
    _checkKeys(step, <String>{'type', '.comment', 'debug', ...allowed}, 'step');

/// JS `checkValidProperties`: fails on a key the runner does not understand.
void _checkKeys(Map<String, Object?> json, Set<String> allowed, String what) {
  for (final String key in json.keys) {
    if (!allowed.contains(key)) {
      fail('Unexpected property found in $what spec: "$key"');
    }
  }
}

EventType _eventType(String type) => switch (type) {
  'value' => EventType.value,
  'child_added' => EventType.childAdded,
  'child_removed' => EventType.childRemoved,
  'child_changed' => EventType.childChanged,
  'child_moved' => EventType.childMoved,
  _ => fail('Unknown event type: $type'),
};
