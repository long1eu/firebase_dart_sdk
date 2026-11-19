// Spec-style tests (the step format and harness of the upstream JSON specs, written here) for a document whose
// acknowledged write the view holds back until watch sends it (`View.shouldWaitForSyncedDocument`), in the orders a
// slow client sees: watch ahead of the write stream, and watch behind it.
//
// The last two tests are the sequence of the flaky first test of test/browser/web_indexeddb_engine_test.dart: a write
// with a transform is acknowledged, the client then deletes another document, and only then watch sends the first
// one. The view of every engine ends right (no pending writes), but that last change is a metadata change only, which
// a listener without metadata changes does not get: its last snapshot keeps `hasPendingWrites`, as upstream.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
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
}) => <String, Object?>{
  'createTime': 0,
  'key': key,
  'options': <String, Object?>{
    'hasCommittedMutations': false,
    'hasLocalMutations': local,
  },
  'value': value,
  'version': version,
};

Map<String, Object?> event({
  List<Object?>? added,
  List<Object?>? modified,
  List<Object?>? metadata,
  List<Object?>? removed,
  required bool fromCache,
  bool hasPendingWrites = false,
}) => <String, Object?>{
  'added': ?added,
  'modified': ?modified,
  'metadata': ?metadata,
  'removed': ?removed,
  'errorCode': 0,
  'fromCache': fromCache,
  'hasPendingWrites': hasPendingWrites,
  'query': collectionQuery,
};

const Map<String, Object?> increment100 = <String, Object?>{
  '_methodName': 'increment',
  '_operand': 100,
};

Map<String, Object?> watchSends(List<Object?> docs) => <String, Object?>{
  'watchEntity': <String, Object?>{
    'docs': docs,
    'targets': <Object?>[2],
  },
};

Map<String, Object?> watchSnapshot(int version, {List<Object?>? events}) =>
    <String, Object?>{
      'watchSnapshot': <String, Object?>{
        'targetIds': <Object?>[],
        'version': version,
      },
      'expectedSnapshotEvents': ?events,
    };

Map<String, Object?> writeAck(
  String key,
  int version, {
  List<Object?>? transformResults,
  List<Object?>? events,
}) => <String, Object?>{
  'writeAck': <String, Object?>{
    'version': version,
    'transformResults': ?transformResults,
  },
  'expectedSnapshotEvents': ?events,
  'expectedState': <String, Object?>{
    'userCallbacks': <String, Object?>{
      'acknowledgedDocs': <Object?>[key],
      'rejectedDocs': <Object?>[],
    },
  },
};

/// Listens to the collection (target 2), which watch has CURRENT and empty at 1000.
List<Map<String, Object?>> listen({required bool metadataChanges}) =>
    <Map<String, Object?>>[
      <String, Object?>{
        'userListen': <String, Object?>{
          'query': collectionQuery,
          'targetId': 2,
          'options': <String, Object?>{
            'includeDocumentMetadataChanges': metadataChanges,
          },
        },
        'expectedState': <String, Object?>{
          'activeTargets': <String, Object?>{
            '2': <String, Object?>{
              'queries': <Object?>[collectionQuery],
              'resumeToken': '',
            },
          },
        },
      },
      <String, Object?>{
        'watchAck': <Object?>[2],
      },
      <String, Object?>{
        'watchCurrent': <Object?>[
          <Object?>[2],
          'resume-token-1000',
        ],
      },
      watchSnapshot(1000, events: <Object?>[event(fromCache: false)]),
    ];

/// The client sets a ({n: 3}), acknowledged at 1500 before watch sends it, and then increments n by 100 (committed at
/// 2000).
List<Map<String, Object?>> setThenIncrement() => <Map<String, Object?>>[
  ...listen(metadataChanges: true),
  <String, Object?>{
    'userSet': <Object?>[
      'collection/a',
      <String, Object?>{'n': 3},
    ],
    'expectedSnapshotEvents': <Object?>[
      event(
        added: <Object?>[
          doc('collection/a', 0, <String, Object?>{'n': 3}, local: true),
        ],
        fromCache: false,
        hasPendingWrites: true,
      ),
    ],
  },
  // Held back until watch sends a.
  writeAck('collection/a', 1500),
  <String, Object?>{
    'userPatch': <Object?>[
      'collection/a',
      <String, Object?>{'n': increment100},
    ],
    'expectedSnapshotEvents': <Object?>[
      event(
        modified: <Object?>[
          doc('collection/a', 0, <String, Object?>{'n': 103}, local: true),
        ],
        fromCache: false,
        hasPendingWrites: true,
      ),
    ],
  },
];

final Map<String, Object?> docA2000 = doc(
  'collection/a',
  2000,
  <String, Object?>{'n': 103},
);

