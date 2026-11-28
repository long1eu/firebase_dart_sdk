@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/rc_sec_harness.dart';

/// Server text that repeats every secret, as a hostile or echoing server would.
const String _echo =
    'echo $authTokenSentinel $refreshTokenSentinel $apiKeySentinel $signalKeySentinel '
    '$signalValueSentinel';

/// An error body that echoes every secret.
Map<String, Object?> _errorBody(int status) => <String, Object?>{
  'error': <String, Object?>{
    'code': status,
    'status': 'ECHO',
    'message': _echo,
  },
};

/// Fails when a sentinel appears in [text].
void _expectNoSentinel(String text, String where) {
  for (final String sentinel in allSentinels) {
    expect(text, isNot(contains(sentinel)), reason: '$where holds $sentinel');
  }
}

/// Checks [error] (its message, its `toString`, and a Firebase exception it wraps) and [logs].
void _expectClean(Object? error, List<String> logs) {
  for (final String line in logs) {
    _expectNoSentinel(line, 'the log line "$line"');
  }
  if (error == null) {
    return;
  }
  _expectNoSentinel(error.toString(), 'toString');
  if (error is FirebaseRemoteConfigException) {
    _expectNoSentinel(error.message ?? '', 'message');
    final Object? cause = error.cause;
    // SPEC: 5.11 rule 6 (no toString holds a token; server text only as serverMessage); code:
    // FirebaseInstallationsException.toString appends serverMessage, so an Installations error
    // body that echoes a token reaches the toString of the installations-error cause.
    if (cause is FirebaseRemoteConfigException ||
        cause is FirebaseInstallationsException) {
      _expectNoSentinel(cause.toString(), 'the cause');
    }
  }
  if (error is FirebaseInstallationsException) {
    _expectNoSentinel(error.message ?? '', 'message');
  }
  if (error is ArgumentError) {
    _expectNoSentinel('${error.message}', 'the ArgumentError message');
    _expectNoSentinel('${error.invalidValue}', 'the ArgumentError value');
  }
}

