@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/rc_sec_harness.dart';
import '../support/rc_sec_io.dart';

/// Origins `checkOrigin` accepts (5.11 rule 1), with the origin requests then go to.
const Map<String, String> _accepted = <String, String>{
  'https://rc.example.com': 'https://rc.example.com',
  'https://rc.example.com/': 'https://rc.example.com',
  'https://rc.example.com:8443': 'https://rc.example.com:8443',
  'http://127.0.0.1:8080': 'http://127.0.0.1:8080',
  'http://127.255.255.254': 'http://127.255.255.254',
  'http://localhost:9000': 'http://localhost:9000',
  'http://LOCALHOST': 'http://localhost',
  'http://[::1]:9000': 'http://[::1]:9000',
};

/// Origins it refuses.
const List<String> _refused = <String>[
  'http://rc.example.com',
  'http://10.0.0.1',
  'http://192.168.1.10:8080',
  'http://128.0.0.1',
  'http://127.0.0.1.evil.test',
  'http://localhost.evil.test',
  'http://127.0.0',
  'http://[::2]',
  'https://rc.example.com/v1',
  'https://rc.example.com/path/',
  'https://rc.example.com?key=x',
  'https://rc.example.com#fragment',
  'https://user:pass@rc.example.com',
  'https://user@rc.example.com',
  'ftp://rc.example.com',
  'ws://127.0.0.1',
  'file:///etc/passwd',
  'rc.example.com',
  '//rc.example.com',
];

