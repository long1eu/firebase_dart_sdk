// Contract of SyncTreeApi (lib/src/core/sync_tree_api.dart) and of how it drives a ListenProvider
// (lib/src/core/listen_provider.dart). sync_tree_api_contract_test.dart runs it against SyncTree.
// No main here: other packages import this file. Needs the data layer and the
// sync tree filled.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree_api.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

/// A listen provider that records starts and stops.
final class RecordingListenProvider implements ListenProvider {
  /// The started listens.
  final List<
    ({
      QuerySpec query,
      Tag? tag,
      ListenHashProvider hash,
      ListenCompletion onComplete,
    })
  >
  started =
      <
        ({
          QuerySpec query,
          Tag? tag,
          ListenHashProvider hash,
          ListenCompletion onComplete,
        })
      >[];

  /// The stopped listens.
  final List<({QuerySpec query, Tag? tag})> stopped =
      <({QuerySpec query, Tag? tag})>[];

  /// The events the next [startListening] calls return (as the `.info` provider does).
  List<Event> eventsOnStart = <Event>[];

  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    started.add((query: query, tag: tag, hash: hash, onComplete: onComplete));
    return eventsOnStart;
  }

  @override
  void stopListening(QuerySpec query, Tag? tag) =>
      stopped.add((query: query, tag: tag));
}

/// A registration that responds to [types] and records fired events.
final class TestRegistration extends EventRegistration {
  /// Creates the registration.
  TestRegistration(
    this.querySpec, [
    this.types = const <EventType>{EventType.value},
  ]);

  @override
  final QuerySpec querySpec;

  /// The event types it wants.
  final Set<EventType> types;

  /// The fired events.
  final List<DataEvent> fired = <DataEvent>[];

  @override
  bool respondsTo(EventType type) => types.contains(type);

  @override
  DataEvent createEvent(Change change, QuerySpec query) => DataEvent(
    change.eventType,
    this,
    change.childKey == null ? query.path : query.path.child(change.childKey!),
    change.node,
    previousName: change.prevName,
  );

  @override
  void fireEvent(DataEvent event) => fired.add(event);

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) =>
      TestRegistration(newQuery, types);

  @override
  bool isSameListener(EventRegistration other) => identical(this, other);
}

