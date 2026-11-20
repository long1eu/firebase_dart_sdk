import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../local/persistence_test_helpers.dart';
import 'spec_test_case.dart';

/// The two specs of index_spec_test.json are multi-client: the same index configuration is checked on a second
/// client. The port has one client per database, so the spec runner skips them. This runs the steps of both clients
/// on one client (the `setIndexConfiguration` step and the `expectedState.indexes` checks; the primary state is
/// dropped), with SQLite persistence (memory persistence has no field indexes).
Map<String, dynamic> _singleClient(Map<String, dynamic> spec) {
  final List<dynamic> steps = <dynamic>[];
  for (final dynamic stepObject in spec['steps'] as List<dynamic>) {
    final Map<String, dynamic> step = Map<String, dynamic>.of(
      stepObject as Map<String, dynamic>,
    );
    step.remove('clientIndex');
    final Map<String, dynamic>? expectedState = step['expectedState'];
    if (expectedState != null) {
      step['expectedState'] = Map<String, dynamic>.of(expectedState)
        ..remove('isPrimary');
    }
    steps.add(step);
  }
  return <String, dynamic>{
    'steps': steps,
    'config': <String, dynamic>{
      ...spec['config'] as Map<String, dynamic>,
      'numClients': 1,
    },
  };
}

Future<void> _run(
  String name,
  Map<String, dynamic> spec, {
  bool keyValue = false,
}) {
  final Map<String, MemoryLogStore> stores = <String, MemoryLogStore>{};
  final SpecTestCase testCase = SpecTestCase(
    (_, String persistenceName) => keyValue
        ? createKeyValuePersistence(
            store: stores.putIfAbsent(persistenceName, MemoryLogStore.new),
            projectId: 'test-project',
          )
        : createSQLitePersistenceForProject(
            'test-project',
            'firebase/firestore/spec/index_spec_single_client_test_${Uri.encodeQueryComponent(persistenceName)}',
          ),
  )..currentName = name;
  return testCase.runSteps(
    spec['steps'] as List<dynamic>,
    spec['config'] as Map<String, dynamic>,
  );
}

void main() {
  for (final bool keyValue in <bool>[false, true]) {
    _define(keyValue);
  }
}

void _define(bool keyValue) {
  final String suffix = keyValue ? ', key-value' : '';
  final Map<String, dynamic> specs =
      jsonDecode(File('test/res/json/index_spec_test.json').readAsStringSync())
          as Map<String, dynamic>;

  int index = 0;
  for (final MapEntry<String, dynamic> entry in specs.entries) {
    final int id = index++;
    test('${entry.key} (on one client$suffix)', () async {
      final Map<String, dynamic> spec = _singleClient(
        jsonDecode(jsonEncode(entry.value)) as Map<String, dynamic>,
      );
      // The index is configured in at least one step and checked.
      final List<dynamic> steps = spec['steps'] as List<dynamic>;
      expect(
        steps.where(
          (dynamic s) =>
              (s as Map<String, dynamic>).containsKey('setIndexConfiguration'),
        ),
        isNotEmpty,
      );
      expect(
        steps.where(
          (dynamic s) =>
              ((s as Map<String, dynamic>)['expectedState']
                      as Map<String, dynamic>?)
                  ?.containsKey('indexes') ==
              true,
        ),
        isNotEmpty,
      );
      await _run('index_single_$id', spec, keyValue: keyValue);
    });
  }

  test(
    'expectedState.indexes fails for an index that is not configured$suffix',
    () async {
      final Map<String, dynamic> spec = <String, dynamic>{
        'config': <String, dynamic>{
          'numClients': 1,
          'useEagerGCForMemory': false,
        },
        'steps': <dynamic>[
          <String, dynamic>{
            'setIndexConfiguration': <String, dynamic>{
              'indexes': <dynamic>[
                <String, dynamic>{
                  'collectionGroup': 'restaurants',
                  'fields': <dynamic>[
                    <String, dynamic>{
                      'fieldPath': 'price',
                      'order': 'ASCENDING',
                    },
                  ],
                },
              ],
            },
            'expectedState': <String, dynamic>{
              'indexes': <dynamic>[
                <String, dynamic>{
                  'collectionGroup': 'restaurants',
                  'fields': <dynamic>[
                    <String, dynamic>{
                      'fieldPath': <String, dynamic>{
                        'segments': <dynamic>['price'],
                      },
                      // Descending: not what was configured.
                      'kind': 1,
                    },
                  ],
                },
              ],
            },
          },
        ],
      };
      await expectLater(
        _run('index_single_mismatch', spec, keyValue: keyValue),
        throwsA(isA<TestFailure>()),
      );
    },
  );
}
