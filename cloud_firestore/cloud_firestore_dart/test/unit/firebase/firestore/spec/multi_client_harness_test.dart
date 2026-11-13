import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

/// Tests of the multi-client part of the spec harness itself: steps are dispatched by `clientIndex` to clients that
/// share one SQLite database, one shared client state and one write tracker. Client 0 is the primary client.
///
/// Multi-client runs need SQLite persistence: like the JS SDK, the memory persistence does not support them.

Future<Persistence> _sqlite(String name) => createSQLitePersistenceForProject(
  'test-project',
  'firebase/firestore/spec/multi_client_harness_test_${Uri.encodeQueryComponent(name)}',
);

Future<void> _run(
  String name,
  List<Map<String, dynamic>> steps, {
  int numClients = 2,
}) {
  final SpecTestCase testCase = SpecTestCase(
    (_, String persistenceName) => _sqlite(persistenceName),
    getSharedPersistence:
        (
          String persistenceName,
          String clientId,
          int Function() clock,
        ) => createSharedSQLitePersistenceForProject(
          'test-project',
          'firebase/firestore/spec/multi_client_harness_test_${Uri.encodeQueryComponent(persistenceName)}',
          clientId,
          clock,
        ),
  )..currentName = name;
  return testCase.runSteps(
    jsonDecode(jsonEncode(steps)) as List<dynamic>,
    <String, dynamic>{'numClients': numClients, 'useEagerGCForMemory': false},
  );
}

Map<String, dynamic> _acknowledged(String key) => <String, dynamic>{
  'userCallbacks': <String, dynamic>{
    'acknowledgedDocs': <dynamic>[key],
    'rejectedDocs': <dynamic>[],
  },
};

/// Both clients write; the primary client sends both writes and the backend acknowledges them in order (the shared
/// write tracker checks the order); each client gets the acknowledgement of its own write. Then client 1 is shut down
/// and client 0 keeps running.
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
    'userSet': <dynamic>[
      'collection/b',
      <String, dynamic>{'v': 1},
    ],
    // A secondary client does not send writes.
    'expectedState': <String, dynamic>{'numOutstandingWrites': 0},
  },
  <String, dynamic>{
    'clientIndex': 0,
    'drainQueue': true,
    'expectedState': <String, dynamic>{'numOutstandingWrites': 2},
  },
  <String, dynamic>{
    'clientIndex': 0,
    'writeAck': <String, dynamic>{'version': 1000},
    'expectedState': _acknowledged('collection/a'),
  },
  <String, dynamic>{
    'clientIndex': 0,
    'writeAck': <String, dynamic>{'version': 2000},
  },
  <String, dynamic>{
    'clientIndex': 1,
    'drainQueue': true,
    'expectedState': _acknowledged('collection/b'),
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
    'clients share the database, the client state and the write tracker',
    () async {
      await _run('shared_sqlite', _sharedPersistenceSteps());
    },
  );

  test('a client is created when a step first addresses it', () async {
    // Client 2 is addressed without clients 1 ever being used.
    await _run('lazy_clients', <Map<String, dynamic>>[
      <String, dynamic>{'clientIndex': 2, 'drainQueue': true},
      <String, dynamic>{'clientIndex': 0, 'drainQueue': true},
    ], numClients: 3);
  });

  test('the clients elect a primary client with the lease', () async {
    await _run('lease', <Map<String, dynamic>>[
      <String, dynamic>{
        'clientIndex': 0,
        'drainQueue': true,
        'expectedState': <String, dynamic>{'isPrimary': true},
      },
      <String, dynamic>{
        'clientIndex': 1,
        'drainQueue': true,
        'expectedState': <String, dynamic>{
          'isPrimary': false,
          'numActiveClients': 2,
        },
      },
      <String, dynamic>{
        'clientIndex': 1,
        'applyClientState': <String, dynamic>{'primary': true},
        'expectedState': <String, dynamic>{'isPrimary': true},
      },
      // The previous primary notices at its next refresh (as in the JS SDK).
      <String, dynamic>{
        'clientIndex': 0,
        'drainQueue': true,
        'expectedState': <String, dynamic>{'isPrimary': true},
      },
      <String, dynamic>{
        'clientIndex': 0,
        'runTimer': 'client_metadata_refresh',
        'expectedState': <String, dynamic>{'isPrimary': false},
      },
      <String, dynamic>{
        'clientIndex': 1,
        'shutdown': true,
        'expectedState': <String, dynamic>{'isShutdown': true},
      },
      <String, dynamic>{
        'clientIndex': 0,
        'runTimer': 'client_metadata_refresh',
        'expectedState': <String, dynamic>{
          'isPrimary': true,
          'numActiveClients': 1,
        },
      },
    ]);
  });

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
