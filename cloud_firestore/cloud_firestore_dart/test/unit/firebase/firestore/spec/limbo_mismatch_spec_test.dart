// Spec-style tests (same step format and harness as the upstream JSON specs,
// but written here) for a limbo document that EXISTS on the backend although
// the target of the query is CURRENT without it: the backend does not
// consider it a result of the query, while the client does (its filter
// semantics differ, see the query property tests).
//
// Upstream keeps such a document in limbo forever: the view never leaves
// `fromCache: true` and a get from the server never completes. This port
// trusts the backend once that is safe and drops the document from the view
// of that query. See
// firebase_dart_sdk_revival_notes/parity/limbo_mismatch.md for the analysis.

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

const Map<String, Object?> collectionQuery = <String, Object?>{
  'filters': <Object?>[],
  'orderBys': <Object?>[],
  'path': 'collection',
};

const Map<String, Object?> limitQuery = <String, Object?>{
  'filters': <Object?>[],
  'limit': 2,
  'limitType': 'LimitToFirst',
  'orderBys': <Object?>[],
  'path': 'collection',
};

Map<String, Object?> docQuery(String key) => <String, Object?>{
  'filters': <Object?>[],
  'orderBys': <Object?>[],
  'path': key,
};

Map<String, Object?> doc(
  String key,
  int version,
  Map<String, Object?> value, {
  bool local = false,
  bool committed = false,
}) => <String, Object?>{
  'createTime': 0,
  'key': key,
  'options': <String, Object?>{
    'hasCommittedMutations': committed,
    'hasLocalMutations': local,
  },
  'value': value,
  'version': version,
};

Map<String, Object?> event(
  Map<String, Object?> query, {
  List<Object?>? added,
  List<Object?>? removed,
  List<Object?>? modified,
  List<Object?>? metadata,
  required bool fromCache,
  bool hasPendingWrites = false,
}) => <String, Object?>{
  'added': ?added,
  'removed': ?removed,
  'modified': ?modified,
  'metadata': ?metadata,
  'errorCode': 0,
  'fromCache': fromCache,
  'hasPendingWrites': hasPendingWrites,
  'query': query,
};

Map<String, Object?> target(
  Map<String, Object?> query, {
  String resumeToken = '',
  bool limbo = false,
}) => <String, Object?>{
  'queries': <Object?>[query],
  'resumeToken': resumeToken,
  if (limbo) 'targetPurpose': 'TargetPurposeLimboResolution',
};

Map<String, Object?> userListen(
  int targetId,
  Map<String, Object?> query, {
  List<Object?>? events,
  Map<String, Object?>? state,
}) => <String, Object?>{
  'userListen': <String, Object?>{'query': query, 'targetId': targetId},
  'expectedSnapshotEvents': ?events,
  'expectedState': ?state,
};

Map<String, Object?> watchAck(int targetId) => <String, Object?>{
  'watchAck': <Object?>[targetId],
};

Map<String, Object?> watchSends(
  List<int> targets,
  List<Object?> docs, {
  List<int>? removedTargets,
}) => <String, Object?>{
  'watchEntity': <String, Object?>{
    'docs': docs,
    if (targets.isNotEmpty) 'targets': targets,
    'removedTargets': ?removedTargets,
  },
};

Map<String, Object?> watchCurrent(int targetId, String resumeToken) =>
    <String, Object?>{
      'watchCurrent': <Object?>[
        <Object?>[targetId],
        resumeToken,
      ],
    };

Map<String, Object?> watchReset(int targetId) => <String, Object?>{
  'watchReset': <Object?>[targetId],
};

Map<String, Object?> watchSnapshot(
  int version, {
  List<Object?>? events,
  Map<String, Object?>? state,
}) => <String, Object?>{
  'watchSnapshot': <String, Object?>{
    'targetIds': <Object?>[],
    'version': version,
  },
  'expectedSnapshotEvents': ?events,
  'expectedState': ?state,
};

final Map<String, Object?> docA = doc('collection/a', 1000, <String, Object?>{
  'key': 'a',
});
final Map<String, Object?> docB = doc('collection/b', 1000, <String, Object?>{
  'key': 'b',
});
final Map<String, Object?> docC = doc('collection/c', 1000, <String, Object?>{
  'key': 'c',
});

