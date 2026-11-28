@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_installations_dart/io.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:test/test.dart';

import '../support/rc_sec_harness.dart';

const int _maxRecordBytes = 16 * 1024 * 1024;

/// One Remote Config record of 5.10: a valid stored form, its wrong-typed variants, how to see that it
/// was loaded or left absent, and the write that replaces it.
final class _Record {
  const _Record({
    required this.name,
    required this.valid,
    required this.wrongTypes,
    required this.expectPresent,
    required this.expectAbsent,
    required this.repair,
    required this.isValidText,
  });

  final String name;
  final Map<String, Object?> valid;
  final Map<String, Map<String, Object?>> wrongTypes;
  final void Function(FirebaseRemoteConfig remoteConfig) expectPresent;
  final Future<void> Function(FirebaseRemoteConfig remoteConfig) expectAbsent;
  final Future<void> Function(RcSecFixture fixture, RcSecBackend backend)
  repair;
  final bool Function(String text) isValidText;
}

Map<String, Object?> _template() => TemplateRecord(
  entries: const <String, String>{'k': 'stored'},
  fetchTime: rcSecNow.subtract(const Duration(days: 1)),
  templateVersion: 7,
).toJson();

Map<String, Object?> _with(
  Map<String, Object?> base,
  Map<String, Object?> changes,
) {
  final Map<String, Object?> result = <String, Object?>{...base};
  for (final MapEntry<String, Object?> entry in changes.entries) {
    if (entry.value == #remove) {
      result.remove(entry.key);
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

Map<String, Map<String, Object?>> _templateWrongTypes() {
  final Map<String, Object?> t = _template();
  return <String, Map<String, Object?>>{
    'entries is a list': _with(t, <String, Object?>{'entries': <Object?>[]}),
    'an entry value is a number': _with(t, <String, Object?>{
      'entries': <String, Object?>{'k': 1},
    }),
    'entries missing': _with(t, <String, Object?>{'entries': #remove}),
    'fetchTime is text': _with(t, <String, Object?>{'fetchTime': 'yesterday'}),
    // A27: negative times within ±8.64e15 ms load; beyond the bound the record is absent.
    'fetchTime is below -8.64e15': _with(t, <String, Object?>{
      'fetchTime': -8640000000000001,
    }),
    'fetchTime is above 8.64e15': _with(t, <String, Object?>{
      'fetchTime': 8640000000000001,
    }),
    'fetchTime is a fraction': _with(t, <String, Object?>{'fetchTime': 1.5}),
    'fetchTime missing': _with(t, <String, Object?>{'fetchTime': #remove}),
    'templateVersion is "-1"': _with(t, <String, Object?>{
      'templateVersion': '-1',
    }),
    'templateVersion is "1e3"': _with(t, <String, Object?>{
      'templateVersion': '1e3',
    }),
    'templateVersion is 2^53': _with(t, <String, Object?>{
      'templateVersion': 9007199254740992,
    }),
  };
}

final Map<String, Object?> _validMeta = <String, Object?>{
  'v': 1,
  'lastFetchStatus': 'success',
  'lastSuccessfulFetchTime': rcSecNow
      .subtract(const Duration(hours: 1))
      .millisecondsSinceEpoch,
  'staleGeneration': 0,
};

final Map<String, Object?> _validThrottle = <String, Object?>{
  'v': 1,
  'count': 2,
  'until': rcSecNow.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
};

final Map<String, Object?> _validSignals = <String, Object?>{
  'v': 1,
  'signals': <String, String>{'tier': 'gold'},
};

final List<_Record> _records = <_Record>[
  _Record(
    name: 'fetched',
    valid: _template(),
    wrongTypes: _templateWrongTypes(),
    expectPresent: (FirebaseRemoteConfig rc) =>
        expect(rc.info.fetchedTemplateVersion, 7),
    expectAbsent: (FirebaseRemoteConfig rc) async {
      expect(rc.info.fetchedTemplateVersion, isNull);
      expect(await rc.activate(), isFalse);
      expect(rc.getValue('k').source, ValueSource.valueDefault);
    },
    repair: (RcSecFixture fixture, RcSecBackend backend) async {
      expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
    },
    isValidText: (String text) =>
        TemplateRecord.tryParse(text)?.templateVersion == 1,
  ),
  _Record(
    name: 'active',
    valid: _template(),
    wrongTypes: _templateWrongTypes(),
    expectPresent: (FirebaseRemoteConfig rc) {
      expect(rc.getString('k'), 'stored');
      expect(rc.info.activeTemplateVersion, 7);
    },
    expectAbsent: (FirebaseRemoteConfig rc) async {
      expect(rc.getString('k'), 'default');
      expect(rc.getValue('k').source, ValueSource.valueDefault);
      expect(rc.info.activeTemplateVersion, isNull);
    },
    repair: (RcSecFixture fixture, RcSecBackend backend) async {
      await fixture.remoteConfig.fetch();
      expect(await fixture.remoteConfig.activate(), isTrue);
      expect(fixture.remoteConfig.getString('k'), 'remote');
    },
    isValidText: (String text) =>
        TemplateRecord.tryParse(text)?.entries['k'] == 'remote',
  ),
  _Record(
    name: 'meta',
    valid: _validMeta,
    wrongTypes: <String, Map<String, Object?>>{
      'lastFetchStatus unknown': _with(_validMeta, <String, Object?>{
        'lastFetchStatus': 'bogus',
      }),
      'lastFetchStatus is a number': _with(_validMeta, <String, Object?>{
        'lastFetchStatus': 1,
      }),
      'staleGeneration is -1': _with(_validMeta, <String, Object?>{
        'staleGeneration': -1,
      }),
      'staleGeneration is 2^31': _with(_validMeta, <String, Object?>{
        'staleGeneration': 2147483648,
      }),
      'staleGeneration is text': _with(_validMeta, <String, Object?>{
        'staleGeneration': 'x',
      }),
      'staleGeneration missing': _with(_validMeta, <String, Object?>{
        'staleGeneration': #remove,
      }),
      'lastSuccessfulFetchTime is text': _with(_validMeta, <String, Object?>{
        'lastSuccessfulFetchTime': 'x',
      }),
      'lastSuccessfulFetchTime is below -8.64e15': _with(
        _validMeta,
        <String, Object?>{'lastSuccessfulFetchTime': -8640000000000001},
      ),
    },
    expectPresent: (FirebaseRemoteConfig rc) {
      expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.success);
      expect(rc.info.lastSuccessfulFetchTime, isNotNull);
    },
    expectAbsent: (FirebaseRemoteConfig rc) async {
      expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
      expect(rc.info.lastSuccessfulFetchTime, isNull);
    },
    repair: (RcSecFixture fixture, RcSecBackend backend) async {
      await fixture.remoteConfig.fetch();
    },
    isValidText: (String text) =>
        MetaRecord.tryParse(text, rcSecNow)?.lastFetchStatus ==
        RemoteConfigFetchStatus.success,
  ),
  _Record(
    name: 'throttle',
    valid: _validThrottle,
    wrongTypes: <String, Map<String, Object?>>{
      'count is -1': _with(_validThrottle, <String, Object?>{'count': -1}),
      'count is 1001': _with(_validThrottle, <String, Object?>{'count': 1001}),
      'count is text': _with(_validThrottle, <String, Object?>{'count': 'a'}),
      'count missing': _with(_validThrottle, <String, Object?>{
        'count': #remove,
      }),
      'until is text': _with(_validThrottle, <String, Object?>{'until': 'x'}),
      'until is a fraction': _with(_validThrottle, <String, Object?>{
        'until': 1.5,
      }),
    },
    expectPresent: (FirebaseRemoteConfig rc) =>
        expect(rc.info.throttledUntil, isNotNull),
    expectAbsent: (FirebaseRemoteConfig rc) async {
      expect(rc.info.throttledUntil, isNull);
    },
    repair: (RcSecFixture fixture, RcSecBackend backend) async {
      backend.onFetch = (RcSecCall call) =>
          jsonResponse(call, 503, <String, Object?>{});
      final FirebaseRemoteConfigException error = await rcErrorOf(
        fixture.remoteConfig.fetch,
      );
      expect(
        error.httpStatus,
        503,
        reason: 'the request was sent: the bad record did not throttle',
      );
    },
    isValidText: (String text) =>
        ThrottleRecord.tryParse(text, rcSecNow)?.count == 1,
  ),
  _Record(
    name: 'signals',
    valid: _validSignals,
    wrongTypes: <String, Map<String, Object?>>{
      'signals is a list': <String, Object?>{'v': 1, 'signals': <Object?>[]},
      'a signal value is a number': <String, Object?>{
        'v': 1,
        'signals': <String, Object?>{'a': 1},
      },
      '101 signals': <String, Object?>{
        'v': 1,
        'signals': <String, String>{for (int i = 0; i < 101; i++) 'key$i': 'v'},
      },
      'a key of 251 characters': <String, Object?>{
        'v': 1,
        'signals': <String, String>{'k' * 251: 'v'},
      },
      'a value of 501 characters': <String, Object?>{
        'v': 1,
        'signals': <String, String>{'k': 'v' * 501},
      },
      'an empty key': <String, Object?>{
        'v': 1,
        'signals': <String, String>{'': 'v'},
      },
      'signals missing': <String, Object?>{'v': 1},
    },
    expectPresent: (FirebaseRemoteConfig rc) =>
        expect(rc.customSignals, <String, String>{'tier': 'gold'}),
    expectAbsent: (FirebaseRemoteConfig rc) async {
      expect(rc.customSignals, isEmpty);
    },
    repair: (RcSecFixture fixture, RcSecBackend backend) async {
      await fixture.remoteConfig.setCustomSignals(<String, Object?>{'a': 'b'});
    },
    isValidText: (String text) {
      final Map<String, String>? signals = SignalsRecord.tryParse(
        text,
      )?.signals;
      return signals != null && signals.length == 1 && signals['a'] == 'b';
    },
  ),
];

/// The corruptions common to every record, built from its valid form.
Map<String, String> _corruptions(Map<String, Object?> valid) {
  final String text = jsonEncode(valid);
  return <String, String>{
    'empty': '',
    '"{"': '{',
    'null': 'null',
    '[]': '[]',
    'a JSON string': '"text"',
    'a JSON number': '42',
    'truncated': text.substring(0, text.length ~/ 2),
    '0xFF bytes read as text': String.fromCharCodes(<int>[
      0xff,
      0xfe,
      0xff,
      0x7b,
    ]),
    'U+FFFD replacement characters': '��',
    'unknown v (2)': jsonEncode(<String, Object?>{...valid, 'v': 2}),
    'v as text "1"': jsonEncode(<String, Object?>{...valid, 'v': '1'}),
    'v missing': jsonEncode(<String, Object?>{...valid}..remove('v')),
    'oversized (16 MiB + 1 byte)': paddedJson(valid, _maxRecordBytes + 1),
    'nested 33 deep': jsonEncode(<String, Object?>{
      ...valid,
      'extra': jsonDecode(nestedArrays(32)),
    }),
  };
}

void main() {
  final List<RcSecFixture> fixtures = <RcSecFixture>[];

  Future<RcSecFixture> open(
    RcSecBackend backend, {
    KeyValueStore? store,
    Map<String, String> seed = const <String, String>{},
  }) async {
    final RcSecFixture fixture = await RcSecFixture.open(
      backend: backend,
      store: store,
      seed: seed,
      clock: () => rcSecNow,
    );
    fixtures.add(fixture);
    return fixture;
  }

  tearDown(() async {
    for (final RcSecFixture fixture in fixtures) {
      await fixture.dispose();
    }
    fixtures.clear();
  });

  for (final _Record record in _records) {
    group('5.10 record ${record.name}', () {
      test('5.10 ${record.name}: a valid record loads (control)', () async {
        final RcSecFixture fixture = await open(
          RcSecBackend(),
          seed: <String, String>{record.name: jsonEncode(record.valid)},
        );
        await fixture.remoteConfig.ensureInitialized();
        record.expectPresent(fixture.remoteConfig);
        expect(
          fixture.logs.where(
            (String line) => line.contains('stored ${record.name} record'),
          ),
          isEmpty,
        );
      });

      final Map<String, String> cases = <String, String>{
        ..._corruptions(record.valid),
        for (final MapEntry<String, Map<String, Object?>> entry
            in record.wrongTypes.entries)
          'wrong type: ${entry.key}': jsonEncode(entry.value),
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        test(
          '5.10 ${record.name}: ${entry.key} → absent, no throw, logged once; the next write repairs',
          () async {
            final RcSecBackend backend = RcSecBackend();
            final RcSecFixture fixture = await open(
              backend,
              seed: <String, String>{record.name: entry.value},
            );
            await fixture.remoteConfig.ensureInitialized();
            expect(fixture.remoteConfig.isInitialized, isTrue);
            await record.expectAbsent(fixture.remoteConfig);
            expect(
              fixture.logs.where(
                (String line) => line.contains('stored ${record.name} record'),
              ),
              hasLength(1),
            );

            await record.repair(fixture, backend);
            final String? repaired = await fixture.store.read(
              fixture.key(record.name),
            );
            expect(repaired, isNotNull);
            expect(
              record.isValidText(repaired!),
              isTrue,
              reason: 'the stored text after the write',
            );
          },
        );
      }
    });
  }

  group('5.10 boundaries and validators', () {
    test('5.10: a fetched record of exactly 16 MiB loads', () async {
      final RcSecFixture fixture = await open(
        RcSecBackend(),
        seed: <String, String>{
          'fetched': paddedJson(_template(), _maxRecordBytes),
        },
      );
      await fixture.remoteConfig.ensureInitialized();
      expect(fixture.remoteConfig.info.fetchedTemplateVersion, 7);
    });

    for (final int millis in <int>[-1, -8640000000000000]) {
      test(
        '5.10 / A27: fetched and active records with fetchTime $millis load',
        () async {
          final Map<String, Object?> record = _with(
            _template(),
            <String, Object?>{'fetchTime': millis},
          );
          final RcSecFixture fixture = await open(
            RcSecBackend(),
            seed: <String, String>{
              'fetched': jsonEncode(record),
              'active': jsonEncode(record),
            },
          );
          await fixture.remoteConfig.ensureInitialized();
          expect(fixture.remoteConfig.info.fetchedTemplateVersion, 7);
          expect(fixture.remoteConfig.info.activeTemplateVersion, 7);
          expect(fixture.remoteConfig.getString('k'), 'stored');
          expect(
            fixture.logs.where((String line) => line.contains('stored')),
            isEmpty,
          );
        },
      );
    }

    test(
      '5.10 / A27: a meta record with lastSuccessfulFetchTime -5 loads with that time',
      () async {
        final RcSecFixture fixture = await open(
          RcSecBackend(),
          seed: <String, String>{
            'meta': jsonEncode(
              _with(_validMeta, <String, Object?>{
                'lastSuccessfulFetchTime': -5,
              }),
            ),
          },
        );
        await fixture.remoteConfig.ensureInitialized();
        expect(
          fixture.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.success,
        );
        expect(
          fixture.remoteConfig.info.lastSuccessfulFetchTime,
          DateTime.fromMillisecondsSinceEpoch(-5, isUtc: true),
        );
      },
    );

    test(
      '5.10: every record bad at once → defaults, no throw, fetch and activate work',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(
          backend,
          seed: <String, String>{
            for (final String name in const <String>[
              'fetched',
              'active',
              'meta',
              'throttle',
              'signals',
            ])
              name: '{',
          },
        );
        await fixture.remoteConfig.ensureInitialized();
        expect(fixture.remoteConfig.getString('k'), 'default');
        expect(await fixture.remoteConfig.fetchAndActivate(), isTrue);
        expect(fixture.remoteConfig.getString('k'), 'remote');
      },
    );

    test(
      '5.10 / 5.5: a stored ETag with CR/LF is dropped: no If-None-Match is sent',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(
          backend,
          seed: <String, String>{
            'fetched': jsonEncode(<String, Object?>{
              ..._template(),
              'etag': 'abc\r\nX-Injected: 1',
            }),
          },
        );
        await fixture.remoteConfig.ensureInitialized();
        expect(fixture.remoteConfig.info.fetchedTemplateVersion, 7);
        await fixture.remoteConfig.fetch(minimumFetchInterval: Duration.zero);
        final Map<String, String> headers =
            backend.fetchCalls.single.request.headers;
        expect(
          headers.keys.map((String name) => name.toLowerCase()),
          isNot(contains('if-none-match')),
        );
        expect(
          headers.keys.map((String name) => name.toLowerCase()),
          isNot(contains('x-injected')),
        );
      },
    );

    test(
      '5.10 / 3.4: stored metadata items of the wrong shape are dropped, the record kept',
      () async {
        final RcSecFixture fixture = await open(
          RcSecBackend(),
          seed: <String, String>{
            'active': jsonEncode(<String, Object?>{
              ..._template(),
              'experimentDescriptions': <Object?>[
                <String, Object?>{'experimentId': 1},
                'text',
              ],
              'rolloutMetadata': 'not a list',
              'personalizationMetadata': <String, Object?>{'k': 5},
            }),
          },
        );
        await fixture.remoteConfig.ensureInitialized();
        expect(fixture.remoteConfig.getString('k'), 'stored');
      },
    );
  });

  group('5.10 over a FileKeyValueStore', () {
    late Directory directory;
    late FileKeyValueStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('rc_sec_store_');
      store = FileKeyValueStore(directory.path);
    });

    tearDown(() async {
      await store.close();
      directory.deleteSync(recursive: true);
    });

    /// Writes [text] for the record [name] of an app called [appName], and returns its file.
    Future<File> seedFile(String appName, String name, String text) async {
      final RcSecFixture probe = await RcSecFixture.open(
        backend: RcSecBackend(),
        store: _NonClosingStore(store),
        name: appName,
      );
      final String key = probe.key(
        name,
      ); // before dispose(), which deletes the app
      await probe.dispose();
      await store.write(key, text);
      final List<File> files = directory
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('.json'))
          .toList();
      return files.single;
    }

    test(
      '5.10: a fetched record of 0xFF bytes on disk (not UTF-8) → absent; the next fetch repairs',
      () async {
        final File file = await seedFile(
          'rc-sec-file-a',
          'fetched',
          jsonEncode(_template()),
        );
        file.writeAsBytesSync(<int>[0xff, 0xfe, 0xfd, 0x7b, 0xff], flush: true);
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await RcSecFixture.open(
          backend: backend,
          store: _NonClosingStore(store),
          name: 'rc-sec-file-a',
        );
        fixtures.add(fixture);
        await fixture.remoteConfig.ensureInitialized();
        expect(fixture.remoteConfig.info.fetchedTemplateVersion, isNull);
        expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
        expect(
          TemplateRecord.tryParse(
            utf8.decode(file.readAsBytesSync()),
          )?.templateVersion,
          1,
        );
      },
    );

    test('5.10: an active record file over 16 MiB → absent', () async {
      final File file = await seedFile(
        'rc-sec-file-b',
        'active',
        jsonEncode(_template()),
      );
      file.writeAsStringSync(
        paddedJson(_template(), _maxRecordBytes + 1),
        flush: true,
      );
      final RcSecFixture fixture = await RcSecFixture.open(
        backend: RcSecBackend(),
        store: _NonClosingStore(store),
        name: 'rc-sec-file-b',
      );
      fixtures.add(fixture);
      await fixture.remoteConfig.ensureInitialized();
      expect(fixture.remoteConfig.getString('k'), 'default');
      expect(fixture.remoteConfig.info.activeTemplateVersion, isNull);
    });
  });
}

/// Passes every call to a store that the group closes itself.
final class _NonClosingStore implements KeyValueStore {
  _NonClosingStore(this._inner);

  final KeyValueStore _inner;

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String? value) => _inner.write(key, value);

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => _inner.update(key, transform);

  @override
  Stream<String> get changes => _inner.changes;

  @override
  Future<void> close() async {}
}
