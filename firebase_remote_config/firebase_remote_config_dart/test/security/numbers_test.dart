// Runs on the VM and in browsers (dart2js and dart2wasm): no dart:io.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/bounded.dart';
import 'package:firebase_remote_config_dart/src/realtime/framer.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/rc_sec_harness.dart';

/// One row of the `parseBoundedInt` table.
final class _Row {
  const _Row(
    this.label,
    this.value,
    this.expected, {
    this.min = 0,
    this.max = maxSafeInteger,
  });

  final String label;
  final Object? value;
  final int? expected;
  final int min;
  final int max;
}

final List<_Row> _rows = <_Row>[
  const _Row('JSON integer 0', 0, 0),
  const _Row('JSON integer 42', 42, 42),
  const _Row('digit string "42"', '42', 42),
  const _Row('leading zeros "007"', '007', 7),
  const _Row('1.0 (a whole double)', 1.0, 1),
  const _Row('1e3 as a number', 1e3, 1000),
  const _Row('2^53 − 1 as a number', maxSafeInteger, maxSafeInteger),
  const _Row('2^53 − 1 as text', '9007199254740991', maxSafeInteger),
  const _Row('2^53 as text', '9007199254740992', null),
  const _Row('2^53 as a double', 9007199254740992.0, null),
  const _Row('17 digits', '12345678901234567', null),
  const _Row('1.5', 1.5, null),
  const _Row('-1 (below min 0)', -1, null),
  const _Row('"-1"', '-1', null),
  const _Row('"+1"', '+1', null),
  const _Row('" 1"', ' 1', null),
  const _Row('"1 "', '1 ', null),
  const _Row('"\\t1"', '\t1', null),
  const _Row('empty string', '', null),
  const _Row('hex "0x10"', '0x10', null),
  const _Row('exponent text "1e3"', '1e3', null),
  const _Row('fraction text "1.0"', '1.0', null),
  const _Row('Arabic-Indic digit', '١', null),
  const _Row('full-width digit', '１', null),
  const _Row('NaN', double.nan, null),
  const _Row('infinity', double.infinity, null),
  const _Row('-infinity', double.negativeInfinity, null),
  const _Row('true', true, null),
  const _Row('null', null, null),
  const _Row('a list', <int>[1], null),
  const _Row('a map', <String, int>{'a': 1}, null),
  const _Row('min inclusive', 10, 10, min: 10, max: 20),
  const _Row('max inclusive', 20, 20, min: 10, max: 20),
  const _Row('above max', 21, null, min: 10, max: 20),
  const _Row('below min', 9, null, min: 10, max: 20),
  const _Row('"21" above max', '21', null, min: 10, max: 20),
  const _Row('negative number in a negative range', -5, -5, min: -10, max: 0),
  const _Row(
    '"-5" stays refused in a negative range (no signs)',
    '-5',
    null,
    min: -10,
    max: 0,
  ),
  const _Row(
    '2147483647 within int32 bounds',
    2147483647,
    2147483647,
    max: 2147483647,
  ),
  const _Row(
    '2147483648 above int32 bounds',
    2147483648,
    null,
    max: 2147483647,
  ),
];

