// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// A multi-client spec that the JS SDK does not have (it shares the gap): a document whose acknowledged write a
// secondary client holds back (waiting for watch to send it), and that watch takes out of the target while that client
// is secondary, must not stay in the view with pending writes once that client becomes primary
// (notes/reviews/final_review_today.md, finding 4).

import 'dart:convert';

import 'package:test/test.dart';

import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

const Map<String, dynamic> _query = <String, dynamic>{
  'path': 'collection',
  'filters': <dynamic>[],
  'orderBys': <dynamic>[],
};

const Map<String, dynamic> _docA = <String, dynamic>{
  'key': 'collection/a',
  'version': 0,
  'value': <String, dynamic>{'v': 1},
  'options': <String, dynamic>{
    'hasLocalMutations': true,
    'hasCommittedMutations': false,
  },
};

Map<String, dynamic> _event({
  List<dynamic> added = const <dynamic>[],
  List<dynamic> removed = const <dynamic>[],
  required bool fromCache,
  required bool hasPendingWrites,
}) => <String, dynamic>{
  'query': _query,
  'added': added,
  'removed': removed,
  'fromCache': fromCache,
  'hasPendingWrites': hasPendingWrites,
  'errorCode': 0,
};

const Map<String, dynamic> _limboTargetA = <String, dynamic>{
  'queries': <dynamic>[
    <String, dynamic>{
      'path': 'collection/a',
      'filters': <dynamic>[],
      'orderBys': <dynamic>[],
    },
  ],
  'targetPurpose': 'TargetPurposeLimboResolution',
  'resumeToken': '',
};

Map<String, dynamic> _target(String resumeToken) => <String, dynamic>{
  'queries': <dynamic>[_query],
  'resumeToken': resumeToken,
};

Future<void> _run(String name, List<Map<String, dynamic>> steps) {
  final SpecTestCase testCase = SpecTestCase(
    (_, String persistenceName) => createSQLitePersistenceForProject(
      'test-project',
      'firebase/firestore/spec/held_back_${Uri.encodeQueryComponent(persistenceName)}',
    ),
    getSharedPersistence:
        (
          String persistenceName,
          String clientId,
          int Function() clock,
        ) => createSharedSQLitePersistenceForProject(
          'test-project',
          'firebase/firestore/spec/held_back_${Uri.encodeQueryComponent(persistenceName)}',
          clientId,
          clock,
        ),
  )..currentName = name;
  return testCase.runSteps(
    jsonDecode(jsonEncode(steps)) as List<dynamic>,
    <String, dynamic>{'numClients': 2, 'useEagerGCForMemory': false},
  );
}