/// The steps that bring [query] (target 2) to: synced with a, b (and c for the
/// limit query's cache), then the backend resets the target to a only, so
/// that b is in limbo (limbo target 1).
List<Map<String, Object?>> untilLimbo(
  Map<String, Object?> query, {
  List<Object?>? initial,
  List<Object?>? afterReset,
}) {
  return <Map<String, Object?>>[
    userListen(
      2,
      query,
      state: <String, Object?>{
        'activeTargets': <String, Object?>{'2': target(query)},
      },
    ),
    watchAck(2),
    watchSends(<int>[2], initial ?? <Object?>[docA, docB]),
    watchCurrent(2, 'resume-token-1000'),
    watchSnapshot(
      1000,
      events: <Object?>[
        event(query, added: initial ?? <Object?>[docA, docB], fromCache: false),
      ],
    ),
    // The backend now says that only a is a result.
    watchReset(2),
    watchSends(<int>[2], afterReset ?? <Object?>[docA]),
    watchCurrent(2, 'resume-token-2000'),
    watchSnapshot(
      2000,
      events: <Object?>[event(query, fromCache: true)],
      state: <String, Object?>{
        'activeLimboDocs': <Object?>['collection/b'],
        'activeTargets': <String, Object?>{
          '1': target(docQuery('collection/b'), limbo: true),
          '2': target(query),
        },
      },
    ),
  ];
}

/// The limbo resolution answers: b exists, unchanged.
List<Map<String, Object?>> limboResolutionFindsTheDocument(
  Map<String, Object?> query, {
  required List<Object?> events,
}) {
  return <Map<String, Object?>>[
    watchAck(1),
    watchSends(<int>[1], <Object?>[docB]),
    watchCurrent(1, 'resume-token-2001'),
    watchSnapshot(
      2001,
      events: events,
      state: <String, Object?>{
        'activeLimboDocs': <Object?>[],
        'activeTargets': <String, Object?>{'2': target(query)},
      },
    ),
  ];
}

