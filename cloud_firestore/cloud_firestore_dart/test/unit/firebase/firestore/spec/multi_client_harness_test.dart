import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

/// Tests of the multi-client part of the spec harness itself: steps are dispatched by `clientIndex` to clients that
/// share one persistence (one SQLite file, or one memory persistence instance) and one write tracker.
///
/// The library has no primary lease and no SharedClientState yet, so every client behaves as a primary with its own
/// network; these tests only use what does not depend on that. The upstream multi-client specs stay skipped (see
/// spec_skip_list.dart).

Future<Persistence> _sqlite(String name) => createSQLitePersistenceForProject(
  'test-project',
  'firebase/firestore/spec/multi_client_harness_test_${Uri.encodeQueryComponent(name)}',
);

Future<void> _run(
  String name,
  List<Map<String, dynamic>> steps, {
  bool sqlite = true,
  int numClients = 2,
}) {
  final SpecTestCase testCase = SpecTestCase(
    (_, String persistenceName) =>
        sqlite ? _sqlite(persistenceName) : createLRUMemoryPersistence(),
  )..currentName = name;
  return testCase.runSteps(
    jsonDecode(jsonEncode(steps)) as List<dynamic>,
    <String, dynamic>{'numClients': numClients, 'useEagerGCForMemory': false},
  );
}

const Map<String, dynamic> _query = <String, dynamic>{
  'path': 'collection',
  'filters': <dynamic>[],
  'orderBys': <dynamic>[],
};

/// Client 0 writes, client 1 (started afterwards on the same persistence) sees the pending write in its view, client
/// 0 gets the acknowledgement, client 1 is shut down and client 0 keeps running.
List<Map<String, dynamic>> _sharedPersistenceSteps() => <Map<String, dynamic>>[
  <String, dynamic>{
    'clientIndex': 0,
    'userSet': <dynamic>[
      'collection/a',
      <String, dynamic>{'v': 1},
    ],
    'expectedState': <String, dynamic>{'numOutstandingWrites': 1},
  },
  <String, dynamic>{
    'clientIndex': 1,
    'userListen': <String, dynamic>{'targetId': 2, 'query': _query},
    'expectedSnapshotEvents': <dynamic>[
      <String, dynamic>{
        'query': _query,
        'added': <dynamic>[
          <String, dynamic>{
            'key': 'collection/a',
            'version': 0,
            'value': <String, dynamic>{'v': 1},
            'options': <String, dynamic>{
              'hasLocalMutations': true,
              'hasCommittedMutations': false,
            },
          },
        ],
        'fromCache': true,
        'hasPendingWrites': true,
        'errorCode': 0,
      },
    ],
    'expectedState': <String, dynamic>{
      'activeTargets': <String, dynamic>{
        '2': <String, dynamic>{
          'queries': <dynamic>[_query],
          'resumeToken': '',
        },
      },
    },
  },
  <String, dynamic>{
    'clientIndex': 0,
    'writeAck': <String, dynamic>{'version': 1000},
    'expectedState': <String, dynamic>{
      'userCallbacks': <String, dynamic>{
        'acknowledgedDocs': <dynamic>['collection/a'],
        'rejectedDocs': <dynamic>[],
      },
    },
  },
  <String, dynamic>{
    'clientIndex': 1,
    'shutdown': true,
    'expectedState': <String, dynamic>{'isShutdown': true},
  },
  <String, dynamic>{
    'clientIndex': 0,
    'drainQueue': true,
    'expectedState': <String, dynamic>{'isShutdown': false},
  },
];

void main() {
  test(
    'clients share the SQLite database file and the write tracker',
    () async {
      await _run('shared_sqlite', _sharedPersistenceSteps());
    },
  );

  test('clients share the memory persistence and the write tracker', () async {
    await _run('shared_memory', _sharedPersistenceSteps(), sqlite: false);
  });

  test('a client is created when a step first addresses it', () async {
    // Client 2 is addressed without clients 1 ever being used.
    await _run('lazy_clients', <Map<String, dynamic>>[
      <String, dynamic>{'clientIndex': 2, 'drainQueue': true},
      <String, dynamic>{'clientIndex': 0, 'drainQueue': true},
    ], numClients: 3);
  });

  test(
    'a step that needs the primary lease fails with UnsupportedSpecFeature',
    () async {
      await expectLater(
        _run('is_primary', <Map<String, dynamic>>[
          <String, dynamic>{
            'clientIndex': 0,
            'drainQueue': true,
            'expectedState': <String, dynamic>{'isPrimary': true},
          },
        ]),
        throwsA(isA<UnsupportedSpecFeature>()),
      );
      await expectLater(
        _run('apply_client_state', <Map<String, dynamic>>[
          <String, dynamic>{
            'clientIndex': 1,
            'applyClientState': <String, dynamic>{'primary': true},
          },
        ]),
        throwsA(isA<UnsupportedSpecFeature>()),
      );
    },
  );

  // The two index specs only need a second client on the same database (and the primary state, which is dropped
  // here): the index configuration written by one client is read by the other.
  final Map<String, dynamic> indexSpecs =
      jsonDecode(File('test/res/json/index_spec_test.json').readAsStringSync())
          as Map<String, dynamic>;
  int index = 0;
  for (final MapEntry<String, dynamic> entry in indexSpecs.entries) {
    final int id = index++;
    test('${entry.key} (two clients, without the primary state)', () async {
      final Map<String, dynamic> spec = entry.value as Map<String, dynamic>;
      final List<Map<String, dynamic>> steps = <Map<String, dynamic>>[
        for (final dynamic stepObject in spec['steps'] as List<dynamic>)
          <String, dynamic>{
            ...stepObject as Map<String, dynamic>,
            if (stepObject['expectedState'] != null)
              'expectedState': Map<String, dynamic>.of(
                stepObject['expectedState'] as Map<String, dynamic>,
              )..remove('isPrimary'),
          },
      ];
      await _run('index_$id', steps);
    });
  }
}
