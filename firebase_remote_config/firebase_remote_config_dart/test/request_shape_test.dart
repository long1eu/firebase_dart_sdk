@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:firebase_remote_config_dart/src/version.dart';
import 'package:test/test.dart';

import 'support/rc_unit_env.dart';

const Map<String, String> restrictedHeaders = <String, String>{
  'X-Android-Package': 'com.example.app',
  'X-Android-Cert': 'ABCDEF0123456789',
};

/// The headers of [request] without the ones a transport adds on its own.
Map<String, String> sentHeaders(RecordedRequest request) =>
    Map<String, String>.of(request.headers)..remove('content-length');

void main() {
  late RcUnitEnv env;

  tearDown(() => env.dispose());

  group('5.5 fetch request', () {
    setUp(() {
      env = RcUnitEnv(installationsHeaders: restrictedHeaders);
    });

    test(
      '5.5 POST to {origin}/v1/projects/{projectId}/namespaces/firebase:fetch '
      'with no query',
      () async {
        await env.newRemoteConfig().fetch();
        final RecordedRequest request = env.fetches.single;
        expect(request.method, 'POST');
        expect(
          request.url.origin,
          'https://firebaseremoteconfig.googleapis.com',
        );
        expect(
          request.url.path,
          '/v1/projects/rc-unit-project/namespaces/firebase:fetch',
        );
        expect(
          request.url.hasQuery,
          isFalse,
          reason: 'the key is not in the URL',
        );
        expect(request.url.hasFragment, isFalse);
      },
    );

    test('5.5 the first fetch sends exactly these headers, with the '
        'Installations headers and no If-None-Match', () async {
      await env.newRemoteConfig().fetch();
      final RecordedRequest request = env.fetches.single;
      expect(sentHeaders(request), <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-goog-api-key': 'A${'x' * 38}',
        'x-goog-firebase-installations-auth': 'auth-token-1',
        'x-firebase-rc-fetch-type': 'BASE/1',
        'x-android-package': 'com.example.app',
        'x-android-cert': 'ABCDEF0123456789',
      });
    });

    test('5.5 §6 row 2: the client sets no Accept-Encoding and no '
        'Content-Encoding', () async {
      await env.newRemoteConfig().fetch();
      final Map<String, String> headers = env.fetches.single.headers;
      expect(headers.containsKey('accept-encoding'), isFalse);
      expect(headers.containsKey('content-encoding'), isFalse);
    });

    test('5.5 Content-Type is exactly application/json, no charset', () async {
      await env.newRemoteConfig().fetch();
      expect(env.fetches.single.headers['content-type'], 'application/json');
    });

    test('5.5 the body is plain UTF-8 JSON with these fields', () async {
      await env.newRemoteConfig(languageCode: 'ro-RO').fetch();
      final RecordedRequest request = env.fetches.single;
      final String fid = env.installationRequests.first.json['fid']! as String;
      expect(request.json, <String, Object?>{
        'sdk_version': packageVersion,
        'app_instance_id': fid,
        'app_instance_id_token': 'auth-token-1',
        'app_id': env.appId,
        'language_code': 'ro-RO',
      });
      expect(request.bodyText.startsWith('{'), isTrue);
    });

    test('5.5 the body has no custom_signals key without signals, and holds '
        'them as text with them', () async {
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      await rc.fetch();
      expect(env.fetches.last.json.containsKey('custom_signals'), isFalse);

      await rc.setCustomSignals(<String, Object?>{'a': 'x', 'n': 2});
      await rc.fetch();
      expect(env.fetches.last.json['custom_signals'], <String, Object?>{
        'a': 'x',
        'n': '2',
      });
    });

    test(
      '5.5 the token in the body and in the header are the same token',
      () async {
        await env.newRemoteConfig().fetch();
        final RecordedRequest request = env.fetches.single;
        expect(
          request.headers['x-goog-firebase-installations-auth'],
          request.json['app_instance_id_token'],
        );
      },
    );

    test(
      '5.5 the FID in the body is the one registered with Installations',
      () async {
        await env.newRemoteConfig().fetch();
        final String registered =
            env.installationRequests.first.json['fid']! as String;
        expect(env.fetches.single.json['app_instance_id'], registered);
        expect(
          env.installationRequests.first.method,
          'POST',
          reason: 'registration came first',
        );
      },
    );

    test(
      '5.5 If-None-Match carries the stored ETag once one is stored',
      () async {
        final FirebaseRemoteConfig rc = env.newRemoteConfig();
        await rc.fetch();
        await rc.fetch(minimumFetchInterval: Duration.zero);
        expect(env.fetches.first.headers.containsKey('if-none-match'), isFalse);
        expect(env.fetches.last.headers['if-none-match'], 'etag-abc');
      },
    );

    test(
      '5.5 a fetch made after a signal change sends no If-None-Match',
      () async {
        final FirebaseRemoteConfig rc = env.newRemoteConfig();
        await rc.fetch();
        await rc.setCustomSignals(<String, Object?>{'a': '1'});
        await rc.fetch(minimumFetchInterval: Duration.zero);
        expect(env.fetches.last.headers.containsKey('if-none-match'), isFalse);
      },
    );

    test('5.5 without a stored ETag there is no If-None-Match', () async {
      env.fetchReply = FetchReply.template(<String, String>{'k': 'v'});
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      await rc.fetch();
      await rc.fetch(minimumFetchInterval: Duration.zero);
      expect(env.fetches.length, 2);
      expect(
        env.fetches.every(
          (RecordedRequest r) => !r.headers.containsKey('if-none-match'),
        ),
        isTrue,
      );
    });

    test('5.5 Installations headers are sent with the Installations requests '
        'too', () async {
      await env.newRemoteConfig().fetch();
      for (final RecordedRequest request in env.installationRequests) {
        expect(request.headers['x-android-package'], 'com.example.app');
        expect(request.headers.containsKey('accept-encoding'), isFalse);
      }
    });

    test('5.5 an instance without Installations headers sends none', () async {
      final RcUnitEnv plain = RcUnitEnv();
      addTearDown(plain.dispose);
      await plain.newRemoteConfig().fetch();
      expect(sentHeaders(plain.fetches.single).keys.toSet(), <String>{
        'content-type',
        'accept',
        'x-goog-api-key',
        'x-goog-firebase-installations-auth',
        'x-firebase-rc-fetch-type',
      });
    });
  });

  group('5.9 realtime request', () {
    setUp(() {
      env = RcUnitEnv(installationsHeaders: restrictedHeaders);
    });

    Future<RecordedRequest> openRealtime(FirebaseRemoteConfig rc) async {
      final StreamSubscription<RemoteConfigUpdate> subscription = rc
          .onConfigUpdated
          .listen((_) {}, onError: (Object _) {});
      addTearDown(subscription.cancel);
      return env.realtimeRequest;
    }

    test('5.9 POST to {realtimeOrigin}/v1/projects/{projectNumber}/namespaces/'
        'firebase:streamFetchInvalidations', () async {
      final RecordedRequest request = await openRealtime(env.newRemoteConfig());
      expect(request.method, 'POST');
      expect(
        request.url.origin,
        'https://firebaseremoteconfigrealtime.googleapis.com',
      );
      expect(
        request.url.path,
        '/v1/projects/1234567890/namespaces/firebase:streamFetchInvalidations',
      );
      expect(request.url.hasQuery, isFalse);
    });

    test('5.9 exactly these headers: no If-None-Match, no '
        'X-Accept-Response-Streaming, no Accept-Encoding', () async {
      final RecordedRequest request = await openRealtime(env.newRemoteConfig());
      expect(sentHeaders(request), <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-goog-api-key': 'A${'x' * 38}',
        'x-goog-firebase-installations-auth': 'auth-token-1',
        'x-android-package': 'com.example.app',
        'x-android-cert': 'ABCDEF0123456789',
      });
      expect(request.headers.containsKey('accept-encoding'), isFalse);
      expect(request.headers.containsKey('if-none-match'), isFalse);
      expect(
        request.headers.containsKey('x-accept-response-streaming'),
        isFalse,
      );
      expect(request.headers.containsKey('x-firebase-rc-fetch-type'), isFalse);
    });

    test('5.9 the body is strict JSON with camelCase string values', () async {
      final RecordedRequest request = await openRealtime(env.newRemoteConfig());
      final String fid = env.installationRequests.first.json['fid']! as String;
      expect(request.json, <String, Object?>{
        'project': '1234567890',
        'namespace': 'firebase',
        'lastKnownVersionNumber': '0',
        'appId': env.appId,
        'sdkVersion': packageVersion,
        'appInstanceId': fid,
      });
      expect(
        request.json.values.every((Object? v) => v is String),
        isTrue,
        reason: 'every value is a string',
      );
    });

    test('5.9 sdkVersion is the same text as the fetch sdk_version', () async {
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      await rc.fetch();
      final RecordedRequest request = await openRealtime(rc);
      expect(
        request.json['sdkVersion'],
        env.fetches.single.json['sdk_version'],
      );
    });

    test('5.9 lastKnownVersionNumber is the fetched version', () async {
      env.fetchReply = FetchReply.template(<String, String>{
        'k': 'v',
      }, version: 7);
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      await rc.fetch();
      final RecordedRequest request = await openRealtime(rc);
      expect(request.json['lastKnownVersionNumber'], '7');
    });

    test('5.9 lastKnownVersionNumber is the fetched version even when it is '
        'newer than the active one', () async {
      env.fetchReply = FetchReply.template(<String, String>{
        'k': 'v',
      }, version: 5);
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      await rc.fetchAndActivate();
      env.fetchReply = FetchReply.template(<String, String>{
        'k': 'w',
      }, version: 8);
      await rc.fetch(minimumFetchInterval: Duration.zero);
      final RecordedRequest request = await openRealtime(rc);
      expect(request.json['lastKnownVersionNumber'], '8');
    });

    test('5.9 lastKnownVersionNumber falls back to the active version when '
        'there is no fetched record', () async {
      final TemplateRecord active = TemplateRecord(
        entries: const <String, String>{'k': 'v'},
        fetchTime: fixedNow,
        templateVersion: 4,
      );
      await env.store.write(env.key('active'), active.encode());
      final FirebaseRemoteConfig rc = env.newRemoteConfig();
      await rc.ensureInitialized();
      final RecordedRequest request = await openRealtime(rc);
      expect(request.json['lastKnownVersionNumber'], '4');
    });

    test(
      '5.9 the project number comes from the second field of appId',
      () async {
        final RecordedRequest request = await openRealtime(
          env.newRemoteConfig(),
        );
        expect(request.json['project'], '1234567890');
        expect(request.json['appId'], '1:1234567890:web:0123456789abcdef');
      },
    );

    test('5.9 an appId without a numeric project number falls back to the '
        'messaging sender id', () async {
      final RcUnitEnv other = RcUnitEnv(
        appId: '1:not-digits:web:0123456789abcdef',
        messagingSenderId: '555000111',
      );
      addTearDown(other.dispose);
      final StreamSubscription<RemoteConfigUpdate> subscription = other
          .newRemoteConfig()
          .onConfigUpdated
          .listen((_) {}, onError: (Object _) {});
      addTearDown(subscription.cancel);
      final RecordedRequest request = await other.realtimeRequest;
      expect(request.json['project'], '555000111');
      expect(
        request.url.path,
        '/v1/projects/555000111/namespaces/firebase:streamFetchInvalidations',
      );
    });

    test('5.9 the auto-fetch after an invalidation sends REALTIME/1 with the '
        'same fetch shape', () async {
      final FirebaseRemoteConfig rc = env.newRemoteConfig(
        delay: (Duration _) async {},
      );
      await openRealtime(rc);
      env.fetchReply = FetchReply.template(<String, String>{
        'k': 'v',
      }, version: 2);
      env.sendRealtime('{"latestTemplateVersionNumber": "2"}');
      for (int i = 0; i < 200 && env.fetches.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final RecordedRequest fetch = env.fetches.first;
      expect(fetch.headers['x-firebase-rc-fetch-type'], 'REALTIME/1');
      expect(fetch.headers['x-goog-api-key'], 'A${'x' * 38}');
      expect(fetch.headers['content-type'], 'application/json');
      expect(fetch.headers.containsKey('accept-encoding'), isFalse);
      expect(fetch.json['sdk_version'], packageVersion);
    });
  });

  group('records used by the shape', () {
    setUp(() {
      env = RcUnitEnv();
    });

    test(
      '5.5 the stored fetched record keeps the ETag the server sent',
      () async {
        await env.newRemoteConfig().fetch();
        final TemplateRecord? fetched = TemplateRecord.tryParse(
          await env.store.read(env.key('fetched')),
        );
        expect(fetched?.etag, 'etag-abc');
        expect(
          MetaRecord.tryParse(
            await env.store.read(env.key('meta')),
            DateTime.now(),
          ),
          isNotNull,
        );
      },
    );
  });
}
