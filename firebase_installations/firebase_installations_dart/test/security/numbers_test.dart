// Spec v4 5.11 rule 9 for Installations: parseBoundedInt, the expiresIn of the server, numbers read
// from the store, and times far in the future. Runs on the VM and in the browser (no dart:io).
library;

import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/src/bounded.dart';
import 'package:firebase_installations_dart/src/record.dart';
import 'package:test/test.dart';

import '../support/fis_sec_support.dart';

/// 2^53 - 1, the largest integer every platform holds exactly.
const int _maxSafe = 9007199254740991;

/// The last millisecond of the year 9999, the largest time a record may hold.
const int _maxEpochMillis = 253402300799999;

final class _Case {
  const _Case(
    this.label,
    this.value,
    this.expected, {
    this.min = 0,
    this.max = 1000,
    this.spec,
  });

  final String label;
  final Object? value;
  final int? expected;
  final int min;
  final int max;

  /// A note when the code is known to differ from the spec for this case.
  final String? spec;
}

void main() {
  group('5.11 rule 9 parseBoundedInt', () {
    final List<_Case> cases = <_Case>[
      const _Case('integer inside', 5, 5),
      const _Case('integer at min', 0, 0),
      const _Case('integer at max', 1000, 1000),
      const _Case('integer above max', 1001, null),
      const _Case('integer below min', -1, null),
      const _Case(
        'negative integer inside a negative range',
        -5,
        -5,
        min: -10,
        max: 10,
      ),
      const _Case('integral double', 5.0, 5),
      const _Case('fraction', 5.5, null),
      const _Case('small fraction', 0.000001, null),
      const _Case('NaN', double.nan, null),
      const _Case('infinity', double.infinity, null),
      const _Case('negative infinity', double.negativeInfinity, null),
      const _Case('digit string inside', '5', 5),
      const _Case('digit string at min', '0', 0),
      const _Case('digit string at max', '1000', 1000),
      const _Case('digit string above max', '1001', null),
      const _Case('leading zeros', '0007', 7),
      const _Case('string fraction', '5.0', null),
      const _Case('string exponent', '1e3', null, max: 100000),
      const _Case('string upper exponent', '1E3', null, max: 100000),
      const _Case('string minus', '-5', null, min: -10, max: 10),
      const _Case('string plus', '+5', null),
      const _Case('string hex', '0x10', null),
      const _Case('string binary', '0b1', null),
      const _Case('leading space', ' 5', null),
      const _Case('trailing space', '5 ', null),
      const _Case('trailing newline', '5\n', null),
      const _Case('tab', '\t5', null),
      const _Case('empty string', '', null),
      const _Case('space only', ' ', null),
      const _Case('underscore separator', '1_000', null, max: 100000),
      const _Case('comma separator', '1,000', null, max: 100000),
      const _Case('Arabic-Indic digits', '١٢', null),
      const _Case('full-width digit', '５', null),
      const _Case('string NaN', 'NaN', null),
      const _Case('string Infinity', 'Infinity', null),
      const _Case('null', null, null),
      const _Case('true', true, null),
      const _Case('false', false, null),
      const _Case('list', <int>[5], null),
      const _Case('map', <String, int>{'v': 5}, null),
      const _Case(
        '15-digit string',
        '999999999999999',
        999999999999999,
        max: _maxSafe,
      ),
      const _Case('2^53 - 1 as a number', _maxSafe, _maxSafe, max: _maxSafe),
      const _Case(
        '2^53 as a number above max',
        9007199254740992.0,
        null,
        max: _maxSafe,
      ),
      const _Case('1e300 as a number', 1e300, null, max: _maxSafe),
      // 5.11 rule 9 and A7: up to 16 digits are accepted (next two cases).
      const _Case(
        '16-digit string inside the range',
        '1000000000000000',
        1000000000000000,
        max: _maxSafe,
        spec:
            '5.11 rule 9; A7 accepts up to 16 digits; longer digit strings are refused',
      ),
      const _Case(
        '16-digit string with leading zeros',
        '0000000000000042',
        42,
        max: _maxSafe,
        spec:
            '5.11 rule 9; A7 accepts up to 16 digits; longer digit strings are refused',
      ),
      _Case('1000 digits', '1' * 1000, null, max: _maxSafe),
    ];
    for (final _Case c in cases) {
      test(
        '5.11 rule 9: ${c.label} (${c.value is String ? jsonEncode(c.value) : c.value}) in [${c.min}, ${c.max}] '
        'gives ${c.expected}',
        () {
          // SPEC notes (when present) name a case where the code differs from the spec.
          expect(
            parseBoundedInt(c.value, min: c.min, max: c.max),
            c.expected,
            reason: c.spec,
          );
        },
      );
    }

    test('5.11 rule 9: JSON 1e400 decodes to infinity and gives null', () {
      expect(
        parseBoundedInt(jsonDecode('1e400'), min: 0, max: _maxSafe),
        isNull,
      );
      expect(
        parseBoundedInt(jsonDecode('-1e400'), min: -_maxSafe, max: _maxSafe),
        isNull,
      );
    });

    test(
      '5.11 rule 9: JSON 2147483647 is read exactly; 2147483648 is out of a 32-bit range',
      () {
        expect(
          parseBoundedInt(jsonDecode('2147483647'), min: 0, max: 2147483647),
          2147483647,
        );
        expect(
          parseBoundedInt(jsonDecode('2147483648'), min: 0, max: 2147483647),
          isNull,
        );
      },
    );
  });

  group('5.3 / 5.11 rule 9 expiresIn of generate', () {
    const Map<String, Duration> accepted = <String, Duration>{
      '1s': Duration(seconds: 1),
      '3600s': Duration(hours: 1),
      '604800s': Duration(days: 7),
      '34560000s': Duration(days: 400),
      '000000001s': Duration(seconds: 1),
    };
    for (final MapEntry<String, Duration> entry in accepted.entries) {
      test(
        '5.3: expiresIn "${entry.key}" is accepted as ${entry.value}',
        () async {
          final FirebaseApp app = fisSecApp();
          final MemoryKeyValueStore store = MemoryKeyValueStore();
          final FisSecClient client = FisSecClient(
            (FisSecRequest r) => r.route == 'generate'
                ? fisSecGenerateOk(
                    token: '${fisSecAuthToken}2',
                    expiresIn: entry.key,
                  )
                : fisSecHappyHandler()(r),
          );
          final FirebaseInstallations installations = fisSecInstallations(
            app,
            store: store,
            client: client,
          );
          await installations.getToken();
          expect(
            await installations.getToken(forceRefresh: true),
            '${fisSecAuthToken}2',
          );
          final InstallationRecord record = InstallationRecord.tryParse(
            await store.read(fisSecRecordKey(app)),
          )!;
          expect(record.tokenExpiresIn, entry.value);
        },
      );
    }

    final Map<String, Object?> refused = <String, Object?>{
      'zero': '0s',
      '400 days + 1 s': '34560001s',
      '9 digits over 400 days': '999999999s',
      '10 digits': '1234567890s',
      'empty': '',
      'unit only': 's',
      'no unit': '3600',
      'upper-case unit': '3600S',
      'milliseconds unit': '3600ms',
      'fraction': '3600.5s',
      'integral fraction': '3600.0s',
      'minus': '-3600s',
      'plus': '+3600s',
      'leading space': ' 3600s',
      'trailing space': '3600s ',
      'inner space': '3600 s',
      'trailing newline': '3600s\n',
      'exponent': '1e3s',
      'hex': '0x10s',
      'Arabic-Indic digit': '٣s',
      'a JSON number': 3600,
      'a JSON double': 3600.0,
      'null': null,
      'true': true,
      'a list': <String>['3600s'],
      'an object': <String, Object?>{'seconds': 3600},
    };
    for (final MapEntry<String, Object?> entry in refused.entries) {
      test(
        '5.3: generate expiresIn ${entry.key} (${jsonEncode(entry.value)}) is invalid-response, nothing stored',
        () async {
          final FirebaseApp app = fisSecApp();
          final MemoryKeyValueStore store = MemoryKeyValueStore();
          final FisSecClient client = FisSecClient(
            (FisSecRequest r) => r.route == 'generate'
                ? fisSecGenerateOk(
                    token: '${fisSecAuthToken}2',
                    expiresIn: entry.value,
                  )
                : fisSecHappyHandler()(r),
          );
          final FirebaseInstallations installations = fisSecInstallations(
            app,
            store: store,
            client: client,
          );
          await installations.getToken();
          await expectLater(
            installations.getToken(forceRefresh: true),
            throwsFisCode('invalid-response'),
          );
          final InstallationRecord record = InstallationRecord.tryParse(
            await store.read(fisSecRecordKey(app)),
          )!;
          expect(record.token, fisSecAuthToken);
          expect(record.tokenExpiresIn, const Duration(days: 7));
        },
      );
    }

    for (final Object? value in <Object?>['0s', '34560001s', 3600, '3600']) {
      test(
        '5.3: create expiresIn ${jsonEncode(value)} is invalid-response and nothing is registered',
        () async {
          final FirebaseApp app = fisSecApp();
          final MemoryKeyValueStore store = MemoryKeyValueStore();
          final FisSecClient client = FisSecClient(
            (FisSecRequest r) => fisSecCreateOk(expiresIn: value),
          );
          final FirebaseInstallations installations = fisSecInstallations(
            app,
            store: store,
            client: client,
          );
          await expectLater(
            installations.getToken(),
            throwsFisCode('invalid-response'),
          );
          final InstallationRecord? record = InstallationRecord.tryParse(
            await store.read(fisSecRecordKey(app)),
          );
          expect(record?.status, isNot(InstallationStatus.registered));
          expect(record?.refreshToken, isNull);
        },
      );
    }
  });

  group('5.11 rule 9 numbers read from the store', () {
    final int nowMillis = fisSecNow.millisecondsSinceEpoch;

    /// Stores [json] (or [raw] text) for a new app and returns the FID getId answers: fisSecServerFid
    /// when the record was read, fisSecFid when it counted as absent.
    Future<String> idFor({Map<String, Object?>? json, String? raw}) async {
      final FirebaseApp app = fisSecApp();
      final MemoryKeyValueStore store = MemoryKeyValueStore();
      await store.write(fisSecRecordKey(app), raw ?? jsonEncode(json));
      final FirebaseInstallations installations = fisSecInstallations(
        app,
        store: store,
        client: FisSecClient(fisSecHappyHandler()),
      );
      return installations.getId();
    }

    Map<String, Object?> registered() =>
        fisSecRegisteredJson()..['fid'] = fisSecServerFid;

    final Map<String, Object?> goodTimes = <String, Object?>{
      'now as an integer': nowMillis,
      'now as a digit string': '$nowMillis',
      'zero': 0,
      'the end of year 9999': _maxEpochMillis,
    };
    for (final MapEntry<String, Object?> entry in goodTimes.entries) {
      test('5.11 rule 9: stored tokenCreatedAt ${entry.key} is read', () async {
        expect(
          await idFor(json: registered()..['tokenCreatedAt'] = entry.value),
          fisSecServerFid,
        );
      });
    }

    final Map<String, Object?> badTimes = <String, Object?>{
      'negative': -1,
      'fraction': nowMillis + 0.5,
      'exponent string': '1.7e12',
      'signed string': '-1',
      'string with a space': ' $nowMillis',
      'after year 9999': _maxEpochMillis + 1,
      'a word': 'yesterday',
      'true': true,
      'a list': <int>[nowMillis],
    };
    for (final MapEntry<String, Object?> entry in badTimes.entries) {
      test(
        '5.11 rule 9: stored tokenCreatedAt ${entry.key} makes the record absent',
        () async {
          expect(
            await idFor(json: registered()..['tokenCreatedAt'] = entry.value),
            fisSecFid,
          );
        },
      );
    }

    test(
      '5.11 rule 9: stored tokenCreatedAt 1e400 (infinity) makes the record absent',
      () async {
        final String raw = jsonEncode(
          registered()..['tokenCreatedAt'] = 1234,
        ).replaceFirst('1234', '1e400');
        expect(await idFor(raw: raw), fisSecFid);
      },
    );

    final Map<String, Object?> expiresIn = <String, Object?>{
      '1 s': 1000,
      '400 days': 34560000000,
      '1 s as a digit string': '1000',
    };
    for (final MapEntry<String, Object?> entry in expiresIn.entries) {
      test('5.11 rule 9: stored tokenExpiresIn ${entry.key} is read', () async {
        expect(
          await idFor(json: registered()..['tokenExpiresIn'] = entry.value),
          fisSecServerFid,
        );
      });
    }

    final Map<String, Object?> badExpiresIn = <String, Object?>{
      'zero': 0,
      '999 ms': 999,
      '400 days + 1 ms': 34560000001,
      'negative': -1000,
      'fraction': 1000.5,
      'seconds string': '3600s',
    };
    for (final MapEntry<String, Object?> entry in badExpiresIn.entries) {
      test(
        '5.11 rule 9: stored tokenExpiresIn ${entry.key} makes the record absent',
        () async {
          expect(
            await idFor(json: registered()..['tokenExpiresIn'] = entry.value),
            fisSecFid,
          );
        },
      );
    }

    for (final Object? value in <Object?>[
      -1,
      1.5,
      '0x10',
      _maxEpochMillis + 1,
    ]) {
      test(
        '5.11 rule 9: stored registrationStartedAt ${jsonEncode(value)} makes a registering record absent',
        () async {
          final Map<String, Object?> json = <String, Object?>{
            'v': 1,
            'fid': fisSecServerFid,
            'status': 'registering',
            'registrationStartedAt': value,
          };
          expect(await idFor(json: json), fisSecFid);
        },
      );
    }

    for (final Object? value in <Object?>[-1, 'soon', nowMillis + 0.25]) {
      test(
        '5.11 rule 9: stored tokenRequestStartedAt ${jsonEncode(value)} makes the record absent',
        () async {
          expect(
            await idFor(json: registered()..['tokenRequestStartedAt'] = value),
            fisSecFid,
          );
        },
      );
    }
  });

  group('5.3 / 5.11 rule 9 stored times in the future do not hold', () {
    final DateTime year2100 = DateTime.utc(2100);

    Future<(FisSecClient, FirebaseInstallations)> seeded(
      Map<String, Object?> json,
    ) async {
      final FirebaseApp app = fisSecApp();
      final MemoryKeyValueStore store = MemoryKeyValueStore();
      await store.write(fisSecRecordKey(app), jsonEncode(json));
      final FisSecClient client = FisSecClient(
        (FisSecRequest r) => switch (r.route) {
          'create' => fisSecCreateOk(token: '${fisSecAuthToken}new'),
          'generate' => fisSecGenerateOk(token: '${fisSecAuthToken}new'),
          _ => fisSecJson(200, <String, Object?>{}),
        },
      );
      return (client, fisSecInstallations(app, store: store, client: client));
    }

    test(
      '5.3: a token created in 2100 is not used; getToken asks for a new one',
      () async {
        final (
          FisSecClient client,
          FirebaseInstallations installations,
        ) = await seeded(
          jsonDecode(fisSecRegisteredRecord(tokenCreatedAt: year2100))
              as Map<String, Object?>,
        );
        expect(await installations.getToken(), '${fisSecAuthToken}new');
        expect(client.of('generate'), hasLength(1));
      },
    );

    test('5.3: a token created at the end of year 9999 is not used', () async {
      final Map<String, Object?> json = fisSecRegisteredJson()
        ..['tokenCreatedAt'] = _maxEpochMillis;
      final (FisSecClient client, FirebaseInstallations installations) =
          await seeded(json);
      expect(await installations.getToken(), '${fisSecAuthToken}new');
      expect(client.of('generate'), hasLength(1));
    });

    test(
      '5.3: a registration marker in 2100 is stale; getToken registers at once',
      () async {
        final (
          FisSecClient client,
          FirebaseInstallations installations,
        ) = await seeded(<String, Object?>{
          'v': 1,
          'fid': fisSecServerFid,
          'status': 'registering',
          'registrationStartedAt': year2100.millisecondsSinceEpoch,
        });
        expect(await installations.getToken(), '${fisSecAuthToken}new');
        expect(client.of('create'), hasLength(1));
        expect(
          jsonDecode(client.of('create').single.body),
          containsPair('fid', fisSecServerFid),
        );
      },
    );

    test(
      '5.3: a token marker in 2100 is stale; getToken sends generate at once',
      () async {
        final Map<String, Object?> json =
            jsonDecode(
                  fisSecRegisteredRecord(
                    tokenCreatedAt: fisSecNow.subtract(
                      const Duration(days: 30),
                    ),
                  ),
                )
                as Map<String, Object?>;
        json['tokenRequestStartedAt'] = year2100.millisecondsSinceEpoch;
        final (FisSecClient client, FirebaseInstallations installations) =
            await seeded(json);
        expect(await installations.getToken(), '${fisSecAuthToken}new');
        expect(client.of('generate'), hasLength(1));
      },
    );

    test(
      '5.3: a marker 1 s in the future is still fresh, 1 s + 1 ms is stale',
      () async {
        DateTime now = fisSecNow;
        final FirebaseApp app = fisSecApp();
        final MemoryKeyValueStore store = MemoryKeyValueStore();
        await store.write(
          fisSecRecordKey(app),
          jsonEncode(<String, Object?>{
            'v': 1,
            'fid': fisSecServerFid,
            'status': 'registering',
            'registrationStartedAt': fisSecNow
                .add(const Duration(seconds: 1, milliseconds: 1))
                .millisecondsSinceEpoch,
          }),
        );
        final FisSecClient client = FisSecClient(fisSecHappyHandler());
        final FirebaseInstallations installations = fisSecInstallations(
          app,
          store: store,
          client: client,
          clock: () => now,
        );
        await installations.getToken();
        expect(
          client.of('create'),
          hasLength(1),
          reason: '1 s + 1 ms ahead is stale',
        );

        final FirebaseApp other = fisSecApp();
        await store.write(
          fisSecRecordKey(other),
          jsonEncode(<String, Object?>{
            'v': 1,
            'fid': fisSecServerFid,
            'status': 'registering',
            'registrationStartedAt': fisSecNow
                .add(const Duration(seconds: 1))
                .millisecondsSinceEpoch,
          }),
        );
        final FisSecClient waiting = FisSecClient(fisSecHappyHandler());
        int pauses = 0;
        final FirebaseInstallations second = fisSecInstallations(
          other,
          store: store,
          client: waiting,
          clock: () => now,
          delay: (Duration d) async {
            pauses++;
            // Time moves on while the caller waits; the marker goes stale 15 s after its time.
            now = now.add(d);
          },
        );
        await second.getToken();
        expect(
          pauses,
          greaterThan(0),
          reason: '1 s ahead is fresh: the caller waits first',
        );
        expect(waiting.of('create'), hasLength(1));
      },
    );
  });
}