void main() {
  final Map<String, Future<Persistence> Function(String name)>
  variants = <String, Future<Persistence> Function(String name)>{
    'memory': (_) async => createLRUMemoryPersistence(),
    'sqlite': (String name) => createSQLitePersistenceForProject(
      'test-project',
      'firebase/firestore/spec/limbo_mismatch_spec_test_${Uri.encodeQueryComponent(name)}',
    ),
  };

  for (final MapEntry<String, Future<Persistence> Function(String)> variant
      in variants.entries) {
    Future<void> run(String name, List<Map<String, Object?>> steps) {
      final SpecTestCase testCase = SpecTestCase(
        (_, String name) => variant.value(name),
      )..currentName = '${variant.key}_$name';
      return testCase.runSteps(steps, <String, dynamic>{
        'numClients': 1,
        'useEagerGCForMemory': false,
      });
    }

    group(variant.key, () {
      test(
        'a limbo document that exists but is not in the target is dropped',
        () async {
          await run('dropped', <Map<String, Object?>>[
            ...untilLimbo(collectionQuery),
            ...limboResolutionFindsTheDocument(
              collectionQuery,
              events: <Object?>[
                event(
                  collectionQuery,
                  removed: <Object?>[docB],
                  fromCache: false,
                ),
              ],
            ),
            // Nothing changes with further snapshots: the document does not
            // go back to limbo.
            watchSnapshot(
              2002,
              state: <String, Object?>{
                'activeLimboDocs': <Object?>[],
                'activeTargets': <String, Object?>{
                  '2': target(collectionQuery),
                },
              },
            ),
            watchSnapshot(2003),
          ]);
        },
      );

      test(
        'the document comes back when the backend adds it to the target',
        () async {
          final Map<String, Object?> newB = doc(
            'collection/b',
            3000,
            <String, Object?>{'key': 'b2'},
          );
          await run('comes_back', <Map<String, Object?>>[
            ...untilLimbo(collectionQuery),
            ...limboResolutionFindsTheDocument(
              collectionQuery,
              events: <Object?>[
                event(
                  collectionQuery,
                  removed: <Object?>[docB],
                  fromCache: false,
                ),
              ],
            ),
            watchSends(<int>[2], <Object?>[newB]),
            watchSnapshot(
              3000,
              events: <Object?>[
                event(
                  collectionQuery,
                  added: <Object?>[newB],
                  fromCache: false,
                ),
              ],
            ),
          ]);
        },
      );

      test('a local write brings the document back', () async {
        final Map<String, Object?> patchedB = doc(
          'collection/b',
          0,
          <String, Object?>{'key': 'b', 'extra': 1},
          local: true,
        );
        await run('local_write', <Map<String, Object?>>[
          ...untilLimbo(collectionQuery),
          ...limboResolutionFindsTheDocument(
            collectionQuery,
            events: <Object?>[
              event(
                collectionQuery,
                removed: <Object?>[docB],
                fromCache: false,
              ),
            ],
          ),
          <String, Object?>{
            'userPatch': <Object?>[
              'collection/b',
              <String, Object?>{'extra': 1},
            ],
            'expectedSnapshotEvents': <Object?>[
              event(
                collectionQuery,
                added: <Object?>[patchedB],
                fromCache: false,
                hasPendingWrites: true,
              ),
            ],
          },
        ]);
      });

      test('a limit query is refilled from the cache', () async {
        // Cached: a, b, c. The limit query shows a and b; the backend says
        // a and c.
        await run('limit', <Map<String, Object?>>[
          // Fill the cache with all three documents.
          userListen(
            2,
            collectionQuery,
            state: <String, Object?>{
              'activeTargets': <String, Object?>{'2': target(collectionQuery)},
            },
          ),
          watchAck(2),
          watchSends(<int>[2], <Object?>[docA, docB, docC]),
          watchCurrent(2, 'resume-token-500'),
          watchSnapshot(
            500,
            events: <Object?>[
              event(
                collectionQuery,
                added: <Object?>[docA, docB, docC],
                fromCache: false,
              ),
            ],
          ),
          <String, Object?>{
            'userUnlisten': <Object?>[2, collectionQuery],
            'expectedState': <String, Object?>{
              'activeTargets': <String, Object?>{},
            },
          },
          userListen(
            4,
            limitQuery,
            events: <Object?>[
              event(limitQuery, added: <Object?>[docA, docB], fromCache: true),
            ],
            state: <String, Object?>{
              'activeTargets': <String, Object?>{'4': target(limitQuery)},
            },
          ),
          watchAck(4),
          watchSends(<int>[4], <Object?>[docA, docC]),
          watchCurrent(4, 'resume-token-2000'),
          watchSnapshot(
            2000,
            state: <String, Object?>{
              'activeLimboDocs': <Object?>['collection/b'],
              'activeTargets': <String, Object?>{
                '1': target(docQuery('collection/b'), limbo: true),
                '4': target(limitQuery),
              },
            },
          ),
          watchAck(1),
          watchSends(<int>[1], <Object?>[docB]),
          watchCurrent(1, 'resume-token-2001'),
          watchSnapshot(
            2001,
            events: <Object?>[
              event(
                limitQuery,
                removed: <Object?>[docB],
                added: <Object?>[docC],
                fromCache: false,
              ),
            ],
            state: <String, Object?>{
              'activeLimboDocs': <Object?>[],
              'activeTargets': <String, Object?>{'4': target(limitQuery)},
            },
          ),
        ]);
      });

      test('a pending write keeps the document in limbo', () async {
        // The write to another document may be the reason why the client
        // has a result the backend does not have yet.
        final Map<String, Object?> patchedA = doc(
          'collection/a',
          0,
          <String, Object?>{'key': 'a', 'extra': 1},
          local: true,
        );
        final List<Map<String, Object?>> steps = untilLimbo(collectionQuery);
        await run('pending_write', <Map<String, Object?>>[
          ...steps,
          <String, Object?>{
            'userPatch': <Object?>[
              'collection/a',
              <String, Object?>{'extra': 1},
            ],
            'expectedSnapshotEvents': <Object?>[
              event(
                collectionQuery,
                modified: <Object?>[patchedA],
                fromCache: true,
                hasPendingWrites: true,
              ),
            ],
          },
          watchAck(1),
          watchSends(<int>[1], <Object?>[docB]),
          watchCurrent(1, 'resume-token-2001'),
          watchSnapshot(
            2001,
            state: <String, Object?>{
              'activeLimboDocs': <Object?>['collection/b'],
              'activeTargets': <String, Object?>{
                '1': target(docQuery('collection/b'), limbo: true),
                '2': target(collectionQuery),
              },
            },
          ),
        ]);
      });

      test('a limbo document that was deleted is still removed', () async {
        await run('deleted', <Map<String, Object?>>[
          ...untilLimbo(collectionQuery),
          watchAck(1),
          watchCurrent(1, 'resume-token-2001'),
          watchSnapshot(
            2001,
            events: <Object?>[
              event(
                collectionQuery,
                removed: <Object?>[docB],
                fromCache: false,
              ),
            ],
            state: <String, Object?>{
              'activeLimboDocs': <Object?>[],
              'activeTargets': <String, Object?>{'2': target(collectionQuery)},
            },
          ),
        ]);
      });

      test('a limbo document that changed is resolved by the change', () async {
        final Map<String, Object?> newB = doc(
          'collection/b',
          2001,
          <String, Object?>{'key': 'b2'},
        );
        await run('changed', <Map<String, Object?>>[
          ...untilLimbo(collectionQuery),
          watchAck(1),
          watchSends(<int>[1], <Object?>[newB]),
          watchCurrent(1, 'resume-token-2001'),
          // The new version still matches the client's query and is still
          // not in the target: the backend does not consider it a result.
          watchSnapshot(
            2001,
            events: <Object?>[
              event(
                collectionQuery,
                removed: <Object?>[docB],
                fromCache: false,
              ),
            ],
            state: <String, Object?>{
              'activeLimboDocs': <Object?>[],
              'activeTargets': <String, Object?>{'2': target(collectionQuery)},
            },
          ),
        ]);
      });
    });
  }
}