/// The contract; [create] builds a tree over a listen provider (a new instance on every call).
void runSyncTreeApiContract(
  SyncTreeApi Function(ListenProvider provider) create,
) {
  late RecordingListenProvider provider;
  late SyncTreeApi tree;

  setUp(() {
    provider = RecordingListenProvider();
    tree = create(provider);
  });

  List<DataEvent> values(List<Event> events) => events
      .whereType<DataEvent>()
      .where((DataEvent e) => e.eventType == EventType.value)
      .toList();

  test('a default listen starts one untagged listen with an empty hash', () {
    tree.addEventRegistration(
      TestRegistration(QuerySpec.defaultAt(Path('/a'))),
    );
    expect(provider.started.single.tag, isNull);
    expect(provider.started.single.hash.simpleHash(), '');
  });

  test(
    'a filtered query gets tag 1 from this tree, independent of other trees',
    () {
      final QuerySpec query = QuerySpec(
        Path('/a'),
        QueryParams.defaultParams.limitToFirst(2),
      );
      tree.addEventRegistration(TestRegistration(query));
      final RecordingListenProvider other = RecordingListenProvider();
      create(other).addEventRegistration(TestRegistration(query));
      expect(provider.started.single.tag, const Tag(1));
      expect(other.started.single.tag, const Tag(1));
      expect(tree.tagForQuery(query), const Tag(1));
    },
  );

  test('the events startListening returns are part of the result', () {
    final QuerySpec query = QuerySpec.defaultAt(Path('/.info/connected'));
    final TestRegistration registration = TestRegistration(query);
    final DataEvent infoEvent = DataEvent(
      EventType.value,
      registration,
      query.path,
      nodeFromJson(true),
    );
    provider.eventsOnStart = <Event>[infoEvent];
    expect(tree.addEventRegistration(registration), contains(infoEvent));
  });

  test(
    'a plain orderByChild is listened to as the default query, untagged',
    () {
      final QuerySpec query = QuerySpec(
        Path('/a'),
        QueryParams.defaultParams.orderBy(PathIndex(Path('age'))),
      );
      tree.addEventRegistration(TestRegistration(query));
      expect(provider.started.single.tag, isNull);
      expect(provider.started.single.query.isDefault, isTrue);
    },
  );

  test('server data raises a value event after the listen', () {
    tree.addEventRegistration(
      TestRegistration(QuerySpec.defaultAt(Path('/a'))),
    );
    final List<Event> events = tree.applyServerOverwrite(
      Path('/a'),
      nodeFromJson('x'),
    );
    expect(values(events).single.snapshot.toJson(), 'x');
  });

  test('a user write raises an event at once and the ack raises none', () {
    tree.addEventRegistration(
      TestRegistration(QuerySpec.defaultAt(Path('/a'))),
    );
    tree.applyServerOverwrite(Path('/a'), nodeFromJson(1));
    final Node two = nodeFromJson(2);
    expect(
      values(
        tree.applyUserOverwrite(
          Path('/a'),
          two,
          two,
          1,
          visible: true,
          persist: false,
        ),
      ),
      hasLength(1),
    );
    expect(
      values(
        tree.ackUserWrite(
          1,
          revert: false,
          persist: false,
          serverValues: <String, Object?>{'timestamp': 0},
        ),
      ),
      isEmpty,
    );
  });

  test('a reverted write restores the server value', () {
    tree.addEventRegistration(
      TestRegistration(QuerySpec.defaultAt(Path('/a'))),
    );
    tree.applyServerOverwrite(Path('/a'), nodeFromJson(1));
    final Node two = nodeFromJson(2);
    tree.applyUserOverwrite(
      Path('/a'),
      two,
      two,
      1,
      visible: true,
      persist: false,
    );
    final List<DataEvent> reverted = values(
      tree.ackUserWrite(
        1,
        revert: true,
        persist: false,
        serverValues: <String, Object?>{'timestamp': 0},
      ),
    );
    expect(reverted.single.snapshot.toJson(), 1);
  });

  test('a merge updates only its children', () {
    tree.addEventRegistration(
      TestRegistration(QuerySpec.defaultAt(Path('/a'))),
    );
    tree.applyServerOverwrite(
      Path('/a'),
      nodeFromJson(<String, Object?>{'b': 1, 'c': 2}),
    );
    final CompoundWrite merge = CompoundWrite.fromChildMerge(<ChildKey, Node>{
      ChildKey('c'): nodeFromJson(3),
    });
    final List<DataEvent> events = values(
      tree.applyUserMerge(Path('/a'), merge, merge, 1, persist: false),
    );
    expect(events.single.snapshot.toJson(), <String, Object?>{'b': 1, 'c': 3});
  });

  test('calcCompleteEventCache includes pending writes', () {
    tree.addEventRegistration(
      TestRegistration(QuerySpec.defaultAt(Path('/a'))),
    );
    tree.applyServerOverwrite(Path('/a'), nodeFromJson(1));
    final Node two = nodeFromJson(2);
    tree.applyUserOverwrite(
      Path('/a'),
      two,
      two,
      7,
      visible: false,
      persist: false,
    );
    expect(tree.calcCompleteEventCache(Path('/a'))?.toJson(), 2);
    expect(
      tree
          .calcCompleteEventCache(Path('/a'), writeIdsToExclude: <int>[7])
          ?.toJson(),
      1,
    );
  });

  test('removing the last registration stops the listen', () {
    final TestRegistration registration = TestRegistration(
      QuerySpec.defaultAt(Path('/a')),
    );
    tree.addEventRegistration(registration);
    tree.removeEventRegistration(registration);
    expect(provider.stopped.single.query, QuerySpec.defaultAt(Path('/a')));
    expect(tree.isEmpty, isTrue);
  });

  test(
    'a failed listen completion cancels every registration of the query',
    () {
      final QuerySpec query = QuerySpec.defaultAt(Path('/a'));
      tree.addEventRegistration(TestRegistration(query));
      final List<Event> events = provider.started.single.onComplete(
        const DatabaseError(DatabaseErrorCode.permissionDenied, 'denied'),
      );
      expect(events.whereType<CancelEvent>(), hasLength(1));
    },
  );

  test('keepSynced listens without user events', () {
    tree.keepSynced(QuerySpec.defaultAt(Path('/a')), keep: true);
    expect(provider.started, hasLength(1));
    tree.keepSynced(QuerySpec.defaultAt(Path('/a')), keep: false);
    expect(provider.stopped, hasLength(1));
  });
}