void main() {
  final List<RcSecFixture> fixtures = <RcSecFixture>[];

  /// A fixture whose fetch body carries the signal sentinels.
  Future<RcSecFixture> open(
    RcSecBackend backend, {
    KeyValueStore? store,
  }) async {
    final RcSecFixture fixture = await RcSecFixture.open(
      backend: backend,
      store: store,
    );
    fixtures.add(fixture);
    await fixture.remoteConfig.setCustomSignals(<String, Object?>{
      signalKeySentinel: signalValueSentinel,
    });
    return fixture;
  }

  tearDown(() async {
    for (final RcSecFixture fixture in fixtures) {
      await fixture.dispose();
    }
    fixtures.clear();
  });

  test(
    '5.11 rule 6: the fetch request does carry the sentinels (control)',
    () async {
      final RcSecBackend backend = RcSecBackend();
      final RcSecFixture fixture = await open(backend);
      await fixture.remoteConfig.fetch();
      final String sent = backend.fetchCalls.single.everything;
      expect(sent, contains(authTokenSentinel));
      expect(sent, contains(apiKeySentinel));
      expect(sent, contains(signalKeySentinel));
      expect(sent, contains(signalValueSentinel));
    },
  );

  group('5.11 rule 6: fetch failures', () {
    for (final int status in <int>[400, 401, 403, 404, 409, 429, 500, 503]) {
      test(
        '5.11 rule 6: HTTP $status echoing the secrets → no sentinel in message, toString or logs',
        () async {
          final RcSecBackend backend = RcSecBackend(
            onFetch: (RcSecCall call) =>
                jsonResponse(call, status, _errorBody(status)),
          );
          final RcSecFixture fixture = await open(backend);
          final FirebaseRemoteConfigException error = await rcErrorOf(
            fixture.remoteConfig.fetch,
          );
          expect(error.code, status == 429 ? 'fetch-throttle' : 'fetch-status');
          expect(error.httpStatus, status);
          // Server text reaches callers only as serverMessage.
          expect(error.serverMessage, _echo);
          _expectClean(error, fixture.logs);
        },
      );
    }

    test('5.11 rule 6: a non-JSON 200 body echoing the secrets', () async {
      final RcSecBackend backend = RcSecBackend(
        onFetch: (RcSecCall call) =>
            textResponse(call, 200, '<html>$_echo</html>'),
      );
      final RcSecFixture fixture = await open(backend);
      final FirebaseRemoteConfigException error = await rcErrorOf(
        fixture.remoteConfig.fetch,
      );
      expect(error.code, 'fetch-client-parse');
      _expectClean(error, fixture.logs);
    });

    test('5.11 rule 6: a non-JSON error body echoing the secrets', () async {
      final RcSecBackend backend = RcSecBackend(
        onFetch: (RcSecCall call) =>
            textResponse(call, 502, 'Bad gateway: $_echo'),
      );
      final RcSecFixture fixture = await open(backend);
      final FirebaseRemoteConfigException error = await rcErrorOf(
        fixture.remoteConfig.fetch,
      );
      expect(error.httpStatus, 502);
      _expectClean(error, fixture.logs);
    });

    test('5.11 rule 6: a timeout', () async {
      final RcSecBackend backend = RcSecBackend(onFetch: pendingResponse);
      final RcSecFixture fixture = await open(backend);
      final FirebaseRemoteConfigException error = await rcErrorOf(
        () => fixture.remoteConfig.fetch(
          timeout: const Duration(milliseconds: 50),
        ),
      );
      expect(error.code, 'fetch-timeout');
      _expectClean(error, fixture.logs);
    });

    test(
      '5.11 rule 6: a 3xx whose Location carries the secrets in a query',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) => textResponse(
            call,
            302,
            _echo,
            headers: <String, String>{
              'location':
                  'https://elsewhere.test/?key=$apiKeySentinel&token=$authTokenSentinel',
            },
          ),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.httpStatus, 302);
        _expectClean(error, fixture.logs);
      },
    );

    test(
      '5.11 rule 6: a transport error whose uri has a query is kept as cause, never interpolated',
      () async {
        final Uri leakyUri = Uri.parse(
          'https://rc.test/v1?key=$apiKeySentinel&t=$authTokenSentinel',
        );
        final http.ClientException transport = http.ClientException(
          'reset by $_echo',
          leakyUri,
        );
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) => throw transport,
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-network');
        expect(error.cause, same(transport));
        _expectClean(error, fixture.logs);
      },
    );

    for (final int status in <int>[400, 403, 500]) {
      test(
        '5.11 rule 6: Installations answering $status with the secrets → installations-error',
        () async {
          final RcSecBackend backend = RcSecBackend(
            onInstallations: (RcSecCall call) =>
                jsonResponse(call, status, _errorBody(status)),
          );
          final RcSecFixture fixture = await open(backend);
          final FirebaseRemoteConfigException error = await rcErrorOf(
            fixture.remoteConfig.fetch,
          );
          expect(error.code, 'installations-error');
          expect(error.cause, isA<FirebaseInstallationsException>());
          _expectClean(error, fixture.logs);
        },
      );
    }
  });

  group('5.11 rule 6: store failures', () {
    test(
      '5.11 rule 6 / 5.10: failed writes: setCustomSignals and activate throw storage-error, fetch '
      'continues; nothing leaks',
      () async {
        final RcSecFlakyStore store = RcSecFlakyStore(
          error: () => _StoreFailure('disk full: $_echo'),
        );
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(backend, store: store);
        store.failRemoteConfigWrites = true;

        final FirebaseRemoteConfigException signals = await rcErrorOf(
          () => fixture.remoteConfig.setCustomSignals(<String, Object?>{
            '${signalKeySentinel}2': '${signalValueSentinel}2',
          }),
        );
        expect(signals.code, 'storage-error');
        _expectClean(signals, fixture.logs);
        expect(fixture.remoteConfig.customSignals, <String, String>{
          signalKeySentinel: signalValueSentinel,
        });

        expect(await fixture.remoteConfig.fetch(), FetchResult.updated);

        final FirebaseRemoteConfigException activate = await rcErrorOf(
          fixture.remoteConfig.activate,
        );
        expect(activate.code, 'storage-error');
        _expectClean(activate, fixture.logs);
        expect(
          fixture.logs,
          isNotEmpty,
          reason: 'the failed writes are logged',
        );
      },
    );

    test(
      '5.11 rule 6: a store that cannot be read at start → storage-error from ensureInitialized',
      () async {
        final RcSecFixture fixture = await RcSecFixture.open(
          backend: RcSecBackend(),
          store: _UnreadableStore(),
        );
        fixtures.add(fixture);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.ensureInitialized,
        );
        expect(error.code, 'storage-error');
        _expectClean(error, fixture.logs);
      },
    );
  });

  group('5.11 rule 6: realtime failures', () {
    for (final int status in <int>[400, 403, 404]) {
      test(
        '5.9.1 / 5.11 rule 6: a non-retryable $status echoing the secrets → stream-error',
        () async {
          final RcSecBackend backend = RcSecBackend(
            onRealtime: (RcSecCall call) =>
                jsonResponse(call, status, _errorBody(status)),
          );
          final RcSecFixture fixture = await open(backend);
          final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
          addTearDown(probe.cancel);
          final FirebaseRemoteConfigException error = await probe.firstError();
          expect(error.code, 'stream-error');
          expect(error.httpStatus, status);
          expect(error.serverMessage, _echo);
          _expectClean(error, fixture.logs);
        },
      );
    }

    test(
      '5.9 / 5.11 rule 6: an invalid message echoing the secrets → update-message-invalid',
      () async {
        final RcSecBackend backend = RcSecBackend();
        backend.onRealtime = (RcSecCall call) =>
            backend.realtimeCalls.length == 1
            ? http.StreamedResponse(
                abortable(
                  call,
                  Stream<List<int>>.value(
                    utf8.encode(
                      '{"latestTemplateVersionNumber": "$authTokenSentinel"}',
                    ),
                  ),
                ),
                200,
                request: call.request,
              )
            : silentStream(call);
        final RcSecFixture fixture = await open(backend);
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'update-message-invalid');
        _expectClean(error, fixture.logs);
      },
    );

    test(
      '5.9.2 / 5.11 rule 6: the auto-fetch failing with an echoing 500 → update-not-fetched',
      () async {
        final StreamController<List<int>> realtime =
            StreamController<List<int>>();
        addTearDown(realtime.close);
        final RcSecBackend backend = RcSecBackend(
          onRealtime: (RcSecCall call) => http.StreamedResponse(
            abortable(call, realtime.stream),
            200,
            request: call.request,
          ),
          onFetch: (RcSecCall call) => jsonResponse(call, 500, _errorBody(500)),
        );
        final RcSecFixture fixture = await open(backend);
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );
        realtime.add(utf8.encode('{"latestTemplateVersionNumber": "9"}'));
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'update-not-fetched');
        _expectClean(error, fixture.logs);
      },
    );

    test(
      '5.9.1 / 5.11 rule 6: Installations bad-config while connecting → stream-error',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onInstallations: (RcSecCall call) =>
              jsonResponse(call, 400, _errorBody(400)),
        );
        final RcSecFixture fixture = await open(backend);
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'stream-error');
        _expectClean(error, fixture.logs);
      },
    );
  });

  group(
    '5.11 rule 6 / 5.8: custom signal limit errors never print the key or value',
    () {
      final Map<String, Map<String, Object?>> bad =
          <String, Map<String, Object?>>{
            'a key of 251 characters': <String, Object?>{
              signalKeySentinel.padRight(251, 'k'): 'v',
            },
            'a value of 501 characters': <String, Object?>{
              'k': signalValueSentinel.padRight(501, 'v'),
            },
            'a list value': <String, Object?>{
              signalKeySentinel: <String>[signalValueSentinel],
            },
            'a NaN value': <String, Object?>{signalKeySentinel: double.nan},
            'an object value': <String, Object?>{signalKeySentinel: _Leaky()},
            'more than 100 signals': <String, Object?>{
              for (int i = 0; i < 101; i++)
                '$signalKeySentinel$i': signalValueSentinel,
            },
          };
      for (final MapEntry<String, Map<String, Object?>> entry in bad.entries) {
        test(
          '5.8 / 5.11 rule 6: ${entry.key} → ArgumentError without the text',
          () async {
            final RcSecFixture fixture = await open(RcSecBackend());
            final Object error = await thrownBy(
              () => fixture.remoteConfig.setCustomSignals(entry.value),
            );
            expect(error, isA<ArgumentError>());
            _expectClean(error, fixture.logs);
            expect(fixture.remoteConfig.customSignals, <String, String>{
              signalKeySentinel: signalValueSentinel,
            });
          },
        );
      }
    },
  );

  group('5.11 rule 6: records, values and the success path', () {
    test('5.11 rule 6: records print <redacted>', () {
      final List<Object> records = <Object>[
        TemplateRecord(
          entries: const <String, String>{signalKeySentinel: authTokenSentinel},
          fetchTime: rcSecNow,
          etag: refreshTokenSentinel,
        ),
        SignalsRecord(const <String, String>{
          signalKeySentinel: signalValueSentinel,
        }),
        const MetaRecord(),
        const ThrottleRecord(),
      ];
      for (final Object record in records) {
        expect(record.toString(), contains('<redacted>'));
        _expectNoSentinel(record.toString(), '${record.runtimeType}.toString');
      }
    });

    test(
      '5.11 rule 6: a full success path (fetch, activate, realtime, auto-fetch) logs no secret',
      () async {
        final StreamController<List<int>> realtime =
            StreamController<List<int>>();
        addTearDown(realtime.close);
        final RcSecBackend backend = RcSecBackend(
          onRealtime: (RcSecCall call) => http.StreamedResponse(
            abortable(call, realtime.stream),
            200,
            request: call.request,
          ),
          onFetch: (RcSecCall call) => templateResponse(
            call,
            entries: <String, String>{'k': authTokenSentinel},
            version: '3',
            headers: <String, String>{'etag': 'etag-1'},
          ),
        );
        final RcSecFixture fixture = await open(backend);
        expect(await fixture.remoteConfig.fetchAndActivate(), isTrue);
        expect(
          fixture.remoteConfig.info.toString(),
          isNot(contains(authTokenSentinel)),
        );
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );
        realtime.add(utf8.encode('{"latestTemplateVersionNumber": "3"}'));
        backend.onFetch = (RcSecCall call) => templateResponse(
          call,
          entries: <String, String>{
            'k': authTokenSentinel,
            'other': signalValueSentinel,
          },
          version: '4',
        );
        realtime.add(utf8.encode('{"latestTemplateVersionNumber": "4"}'));
        await waitUntil(
          () => probe.updates.isNotEmpty,
          reason: 'the realtime update',
        );
        expect(probe.updates.single.toString(), isNot(contains('other')));
        _expectClean(null, fixture.logs);
      },
    );
  });
}

/// A store failure whose text holds secrets.
final class _StoreFailure implements Exception {
  _StoreFailure(this.text);

  final String text;

  @override
  String toString() => 'StoreFailure: $text';
}

/// A store whose reads fail with secrets in the text.
final class _UnreadableStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async =>
      throw _StoreFailure('cannot read: $_echo');

  @override
  Future<void> write(String key, String? value) async =>
      throw _StoreFailure('cannot write: $_echo');

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async => throw _StoreFailure('cannot update: $_echo');

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() async {}
}

/// A value whose text is a secret.
final class _Leaky {
  @override
  String toString() => signalValueSentinel;
}