void main() {
  final List<RcSecFixture> fixtures = <RcSecFixture>[];

  Future<RcSecFixture> open({
    RcSecBackend? backend,
    Uri? serverOrigin,
    Uri? realtimeOrigin,
    String appId = rcSecAppId,
    String? messagingSenderId,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final RcSecFixture fixture = await RcSecFixture.open(
      backend: backend ?? RcSecBackend(),
      serverOrigin: serverOrigin,
      realtimeOrigin: realtimeOrigin,
      appId: appId,
      messagingSenderId: messagingSenderId,
      headers: headers,
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

  group('5.11 rule 1: origins are constructor arguments, checked', () {
    for (final MapEntry<String, String> entry in _accepted.entries) {
      test(
        '5.11 rule 1: serverOrigin ${entry.key} is accepted; fetch goes to ${entry.value}/v1/...',
        () async {
          final RcSecBackend backend = RcSecBackend();
          final RcSecFixture fixture = await open(
            backend: backend,
            serverOrigin: Uri.parse(entry.key),
          );
          await fixture.remoteConfig.fetch();
          expect(
            backend.fetchCalls.single.url.toString(),
            '${entry.value}/v1/projects/$rcSecProjectId/namespaces/firebase:fetch',
          );
        },
      );

      test(
        '5.11 rule 1: realtimeOrigin ${entry.key} is accepted; the stream goes to '
        '${entry.value}/v1/...',
        () async {
          final RcSecBackend backend = RcSecBackend();
          final RcSecFixture fixture = await open(
            backend: backend,
            realtimeOrigin: Uri.parse(entry.key),
          );
          final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
          addTearDown(probe.cancel);
          await waitUntil(
            () => backend.realtimeCalls.isNotEmpty,
            reason: 'the realtime request',
          );
          expect(
            backend.realtimeCalls.single.url.toString(),
            '${entry.value}/v1/projects/$rcSecProjectNumber/namespaces/firebase:streamFetchInvalidations',
          );
        },
      );
    }

    for (final String origin in _refused) {
      test('5.11 rule 1: serverOrigin $origin throws ArgumentError', () async {
        final RcSecFixture fixture = await open();
        expect(
          () => FirebaseRemoteConfig(
            fixture.app,
            installations: fixture.installations,
            httpClient: RcSecBackend().client,
            serverOrigin: Uri.parse(origin),
          ),
          throwsArgumentError,
        );
      });

      test(
        '5.11 rule 1: realtimeOrigin $origin throws ArgumentError',
        () async {
          final RcSecFixture fixture = await open();
          expect(
            () => FirebaseRemoteConfig(
              fixture.app,
              installations: fixture.installations,
              httpClient: RcSecBackend().client,
              realtimeOrigin: Uri.parse(origin),
            ),
            throwsArgumentError,
          );
        },
      );
    }

    test('5.11 rule 1: without origins the production hosts are used', () async {
      final RcSecBackend backend = RcSecBackend();
      final RcSecFixture base = await open(backend: backend);
      final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
        base.app,
        installations: base.installations,
        httpClient: backend.client,
        delay: (Duration _) async {},
      );
      addTearDown(remoteConfig.close);
      await remoteConfig.fetch();
      expect(
        backend.fetchCalls.single.url.toString(),
        'https://firebaseremoteconfig.googleapis.com/v1/projects/$rcSecProjectId/namespaces/'
        'firebase:fetch',
      );
      final StreamSubscription<RemoteConfigUpdate> subscription = remoteConfig
          .onConfigUpdated
          .listen(null, onError: (Object _) {});
      addTearDown(subscription.cancel);
      await waitUntil(
        () => backend.realtimeCalls.isNotEmpty,
        reason: 'the realtime request',
      );
      expect(
        backend.realtimeCalls.single.url.toString(),
        'https://firebaseremoteconfigrealtime.googleapis.com/v1/projects/$rcSecProjectNumber/'
        'namespaces/firebase:streamFetchInvalidations',
      );
    });
  });

  group('5.11 rule 2: the refresh token goes only to Installations', () {
    test(
      '5.11 rule 2: fetch and realtime never carry the refresh token; only the FIS origin gets it',
      () async {
        final RcSecBackend backend = RcSecBackend()
          // A first token living less than an hour makes Installations call generateAuthToken, the one
          // request that carries the refresh token.
          ..createExpiresIn = '3000s';
        final RcSecFixture fixture = await open(backend: backend);
        await fixture.remoteConfig.fetch();
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );

        final List<RcSecCall> carrying = backend.calls
            .where(
              (RcSecCall call) =>
                  call.everything.contains(refreshTokenSentinel),
            )
            .toList();
        expect(
          carrying,
          isNotEmpty,
          reason: 'the generate call carries the refresh token',
        );
        for (final RcSecCall call in carrying) {
          expect(call.url.host, rcSecFisOrigin.host);
          expect(call.url.pathSegments.take(3), <String>[
            'v1',
            'projects',
            rcSecProjectId,
          ]);
          expect(call.url.pathSegments, contains('installations'));
        }
        for (final RcSecCall call in <RcSecCall>[
          ...backend.fetchCalls,
          ...backend.realtimeCalls,
        ]) {
          expect(call.everything, isNot(contains(refreshTokenSentinel)));
          expect(
            call.request.headers.keys.map((String name) => name.toLowerCase()),
            isNot(contains('authorization')),
          );
        }
      },
    );
  });

  group('5.11 rule 3: URLs from validated parts', () {
    test(
      '5.9 / 5.11 rule 3: a non-digit messagingSenderId is never put in the realtime path',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(
          backend: backend,
          appId: '1:not-a-number:web:0a1b2c',
          messagingSenderId: '../../admin',
        );
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'stream-error');
        expect(backend.realtimeCalls, isEmpty);
      },
    );

    test(
      '5.9 / 5.11 rule 3: a digit messagingSenderId is the project number when appId has none',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(
          backend: backend,
          appId: '1:not-a-number:web:0a1b2c',
          messagingSenderId: '987654321',
        );
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );
        expect(backend.realtimeCalls.single.url.pathSegments, <String>[
          'v1',
          'projects',
          '987654321',
          'namespaces',
          'firebase:streamFetchInvalidations',
        ]);
      },
    );
  });

  group('5.11 rule 4: headers', () {
    test(
      '5.5 / 5.11 rule 4: fetch sends its headers plus installations.headers, nothing else',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(
          backend: backend,
          headers: <String, String>{'X-Android-Package': 'com.example.app'},
        );
        await fixture.remoteConfig.fetch();
        final Map<String, String> headers =
            backend.fetchCalls.single.request.headers;
        expect(
          headers.keys.map((String name) => name.toLowerCase()).toSet(),
          <String>{
            'content-type',
            'accept',
            'x-goog-api-key',
            'x-goog-firebase-installations-auth',
            'x-firebase-rc-fetch-type',
            'x-android-package',
          },
        );
        expect(headers['X-Android-Package'], 'com.example.app');
      },
    );

    test(
      '5.9 / 5.11 rule 4: realtime sends its headers plus installations.headers, nothing else',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(
          backend: backend,
          headers: <String, String>{
            'X-Ios-Bundle-Identifier': 'com.example.app',
          },
        );
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );
        expect(
          backend.realtimeCalls.single.request.headers.keys
              .map((String name) => name.toLowerCase())
              .toSet(),
          <String>{
            'content-type',
            'accept',
            'x-goog-api-key',
            'x-goog-firebase-installations-auth',
            'x-ios-bundle-identifier',
          },
        );
      },
    );
  });

  group('5.11 rule 5: redirects refused', () {
    test(
      '5.11 rule 5: fetch and realtime requests have followRedirects false',
      () async {
        final RcSecBackend backend = RcSecBackend();
        final RcSecFixture fixture = await open(backend: backend);
        await fixture.remoteConfig.fetch();
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        await waitUntil(
          () => backend.realtimeCalls.isNotEmpty,
          reason: 'the realtime request',
        );
        expect(backend.fetchCalls.single.request.followRedirects, isFalse);
        expect(backend.realtimeCalls.single.request.followRedirects, isFalse);
      },
    );

    for (final int status in <int>[301, 302, 303, 307, 308]) {
      test(
        '5.5 / 5.11 rule 5: a $status on fetch is fetch-status with httpStatus $status, not followed',
        () async {
          final RcSecBackend backend = RcSecBackend(
            onFetch: (RcSecCall call) => textResponse(
              call,
              status,
              '',
              headers: <String, String>{
                'location': 'https://elsewhere.test/v1/steal',
              },
            ),
          );
          final RcSecFixture fixture = await open(backend: backend);
          final FirebaseRemoteConfigException error = await rcErrorOf(
            fixture.remoteConfig.fetch,
          );
          expect(error.code, 'fetch-status');
          expect(error.httpStatus, status);
          expect(
            backend.calls.where(
              (RcSecCall call) => call.url.host == 'elsewhere.test',
            ),
            isEmpty,
          );
          expect(backend.fetchCalls, hasLength(1));
        },
      );
    }

    test(
      '5.9.1 / 5.11 rule 5: a 302 on realtime is one stream-error and no request to the target',
      () async {
        final RcSecBackend backend = RcSecBackend(
          onRealtime: (RcSecCall call) => textResponse(
            call,
            302,
            '',
            headers: <String, String>{
              'location': 'https://elsewhere.test/stream',
            },
          ),
        );
        final RcSecFixture fixture = await open(backend: backend);
        final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
        addTearDown(probe.cancel);
        final FirebaseRemoteConfigException error = await probe.firstError();
        expect(error.code, 'stream-error');
        expect(error.httpStatus, 302);
        expect(backend.realtimeCalls, hasLength(1));
        expect(
          backend.calls.where(
            (RcSecCall call) => call.url.host == 'elsewhere.test',
          ),
          isEmpty,
        );
      },
    );

    group('over a loopback HttpServer (IOClient)', () {
      late RcSecServer server;

      setUp(() async {
        server = await RcSecServer.start();
        server.onOther = (HttpRequest request, Uint8List body) async {
          request.response.statusCode = 200;
          request.response.write('{"state":"UPDATE","entries":{"k":"stolen"}}');
          await request.response.close();
        };
      });

      tearDown(() => server.close());

      Future<RcSecFixture> openOnServer() async {
        final http.Client client = http.Client();
        addTearDown(client.close);
        final RcSecFixture fixture = await RcSecFixture.open(
          client: client,
          fisOrigin: server.origin,
          serverOrigin: server.origin,
          realtimeOrigin: server.origin,
        );
        fixtures.add(fixture);
        return fixture;
      }

      for (final int status in <int>[302, 307]) {
        test(
          '5.5 / 5.11 rule 5: a real $status on fetch is not followed',
          () async {
            server.onFetch = (HttpRequest request, Uint8List body) async {
              request.response
                ..statusCode = status
                ..headers.set(
                  HttpHeaders.locationHeader,
                  '${server.origin}/redirected',
                );
              await request.response.close();
            };
            final RcSecFixture fixture = await openOnServer();
            final FirebaseRemoteConfigException error = await rcErrorOf(
              fixture.remoteConfig.fetch,
            );
            expect(error.code, 'fetch-status');
            expect(error.httpStatus, status);
            expect(server.paths, isNot(contains('/redirected')));
            expect(fixture.remoteConfig.getString('k'), 'default');
          },
        );
      }

      test(
        '5.9.1 / 5.11 rule 5: a real 302 on realtime is not followed',
        () async {
          server.onRealtime = (HttpRequest request, Uint8List body) async {
            request.response
              ..statusCode = 302
              ..headers.set(
                HttpHeaders.locationHeader,
                '${server.origin}/redirected',
              );
            await request.response.close();
          };
          final RcSecFixture fixture = await openOnServer();
          final RealtimeProbe probe = RealtimeProbe(fixture.remoteConfig);
          addTearDown(probe.cancel);
          final FirebaseRemoteConfigException error = await probe.firstError();
          expect(error.code, 'stream-error');
          expect(error.httpStatus, 302);
          expect(server.paths, isNot(contains('/redirected')));
        },
      );
    });
  });
}
