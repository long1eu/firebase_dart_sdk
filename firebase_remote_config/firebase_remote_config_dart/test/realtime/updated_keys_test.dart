import 'dart:convert';

import 'package:firebase_remote_config_dart/src/realtime/updated_keys.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:test/test.dart';

/// A record read the way stored and fetched records are read, failing the test if any item is dropped
/// (a dropped item on both sides would hide a difference).
TemplateRecord _record({
  Map<String, String> entries = const <String, String>{},
  List<Map<String, Object?>> experiments = const <Map<String, Object?>>[],
  List<Map<String, Object?>> rollouts = const <Map<String, Object?>>[],
  Map<String, Map<String, Object?>> personalization =
      const <String, Map<String, Object?>>{},
  int templateVersion = 1,
}) {
  final String text = jsonEncode(<String, Object?>{
    'v': 1,
    'entries': entries,
    'templateVersion': templateVersion,
    'experimentDescriptions': experiments,
    'rolloutMetadata': rollouts,
    'personalizationMetadata': personalization,
    'fetchTime': 0,
  });
  final TemplateRecord? record = TemplateRecord.tryParse(
    text,
    onDrop: (String field) => fail('fixture dropped $field'),
  );
  expect(record, isNotNull, reason: 'fixture record must parse');
  return record!;
}

Map<String, Object?> _experiment(
  String id, {
  String variant = '1',
  List<String>? keys,
  Object? ttl,
  Object? trigger,
  String? startTime,
}) => <String, Object?>{
  'experimentId': id,
  'variantId': variant,
  'affectedParameterKeys': ?keys,
  'timeToLiveMillis': ?ttl,
  'triggerTimeoutMillis': ?trigger,
  'experimentStartTime': ?startTime,
};

Map<String, Object?> _rollout(
  String id, {
  String variant = 'v1',
  List<String>? keys,
}) => <String, Object?>{
  'rolloutId': id,
  'variantId': variant,
  'affectedParameterKeys': ?keys,
};

const Map<String, String> _base = <String, String>{
  'a': '1',
  'b': 'two',
  'c': 'true',
};

