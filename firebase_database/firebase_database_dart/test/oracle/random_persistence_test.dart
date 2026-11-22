// Oracle: Android test/.../core/persistence/RandomPersistenceTest.java with its generator,
// testUtil/.../core/RandomOperationGenerator.java, ported with a seeded Random (dart:math's sequence
// differs from java.util.Random's, so the seeds are our own). Runs SyncTree + DefaultPersistenceManager
// (CachePolicy.none) over the engine [runRandomPersistenceOracle] is given.
//
// Upstream runs 25 random seeds of 300 operations; here a fixed list of seeds, printed on failure.
// The generator's WriteTree and getExpectedClientState are left out: RandomPersistenceTest does not
// use them.
import 'dart:math';

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/filter/node_filter.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

import 'oracle_support.dart';

void main() => runRandomPersistenceOracle(openInMemoryEngine);

/// The seeds run (upstream: 25 fresh random seeds per run).
const List<int> randomPersistenceSeeds = <int>[
  1,
  2,
  3,
  5,
  8,
  13,
  21,
  34,
  55,
  89,
];

/// Set to true for debugging.
bool _verbose = false;

const int _operationsPerTest = 300;
const double _listenProbability = 0.1;
const int _maxListenDepth = 3;

/// Android `RandomPersistenceTest.TestEventRegistration`: responds to nothing.
final class _TestEventRegistration extends EventRegistration {
  _TestEventRegistration(this.querySpec);

  @override
  final QuerySpec querySpec;

  @override
  bool respondsTo(EventType type) => false;

  @override
  DataEvent createEvent(Change change, QuerySpec query) =>
      DataEvent(change.eventType, this, query.path, change.node);

  @override
  void fireEvent(DataEvent event) {}

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) =>
      _TestEventRegistration(newQuery);

  @override
  bool isSameListener(EventRegistration other) => identical(other, this);
}

/// Records each started listen into the generator and the tags.
final class _GeneratorListenProvider implements ListenProvider {
  _GeneratorListenProvider(this._generator, this._tagMap);

  final _RandomOperationGenerator _generator;
  final Map<QuerySpec, Tag> _tagMap;

  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) {
    _generator.listen(query);
    if (tag != null) {
      _tagMap[query] = tag;
    }
    return const <Event>[];
  }

  @override
  void stopListening(QuerySpec query, Tag? tag) {
    // TODO: unlisten
  }
}

Map<Path, Node> _fromCompoundWrite(CompoundWrite write) => <Path, Node>{
  for (final MapEntry<Path, Node> entry in write.entries)
    entry.key: entry.value,
};

/// The RandomPersistenceTest suite against the engines [openEngine] opens (clean ones).
void runRandomPersistenceOracle(
  OpenEngine openEngine, {
  List<int> seeds = randomPersistenceSeeds,
  int operationsPerTest = _operationsPerTest,
}) {
  group('RandomPersistenceTest', () {
    test('randomOperations', () {
      for (final int seed in seeds) {
        final PersistenceStorageEngine storageEngine = openEngine();
        int operation = -1;
        try {
          _runSeed(seed, storageEngine, operationsPerTest, (int j) {
            operation = j;
          });
        } on Object {
          printOnFailure(
            'randomOperations failed with seed $seed at operation $operation',
          );
          rethrow;
        } finally {
          storageEngine.close();
        }
      }
    });
  });
}

