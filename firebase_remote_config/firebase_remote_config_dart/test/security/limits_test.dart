@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/rc_sec_harness.dart';
import '../support/rc_sec_io.dart';

const int _fetchCap = 8 * 1024 * 1024;
const int _errorCap = 16 * 1024;
const int _messageCap = 16 * 1024;

/// A JSON template of exactly [length] bytes: `{"entries":{"k":"aaa…"}}`.
Uint8List _templateOfLength(int length) {
  const String head = '{"entries":{"k":"';
  const String tail = '"}}';
  final int fill = length - head.length - tail.length;
  return Uint8List.fromList(utf8.encode('$head${'a' * fill}$tail'));
}

/// An error body of exactly [length] bytes whose `error.message` is `"aaa…"`.
Uint8List _errorOfLength(int length) {
  const String head = '{"error":{"code":500,"status":"INTERNAL","message":"';
  const String tail = '"}}';
  final int fill = length - head.length - tail.length;
  return Uint8List.fromList(utf8.encode('$head${'a' * fill}$tail'));
}

void main() {
  final List<RcSecFixture> fixtures = <RcSecFixture>[];

  Future<RcSecFixture> open(RcSecBackend backend) async {
    final RcSecFixture fixture = await RcSecFixture.open(backend: backend);
    fixtures.add(fixture);
    return fixture;
  }

  tearDown(() async {
    for (final RcSecFixture fixture in fixtures) {
      await fixture.dispose();
    }
    fixtures.clear();
  });

  group('5.11 rule 7: endless bodies stop at each cap', () {
    test(
      '5.11 rule 7: an endless 200 fetch body stops at 8 MiB → fetch-client-parse',
      () async {
        final EndlessBody body = EndlessBody(Uint8List(64 * 1024));
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) => body.response(call, 200),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-parse');
        await waitUntil(
          () => body.cancelled,
          reason: 'the client to stop reading',
        );
        expect(body.emitted, lessThanOrEqualTo(_fetchCap + 2 * 64 * 1024));
        expect(fixture.remoteConfig.info.fetchedTemplateVersion, isNull);
        expect(await fixture.store.read(fixture.key('fetched')), isNull);
      },
    );

    test('5.11 rule 7: a 200 fetch body of exactly 8 MiB is read', () async {
      final RcSecBackend backend = RcSecBackend(
        onFetch: (RcSecCall call) =>
            bytesResponse(call, 200, _templateOfLength(_fetchCap)),
      );
      final RcSecFixture fixture = await open(backend);
      expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
    });

    test(
      '5.11 rule 7: a 200 fetch body of 8 MiB + 1 byte → fetch-client-parse',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) =>
              bytesResponse(call, 200, _templateOfLength(_fetchCap + 1)),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-parse');
      },
    );

    for (final int status in <int>[400, 500, 503]) {
      test(
        '5.11 rule 7: an endless $status fetch body stops at 16 KiB; the status stays',
        () async {
          final EndlessBody body = EndlessBody(Uint8List(1024));
          final RcSecBackend backend = RcSecBackend(
            onFetch: (RcSecCall call) => body.response(call, status),
          );
          final RcSecFixture fixture = await open(backend);
          final FirebaseRemoteConfigException error = await rcErrorOf(
            fixture.remoteConfig.fetch,
          );
          expect(error.code, 'fetch-status');
          expect(error.httpStatus, status);
          expect(error.serverMessage, isNull);
          await waitUntil(
            () => body.cancelled,
            reason: 'the client to stop reading',
          );
          expect(body.emitted, lessThanOrEqualTo(_errorCap + 2 * 1024));
        },
      );
    }

    test(
      '5.11 rule 7: an error body of exactly 16 KiB is parsed; its message is cut at 1 KiB',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) =>
              bytesResponse(call, 500, _errorOfLength(_errorCap)),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.httpStatus, 500);
        expect(error.serverStatus, 'INTERNAL');
        expect(error.serverMessage, 'a' * 1024);
      },
    );

    test(
      '5.11 rule 7: an error body of 16 KiB + 1 byte is cut (not JSON any more); the status stays',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) =>
              bytesResponse(call, 500, _errorOfLength(_errorCap + 1)),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-status');
        expect(error.httpStatus, 500);
        expect(error.serverMessage, isNull);
      },
    );

    test(
      '5.11 rule 6: serverMessage is at most 1 KiB of UTF-8, cut at a character, no controls',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) =>
              jsonResponse(call, 400, <String, Object?>{
                'error': <String, Object?>{
                  'message': 'line\none\u0000\u0085${'é' * 4000}',
                },
              }),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        final String message = error.serverMessage!;
        expect(utf8.encode(message).length, lessThanOrEqualTo(1024));
        expect(message, startsWith('lineone'));
        expect(
          message.runes.where(
            (int rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f),
          ),
          isEmpty,
        );
        expect(message.endsWith('é'), isTrue);
      },
    );

    test(
      '5.9 / 5.11 rule 7: an endless realtime message stops at 16 KiB → one update-message-invalid',
      () async {
        final EndlessBody body = EndlessBody(
          utf8.encode('a' * 1024),
          prefix: utf8.encode('{'),
        );
        final RcSecBackend backend = RcSecBackend();
        // Later connections (after the backoff) stay silent.
        backend.onRealtime = (RcSecCall call) =>
            backend.realtimeCalls.length == 1
            ? body.response(call, 200)
            : silentStream(call);
        final RcSecFixture fixture = await open(backend);
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'update-message-invalid');
        await waitUntil(() => body.cancelled, reason: 'the connection to end');
        expect(body.emitted, lessThanOrEqualTo(1 + _messageCap + 2 * 1024));
        await probe.cancel();
        expect(probe.errors, hasLength(1));
      },
    );

    for (final int status in <int>[403, 503]) {
      test(
        '5.9.1 / 5.11 rule 7: an endless realtime $status body stops at 16 KiB',
        () async {
          final EndlessBody body = EndlessBody(Uint8List(1024));
          final RcSecBackend backend = RcSecBackend(
            onRealtime: (RcSecCall call) => body.response(call, status),
          );
          final RcSecFixture fixture = await open(backend);
          final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
          addTearDown(probe.cancel);
          await waitUntil(
            () => body.cancelled,
            reason: 'the client to stop reading',
          );
          expect(body.emitted, lessThanOrEqualTo(_errorCap + 2 * 1024));
          if (status == 403) {
            final FirebaseRemoteConfigException error = await probe
                .firstError();
            expect(error.code, 'stream-error');
            expect(error.httpStatus, 403);
          }
        },
      );
    }

    test(
      '5.9 framing: 1 MiB of text outside braces is dropped as it arrives; a later message works',
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
          onFetch: (RcSecCall call) => templateResponse(call, version: '5'),
        );
        final RcSecFixture fixture = await open(backend);
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );
        for (int i = 0; i < 1024; i++) {
          realtime.add(utf8.encode('[,]\n' * 256));
        }
        realtime.add(utf8.encode('{"latestTemplateVersionNumber": "5"}'));
        await waitUntil(
          () => probe.updates.isNotEmpty,
          reason: 'the update after the auto-fetch',
        );
        expect(
          backend.fetchCalls.first.request.headers['X-Firebase-RC-Fetch-Type'],
          'REALTIME/1',
        );
        expect(probe.updates.single.updatedKeys, <String>{'k'});
        expect(probe.errors, isEmpty);
      },
    );
  });

  group('5.11 rule 7: a gzip bomb served by a loopback HttpServer stops at the cap', () {
    late RcSecServer server;
    late http.Client client;

    setUp(() async {
      server = await RcSecServer.start();
      client = http.Client();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    Future<RcSecFixture> openOnServer() async {
      final RcSecFixture fixture = await RcSecFixture.open(
        client: client,
        fisOrigin: server.origin,
        serverOrigin: server.origin,
        realtimeOrigin: server.origin,
      );
      fixtures.add(fixture);
      return fixture;
    }

    test(
      '5.11 rule 7: an endless gzip 200 fetch body (decompressed) stops at 8 MiB → fetch-client-parse',
      () async {
        // The source never ends: the server stops writing only when the client goes away.
        final Completer<bool> clientLeft = Completer<bool>();
        server.onFetch = (HttpRequest request, Uint8List body) async {
          clientLeft.complete(
            await sendGzip(request, 200, endlessChunks(Uint8List(1024 * 1024))),
          );
        };
        final RcSecFixture fixture = await openOnServer();
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-parse');
        await clientLeft.future.timeout(const Duration(seconds: 20));
      },
    );

    test(
      '5.11 rule 7: a finite gzip body of 9 MiB decompressed (tiny on the wire) → fetch-client-parse',
      () async {
        server.onFetch = (HttpRequest request, Uint8List body) async {
          await sendGzip(
            request,
            200,
            Stream<List<int>>.value(_templateOfLength(9 * 1024 * 1024)),
          );
        };
        final RcSecFixture fixture = await openOnServer();
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-parse');
      },
    );

    test('5.11 rule 7: a gzip body of 7 MiB decompressed is read', () async {
      server.onFetch = (HttpRequest request, Uint8List body) async {
        await sendGzip(
          request,
          200,
          Stream<List<int>>.value(_templateOfLength(7 * 1024 * 1024)),
        );
      };
      final RcSecFixture fixture = await openOnServer();
      expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
    });

    test(
      '5.11 rule 7: an endless gzip 500 body stops at 16 KiB; fetch-status 500',
      () async {
        final Completer<bool> clientLeft = Completer<bool>();
        server.onFetch = (HttpRequest request, Uint8List body) async {
          clientLeft.complete(
            await sendGzip(request, 500, endlessChunks(Uint8List(1024 * 1024))),
          );
        };
        final RcSecFixture fixture = await openOnServer();
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-status');
        expect(error.httpStatus, 500);
        await clientLeft.future.timeout(const Duration(seconds: 20));
      },
    );

    test(
      '5.9 / 5.11 rule 7: an endless gzip realtime message stops at 16 KiB → update-message-invalid',
      () async {
        final Completer<bool> clientLeft = Completer<bool>();
        server.onRealtime = (HttpRequest request, Uint8List body) async {
          if (clientLeft.isCompleted) {
            request.response.statusCode = 503;
            await request.response.close();
            return;
          }
          clientLeft.complete(
            await sendGzip(
              request,
              200,
              endlessChunks(
                utf8.encode('a' * (1024 * 1024)),
                prefix: utf8.encode('{'),
              ),
            ),
          );
        };
        final RcSecFixture fixture = await openOnServer();
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'update-message-invalid');
        await clientLeft.future.timeout(const Duration(seconds: 20));
      },
    );
  });

  group('5.5 Response: the depth scan (32 levels)', () {
    test('5.5: a 200 body nested 32 deep is read', () async {
      final RcSecBackend backend = RcSecBackend(
        onFetch: (RcSecCall call) => textResponse(
          call,
          200,
          '{"entries":{"k":"v"},"extra":${nestedArrays(31)}}',
        ),
      );
      final RcSecFixture fixture = await open(backend);
      expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
    });

    test(
      '5.5: a 200 body nested 33 deep → fetch-client-parse, nothing stored',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) => textResponse(
            call,
            200,
            '{"entries":{"k":"v"},"extra":${nestedArrays(32)}}',
          ),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-parse');
        expect(await fixture.store.read(fixture.key('fetched')), isNull);
        expect(
          fixture.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.failure,
        );
      },
    );

    test(
      '5.5: a body nested 100 000 deep is refused without decoding',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) =>
              textResponse(call, 200, nestedArrays(100000)),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-client-parse');
      },
    );

    test('5.5: brackets inside strings do not count', () async {
      final RcSecBackend backend = RcSecBackend(
        onFetch: (RcSecCall call) => templateResponse(
          call,
          entries: <String, String>{'k': '${'[' * 100}\\"${'{' * 100}'},
        ),
      );
      final RcSecFixture fixture = await open(backend);
      expect(await fixture.remoteConfig.fetch(), FetchResult.updated);
      await fixture.remoteConfig.activate();
      expect(fixture.remoteConfig.getString('k'), startsWith('[' * 100));
    });

    test(
      '5.5: an error body nested 33 deep keeps the status; serverMessage is null',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onFetch: (RcSecCall call) => textResponse(
            call,
            500,
            '{"error":{"message":"m","details":${nestedArrays(31)}}}',
          ),
        );
        final RcSecFixture fixture = await open(backend);
        final FirebaseRemoteConfigException error = await rcErrorOf(
          fixture.remoteConfig.fetch,
        );
        expect(error.code, 'fetch-status');
        expect(error.httpStatus, 500);
        expect(error.serverMessage, isNull);
      },
    );
  });
}
