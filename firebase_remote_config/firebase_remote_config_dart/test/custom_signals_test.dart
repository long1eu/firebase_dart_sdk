import 'dart:convert';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'support/rc_unit_env.dart';

Matcher argumentErrorWith(String position) => isA<ArgumentError>().having(
  (ArgumentError e) => e.toString(),
  'message',
  contains('position $position'),
);

void main() {
  late RcUnitEnv env;
  late FirebaseRemoteConfig rc;

  setUp(() {
    env = RcUnitEnv();
    rc = env.newRemoteConfig();
  });

  tearDown(() => env.dispose());

  Future<Map<String, Object?>?> storedRecord() async {
    final String? text = await env.store.read(env.key('signals'));
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  group('5.8 limit table', () {
    test('5.8 a key of 1 and of 250 characters is accepted', () async {
      await rc.setCustomSignals(<String, Object?>{'k': 'a', 'x' * 250: 'b'});
      expect(rc.customSignals.length, 2);
      expect(rc.customSignals['x' * 250], 'b');
    });

    test('5.8 an empty key is refused and names its position', () async {
      await expectLater(
        rc.setCustomSignals(<String, Object?>{'ok': '1', '': '2'}),
        throwsA(argumentErrorWith('1')),
      );
      expect(rc.customSignals, isEmpty);
      expect(await storedRecord(), isNull);
    });

    test('5.8 a key of 251 characters is refused', () async {
      await expectLater(
        rc.setCustomSignals(<String, Object?>{'x' * 251: '1'}),
        throwsA(argumentErrorWith('0')),
      );
      expect(await storedRecord(), isNull);
    });

    test(
      '5.8 a string value of 500 characters is accepted, 501 refused',
      () async {
        await rc.setCustomSignals(<String, Object?>{'k': 'v' * 500});
        expect(rc.customSignals['k']?.length, 500);
        await expectLater(
          rc.setCustomSignals(<String, Object?>{'other': 'v' * 501}),
          throwsA(argumentErrorWith('0')),
        );
        expect(rc.customSignals.keys, <String>['k']);
      },
    );

    test('5.8 the empty string is a valid value', () async {
      await rc.setCustomSignals(<String, Object?>{'k': ''});
      expect(rc.customSignals['k'], '');
    });

    test('5.8 100 signals are accepted, the 101st is refused and nothing '
        'changes', () async {
      await rc.setCustomSignals(<String, Object?>{
        for (int i = 0; i < 100; i++) 'k$i': '$i',
      });
      expect(rc.customSignals.length, 100);
      final String? before = await env.store.read(env.key('signals'));
      await expectLater(
        rc.setCustomSignals(<String, Object?>{'one-too-many': 'x'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(rc.customSignals.length, 100);
      expect(await env.store.read(env.key('signals')), before);
    });

    test('5.8 the limit counts the merge: a removal in the same call makes '
        'room', () async {
      await rc.setCustomSignals(<String, Object?>{
        for (int i = 0; i < 100; i++) 'k$i': '$i',
      });
      await rc.setCustomSignals(<String, Object?>{'k0': null, 'new': 'x'});
      expect(rc.customSignals.length, 100);
      expect(rc.customSignals.containsKey('k0'), isFalse);
      expect(rc.customSignals['new'], 'x');
    });

    test('5.8 updating existing keys at the limit is accepted', () async {
      await rc.setCustomSignals(<String, Object?>{
        for (int i = 0; i < 100; i++) 'k$i': '$i',
      });
      await rc.setCustomSignals(<String, Object?>{'k5': 'changed'});
      expect(rc.customSignals['k5'], 'changed');
    });

    test(
      '5.8 a value that is not String, int or finite double is refused',
      () async {
        for (final Object value in <Object>[
          true,
          <Object>[1],
          <String, Object>{'a': 1},
          DateTime.utc(2026),
        ]) {
          await expectLater(
            rc.setCustomSignals(<String, Object?>{'k': value}),
            throwsA(isA<ArgumentError>()),
            reason: '$value',
          );
        }
        expect(await storedRecord(), isNull);
      },
    );

    test('5.8 a violation stores nothing, even when earlier entries were '
        'valid', () async {
      await expectLater(
        rc.setCustomSignals(<String, Object?>{'good': 'v', 'bad': true}),
        throwsA(argumentErrorWith('1')),
      );
      expect(rc.customSignals, isEmpty);
      expect(await storedRecord(), isNull);
    });

    test(
      '5.8 the error names the position and never the key or the value',
      () async {
        const String secretKey = 'SECRET-KEY-SENTINEL';
        const String secretValue = 'SECRET-VALUE-SENTINEL';
        final List<Map<String, Object?>> bad = <Map<String, Object?>>[
          <String, Object?>{secretKey: true},
          <String, Object?>{secretKey: secretValue * 40},
          <String, Object?>{'k' * 251: secretValue},
          <String, Object?>{secretKey: double.nan},
        ];
        for (final Map<String, Object?> changes in bad) {
          try {
            await rc.setCustomSignals(changes);
            fail('expected an ArgumentError for $changes');
          } on ArgumentError catch (error) {
            final String text = error.toString();
            expect(text, isNot(contains(secretKey)));
            expect(text, isNot(contains(secretValue)));
            expect(text, contains('position 0'));
          }
        }
      },
    );
  });

  group('5.8 numbers', () {
    test('5.8 NaN and the infinities are refused', () async {
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        await expectLater(
          rc.setCustomSignals(<String, Object?>{'k': value}),
          throwsA(isA<ArgumentError>()),
          reason: '$value',
        );
      }
      expect(await storedRecord(), isNull);
    });

    test('5.8 numbers are stored as text: 1.0 becomes "1"', () async {
      await rc.setCustomSignals(<String, Object?>{
        'whole': 1.0,
        'int': 42,
        'negative': -7,
        'fraction': 1.5,
        'zero': 0,
      });
      expect(rc.customSignals, <String, String>{
        'whole': '1',
        'int': '42',
        'negative': '-7',
        'fraction': '1.5',
        'zero': '0',
      });
      final Map<String, Object?>? record = await storedRecord();
      expect(record?['signals'], <String, Object?>{
        'whole': '1',
        'int': '42',
        'negative': '-7',
        'fraction': '1.5',
        'zero': '0',
      });
    });

    test('5.8 strings that look like numbers stay strings', () async {
      await rc.setCustomSignals(<String, Object?>{'k': '1.0'});
      expect(rc.customSignals['k'], '1.0');
    });
  });

  group('5.8 storage', () {
    test(
      '5.8 the stored record is versioned JSON with the signals as text',
      () async {
        await rc.setCustomSignals(<String, Object?>{'plan': 'pro', 'n': 3});
        final Map<String, Object?>? record = await storedRecord();
        expect(record?['v'], 1);
        expect(record?['signals'], <String, Object?>{'plan': 'pro', 'n': '3'});
      },
    );

    test('5.8 a null value removes its key and leaves no trace in the stored '
        'text', () async {
      await rc.setCustomSignals(<String, Object?>{
        'removed-key-sentinel': 'removed-value-sentinel',
        'kept': 'x',
      });
      await rc.setCustomSignals(<String, Object?>{
        'removed-key-sentinel': null,
      });
      expect(rc.customSignals, <String, String>{'kept': 'x'});
      final String? text = await env.store.read(env.key('signals'));
      expect(text, isNotNull);
      expect(text, isNot(contains('removed-key-sentinel')));
      expect(text, isNot(contains('removed-value-sentinel')));
    });

    test(
      '5.8 removing the last key leaves an empty map, still no trace',
      () async {
        await rc.setCustomSignals(<String, Object?>{'only-sentinel': 'v'});
        await rc.setCustomSignals(<String, Object?>{'only-sentinel': null});
        expect(rc.customSignals, isEmpty);
        final String? text = await env.store.read(env.key('signals'));
        expect(text, isNot(contains('only-sentinel')));
      },
    );

    test('5.8 removing a key that is not there changes nothing', () async {
      await rc.setCustomSignals(<String, Object?>{'a': '1'});
      final String? before = await env.store.read(env.key('signals'));
      await rc.setCustomSignals(<String, Object?>{'absent': null});
      expect(await env.store.read(env.key('signals')), before);
      expect(rc.customSignals, <String, String>{'a': '1'});
    });

    test(
      '5.8 a later call replaces the value of a key and keeps the others',
      () async {
        await rc.setCustomSignals(<String, Object?>{'a': '1', 'b': '2'});
        await rc.setCustomSignals(<String, Object?>{'a': '9'});
        expect(rc.customSignals, <String, String>{'a': '9', 'b': '2'});
      },
    );

    test('5.8 customSignals is unmodifiable', () async {
      await rc.setCustomSignals(<String, Object?>{'a': '1'});
      expect(() => rc.customSignals['b'] = '2', throwsUnsupportedError);
    });

    test(
      '5.8 a new instance on the same store reads the signals back',
      () async {
        await rc.setCustomSignals(<String, Object?>{'a': '1', 'n': 2});
        final FirebaseRemoteConfig again = env.newRemoteConfig();
        await again.ensureInitialized();
        expect(again.customSignals, <String, String>{'a': '1', 'n': '2'});
      },
    );

    test(
      '5.8 two instances setting different keys at once keep both',
      () async {
        final FirebaseRemoteConfig other = env.newRemoteConfig();
        await Future.wait(<Future<void>>[
          rc.ensureInitialized(),
          other.ensureInitialized(),
        ]);
        await Future.wait(<Future<void>>[
          rc.setCustomSignals(<String, Object?>{'from-a': '1'}),
          other.setCustomSignals(<String, Object?>{'from-b': '2'}),
        ]);
        final Map<String, Object?>? record = await storedRecord();
        expect(record?['signals'], <String, Object?>{
          'from-a': '1',
          'from-b': '2',
        });
      },
    );

    test('5.8 the second of two instances sees the first one\'s keys after '
        'its own update', () async {
      final FirebaseRemoteConfig other = env.newRemoteConfig();
      await rc.setCustomSignals(<String, Object?>{'from-a': '1'});
      await other.setCustomSignals(<String, Object?>{'from-b': '2'});
      expect(other.customSignals, <String, String>{
        'from-a': '1',
        'from-b': '2',
      });
    });

    test('5.8 a closed instance refuses with remote-config-closed', () async {
      await rc.close();
      await expectLater(
        rc.setCustomSignals(<String, Object?>{'a': '1'}),
        throwsA(
          isA<FirebaseRemoteConfigException>().having(
            (FirebaseRemoteConfigException e) => e.code,
            'code',
            'remote-config-closed',
          ),
        ),
      );
    });
  });

  group('5.8 effect on fetch', () {
    test('5.8 a change makes the next fetch skip the cache and sends the '
        'signals', () async {
      await rc.fetch();
      expect(await rc.fetch(), FetchResult.cached);
      expect(env.fetches.length, 1);

      await rc.setCustomSignals(<String, Object?>{'plan': 'pro', 'n': 1.0});
      expect(await rc.fetch(), FetchResult.updated);
      expect(env.fetches.length, 2);
      expect(env.fetches.last.json['custom_signals'], <String, Object?>{
        'plan': 'pro',
        'n': '1',
      });
    });

    test('5.8 a call that changes nothing does not skip the cache', () async {
      await rc.setCustomSignals(<String, Object?>{'plan': 'pro'});
      await rc.fetch();
      await rc.setCustomSignals(<String, Object?>{'plan': 'pro'});
      expect(await rc.fetch(), FetchResult.cached);
      expect(env.fetches.length, 1);
    });

    test('5.8 an empty signal map is left out of the body', () async {
      await rc.fetch();
      expect(env.fetches.single.json.containsKey('custom_signals'), isFalse);
    });

    test('5.8 after a removal that empties the map, the body has no '
        'custom_signals', () async {
      await rc.setCustomSignals(<String, Object?>{'a': '1'});
      await rc.setCustomSignals(<String, Object?>{'a': null});
      await rc.fetch();
      expect(env.fetches.single.json.containsKey('custom_signals'), isFalse);
    });
  });
}