void main() {
  group(
    '5.11 rule 9: parseBoundedInt, the same on the VM, dart2js and dart2wasm',
    () {
      for (final _Row row in _rows) {
        test('5.11 rule 9: ${row.label} → ${row.expected}', () {
          expect(
            parseBoundedInt(row.value, min: row.min, max: row.max),
            row.expected,
          );
        });
      }

      final Map<String, int?> decoded = <String, int?>{
        '1e400': null,
        '-1e400': null,
        '2147483647': 2147483647,
        '1.0': 1,
        '1e2': 100,
        '-0': 0,
        '0.5': null,
        '9007199254740993': null,
      };
      for (final MapEntry<String, int?> entry in decoded.entries) {
        test(
          '5.11 rule 9: JSON ${entry.key} as decoded by jsonDecode → ${entry.value}',
          () {
            expect(
              parseBoundedInt(
                jsonDecode(entry.key),
                min: 0,
                max: maxSafeInteger,
              ),
              entry.value,
            );
          },
        );
      }
    },
  );

  group('5.9: retryIntervalSeconds and latestTemplateVersionNumber', () {
    // A28: a value above the range clamps to 86400, even past 2^53 − 1.
    final Map<String, int?> retries = <String, int?>{
      '2147483647': 86400,
      '86400': 86400,
      '86401': 86400,
      '"99999999999999999999"': 86400,
      '1e20': 86400,
      '"00000000000000000600"': 600,
      '"000000000000000000000"': null,
      '1e400': null,
      '-5': null,
      '"abc"': null,
      '0': null,
      '1.5': null,
      '"30"': 30,
      '30': 30,
      '"1e3"': null,
      'null': null,
      'true': null,
    };
    for (final MapEntry<String, int?> entry in retries.entries) {
      test(
        '5.9: retryIntervalSeconds ${entry.key} → ${entry.value ?? 'ignored'} (not invalid)',
        () {
          final FramerEvent event = parseRealtimeMessage(
            '{"retryIntervalSeconds": ${entry.key}}',
          );
          expect(event, isA<FramedMessage>());
          expect(
            (event as FramedMessage).message.retryIntervalSeconds,
            entry.value,
          );
        },
      );
    }

    final Map<String, int?> versions = <String, int?>{
      '"5"': 5,
      '5': 5,
      '9007199254740991': maxSafeInteger,
      '"9007199254740992"': null,
      '1e400': null,
      '-1': null,
      '"abc"': null,
      '1.5': null,
      '"0x10"': null,
    };
    for (final MapEntry<String, int?> entry in versions.entries) {
      test(
        '5.9: latestTemplateVersionNumber ${entry.key} → ${entry.value ?? 'update-message-invalid'}',
        () {
          final FramerEvent event = parseRealtimeMessage(
            '{"latestTemplateVersionNumber": ${entry.key}}',
          );
          if (entry.value == null) {
            expect(event, isA<FramedInvalid>());
          } else {
            expect(
              (event as FramedMessage).message.latestTemplateVersion,
              entry.value,
            );
          }
        },
      );
    }

    test(
      '5.9: retryIntervalSeconds 2147483647 is capped at 86400 s before the next connect',
      () {
        fakeAsync((FakeAsync async) {
          final DateTime start = DateTime.utc(2026, 6, 1);
          final RcSecBackend backend = RcSecBackend(
            onRealtime: (RcSecCall call) => http.StreamedResponse(
              Stream<List<int>>.value(
                utf8.encode('[{"retryIntervalSeconds": 2147483647}'),
              ),
              200,
              request: call.request,
            ),
          );
          RcSecFixture? fixture;
          unawaited(
            RcSecFixture.open(
              backend: backend,
              clock: () => start.add(async.elapsed),
            ).then((RcSecFixture opened) => fixture = opened),
          );
          async.flushMicrotasks();
          final StreamSubscription<RemoteConfigUpdate> subscription = fixture!
              .remoteConfig
              .onConfigUpdated
              .listen(null, onError: (Object _) {});
          async.elapse(const Duration(seconds: 1));
          expect(backend.realtimeCalls, hasLength(1));
          // The early end is a transport failure (backoff 0.5 s with the random seam at 0); the server's
          // interval, capped at 86 400 s, decides the next connect.
          async.elapse(const Duration(seconds: 86400 - 3));
          expect(backend.realtimeCalls, hasLength(1));
          async.elapse(const Duration(seconds: 4));
          expect(backend.realtimeCalls, hasLength(2));
          unawaited(subscription.cancel());
          unawaited(fixture!.dispose());
          async.flushMicrotasks();
        });
      },
    );
  });

  group('5.5 Response: templateVersion from the server', () {
    final Map<String, int> accepted = <String, int>{
      '"9007199254740991"': maxSafeInteger,
      '9007199254740991': maxSafeInteger,
      '"0"': 0,
      '3.0': 3,
      '1e2': 100,
    };
    final List<String> refused = <String>[
      '"9007199254740992"',
      '9007199254740992',
      '"-1"',
      '-1',
      '"1e3"',
      '1.5',
      '"0x10"',
      '" 1"',
      '""',
      'true',
      '1e400',
      '{}',
    ];

    Future<RcSecFixture> openWith(String version) {
      return RcSecFixture.open(
        backend: RcSecBackend(
          onFetch: (RcSecCall call) => textResponse(
            call,
            200,
            '{"state":"UPDATE","entries":{},"templateVersion":$version}',
          ),
        ),
      );
    }

    for (final MapEntry<String, int> entry in accepted.entries) {
      test(
        '5.5 / 5.11 rule 9: templateVersion ${entry.key} → ${entry.value}',
        () async {
          final RcSecFixture fixture = await openWith(entry.key);
          addTearDown(fixture.dispose);
          expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
          expect(fixture.remoteConfig.info.fetchedTemplateVersion, entry.value);
        },
      );
    }

    for (final String version in refused) {
      test(
        '5.5 / 5.11 rule 9: templateVersion $version → fetch-client-parse, nothing stored',
        () async {
          final RcSecFixture fixture = await openWith(version);
          addTearDown(fixture.dispose);
          final FirebaseRemoteConfigException error = await rcErrorOf(
            fixture.remoteConfig.fetch,
          );
          expect(error.code, 'fetch-client-parse');
          expect(await fixture.store.read(fixture.key('fetched')), isNull);
        },
      );
    }
  });

  group('5.10: persisted times in 2100', () {
    final int year2100 = DateTime.utc(2100).millisecondsSinceEpoch;

    test('5.10: MetaRecord drops a lastSuccessfulFetchTime later than now', () {
      final MetaRecord? meta = MetaRecord.tryParse(
        jsonEncode(<String, Object?>{
          'v': 1,
          'lastFetchStatus': 'success',
          'lastSuccessfulFetchTime': year2100,
          'staleGeneration': 0,
        }),
        rcSecNow,
      );
      expect(meta, isNotNull);
      expect(meta!.lastSuccessfulFetchTime, isNull);
      expect(meta.lastFetchStatus, RemoteConfigFetchStatus.success);
    });

    test('5.10: ThrottleRecord clamps an until in 2100 to now + 24 h', () {
      final ThrottleRecord? throttle = ThrottleRecord.tryParse(
        jsonEncode(<String, Object?>{'v': 1, 'count': 3, 'until': year2100}),
        rcSecNow,
      );
      expect(throttle!.until, rcSecNow.add(const Duration(hours: 24)));
      expect(throttle.count, 3);
    });

    test(
      '5.10: a stored lastSuccessfulFetchTime in 2100 is absent: the next fetch is not cached',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await RcSecFixture.open(
          backend: backend,
          clock: () => rcSecNow,
          seed: <String, String>{
            'fetched': TemplateRecord(
              entries: const <String, String>{'k': 'stored'},
              fetchTime: rcSecNow.subtract(const Duration(minutes: 1)),
              templateVersion: 1,
            ).encode(),
            'meta': jsonEncode(<String, Object?>{
              'v': 1,
              'lastFetchStatus': 'success',
              'lastSuccessfulFetchTime': year2100,
              'staleGeneration': 0,
            }),
          },
        );
        addTearDown(fixture.dispose);
        await fixture.remoteConfig.ensureInitialized();
        expect(fixture.remoteConfig.info.lastSuccessfulFetchTime, isNull);
        expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
        expect(backend.fetchCalls, hasLength(1));
      },
    );

    test(
      '5.10: a stored throttle until 2100 ends at now + 24 h; fetch fails fast and sends nothing',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await RcSecFixture.open(
          backend: backend,
          clock: () => rcSecNow,
          seed: <String, String>{
            'throttle': jsonEncode(<String, Object?>{
              'v': 1,
              'count': 3,
              'until': year2100,
            }),
          },
        );
        addTearDown(fixture.dispose);
        await fixture.remoteConfig.ensureInitialized();
        final DateTime cap = rcSecNow.add(const Duration(hours: 24));
        expect(fixture.remoteConfig.info.throttledUntil, cap);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-throttle');
        expect(error.throttledUntil, cap);
        expect(backend.calls, isEmpty);
      },
    );
  });
}