void _runSeed(
  int seed,
  PersistenceStorageEngine storageEngine,
  int operationsPerTest,
  void Function(int operation) onOperation,
) {
  final bool verbose = _verbose;
  final _RandomOperationGenerator generator = _RandomOperationGenerator(seed);
  final Random random = Random(seed);

  final Set<QuerySpec> activeListens = <QuerySpec>{};
  final Set<QuerySpec> completeListens = <QuerySpec>{};
  int currentWriteId = 0;
  int currentUnackedWriteId = 0;

  final DefaultPersistenceManager manager = DefaultPersistenceManager(
    storageEngine,
    CachePolicy.none,
    DateTime.now,
  );
  final Map<QuerySpec, Tag> tagMap = <QuerySpec, Tag>{};
  final SyncTree syncTree = SyncTree(
    listenProvider: _GeneratorListenProvider(generator, tagMap),
    persistenceManager: manager,
  );

  void applyOperation(Operation operation) {
    final OperationSource source = operation.source;
    if (source.tagged) {
      final Tag? tag = tagMap[QuerySpec(operation.path, source.queryParams!)];
      expect(tag, isNotNull);
      switch (operation) {
        case ListenComplete():
          syncTree.applyTaggedListenComplete(tag!);
        case Overwrite(:final Node snapshot):
          syncTree.applyTaggedQueryOverwrite(operation.path, snapshot, tag!);
        case Merge(:final CompoundWrite children):
          syncTree.applyTaggedQueryMerge(
            operation.path,
            _fromCompoundWrite(children),
            tag!,
          );
        default:
          throw ArgumentError("Can't have tagged operation: $operation");
      }
    } else {
      switch (operation) {
        case ListenComplete():
          syncTree.applyListenComplete(operation.path);
        case Overwrite(:final Node snapshot):
          if (source.fromServer) {
            syncTree.applyServerOverwrite(operation.path, snapshot);
          } else {
            syncTree.applyUserOverwrite(
              operation.path,
              snapshot,
              snapshot,
              currentWriteId++,
              visible: true,
              persist: true,
            );
          }
        case Merge(:final CompoundWrite children):
          if (source.fromServer) {
            syncTree.applyServerMerge(
              operation.path,
              _fromCompoundWrite(children),
            );
          } else {
            syncTree.applyUserMerge(
              operation.path,
              children,
              children,
              currentWriteId++,
              persist: true,
            );
          }
        case AckUserWrite(:final bool revert):
          syncTree.ackUserWrite(
            currentUnackedWriteId++,
            revert: revert,
            persist: true,
            serverValues: generateServerValues(timestamp: 1),
          );
      }
    }
  }

  for (int j = 0; j < operationsPerTest; j++) {
    onOperation(j);
    if (activeListens.isEmpty || random.nextDouble() < _listenProbability) {
      final Path path = generator.nextRandomPath(_maxListenDepth);
      final QueryParams params = generator.nextRandomParams();
      // TODO: removable event registrations
      // TODO: unlistens
      final QuerySpec querySpec = QuerySpec(path, params);
      activeListens.add(querySpec);
      syncTree.addEventRegistration(_TestEventRegistration(querySpec));
      if (verbose) {
        printOnFailure('Adding listen for: $path => $params');
      }
    } else {
      final Operation op = generator.nextOperation();
      if (verbose) {
        printOnFailure('Applying operation: $op');
      }
      if (op is ListenComplete) {
        final QueryParams? params = op.source.queryParams;
        if (params != null) {
          completeListens.add(QuerySpec(op.path, params));
        } else {
          completeListens.add(QuerySpec.defaultAt(op.path));
        }
      }
      applyOperation(op);
    }

    final List<TrackedQuery> trackedQueries = storageEngine
        .loadTrackedQueries();

    // Check that active listens match tracked queries
    for (final QuerySpec entry in completeListens) {
      final Path path = entry.path;
      final QueryParams params = entry.params;
      bool found = false;
      for (final TrackedQuery trackedQuery in trackedQueries) {
        if (trackedQuery.querySpec == entry) {
          expect(trackedQuery.complete, isTrue);
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Active listen must be in tracked queries');
      if (params.loadsAllData) {
        final Node persistenceNode = storageEngine.serverCache(path);
        final Node serverNode = generator.getCurrentServerNode(path);
        expect(
          persistenceNode,
          serverNode,
          reason: 'Node persisted should match server code',
        );
      }
    }
  }
}

/// Android `RandomOperationGenerator.WriteOp`.
final class _WriteOp {
  _WriteOp(this.operation, this.writeId);

  final int writeId;
  final Operation operation;
}

/// Android `testUtil/.../core/RandomOperationGenerator.java`: random write, merge and ack operations
/// for server and user, tracking the server state as ground truth.
final class _RandomOperationGenerator {
  _RandomOperationGenerator(this.seed) : _random = Random(seed) {
    _currentServerState = _getRandomNode(0, _maxDepth);
  }

  static const double _serverOpProbability = 0.7;
  static const double _mergeProbability = 0.3;
  static const double _revertProbability = 0.5;
  static const double _serverAckProbability = 0.7;
  static const double _serverListenResponseProbability = 0.7;
  static const double _defaultParamsProbability = 0.5;
  static const int _maxMergeSize = 20;
  static const int _maxDepth = 3;
  static const int _maxTopChildren = 10;
  static const int _maxOtherChildren = 3;
  static const double _priorityKeyProbability = 0.1;
  static const double _indexKeyProbability = 0.1;
  static const int _maxPrioValues = 10;
  static const int _maxKeyValues = 100;

  final int seed;
  final Random _random;
  late Node _currentServerState;
  int _currentWriteId = 0;
  final List<_WriteOp> _outstandingWrites = <_WriteOp>[];
  final List<QuerySpec> _outstandingListens = <QuerySpec>[];
  final List<QuerySpec> _outstandingUnlistens = <QuerySpec>[];

  /// Never set upstream either: no ListenComplete is ever generated.
  QuerySpec? _completeDataJustSentForListen;
  _WriteOp? _writeOpForLastUpdate;

  void listen(QuerySpec query) => _outstandingListens.add(query);

  Operation nextOperation() {
    if (_writeOpForLastUpdate != null) {
      return _getAck();
    }
    if (_random.nextDouble() < _serverOpProbability) {
      final QuerySpec? complete = _completeDataJustSentForListen;
      if (complete != null) {
        final Path path = complete.path;
        final QueryParams params = complete.params;
        final OperationSource source;
        if (!params.loadsAllData) {
          source = OperationSource.forServerTaggedQuery(params);
        } else {
          source = OperationSource.server;
        }
        _completeDataJustSentForListen = null;
        return ListenComplete(source, path);
      } else if (_outstandingListens.isNotEmpty &&
          _random.nextDouble() < _serverListenResponseProbability) {
        final QuerySpec listen = _outstandingListens.removeAt(0);
        final QueryParams params = listen.params;
        final Path path = listen.path;
        final Node currentServerNode = _currentServerState.getChild(path);
        if (!params.loadsAllData) {
          final Node emptyNode = ChildrenNode.empty.withIndex(params.index);
          final Node node = nodeFilterFor(params).updateFullNode(
            emptyNode,
            currentServerNode.withIndex(params.index),
            null,
          );
          final OperationSource source = OperationSource.forServerTaggedQuery(
            listen.params,
          );
          return Overwrite(source, path, node);
        } else {
          return Overwrite(OperationSource.server, path, currentServerNode);
        }
      } else if (_outstandingUnlistens.isNotEmpty &&
          _random.nextDouble() < _serverListenResponseProbability) {
        throw StateError('NOT IMPL!');
      } else if (_outstandingWrites.isNotEmpty &&
          _random.nextDouble() < _serverAckProbability) {
        final _WriteOp op = _outstandingWrites.first;
        final Path path = op.operation.path;
        final bool isEmptyPriorityError =
            !path.isEmpty &&
            path.back!.isPriorityKey &&
            _currentServerState.getChild(path.parent!).isEmpty;
        if (_random.nextDouble() < _revertProbability || isEmptyPriorityError) {
          _outstandingWrites.removeAt(0);
          return _getAckForWrite(op.operation, revert: true);
        } else {
          // TODO: maybe ignore if write equals server data
          final Operation serverOp = _userOperationToServerOperation(
            op.operation,
          );
          _currentServerState = _applyOperation(serverOp, _currentServerState);
          _writeOpForLastUpdate = op;
          return serverOp;
        }
      } else {
        if (_random.nextDouble() < _mergeProbability) {
          final Merge merge = _getRandomMerge(OperationSource.server);
          _currentServerState = _applyOperation(merge, _currentServerState);
          return merge;
        } else {
          final Overwrite overwrite = _getRandomOverwrite(
            OperationSource.server,
          );
          final ChildKey? back = overwrite.path.back;
          if (back != null &&
              back.isPriorityKey &&
              _currentServerState.getChild(overwrite.path.parent!).isEmpty) {
            // This is a case where we would overwrite a priority on an empty node which is an
            // illegal update
            return nextOperation();
          }
          _currentServerState = _applyOperation(overwrite, _currentServerState);
          return overwrite;
        }
      }
    } else {
      if (_random.nextDouble() < _mergeProbability) {
        final Merge merge = _getRandomMerge(OperationSource.user);
        _outstandingWrites.add(_WriteOp(merge, _currentWriteId++));
        return merge;
      } else {
        final Overwrite overwrite = _getRandomOverwrite(OperationSource.user);
        _outstandingWrites.add(_WriteOp(overwrite, _currentWriteId++));
        return overwrite;
      }
    }
  }

  QueryParams nextRandomParams() => _getRandomQueryParams();

  Node getCurrentServerNode(Path path) => _currentServerState.getChild(path);

  Operation _getAck() {
    final _WriteOp op = _writeOpForLastUpdate!;
    final _WriteOp frontOp = _outstandingWrites.removeAt(0);
    expect(
      identical(op, frontOp),
      isTrue,
      reason: 'The write op should be the front of the queue',
    );
    _writeOpForLastUpdate = null;
    return _getAckForWrite(op.operation, revert: false);
  }

  Operation _getAckForWrite(Operation writeOp, {required bool revert}) {
    switch (writeOp) {
      case Overwrite():
        return AckUserWrite(
          writeOp.path,
          ImmutableTree<bool>(true),
          revert: revert,
        );
      case Merge(:final CompoundWrite children):
        ImmutableTree<bool> affectedTree = ImmutableTree<bool>.empty();
        for (final MapEntry<Path, Node> entry in children.entries) {
          affectedTree = affectedTree.set(entry.key, true);
        }
        return AckUserWrite(writeOp.path, affectedTree, revert: revert);
      default:
        throw StateError('Not a write: $writeOp');
    }
  }

  ChildKey _getRandomKey({required bool allowPriority}) {
    final double randValue = _random.nextDouble();
    if (allowPriority && randValue < _priorityKeyProbability) {
      return ChildKey.priority;
    } else if (_random.nextDouble() < _indexKeyProbability) {
      return ChildKey('index-key');
    } else {
      return ChildKey('key-${_random.nextInt(_maxKeyValues)}');
    }
  }

  Node _getRandomPriority() {
    if (_random.nextDouble() < 0.9) {
      return ChildrenNode.empty;
    } else if (_random.nextDouble() < 0.5) {
      return LeafNode('prio-${_random.nextInt(_maxPrioValues)}');
    } else {
      return LeafNode(_random.nextInt(_maxPrioValues).toDouble());
    }
  }

  /// Java `Random.nextInt()`: any 32-bit int.
  int _nextInt32() => _random.nextInt(1 << 32) - (1 << 31);

  /// Java `Random.nextLong()`: any 64-bit int.
  int _nextLong() =>
      (_random.nextInt(1 << 32) << 32) | _random.nextInt(1 << 32);

  Node _getRandomLeafNodeWithoutLongs() =>
      _getRandomLeafNodeFromRandom(_random.nextDouble() * 0.8);

  Node _getRandomLeafNode() =>
      _getRandomLeafNodeFromRandom(_random.nextDouble());

  Node _getRandomLeafNodeFromRandom(double randValue) {
    if (randValue < 0.2) {
      return ChildrenNode.empty;
    } else if (randValue < 0.4) {
      return LeafNode(_random.nextBool(), _getRandomPriority());
    } else if (randValue < 0.6) {
      return LeafNode('string-${_nextInt32()}', _getRandomPriority());
    } else if (randValue < 0.8) {
      return LeafNode(_random.nextDouble(), _getRandomPriority());
    } else {
      return LeafNode(_nextLong(), _getRandomPriority());
    }
  }

  Node _getRandomNode(int curDepth, int maxDepth) {
    if (curDepth >= maxDepth) {
      return _getRandomLeafNode();
    } else {
      final double randValue = _random.nextDouble();
      if (randValue < 0.2) {
        return ChildrenNode.empty;
      } else if (randValue < 0.4) {
        return _getRandomLeafNode();
      } else {
        final int numChildren =
            1 +
            _random.nextInt(
              curDepth == 0 ? _maxTopChildren : _maxOtherChildren,
            );
        Node currentNode = ChildrenNode.empty;
        for (int i = 0; i < numChildren; i++) {
          final ChildKey randomKey = _getRandomKey(allowPriority: false);
          final Node randomChildNode = _getRandomNode(curDepth + 1, maxDepth);
          currentNode = currentNode.updateImmediateChild(
            randomKey,
            randomChildNode,
          );
        }
        if (currentNode.isEmpty) {
          return ChildrenNode.empty;
        } else {
          return currentNode.updatePriority(_getRandomPriority());
        }
      }
    }
  }

  QueryParams _getRandomQueryParams() {
    if (_random.nextDouble() < _defaultParamsProbability) {
      return QueryParams.defaultParams;
    } else {
      final double type = _random.nextDouble();
      final bool hasEnd = _random.nextBool();
      final bool hasStart = _random.nextBool();
      final bool hasLimit = _random.nextBool();
      QueryParams params = QueryParams.defaultParams;
      Node start;
      Node end;
      if (type < 0.4) {
        params = params.orderBy(PathIndex(Path('index-key')));
        start = _getRandomLeafNodeWithoutLongs();
        end = _getRandomLeafNodeWithoutLongs();
      } else if (type < 0.8) {
        // Order by key
        params = params.orderBy(keyIndex);
        final ChildKey startKey = _getRandomKey(allowPriority: false);
        final ChildKey endKey = _getRandomKey(allowPriority: false);
        start = LeafNode(startKey.name);
        end = LeafNode(endKey.name);
      } else {
        // Order by Priority
        params = params.orderBy(priorityIndex);
        start = _getRandomPriority();
        end = _getRandomPriority();
      }
      if (hasStart && hasEnd && start.compareTo(end) > 0) {
        final Node tmp = start;
        start = end;
        end = tmp;
      }
      if (hasStart) {
        params = params.startAt(start);
      }
      if (hasEnd) {
        params = params.endAt(end);
      }
      if (hasLimit) {
        final int limit = _random.nextInt(30) + 1;
        final bool limitToFirst = _random.nextBool();
        if (limitToFirst) {
          params = params.limitToFirst(limit);
        } else {
          params = params.limitToLast(limit);
        }
      }
      return params;
    }
  }

  Path nextRandomPath(int maxDepth) {
    final int depth = _random.nextInt(maxDepth);
    Path path = Path.empty;
    for (int i = 0; i < depth; i++) {
      final ChildKey key = _getRandomKey(allowPriority: false);
      path = path.child(key);
    }
    return path;
  }

  Merge _getRandomMerge(OperationSource source) {
    final Path path = nextRandomPath(_maxDepth);
    final int numMergeNodes = _random.nextInt(_maxMergeSize) + 1;
    CompoundWrite write = CompoundWrite.empty;
    for (int i = 0; i < numMergeNodes; i++) {
      write = write.addWrite(
        Path.fromKeys(<ChildKey>[_getRandomKey(allowPriority: false)]),
        _getRandomNode(path.length + 1, _maxDepth),
      );
    }
    return Merge(source, path, write);
  }

  Overwrite _getRandomOverwrite(OperationSource source) {
    Path path = nextRandomPath(_maxDepth);
    final Node node;
    if (_random.nextDouble() < _priorityKeyProbability) {
      path = path.child(ChildKey.priority);
      node = _getRandomPriority();
    } else {
      final int maxNodeDepth = _maxDepth - path.length;
      node = _getRandomNode(path.length, maxNodeDepth);
    }
    return Overwrite(source, path, node);
  }

  static Operation _userOperationToServerOperation(Operation operation) {
    expect(operation.source.fromUser, isTrue);
    switch (operation) {
      case Overwrite(:final Node snapshot):
        return Overwrite(OperationSource.server, operation.path, snapshot);
      case Merge(:final CompoundWrite children):
        return Merge(OperationSource.server, operation.path, children);
      default:
        throw ArgumentError(
          "Can't convert operation of type $operation to node",
        );
    }
  }

  static Node _applyOperation(Operation operation, Node node) {
    switch (operation) {
      case Overwrite(:final Node snapshot):
        final Path path = operation.path;
        if (!path.isEmpty &&
            path.back!.isPriorityKey &&
            node.getChild(path.parent!).isEmpty) {
          // Don't update priorities on empty nodes
          return node;
        } else {
          return node.updateChild(operation.path, snapshot);
        }
      case Merge(:final CompoundWrite children):
        final Path path = operation.path;
        final Node child = node.getChild(path);
        return node.updateChild(path, children.apply(child));
      case ListenComplete():
        // No-op
        return node;
      default:
        throw ArgumentError("Can't apply operation of type $operation to node");
    }
  }
}