void main() {
  group('5.9.4 updatedKeys: values', () {
    test('5.9.4 identical records give no keys', () {
      expect(
        updatedKeys(_record(entries: _base), _record(entries: _base)),
        isEmpty,
      );
    });

    test('5.9.4 two missing records give no keys', () {
      expect(updatedKeys(null, null), isEmpty);
    });

    test('5.9.4 no active record: every fetched key is updated', () {
      expect(updatedKeys(null, _record(entries: _base)), <String>{
        'a',
        'b',
        'c',
      });
    });

    test('5.9.4 no fetched record: every active key is updated', () {
      expect(updatedKeys(_record(entries: _base), null), <String>{
        'a',
        'b',
        'c',
      });
    });

    test('5.9.4 a changed value marks only that key', () {
      final TemplateRecord fetched = _record(
        entries: <String, String>{..._base, 'b': 'three'},
      );

      expect(updatedKeys(_record(entries: _base), fetched), <String>{'b'});
    });

    test('5.9.4 a key in only one record is updated (added and removed)', () {
      final TemplateRecord active = _record(
        entries: <String, String>{'a': '1', 'gone': 'x'},
      );
      final TemplateRecord fetched = _record(
        entries: <String, String>{'a': '1', 'new': 'y'},
      );

      expect(updatedKeys(active, fetched), <String>{'gone', 'new'});
    });

    test('5.9.4 an empty value differs from a missing key', () {
      expect(
        updatedKeys(
          _record(entries: <String, String>{'a': '1'}),
          _record(entries: <String, String>{'a': '1', 'e': ''}),
        ),
        <String>{'e'},
      );
    });

    test('5.9.4 values compare exactly (case and whitespace)', () {
      expect(
        updatedKeys(
          _record(entries: <String, String>{'x': 'true', 'y': '1'}),
          _record(entries: <String, String>{'x': 'TRUE', 'y': '1 '}),
        ),
        <String>{'x', 'y'},
      );
    });

    test('5.9.4 key order of the entries never matters', () {
      final TemplateRecord active = _record(
        entries: <String, String>{'a': '1', 'b': '2', 'c': '3'},
      );
      final TemplateRecord fetched = _record(
        entries: <String, String>{'c': '3', 'a': '1', 'b': '2'},
      );

      expect(updatedKeys(active, fetched), isEmpty);
    });

    test('5.9.4 a new template version alone marks no key', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(entries: _base, templateVersion: 9),
        ),
        isEmpty,
      );
    });

    test('5.9.4 the result is the union over both records', () {
      final TemplateRecord active = _record(
        entries: <String, String>{'only_active': '1', 'same': 's', 'diff': 'a'},
      );
      final TemplateRecord fetched = _record(
        entries: <String, String>{
          'only_fetched': '1',
          'same': 's',
          'diff': 'b',
        },
      );

      expect(updatedKeys(active, fetched), <String>{
        'only_active',
        'only_fetched',
        'diff',
      });
    });
  });

  group('5.9.4 updatedKeys: personalization', () {
    const Map<String, Object?> entry = <String, Object?>{
      'personalizationId': 'p1',
      'group': 'P13N',
      'choiceId': 'c1',
      'armIndex': 0,
    };

    test('5.9.4 a personalization entry added to a key marks it', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(
            entries: _base,
            personalization: <String, Map<String, Object?>>{'a': entry},
          ),
        ),
        <String>{'a'},
      );
    });

    test('5.9.4 a personalization entry removed from a key marks it', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            personalization: <String, Map<String, Object?>>{'b': entry},
          ),
          _record(entries: _base),
        ),
        <String>{'b'},
      );
    });

    for (final MapEntry<String, Object?> change in <MapEntry<String, Object?>>[
      const MapEntry<String, Object?>('personalizationId', 'p2'),
      const MapEntry<String, Object?>('group', 'BASELINE'),
      const MapEntry<String, Object?>('choiceId', 'c2'),
      const MapEntry<String, Object?>('armIndex', 3),
    ]) {
      test('5.9.4 a changed personalization ${change.key} marks the key', () {
        expect(
          updatedKeys(
            _record(
              entries: _base,
              personalization: <String, Map<String, Object?>>{'a': entry},
            ),
            _record(
              entries: _base,
              personalization: <String, Map<String, Object?>>{
                'a': <String, Object?>{...entry, change.key: change.value},
              },
            ),
          ),
          <String>{'a'},
        );
      });
    }

    test('5.9.4 the same personalization entry in another field order marks '
        'nothing', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            personalization: <String, Map<String, Object?>>{'a': entry},
          ),
          _record(
            entries: _base,
            personalization: <String, Map<String, Object?>>{
              'a': <String, Object?>{
                'armIndex': 0,
                'choiceId': 'c1',
                'group': 'P13N',
                'personalizationId': 'p1',
              },
            },
          ),
        ),
        isEmpty,
      );
    });

    test('5.9.4 a personalization key with no value is still in the union', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(
            entries: _base,
            personalization: <String, Map<String, Object?>>{'ghost': entry},
          ),
        ),
        <String>{'ghost'},
      );
    });
  });

  group('5.9.4 updatedKeys: rollouts', () {
    test('5.9.4 a rollout variant change marks only its affected keys', () {
      final TemplateRecord active = _record(
        entries: _base,
        rollouts: <Map<String, Object?>>[
          _rollout('r1', keys: <String>['a', 'b']),
        ],
      );
      final TemplateRecord fetched = _record(
        entries: _base,
        rollouts: <Map<String, Object?>>[
          _rollout('r1', variant: 'v2', keys: <String>['a', 'b']),
        ],
      );

      expect(updatedKeys(active, fetched), <String>{'a', 'b'});
    });

    test('5.9.4 a rollout added to a key marks it', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['c']),
            ],
          ),
        ),
        <String>{'c'},
      );
    });

    test('5.9.4 a rollout removed from a key marks it', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['a']),
              _rollout('r2', keys: <String>['b']),
            ],
          ),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['a']),
            ],
          ),
        ),
        <String>{'b'},
      );
    });

    test('5.9.4 a key added to a rollout\'s affectedParameterKeys marks only '
        'that key', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['a']),
            ],
          ),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['a', 'b']),
            ],
          ),
        ),
        <String>{'b'},
      );
    });

    test('5.9.4 the rollout id counts, not only the variant', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['a']),
            ],
          ),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r9', keys: <String>['a']),
            ],
          ),
        ),
        <String>{'a'},
      );
    });

    test('5.9.4 rollout and affectedParameterKeys order never matter', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['a', 'b']),
              _rollout('r2', variant: 'v7', keys: <String>['b', 'c']),
            ],
          ),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r2', variant: 'v7', keys: <String>['c', 'b']),
              _rollout('r1', keys: <String>['b', 'a']),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('5.9.4 a rollout without affectedParameterKeys marks nothing', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[_rollout('r1')],
          ),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[_rollout('r1', variant: 'v2')],
          ),
        ),
        isEmpty,
      );
    });

    test('5.9.4 a rollout key with no value is still in the union', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(
            entries: _base,
            rollouts: <Map<String, Object?>>[
              _rollout('r1', keys: <String>['ghost']),
            ],
          ),
        ),
        <String>{'ghost'},
      );
    });
  });

  group('5.9.4 updatedKeys: experiments', () {
    Map<String, Object?> exp1({
      String variant = '1',
      Object? ttl = '15552000000',
      Object? trigger = '15552000000',
      String? startTime = '2026-01-01T00:00:00Z',
      List<String> keys = const <String>['a', 'b'],
    }) => _experiment(
      'exp_1',
      variant: variant,
      keys: keys,
      ttl: ttl,
      trigger: trigger,
      startTime: startTime,
    );

    Set<String> diff(Map<String, Object?> before, Map<String, Object?> after) =>
        updatedKeys(
          _record(entries: _base, experiments: <Map<String, Object?>>[before]),
          _record(entries: _base, experiments: <Map<String, Object?>>[after]),
        );

    test('5.9.4 the same experiment marks nothing', () {
      expect(diff(exp1(), exp1()), isEmpty);
    });

    test('5.9.4 a changed variantId marks the affected keys', () {
      expect(diff(exp1(), exp1(variant: '2')), <String>{'a', 'b'});
    });

    test('5.9.4 a changed experimentId marks the affected keys', () {
      expect(
        diff(
          exp1(),
          _experiment(
            'exp_2',
            keys: <String>['a', 'b'],
            ttl: '15552000000',
            trigger: '15552000000',
            startTime: '2026-01-01T00:00:00Z',
          ),
        ),
        <String>{'a', 'b'},
      );
    });

    test('5.9.4 a changed timeToLiveMillis marks the affected keys', () {
      expect(diff(exp1(), exp1(ttl: '1000')), <String>{'a', 'b'});
    });

    test('5.9.4 a changed triggerTimeoutMillis marks the affected keys', () {
      expect(diff(exp1(), exp1(trigger: '1000')), <String>{'a', 'b'});
    });

    test('5.9.4 a timeToLiveMillis that appears marks the affected keys', () {
      expect(diff(exp1(ttl: null), exp1()), <String>{'a', 'b'});
    });

    test('5.9.4 a changed experimentStartTime is not compared', () {
      expect(diff(exp1(), exp1(startTime: '2026-06-01T00:00:00Z')), isEmpty);
    });

    test('5.9.4 an experiment added to a key marks it', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('exp_1', keys: <String>['c']),
            ],
          ),
        ),
        <String>{'c'},
      );
    });

    test('5.9.4 an experiment removed from a key marks it', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('exp_1', keys: <String>['c']),
            ],
          ),
          _record(entries: _base),
        ),
        <String>{'c'},
      );
    });

    test('5.9.4 a key added to an experiment marks only that key', () {
      expect(diff(exp1(), exp1(keys: const <String>['a', 'b', 'c'])), <String>{
        'c',
      });
    });

    test('5.9.4 an experiment without affectedParameterKeys is skipped', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[_experiment('exp_1')],
          ),
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('exp_1', variant: '2', ttl: 5),
            ],
          ),
        ),
        isEmpty,
      );
    });

    for (final String id in <String>['_exp_rollout', '_exp_rollout_abc123']) {
      test('5.9.4 an experiment whose id starts with _exp_rollout ($id) is '
          'skipped', () {
        expect(
          updatedKeys(
            _record(
              entries: _base,
              experiments: <Map<String, Object?>>[
                _experiment(id, keys: <String>['a']),
              ],
            ),
            _record(
              entries: _base,
              experiments: <Map<String, Object?>>[
                _experiment(id, variant: '2', keys: <String>['a', 'b']),
              ],
            ),
          ),
          isEmpty,
        );
      });
    }

    test('5.9.4 an _exp_rollout experiment added or removed is skipped', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('_exp_rollout_1', keys: <String>['a']),
            ],
          ),
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('_exp_rollout_2', keys: <String>['b']),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('5.9.4 _exp_rollout only as a prefix: an id containing it later is '
        'compared', () {
      expect(
        updatedKeys(
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('exp_exp_rollout', keys: <String>['a']),
            ],
          ),
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('exp_exp_rollout', variant: '2', keys: <String>['a']),
            ],
          ),
        ),
        <String>{'a'},
      );
    });

    test('5.9.4 experiment, field and affectedParameterKeys order never '
        'matter', () {
      final Map<String, Object?> first = _experiment(
        'exp_1',
        keys: <String>['a', 'b'],
        ttl: '100',
        trigger: '200',
      );
      final Map<String, Object?> second = _experiment(
        'exp_2',
        variant: '3',
        keys: <String>['b', 'c'],
      );
      final Map<String, Object?> firstReordered = <String, Object?>{
        'triggerTimeoutMillis': '200',
        'affectedParameterKeys': <String>['b', 'a'],
        'timeToLiveMillis': '100',
        'variantId': '1',
        'experimentId': 'exp_1',
      };
      final Map<String, Object?> secondReordered = <String, Object?>{
        'affectedParameterKeys': <String>['c', 'b'],
        'variantId': '3',
        'experimentId': 'exp_2',
      };

      expect(
        updatedKeys(
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[first, second],
          ),
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              secondReordered,
              firstReordered,
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('5.9.4 an experiment key with no value is still in the union', () {
      expect(
        updatedKeys(
          _record(entries: _base),
          _record(
            entries: _base,
            experiments: <Map<String, Object?>>[
              _experiment('exp_1', keys: <String>['ghost']),
            ],
          ),
        ),
        <String>{'ghost'},
      );
    });
  });

  group('5.9.4 updatedKeys: combined', () {
    test('5.9.4 each kind of change marks its own key and nothing else', () {
      const Map<String, String> entries = <String, String>{
        'value': '1',
        'p13n': 'x',
        'rollout': 'y',
        'experiment': 'z',
        'untouched': 'u',
      };
      final TemplateRecord active = _record(
        entries: entries,
        personalization: <String, Map<String, Object?>>{
          'p13n': <String, Object?>{'choiceId': 'c1'},
          'untouched': <String, Object?>{'choiceId': 'u1'},
        },
        rollouts: <Map<String, Object?>>[
          _rollout('r1', keys: <String>['rollout']),
          _rollout('r2', keys: <String>['untouched']),
        ],
        experiments: <Map<String, Object?>>[
          _experiment('exp_1', keys: <String>['experiment']),
          _experiment('exp_2', keys: <String>['untouched']),
        ],
      );
      final TemplateRecord fetched = _record(
        entries: <String, String>{...entries, 'value': '2'},
        personalization: <String, Map<String, Object?>>{
          'untouched': <String, Object?>{'choiceId': 'u1'},
          'p13n': <String, Object?>{'choiceId': 'c2'},
        },
        rollouts: <Map<String, Object?>>[
          _rollout('r2', keys: <String>['untouched']),
          _rollout('r1', variant: 'v2', keys: <String>['rollout']),
        ],
        experiments: <Map<String, Object?>>[
          _experiment('exp_2', keys: <String>['untouched']),
          _experiment('exp_1', variant: '2', keys: <String>['experiment']),
        ],
      );

      expect(updatedKeys(active, fetched), <String>{
        'value',
        'p13n',
        'rollout',
        'experiment',
      });
    });

    test('5.9.4 the comparison is symmetric', () {
      final TemplateRecord one = _record(
        entries: <String, String>{'a': '1', 'b': '2'},
        rollouts: <Map<String, Object?>>[
          _rollout('r1', keys: <String>['b']),
        ],
      );
      final TemplateRecord two = _record(
        entries: <String, String>{'a': '1', 'c': '3'},
        experiments: <Map<String, Object?>>[
          _experiment('exp_1', keys: <String>['a']),
        ],
      );

      expect(updatedKeys(one, two), updatedKeys(two, one));
      expect(updatedKeys(one, two), <String>{'a', 'b', 'c'});
    });
  });
}