void main() {
  test('A held-back document that watch removed while the client was secondary is resolved after it becomes '
      'primary', () async {
    await _run('held_back_failover', <Map<String, dynamic>>[
      <String, dynamic>{
        'clientIndex': 0,
        'drainQueue': true,
        'expectedState': <String, dynamic>{'isPrimary': true},
      },
      <String, dynamic>{
        'clientIndex': 1,
        'drainQueue': true,
        'expectedState': <String, dynamic>{'isPrimary': false},
      },
      // The secondary listens; the primary listens to the target for it, and the target becomes current.
      <String, dynamic>{
        'clientIndex': 1,
        'userListen': <String, dynamic>{'targetId': 2, 'query': _query},
      },
      <String, dynamic>{
        'clientIndex': 0,
        'drainQueue': true,
        'expectedState': <String, dynamic>{
          'activeTargets': <String, dynamic>{'2': _target('')},
        },
      },
      <String, dynamic>{
        'clientIndex': 0,
        'watchAck': <dynamic>[2],
      },
      <String, dynamic>{
        'clientIndex': 0,
        'watchCurrent': <dynamic>[
          <dynamic>[2],
          'resume-token-500',
        ],
      },
      <String, dynamic>{
        'clientIndex': 0,
        'watchSnapshot': <String, dynamic>{
          'targetIds': <dynamic>[],
          'version': 500,
        },
      },
      <String, dynamic>{
        'clientIndex': 1,
        'drainQueue': true,
        'expectedSnapshotEvents': <dynamic>[
          _event(fromCache: false, hasPendingWrites: false),
        ],
      },
      // The secondary writes; the primary sends the write and the backend acknowledges it. The secondary holds the
      // change back until watch sends the document.
      <String, dynamic>{
        'clientIndex': 1,
        'userSet': <dynamic>[
          'collection/a',
          <String, dynamic>{'v': 1},
        ],
        'expectedSnapshotEvents': <dynamic>[
          _event(
            added: <dynamic>[_docA],
            fromCache: false,
            hasPendingWrites: true,
          ),
        ],
      },
      <String, dynamic>{'clientIndex': 0, 'drainQueue': true},
      <String, dynamic>{
        'clientIndex': 0,
        'writeAck': <String, dynamic>{'version': 1000},
      },
      <String, dynamic>{
        'clientIndex': 1,
        'drainQueue': true,
        'expectedState': <String, dynamic>{
          'userCallbacks': <String, dynamic>{
            'acknowledgedDocs': <dynamic>['collection/a'],
            'rejectedDocs': <dynamic>[],
          },
        },
      },
      // Watch takes the document out of the target without sending it (it was deleted on the backend meanwhile).
      <String, dynamic>{
        'clientIndex': 0,
        'watchEntity': <String, dynamic>{
          'key': 'collection/a',
          'removedTargets': <dynamic>[2],
        },
      },
      <String, dynamic>{
        'clientIndex': 0,
        'watchSnapshot': <String, dynamic>{
          'targetIds': <dynamic>[],
          'version': 2000,
        },
        // The primary holds the document back too: it puts it in limbo (as a single client does).
        'expectedState': <String, dynamic>{
          'activeLimboDocs': <dynamic>['collection/a'],
          'activeTargets': <String, dynamic>{
            '1': _limboTargetA,
            '2': _target(''),
          },
        },
      },
      // The target of the primary is no longer current (it waits for the limbo resolution): so is the view of the
      // secondary.
      <String, dynamic>{
        'clientIndex': 1,
        'drainQueue': true,
        'expectedSnapshotEvents': <dynamic>[
          _event(fromCache: true, hasPendingWrites: true),
        ],
      },
      // The secondary takes over before the primary resolved the limbo document. It listens to the target again; once
      // watch shows the target current without the document, the held-back document is in limbo, and its
      // resolution removes it.
      <String, dynamic>{
        'clientIndex': 1,
        'applyClientState': <String, dynamic>{'primary': true},
        'expectedState': <String, dynamic>{
          'isPrimary': true,
          'activeTargets': <String, dynamic>{'2': _target('resume-token-500')},
        },
      },
      <String, dynamic>{
        'clientIndex': 1,
        'watchAck': <dynamic>[2],
      },
      <String, dynamic>{
        'clientIndex': 1,
        'watchCurrent': <dynamic>[
          <dynamic>[2],
          'resume-token-3000',
        ],
      },
      <String, dynamic>{
        'clientIndex': 1,
        'watchSnapshot': <String, dynamic>{
          'targetIds': <dynamic>[],
          'version': 3000,
        },
        'expectedState': <String, dynamic>{
          'activeLimboDocs': <dynamic>['collection/a'],
          'activeTargets': <String, dynamic>{
            '1': _limboTargetA,
            '2': _target('resume-token-500'),
          },
        },
      },
      <String, dynamic>{
        'clientIndex': 1,
        'watchAck': <dynamic>[1],
      },
      <String, dynamic>{
        'clientIndex': 1,
        'watchCurrent': <dynamic>[
          <dynamic>[1],
          'resume-token-4000',
        ],
      },
      <String, dynamic>{
        'clientIndex': 1,
        'watchSnapshot': <String, dynamic>{
          'targetIds': <dynamic>[],
          'version': 4000,
        },
        'expectedSnapshotEvents': <dynamic>[
          _event(
            removed: <dynamic>[_docA],
            fromCache: false,
            hasPendingWrites: false,
          ),
        ],
        'expectedState': <String, dynamic>{
          'activeLimboDocs': <dynamic>[],
          'activeTargets': <String, dynamic>{'2': _target('resume-token-500')},
        },
      },
    ]);
  });
}