/// The sequence of the browser test: a and b are set and synced, a is incremented and the increment acknowledged
/// (held back: the view keeps the local version, with pending writes), b is deleted, and only then watch sends a.
List<Map<String, Object?>> watchBehind({required bool metadataChanges}) {
  final Map<String, Object?> docA1500 = doc(
    'collection/a',
    1500,
    <String, Object?>{'n': 3},
  );
  final Map<String, Object?> docB1600 = doc(
    'collection/b',
    1600,
    <String, Object?>{'n': 4},
  );
  return <Map<String, Object?>>[
    ...listen(metadataChanges: metadataChanges),
    <String, Object?>{
      'userSet': <Object?>[
        'collection/a',
        <String, Object?>{'n': 3},
      ],
      'expectedSnapshotEvents': <Object?>[
        event(
          added: <Object?>[
            doc('collection/a', 0, <String, Object?>{'n': 3}, local: true),
          ],
          fromCache: false,
          hasPendingWrites: true,
        ),
      ],
    },
    writeAck('collection/a', 1500),
    watchSends(<Object?>[docA1500]),
    watchSnapshot(
      1500,
      events: <Object?>[
        if (metadataChanges)
          event(metadata: <Object?>[docA1500], fromCache: false),
      ],
    ),
    <String, Object?>{
      'userSet': <Object?>[
        'collection/b',
        <String, Object?>{'n': 4},
      ],
      'expectedSnapshotEvents': <Object?>[
        event(
          added: <Object?>[
            doc('collection/b', 0, <String, Object?>{'n': 4}, local: true),
          ],
          fromCache: false,
          hasPendingWrites: true,
        ),
      ],
    },
    writeAck('collection/b', 1600),
    watchSends(<Object?>[docB1600]),
    watchSnapshot(
      1600,
      events: <Object?>[
        if (metadataChanges)
          event(metadata: <Object?>[docB1600], fromCache: false),
      ],
    ),
    <String, Object?>{
      'userPatch': <Object?>[
        'collection/a',
        <String, Object?>{'n': increment100},
      ],
      'expectedSnapshotEvents': <Object?>[
        event(
          modified: <Object?>[
            doc('collection/a', 0, <String, Object?>{'n': 103}, local: true),
          ],
          fromCache: false,
          hasPendingWrites: true,
        ),
      ],
    },
    // The acknowledgement of the increment: the view holds a back until watch sends it, no event.
    writeAck(
      'collection/a',
      2000,
      transformResults: <Object?>[
        <String, Object?>{'integerValue': '103'},
      ],
    ),
    // The last event of the default listener: a still has pending writes.
    <String, Object?>{
      'userDelete': 'collection/b',
      'expectedSnapshotEvents': <Object?>[
        event(
          removed: <Object?>[docB1600],
          fromCache: false,
          hasPendingWrites: true,
        ),
      ],
    },
    writeAck('collection/b', 2100),
    // Watch catches up. The view drops the pending writes of a, a metadata change only.
    watchSends(<Object?>[docA2000]),
    <String, Object?>{
      'watchEntity': <String, Object?>{
        'key': 'collection/b',
        'removedTargets': <Object?>[2],
      },
    },
    watchSnapshot(
      2100,
      events: <Object?>[
        if (metadataChanges)
          event(metadata: <Object?>[docA2000], fromCache: false),
      ],
    ),
  ];
}

void main() {
  final Map<String, MemoryLogStore> stores = <String, MemoryLogStore>{};
  final Map<String, Future<Persistence> Function(String name)>
  variants = <String, Future<Persistence> Function(String name)>{
    'memory': (_) async => createLRUMemoryPersistence(),
    'sqlite': (String name) => createSQLitePersistenceForProject(
      'test-project',
      'firebase/firestore/spec/held_back_listener_spec_test_${Uri.encodeQueryComponent(name)}',
    ),
    'keyvalue': (String name) => createKeyValuePersistence(
      store: stores.putIfAbsent(name, MemoryLogStore.new),
      projectId: 'test-project',
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
      test('watch sends the incremented document before its acknowledgement '
          '(and never the set before it)', () async {
        await run('ahead_skips', <Map<String, Object?>>[
          ...setThenIncrement(),
          watchSends(<Object?>[docA2000]),
          // The local view does not change (the overlay holds n: 103).
          watchSnapshot(2000),
          writeAck(
            'collection/a',
            2000,
            transformResults: <Object?>[
              <String, Object?>{'integerValue': '103'},
            ],
            events: <Object?>[
              event(metadata: <Object?>[docA2000], fromCache: false),
            ],
          ),
        ]);
      });

      test('watch sends the set and then the incremented document before the '
          'acknowledgement of the increment', () async {
        await run('ahead_both', <Map<String, Object?>>[
          ...setThenIncrement(),
          watchSends(<Object?>[
            doc('collection/a', 1500, <String, Object?>{'n': 3}),
          ]),
          watchSnapshot(1500),
          watchSends(<Object?>[docA2000]),
          watchSnapshot(2000),
          writeAck(
            'collection/a',
            2000,
            transformResults: <Object?>[
              <String, Object?>{'integerValue': '103'},
            ],
            events: <Object?>[
              event(metadata: <Object?>[docA2000], fromCache: false),
            ],
          ),
        ]);
      });

      test('watch behind: a listener with metadata changes gets the end of the '
          'pending writes of a held back document', () async {
        await run('behind_metadata', watchBehind(metadataChanges: true));
      });

      test('watch behind: a listener without metadata changes keeps '
          'hasPendingWrites in its last snapshot', () async {
        await run('behind_default', watchBehind(metadataChanges: false));
      });
    });
  }
}
