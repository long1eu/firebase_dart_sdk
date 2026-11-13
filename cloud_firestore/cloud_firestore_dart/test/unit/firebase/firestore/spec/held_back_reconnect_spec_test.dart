// Spec-style tests (same step format and harness as the upstream JSON specs, but written here) for a document whose
// acknowledged write the view holds back until watch sends it (see `View._awaitingSync`).
//
// The view puts such a document in limbo once a snapshot of watch at or after the commit does not have it. That is
// only right when the target itself is CURRENT in that snapshot: after the watch stream reconnects, the target is
// resumed from an older resume token and catches up later, while a global snapshot at or after the commit can already
// arrive (final review 2026-11-14, finding 3).

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

const Map<String, Object?> collectionQuery = <String, Object?>{
  'filters': <Object?>[],
  'orderBys': <Object?>[],
  'path': 'collection',
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

Map<String, Object?> event({
  List<Object?>? added,
  List<Object?>? metadata,
  required bool fromCache,
  bool hasPendingWrites = false,
}) => <String, Object?>{
  'added': ?added,
  'metadata': ?metadata,
  'errorCode': 0,
  'fromCache': fromCache,
  'hasPendingWrites': hasPendingWrites,
  'query': collectionQuery,
};

Map<String, Object?> target({String resumeToken = ''}) => <String, Object?>{
  'queries': <Object?>[collectionQuery],
  'resumeToken': resumeToken,
};

Map<String, Object?> watchAck(int targetId) => <String, Object?>{
  'watchAck': <Object?>[targetId],
};

Map<String, Object?> watchSends(List<int> targets, List<Object?> docs) =>
    <String, Object?>{
      'watchEntity': <String, Object?>{'docs': docs, 'targets': targets},
    };

Map<String, Object?> watchCurrent(int targetId, String resumeToken) =>
    <String, Object?>{
      'watchCurrent': <Object?>[
        <Object?>[targetId],
        resumeToken,
      ],
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
  'v': 1,
});
final Map<String, Object?> docBLocal = doc(
  'collection/b',
  0,
  <String, Object?>{'v': 2},
  local: true,
);
final Map<String, Object?> docB = doc('collection/b', 2000, <String, Object?>{
  'v': 2,
});

/// Target 2 synced with a at 1000; the client writes b, which is acknowledged at 2000 before watch sends it.
List<Map<String, Object?>> untilHeldBack() => <Map<String, Object?>>[
  <String, Object?>{
    'userListen': <String, Object?>{'query': collectionQuery, 'targetId': 2},
    'expectedState': <String, Object?>{
      'activeTargets': <String, Object?>{'2': target()},
    },
  },
  watchAck(2),
  watchSends(<int>[2], <Object?>[docA]),
  watchCurrent(2, 'resume-token-1000'),
  watchSnapshot(
    1000,
    events: <Object?>[
      event(added: <Object?>[docA], fromCache: false),
    ],
  ),
  <String, Object?>{
    'userSet': <Object?>[
      'collection/b',
      <String, Object?>{'v': 2},
    ],
    'expectedSnapshotEvents': <Object?>[
      event(
        added: <Object?>[docBLocal],
        fromCache: false,
        hasPendingWrites: true,
      ),
    ],
  },
  <String, Object?>{
    'writeAck': <String, Object?>{'version': 2000},
    'expectedState': <String, Object?>{
      'userCallbacks': <String, Object?>{
        'acknowledgedDocs': <Object?>['collection/b'],
        'rejectedDocs': <Object?>[],
      },
    },
  },
];

void main() {
  final Map<String, Future<Persistence> Function(String name)>
  variants = <String, Future<Persistence> Function(String name)>{
    'memory': (_) async => createLRUMemoryPersistence(),
    'sqlite': (String name) => createSQLitePersistenceForProject(
      'test-project',
      'firebase/firestore/spec/held_back_reconnect_spec_test_${Uri.encodeQueryComponent(name)}',
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
        'a held back document is not in limbo while its resumed target has not '
        'caught up after a watch reconnect',
        () async {
          await run('reconnect', <Map<String, Object?>>[
            ...untilHeldBack(),
            // The watch stream fails and reconnects: target 2 is resumed from its token of 1000.
            <String, Object?>{
              'watchStreamClose': <String, Object?>{
                'error': <String, Object?>{
                  'code': 14,
                  'message': 'Simulated Backend Error',
                },
                'runBackoffTimer': true,
              },
              'expectedState': <String, Object?>{
                'activeTargets': <String, Object?>{
                  '2': target(resumeToken: 'resume-token-1000'),
                },
              },
            },
            watchAck(2),
            // A global snapshot at the commit version, before target 2 caught up: it says nothing about b.
            watchSnapshot(
              2000,
              state: <String, Object?>{
                'activeLimboDocs': <Object?>[],
                'activeTargets': <String, Object?>{
                  '2': target(resumeToken: 'resume-token-1000'),
                },
              },
            ),
            // Target 2 catches up with b.
            watchSends(<int>[2], <Object?>[docB]),
            watchCurrent(2, 'resume-token-2001'),
            watchSnapshot(
              2001,
              events: <Object?>[
                event(metadata: <Object?>[docB], fromCache: false),
              ],
              state: <String, Object?>{'activeLimboDocs': <Object?>[]},
            ),
          ]);
        },
      );

      test(
        'a held back document is in limbo once its target is CURRENT without it '
        'at or after the commit',
        () async {
          await run('current', <Map<String, Object?>>[
            ...untilHeldBack(),
            // b was deleted by another client before watch sent it: the target is CURRENT at 2000 without it.
            watchCurrent(2, 'resume-token-2000'),
            watchSnapshot(
              2000,
              events: <Object?>[
                event(fromCache: true, hasPendingWrites: true),
              ],
              state: <String, Object?>{
                'activeLimboDocs': <Object?>['collection/b'],
                'activeTargets': <String, Object?>{
                  '1': <String, Object?>{
                    'queries': <Object?>[
                      <String, Object?>{
                        'filters': <Object?>[],
                        'orderBys': <Object?>[],
                        'path': 'collection/b',
                      },
                    ],
                    'resumeToken': '',
                    'targetPurpose': 'TargetPurposeLimboResolution',
                  },
                  '2': target(),
                },
              },
            ),
          ]);
        },
      );
    });
  }
}
