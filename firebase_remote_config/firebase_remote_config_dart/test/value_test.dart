import 'dart:convert';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:firebase_remote_config_dart/src/value.dart' show staticValue;
import 'package:test/test.dart';

import 'support/rc_unit_env.dart';

RemoteConfigValue remote(String text) =>
    RemoteConfigValue(text, ValueSource.valueRemote);

void main() {
  group('5.7 asBool', () {
    const Map<String, bool> table = <String, bool>{
      '1': true,
      'true': true,
      'TRUE': true,
      't': true,
      'yes': true,
      'Yes': true,
      'y': true,
      'on': true,
      ' ON ': true,
      '0': false,
      'false': false,
      'f': false,
      'no': false,
      'n': false,
      'off': false,
      '': false,
      '   ': false,
    };
    for (final MapEntry<String, bool> entry in table.entries) {
      test('5.7 asBool of "${entry.key}" is ${entry.value}', () {
        expect(remote(entry.key).asBool(), entry.value);
      });
    }

    for (final String text in <String>['2', '01', 'maybe', 'truee', '0x1']) {
      test('5.7 asBool of "$text" is null', () {
        expect(remote(text).asBool(), isNull);
      });
    }
  });

  group('5.7 asInt', () {
    const Map<String, int> accepted = <String, int>{
      '0': 0,
      '10': 10,
      '+10': 10,
      '-10': -10,
      ' 42 ': 42,
      '007': 7,
      '9007199254740991': 9007199254740991,
      '-9007199254740991': -9007199254740991,
    };
    for (final MapEntry<String, int> entry in accepted.entries) {
      test('5.7 asInt of "${entry.key}" is ${entry.value}', () {
        expect(remote(entry.key).asInt(), entry.value);
      });
    }

    for (final String text in <String>[
      '',
      ' ',
      'yes',
      '0x10',
      'Infinity',
      '1.5',
      '1.0',
      '1e3',
      '1e400',
      '1_000',
      '--1',
      '9223372036854775808',
      '-9223372036854775809',
    ]) {
      test('5.7 asInt of "$text" is null', () {
        expect(remote(text).asInt(), isNull);
      });
    }

    // SPEC: 5.7; on dart2wasm the code compares with `identical(0, 0.0)`, which is false there, so
    // it may accept 2^53 where the spec says the web stops at 2^53 - 1.
    test('5.7 asInt of +-2^53 is null on the web, exact on the VM', () {
      const String up = '9007199254740992';
      const String down = '-9007199254740992';
      if (isWebCompiled) {
        expect(remote(up).asInt(), isNull);
        expect(remote(down).asInt(), isNull);
      } else {
        expect(remote(up).asInt(), 9007199254740992);
        expect(remote(down).asInt(), -9007199254740992);
      }
    });
  });

  group('5.7 asDouble', () {
    const Map<String, double> accepted = <String, double>{
      '0': 0.0,
      '1.5': 1.5,
      '-2.25': -2.25,
      ' 2 ': 2.0,
      '1e3': 1000.0,
      '.5': 0.5,
    };
    for (final MapEntry<String, double> entry in accepted.entries) {
      test('5.7 asDouble of "${entry.key}" is ${entry.value}', () {
        expect(remote(entry.key).asDouble(), entry.value);
      });
    }

    for (final String text in <String>[
      '',
      'yes',
      'Infinity',
      '-Infinity',
      'NaN',
      '1e400',
      '-1e400',
      '1,5',
    ]) {
      test('5.7 asDouble of "$text" is null', () {
        expect(remote(text).asDouble(), isNull);
      });
    }
  });

  group('5.7 static value', () {
    test('5.7 a static value converts to null whatever its text', () {
      for (final String text in <String>['', 'true', '1', '1.5']) {
        final RemoteConfigValue value = RemoteConfigValue(
          text,
          ValueSource.valueStatic,
        );
        expect(value.asBool(), isNull, reason: text);
        expect(value.asInt(), isNull, reason: text);
        expect(value.asDouble(), isNull, reason: text);
        expect(value.asString(), text);
      }
    });

    test('5.7 staticValue is empty text with the static source', () {
      expect(staticValue.text, '');
      expect(staticValue.source, ValueSource.valueStatic);
    });

    test('5.7 value equality covers text and source', () {
      expect(remote('a'), remote('a'));
      expect(remote('a'), isNot(remote('b')));
      expect(
        remote('a'),
        isNot(const RemoteConfigValue('a', ValueSource.valueDefault)),
      );
      expect(remote('a').hashCode, remote('a').hashCode);
    });
  });

  group('5.7 getters on an instance', () {
    late RcUnitEnv env;

    setUp(() {
      env = RcUnitEnv();
    });

    tearDown(() => env.dispose());

    Future<FirebaseRemoteConfig> activated(
      Map<String, String> entries,
      Map<String, Object> defaults,
    ) async {
      env.fetchReply = FetchReply.template(entries, version: 1);
      final FirebaseRemoteConfig rc = env.newRemoteConfig(defaults: defaults);
      await rc.fetchAndActivate();
      return rc;
    }

    test('5.7 an active value that converts wins over the default', () async {
      final FirebaseRemoteConfig rc = await activated(
        <String, String>{'b': 'yes', 'i': '12', 'd': '2.5', 's': 'remote'},
        <String, Object>{'b': false, 'i': 7, 'd': 9.5, 's': 'default'},
      );
      expect(rc.getBool('b'), isTrue);
      expect(rc.getInt('i'), 12);
      expect(rc.getDouble('d'), 2.5);
      expect(rc.getString('s'), 'remote');
    });

    test('5.7 getters fall through to the default when the text does not '
        'convert: 0x10, Infinity, 1e400, maybe', () async {
      final FirebaseRemoteConfig rc = await activated(
        <String, String>{
          'hex': '0x10',
          'inf': 'Infinity',
          'huge': '1e400',
          'word': 'maybe',
        },
        <String, Object>{'hex': 7, 'inf': 2.5, 'huge': 3.5, 'word': true},
      );
      expect(rc.getInt('hex'), 7);
      expect(rc.getDouble('inf'), 2.5);
      expect(rc.getDouble('huge'), 3.5);
      expect(rc.getBool('word'), isTrue);
    });

    test('5.7 getters answer false, 0, 0.0 when neither side converts, and '
        'getString still gives the remote text', () async {
      final FirebaseRemoteConfig rc = await activated(
        <String, String>{
          'word': 'maybe',
          'hex': '0x10',
          'inf': 'Infinity',
          'big': '9223372036854775808',
        },
        <String, Object>{'hex': 'also-not-a-number'},
      );
      expect(rc.getBool('word'), isFalse);
      expect(rc.getInt('hex'), 0);
      expect(rc.getDouble('inf'), 0.0);
      expect(rc.getInt('big'), 0);
      expect(rc.getString('word'), 'maybe');
      expect(rc.getString('hex'), '0x10');
    });

    test(
      '5.7 yes and the edge texts read the way Android reads them',
      () async {
        final FirebaseRemoteConfig rc = await activated(<String, String>{
          'a': ' YES ',
          'b': '',
          'c': '9007199254740991',
        }, const <String, Object>{});
        expect(rc.getBool('a'), isTrue);
        expect(rc.getBool('b'), isFalse);
        expect(rc.getInt('c'), 9007199254740991);
      },
    );

    test('5.7 a key in neither place is the static value', () async {
      final FirebaseRemoteConfig rc = await activated(
        <String, String>{'k': 'v'},
        <String, Object>{'d': 'x'},
      );
      expect(rc.getValue('missing'), staticValue);
      expect(rc.getValue('missing').source, ValueSource.valueStatic);
      expect(rc.getString('missing'), '');
      expect(rc.getBool('missing'), isFalse);
      expect(rc.getInt('missing'), 0);
      expect(rc.getDouble('missing'), 0.0);
    });

    test('5.7 sources: remote, default, static', () async {
      final FirebaseRemoteConfig rc = await activated(
        <String, String>{'r': '1'},
        <String, Object>{'d': 'x', 'r': 'overridden'},
      );
      expect(rc.getValue('r').source, ValueSource.valueRemote);
      expect(rc.getValue('d').source, ValueSource.valueDefault);
      expect(rc.getValue('zzz').source, ValueSource.valueStatic);
    });

    test('5.7 defaults of other types are rendered as text', () {
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        defaults: <String, Object>{
          's': 'text',
          'b': true,
          'i': 5,
          'whole': 1.0,
          'half': 1.5,
        },
      );
      expect(rc.defaults['s']?.text, 'text');
      expect(rc.defaults['b']?.text, 'true');
      expect(rc.defaults['i']?.text, '5');
      expect(rc.defaults['whole']?.text, '1');
      expect(rc.defaults['half']?.text, '1.5');
      expect(rc.getBool('b'), isTrue);
      expect(rc.getInt('whole'), 1);
      expect(rc.getDouble('half'), 1.5);
    });

    test(
      '5.7 getAll is the union of the active keys and the defaults',
      () async {
        final FirebaseRemoteConfig rc = await activated(
          <String, String>{'both': 'remote', 'remote_only': 'r'},
          <String, Object>{'both': 'default', 'default_only': 'd'},
        );
        final Map<String, RemoteConfigValue> all = rc.getAll();
        expect(all.keys.toSet(), <String>{
          'both',
          'remote_only',
          'default_only',
        });
        expect(all['both'], remote('remote'));
        expect(all['remote_only'], remote('r'));
        expect(
          all['default_only'],
          const RemoteConfigValue('d', ValueSource.valueDefault),
        );
      },
    );

    test('5.7 getAll before any activation holds only the defaults', () {
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        defaults: <String, Object>{'a': 'x', 'b': 2},
      );
      expect(rc.getAll().keys.toSet(), <String>{'a', 'b'});
      expect(
        rc.getAll().values.every(
          (RemoteConfigValue v) => v.source == ValueSource.valueDefault,
        ),
        isTrue,
      );
    });

    test('5.7 a fetched but not activated template is not read', () async {
      env.fetchReply = FetchReply.template(<String, String>{
        'k': 'fetched',
      }, version: 1);
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        defaults: <String, Object>{'k': 'default'},
      );
      await rc.fetch();
      expect(rc.getString('k'), 'default');
      expect(await rc.activate(), isTrue);
      expect(rc.getString('k'), 'fetched');
    });
  });

  group('5.7 reads before isInitialized', () {
    late RcUnitEnv env;

    setUp(() {
      env = RcUnitEnv();
    });

    tearDown(() => env.dispose());

    test('5.7 reads answer from the defaults until the records are loaded, '
        'then from the stored active template', () async {
      final TemplateRecord stored = TemplateRecord(
        entries: const <String, String>{'k': 'stored', 'other': 'x'},
        fetchTime: fixedNow,
        templateVersion: 4,
      );
      await env.store.write(env.key('active'), stored.encode());

      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        defaults: <String, Object>{'k': 'default'},
      );
      expect(rc.isInitialized, isFalse);
      expect(rc.getString('k'), 'default');
      expect(rc.getString('other'), '');
      expect(rc.getAll().keys, <String>['k']);
      expect(rc.info.activeTemplateVersion, isNull);
      expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);

      await rc.ensureInitialized();
      expect(rc.isInitialized, isTrue);
      expect(rc.getString('k'), 'stored');
      expect(rc.getString('other'), 'x');
      expect(rc.info.activeTemplateVersion, 4);
      expect(env.requests, isEmpty, reason: 'the constructor sends nothing');
    });

    test('5.7 reads do not throw before or after initialization with an empty '
        'store', () async {
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      expect(rc.getString('a'), '');
      expect(rc.getBool('a'), isFalse);
      expect(rc.getInt('a'), 0);
      expect(rc.getDouble('a'), 0.0);
      expect(rc.getAll(), isEmpty);
      await rc.ensureInitialized();
      expect(rc.getAll(), isEmpty);
    });
  });

  group('5.7 info', () {
    late RcUnitEnv env;

    setUp(() {
      env = RcUnitEnv();
    });

    tearDown(() => env.dispose());

    test('5.7 info of a fresh instance has no fetch and no versions', () async {
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        clock: () => fixedNow,
      );
      await rc.ensureInitialized();
      expect(
        rc.info,
        const RemoteConfigInfo(
          lastFetchStatus: RemoteConfigFetchStatus.noFetchYet,
        ),
      );
    });

    test('5.7 info after fetch and after activate', () async {
      env.fetchReply = FetchReply.template(<String, String>{
        'k': 'v',
      }, version: 6);
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        clock: () => fixedNow,
      );
      await rc.fetch();
      expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.success);
      expect(rc.info.lastSuccessfulFetchTime, fixedNow);
      expect(rc.info.fetchedTemplateVersion, 6);
      expect(rc.info.activeTemplateVersion, isNull);
      expect(rc.info.throttledUntil, isNull);

      await rc.activate();
      expect(rc.info.activeTemplateVersion, 6);
      expect(rc.info.fetchedTemplateVersion, 6);
    });

    test('5.7 info after a 503: failure status and a throttle window of '
        '2 minutes times [0.5, 1.5)', () async {
      env.fetchReply = const FetchReply(503, '{}');
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        clock: () => fixedNow,
      );
      await expectLater(
        rc.fetch(),
        throwsA(
          isA<FirebaseRemoteConfigException>().having(
            (FirebaseRemoteConfigException e) => e.httpStatus,
            'httpStatus',
            503,
          ),
        ),
      );
      expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.failure);
      final DateTime? until = rc.info.throttledUntil;
      expect(until, isNotNull);
      final Duration window = until!.difference(fixedNow);
      expect(window, greaterThanOrEqualTo(const Duration(minutes: 1)));
      expect(window, lessThan(const Duration(minutes: 3)));
      expect(rc.info.lastSuccessfulFetchTime, isNull);
    });

    test('5.7 info after a 429 is throttled', () async {
      env.fetchReply = const FetchReply(429, '{}');
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        clock: () => fixedNow,
      );
      await expectLater(
        rc.fetch(),
        throwsA(
          isA<FirebaseRemoteConfigException>().having(
            (FirebaseRemoteConfigException e) => e.code,
            'code',
            'fetch-throttle',
          ),
        ),
      );
      expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.throttled);
      expect(rc.info.throttledUntil, isNotNull);
    });

    test(
      '5.7 info reads the stored meta and versions of an earlier run',
      () async {
        final TemplateRecord record = TemplateRecord(
          entries: const <String, String>{'k': 'v'},
          fetchTime: fixedNow,
          templateVersion: 9,
        );
        await env.store.write(env.key('fetched'), record.encode());
        await env.store.write(env.key('active'), record.encode());
        await env.store.write(
          env.key('meta'),
          jsonEncode(<String, Object?>{
            'v': 1,
            'lastFetchStatus': 'success',
            'lastSuccessfulFetchTime': fixedNow.millisecondsSinceEpoch,
            'staleGeneration': 0,
          }),
        );
        final FirebaseRemoteConfig rc = env.newRemoteConfig(
          clock: () => fixedNow.add(const Duration(minutes: 1)),
        );
        await rc.ensureInitialized();
        expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.success);
        expect(rc.info.lastSuccessfulFetchTime, fixedNow);
        expect(rc.info.activeTemplateVersion, 9);
        expect(rc.info.fetchedTemplateVersion, 9);
        expect(MetaRecord.tryParse('{', fixedNow), isNull);
      },
    );
  });
}
